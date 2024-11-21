#!/bin/bash
# Description:
#   This script executes the steps to upgrade the PostgreSQL server to a newer major version for the SAS internal PostgreSQL server, based on Crunchy Postgres.
#   If your SAS Viya platform deployment uses an external PostgreSQL server, do not execute this script.
#   See the 2024.09 Deployment Notes for details about how to execute this script.

set -o pipefail

export MSYS_NO_PATHCONV=1

# Enable alias expansion
shopt -s expand_aliases

# Check parameter count
if [[ "$#" -lt "3" ]]; then
  echo "Usage: $BASH_SOURCE <namespace> <update-target-manifests-file> [log-debug] [sas-crunchy-platform-postgres|sas-crunchy-cds-postgres]" >&2
  exit 1
fi

NAMESPACE="$1"
MANIFESTS_FILE="$2"
LOG_DEBUG="$3"  # Optional for internal use to dump more log info
CLUSTER_NAME_PARM="$4"  # Optional for internal use: Upgrade only the specified cluster. If not specified, both clusters are upgraded.
PGO_FQDN="postgres-operator.crunchydata.com"
PGO_LABEL="$PGO_FQDN/control-plane=postgres-operator"
fromPostgresVersion=12  # Upgrade 'from' & 'to' versions should match with PGUpgrade CR 'fromPostgresVersion:' & 'toPostgresVersion:'.
toPostgresVersion=16    # The lifecycle operation 'deploy-pre-crunchy5' also has these hard-coded versions which must match with each other.

alias kc='oc -n $NAMESPACE '

# Function to log debug msg
f_log_debug() {
  if [ -n "$LOG_DEBUG" ]; then
    echo -e "DEBUG: $1"
  fi
} # f_log_debug

f_check_return_code() {
    return_code=$1
    str1=$2
    if [ "$return_code" -ne 0 ]; then
        echo "error from ${FUNCNAME[1]}: '$str1': return code: $return_code"  >&2   # ${FUNCNAME[1]}: caller of this function
        exit "$return_code"
    fi
} # f_check_return_code

f_error_exit() {
    error_msg=$1
    echo "error: $error_msg"  >&2
    exit 1
} # f_error_exit

f_check_pgversion() {
    expected_pg_version="$1"
    echo
    echo "Checking PostgreSQL version..."

    if [ -z "$expected_pg_version" ]; then
        echo "error from ${FUNCNAME[0]}: Version parameter is missing" >&2  # ${FUNCNAME[0]}: current function
        exit 1
    fi

    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        # Get the cluster's primary pod
        pod1=$(kc get pods --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master" -o jsonpath="{.items[*].metadata.name}")
        return_code=$?
        f_log_debug "pod1: $pod1"
        if [ "$return_code" -ne 0 ] || [ -z "$pod1" ]; then
            echo "error from ${FUNCNAME[0]}: error finding the primary pod of $CLUSTER_NAME. The cluster may be down. Bring up the cluster and retry."  >&2
            exit "$return_code"
        fi

        # Get the Postgres version using psql
        pg_version=$( kc exec $pod1 -c database -- psql --tuples-only --command='SELECT version()' 2>/dev/null | cut -f1 -d'.' | cut -f3 -d' ')
        f_check_return_code "$?" "kc exec $pod1 -c database -- psql --tuples-only --command='SELECT version()' ..."
        f_log_debug "pg_version: $pg_version"

        # Check the obtained version against the expected version
        if [[ "$pg_version" != "$expected_pg_version" ]]; then
            echo "error from ${FUNCNAME[0]}: The current PostgreSQL version $pg_version of $CLUSTER_NAME is different from what is expected. It is expected to be $expected_pg_version."  >&2
            exit 1
        fi
        echo "PostgreSQL version $pg_version of $CLUSTER_NAME matches the expected version $expected_pg_version."
    done
} # f_check_pgversion

f_delete_pgupgrade_cr_annotation() {
    echo
    echo "Deleting PGUpgrade CustomResources if exists..."
    # Delete all pgupgrade CRs.
    # The command always returns the return code 0. If CR doesn't exists, it displays 'No resources found'.
    kc delete pgupgrade --all
    echo "Deleting annotations if exists..."
    # Delete annotations by suffixing (-) to the annotations.
    # The command always displays '...annotated', and alwyas returns the return code 0 regardless that the annotation exists or not.
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        kc annotate postgrescluster "$CLUSTER_NAME" postgres-operator.crunchydata.com/allow-upgrade-
    done
} # f_delete_pgupgrade_cr_annotation

f_wait_object_created() {
    # Function to check if the object is existing, and if not, wait for its creation.

    object_to_wait=$1
    selector=$2

    max_wait=180 # Maximum wait time in seconds
    interval=5  # Interval between checks in seconds
    total_wait=0

    echo "Checking the object type '$object_to_wait' of '$selector'..."
    while true; do
        if [ $total_wait -ge $max_wait ]; then
            echo "Timed out waiting for the object $object_to_wait of '$selector'. Max wait time: $max_wait." >&2
            exit 1
        fi

        # Check if the object exists
        obj1=$(kc get $object_to_wait --selector="$selector" -o jsonpath="{.items[*].metadata.name}")
        if [ -n "$obj1" ]; then
            # If the object was not found at the first try, then log the wait time
            if [ $total_wait -gt 0 ]; then
                echo "Object $object_to_wait of '$selector' found after $total_wait seconds"
            fi
            return 0
        fi

        # Object does not exists. Wait to be created. Log only at the first loop
        if [ $total_wait -eq 0 ]; then
            echo "Object $object_to_wait of '$selector' waiting to be created..."
        fi

        sleep $interval
        total_wait=$((total_wait + interval))
    done
} # f_wait_object_created

f_shutdown_dso() {
    echo
    echo "Shutting down Data Server Operator..."
    kc scale deploy --replicas=0 sas-data-server-operator
    f_check_return_code "$?" "scale deploy --replicas=0 sas-data-server-operator"

    echo "Waiting for Data Server Operator to be down..."
    kc wait pods --for=delete --selector="app.kubernetes.io/name=sas-data-server-operator" --timeout=300s
    f_check_return_code "$?" "wait --for=delete --selector=\"app.kubernetes.io/name=sas-data-server-operator\" pods --timeout=300s"

    # Check if a pod is still there
    pod1=$(kc get pods --selector="app.kubernetes.io/name=sas-data-server-operator" -o jsonpath="{.items[*].metadata.name}")
    f_log_debug "pod1: $pod1"
    if [ -n "$pod1" ]; then
        f_error_exit "Data Server Operator pod still found"
    fi
} # f_shutdown_dso

f_drop_replicas() {
    echo
    echo "Dropping replicas..."
    # Repeat for Postgres cluster
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        f_log_debug "${FUNCNAME[0]} for $CLUSTER_NAME"  # ${FUNCNAME[0]} is the current function

        kc patch postgrescluster/$CLUSTER_NAME --type json --patch '[{"op":"replace", "path": "/spec/instances/0/replicas", "value": 1}]'
        f_check_return_code "$?" "patch postgrescluster/$CLUSTER_NAME --type json --patch ..."

        kc wait --for=delete --selector="$PGO_FQDN/role=replica,$PGO_FQDN/cluster=$CLUSTER_NAME" pods --timeout=300s
        f_check_return_code "$?" "wait --for=delete --selector=\"$PGO_FQDN/role=replica,$PGO_FQDN/cluster=$CLUSTER_NAME\" pods --timeout=300s"

        # Check if a pod is still there
        pod1=$(kc get pods --selector="$PGO_FQDN/role=replica,$PGO_FQDN/cluster=$CLUSTER_NAME" -o jsonpath="{.items[*].metadata.name}")
        f_log_debug "pod1: $pod1"
        if [ -n "$pod1" ]; then
            f_error_exit "Replica pod still found"
        fi
    done
} # f_drop_replicas

f_apply_crd() {
    echo
    echo "Applying Crunchy CRDs..."
    oc apply --selector="sas.com/admin=cluster-api,$PGO_LABEL" -f $MANIFESTS_FILE --server-side --force-conflicts
    f_check_return_code "$?" "apply --selector=\"sas.com/admin=cluster-api,$PGO_LABEL\" --server-side --force-conflicts -f $MANIFESTS_FILE"

    oc wait crd --for condition=established --selector="sas.com/admin=cluster-api,$PGO_LABEL" --timeout=60s
    f_check_return_code "$?" "wait crd --for condition=established --selector=\"sas.com/admin=cluster-api,$PGO_LABEL\" --timeout=60s"

    # Check if crds are found
    pod1=$(kc get crd --selector="sas.com/admin=cluster-api,$PGO_LABEL" -o jsonpath="{.items[*].metadata.name}")
    f_log_debug "pod1: $pod1"

    podc=$(echo $pod1 | wc -w)
    f_log_debug "podc: $podc"
    if [ "$podc" -ne 4 ]; then
        f_error_exit "CRD counts are not 4"
    fi
} # f_apply_crd


f_apply_pgo() {
    echo
    echo "Applying Crunchy Postgres Operator..."

    # Apply the image pull secret that is required to pull the new PGO image.
    echo "Apply a new image pull secret"
    yq e 'select((.kind == "Secret") and .metadata.name == "sas-image-pull-secrets-*")' $MANIFESTS_FILE |  kc apply -f-
    f_check_return_code "$?" "applying the new image pull secret failed"

    
    echo "Apply serviceaccount/pgo and role"
    oc apply --selector="sas.com/admin=cluster-wide,$PGO_LABEL" -f $MANIFESTS_FILE  # Creates serviceaccount/pgo and role.rbac.authorization.k8s.io/postgres-operator
    f_check_return_code "$?" "apply --selector=sas.com/admin=cluster-wide,$PGO_LABEL"

    # kc get serviceaccount --selector="sas.com/admin=cluster-wide,$PGO_LABEL"
    # kc get role --selector="sas.com/admin=cluster-wide,$PGO_LABEL"

    echo "Apply rolebinding"
    oc apply --selector="sas.com/admin=cluster-local,$PGO_LABEL" -f $MANIFESTS_FILE --prune # Creates rolebinding.rbac.authorization.k8s.io/postgres-operator
    f_check_return_code "$?" "apply --selector=sas.com/admin=cluster-local,$PGO_LABEL"

    # kc get rolebinding --selector="sas.com/admin=cluster-local,$PGO_LABEL"

    echo "Apply PGO deployment"
    oc apply --selector="sas.com/admin=namespace,$PGO_LABEL" -f $MANIFESTS_FILE --prune --prune-allowlist=autoscaling/v2/HorizontalPodAutoscaler # Creates deployment.apps/sas-crunchy5-postgres-operator
    f_check_return_code "$?" "apply --selector=sas.com/admin=namespace,$PGO_LABEL"

    pgo_deploy=$(kc get deploy --selector="sas.com/admin=namespace,$PGO_LABEL" -o jsonpath="{.items[*].metadata.name}")
    f_log_debug "pgo_deploy: $pgo_deploy"

    # Wait for the updated PGO deployment to be rolled out. Use either kc rollout status or kc wait --for=condition=available deployment.
    echo "Wait for PGO deployment to be rolled out"
    kc rollout status deployment/$pgo_deploy --timeout=300s
    f_check_return_code "$?" "rollout status deployment/$pgo_deploy"

    # Wait for the pgcluster restarted
    # Restart happens node by node, so 'k wait' may exit before the restart is commenced or when one node is completed but the next node hasn't begun.
    # So, do 'k wait' up to (number-of-cluster * 2 nodes + 1 extra) times, giving time between.
    echo "Wait for pgclusters to be restarted by the new PGO"
    sleep 30  # Wait for the restart is commenced.
    max_try=$(( $CR_COUNT * 2 + 1 ))
    for i in $(seq 1 $max_try); do 
        echo "Wait loop: $i/$max_try";
        sleep 10  # Sleep to wait for the next node to begin.

        kc wait pods --for=condition=ready --selector="$PGO_FQDN/cluster,$PGO_FQDN/data" --timeout=600s
        f_check_return_code "$?" "wait pods --for=condition=ready --selector=$PGO_FQDN/cluster,$PGO_FQDN/data"
    done

    # Check if pgo pod is found. Note: If selector is used, k get always returns 0.
    pod1=$(kc get pod --selector="$PGO_LABEL" -o jsonpath="{.items[*].metadata.name}")
    f_log_debug "PGO pod: $pod1"
    if [ -z "$pod1" ]; then
        f_error_exit "PGO pod is not found"
    fi

    # Check if all expected resources were created. Note: Resource names are not allowed with --all-namespaces
    # kc get serviceaccount  --all-namespaces | grep pgo
    # kc get role.rbac.authorization.k8s.io --all-namespaces | grep postgres-operator
    # kc get rolebinding.rbac.authorization.k8s.io --all-namespaces | grep postgres-operator
    # kc get deployment.apps --all-namespaces | grep sas-crunchy5-postgres-operator
} # f_apply_pgo

f_backup_pgcluster() {
    echo "WARNING: f_backup_pgcluster was not tested enough. Use it in your own risk."
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        echo "Backup the cluster $CLUSTER_NAME..."
        REPO_POD=$(kc get pod --selector="$PGO_FQDN/data=pgbackrest,$PGO_FQDN/cluster=$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}');
        # echo "Before the new backup:"
        # kc exec -it -c pgbackrest $REPO_POD -- pgbackrest info
        echo "Running a new backup: pgbackrest backup --stanza db --type=full..."
        kc exec -it -c pgbackrest $REPO_POD -- pgbackrest backup --stanza db --type=full
        f_check_return_code "$?" "pgbackrest backup"
        sleep 3

        echo "After the new backup:"
        kc exec -it -c pgbackrest $REPO_POD -- pgbackrest info
    done
} # f_backup_pgcluster

f_create_pgupgrade_cr() {
    echo
    echo "Create PGUpgrade CRs..."
    kc apply -f $MANIFESTS_FILE --selector="sas.com/pgupgrade-cr"
    f_check_return_code "$?" "apply pgupgrade"

    # kc get pgupgrade

    # Check if pgupgrade CRs are found
    cr1=$(kc get pgupgrade -o jsonpath="{.items[*].metadata.name}")
    f_check_return_code "$?" "get pgupgrade"
    f_log_debug "cr1: $cr1"
    if [ -z "$cr1" ]; then
        f_error_exit "PGUpgrade CR is not found"
    fi
} # f_create_pgupgrade_cr

f_shutdown_pgcluster() {
    echo
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        echo "Shutting down the cluster, $CLUSTER_NAME..."
        kc patch postgrescluster/$CLUSTER_NAME --type json --patch '[{"op":"replace", "path": "/spec/shutdown", "value": true}]'
        f_check_return_code "$?" "patch postgrescluster shutdown"
        
        kc wait pods --for=delete --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/data" --timeout=300s
        f_check_return_code "$?" "wait pods --for=delete --selector=$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/data"

        # Check if all PG pods are deleted. Note: If selector is used, it always returns 0.
        pod1=$(kc get pod --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/data" -o jsonpath="{.items[*].metadata.name}")
        f_log_debug "pod1: $pod1"
        if [ -n "$pod1" ]; then
            f_error_exit "Postgres pods are left undeleted"
        fi
    done
} # f_shutdown_pgcluster

f_annotate_pgupgrade() {
    echo
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        echo "Annotate for the upgrade of $CLUSTER_NAME..."
        kc annotate postgrescluster $CLUSTER_NAME $PGO_FQDN/allow-upgrade="${CLUSTER_NAME}-upgrade"
        f_check_return_code "$?" "annotate postgrescluster pgupgrade"
        
        # Check the annotation
        cnt1=$(kc get postgrescluster $CLUSTER_NAME -o yaml | grep allow-upgrade | wc -l)
        f_check_return_code "$?" "get postgrescluster for pgupgrade annotation"
        f_log_debug "cnt1: $cnt1"
        if [ "$cnt1" -ne 1 ]; then
            f_error_exit "Annotation is missing or too many"
        fi
    done
} # f_annotate_pgupgrade

f_wait_pgupgrade() {
    echo
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        echo "Waiting for the $CLUSTER_NAME pgupgrade job to finish..."

        # Check if the object exists, and if not, then wait for it to be created
        f_wait_object_created "job" "$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/pgupgrade=${CLUSTER_NAME}-upgrade"

        # Wait for the job to be completed. Note: condition is NOT 'completed' BUT 'complete' (case insensitive)
        # Using '--timeout' makes a job failure case to wait until timeout instead returning at the failure.
        # But without '--timeout', the 'wait' returns 'timeout' prematurely. So, use it always.
        kc wait job --for=condition=complete --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/pgupgrade=${CLUSTER_NAME}-upgrade"  --timeout=1800s
        f_check_return_code "$?" "wait for pgupgrade job to complete or fails..."

        # Check if pgupgrade job is completed successfully. Note: the field name is status.**succeeded**, but the field-selector is status.**successful**.
        # Note: If a selector is used, it always returns 0.
        job1=$(kc get job --field-selector=status.successful=1 --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/pgupgrade=${CLUSTER_NAME}-upgrade" -o jsonpath="{.items[*].metadata.name}")
        if [ -z "$job1" ]; then
            f_error_exit "There is no successfully completed PGUpgrade job"
        fi
        f_log_debug "job1: $job1"

        # Check the status in a different way to be certain.
        job_name=$(kc get job --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/pgupgrade=${CLUSTER_NAME}-upgrade" -o jsonpath="{.items[*].metadata.name}")
        job_status=$(kc get job "$job_name" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
        failed_pods=$(kc get job "$job_name" -o jsonpath='{.status.failed}')
        f_log_debug "job_name: $job_name, job_status: $job_status, failed_pods: $failed_pods"

        if [ "$job_status" == "True" ]; then
            echo "Job $job_name completed successfully."
        elif [ "$failed_pods" -gt 0 ]; then
            echo "Job $job_name failed." >&2
            exit 1
        else
            echo "Job $job_name is in an unknown state." >&2
            exit 1
        fi
    done
} # f_wait_pgupgrade

f_check_pgupgrade_status() {
    echo
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        echo "Checking the PGUpgrade CustomResource status for ${CLUSTER_NAME}-upgrade..."
        status_reason=$(kc get pgupgrade ${CLUSTER_NAME}-upgrade -o jsonpath="{.status.conditions[-1].reason}")  # -1 is last entry
        status_status=$(kc get pgupgrade ${CLUSTER_NAME}-upgrade -o jsonpath="{.status.conditions[-1].status}")
        status_type=$(kc get pgupgrade ${CLUSTER_NAME}-upgrade -o jsonpath="{.status.conditions[-1].type}")
        f_log_debug "status_reason: $status_reason, status_status: $status_status, status_type: $status_type"

        if [[ "$status_reason" == "PGUpgradeSucceeded" ]] && [[ "$status_status" == "True" ]] && [[ "$status_type" == "Succeeded" ]]; then
            echo "PGUpgrade was successful"
        else
            echo "error: PGUpgrade failed. Check the status block of PGUpgrade CustomResource and check log of the pgupgrade pod" >&2
            exit 1
        fi
    done
} # f_check_pgupgrade_status

f_start_pgcluster() {
    echo
    echo "Applying Postgres new images to the upgraded cluster..."
    oc apply --selector="sas.com/postgrescluster-cr" -f "$MANIFESTS_FILE"  # applies postgrescluster customer resources for updated postgres
    f_check_return_code "$?" "apply --selector=sas.com/postgrescluster-cr"

    # Wait for the primary pod running
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        # PostgresCluster CR sets 'shutdown:' to false, so the cluster is started.
        # Check if the object exists, and if not, then wait for it to be created.
        f_wait_object_created "pod" "$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master"

        echo "Waiting for the primary node (leader) to be running..."
        kc wait pods --for=condition=ready --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master" --timeout=300s
        f_check_return_code "$?" "wait pods --for=condition=ready --selector=$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master"

        # Double check if the primary pod is there before using it
        f_wait_object_created "pod" "$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master"

        # Get the pod. If a selector is used, then the return code is 0 even when there is none found.
        pod1=$(kc get pods --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master" -o jsonpath="{.items[*].metadata.name}")
        f_check_return_code "$?" "get pods --selector=$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master"

        f_log_debug "pod1: $pod1"
        if [ -z "$pod1" ]; then
            f_error_exit "PG cluster primary pod not found"
        fi

        # # Show the cluster
        # echo "Displaying the cluster status for $CLUSTER_NAME using the pod $pod1..."
        # kc exec $pod1 -c database -- patronictl list
        # f_check_return_code "$?" "exec $pod1 -c database -- patronictl list"

        # echo "INFO: Creating replicas may take time if the database size is big, so the process continues without waiting for replicas to come up."
        # echo "      For now, safely ignore the 'unknown', 'stopped', or 'creating' for Replicas. The Postgres cluster works without replicas."
        # echo "      Check later if Replicas are 'streaming' by running: oc exec $pod1 -n $NAMESPACE -c database -- patronictl list"
    done
} # f_start_pgcluster

f_start_dso() {
    echo
    echo "Starting up Data Server Operator..."
    kc scale deploy --replicas=1 sas-data-server-operator
    f_check_return_code "$?" "scale deploy --replicas=1 sas-data-server-operator"

    # Wait the object to be created first before starting to wait for the condition.
    f_wait_object_created "pod" "app=sas-data-server-operator"

    kc wait pod --for=condition=ready --selector="app=sas-data-server-operator" --timeout=300s
    f_check_return_code "$?" "wait pod --for=condition=ready --selector=app=sas-data-server-operator"

    # Check if a pod is there. Note: If a selector is used, it always returns 0.
    pod1=$(kc get pods --selector="app.kubernetes.io/name=sas-data-server-operator" -o jsonpath="{.items[*].metadata.name}")
    if [ -z "$pod1" ]; then
        f_error_exit "Data Server Operator pod not found"
    fi
    kc get pod $pod1
    f_check_return_code "$?" "get pod $pod1"
} # f_start_dso

# Post-upgrade task: Upgrade extensions
f_post_upgrade_extension_upgrade() {
    for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        echo
        echo "Post-upgrade task for $CLUSTER_NAME: Upgrading Postgres extensions..."
        echo "Get the primary pod of $CLUSTER_NAME"

        # Get the cluster's primary pod
        pod1=$(kc get pods --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master" -o name)
        return_code=$?
        if [ "$return_code" -ne 0 ] || [ -z "$pod1" ]; then
            echo "error from ${FUNCNAME[0]}: error finding the primary pod of $CLUSTER_NAME. The cluster may be down or is not healthy."  >&2
            exit "$return_code"
        fi
        f_log_debug "Primary pod is $pod1"

        # Run the script within the primary pod.
        # Do not use '-it' for exec. It is not interactive.
        # bash -c: commands;  -e: exit on error;  -u: undeclared variables are considered as an error
        # WARNING: Do not use (') within the bash code block because it is wrapped with single quotes.
        kc exec "$pod1" -c database -- /bin/bash -ceu '
logFile="/pgdata/upgrade_extensions.log"
echo > $logFile    # CAUTION: ">" overwrites the log file if exists while ">>" appends to it

# Show the current extension versions
echo "Before extensions are upgraded..." >> $logFile
psql -c "\dx" >> $logFile

# Show the content of the script that pg_upgrade created
echo >> $logFile
echo "Original script:" >> $logFile
cat /pgdata/update_extensions.sql >> $logFile

# Copy the script to a new file in order to edit it for pgaudit
cp /pgdata/update_extensions.sql /pgdata/drop_create_extensions.sql

# For the extension "pgaudit", replace "ALTER EXTENSION...UPDATE" with  "DROP/CREATE EXTENSION"  
# because it returns "ERROR:  extension pgaudit has no update path from version 1.4.3 to version 16.0"
sed -i "/pgaudit/c\DROP EXTENSION pgaudit;  CREATE EXTENSION pgaudit;" /pgdata/drop_create_extensions.sql
echo >> $logFile
echo "Updated script:" >> $logFile
cat /pgdata/drop_create_extensions.sql >> $logFile

# Execute the script through psql
echo >> $logFile
echo "Excute the ppdated script:" >> $logFile
psql -f /pgdata/drop_create_extensions.sql | tee -a $logFile

# Show the extension versions again
echo >> $logFile
echo "After extensions are upgraded..." >> $logFile
echo >> $logFile
psql -c "\dx" >> $logFile
echo "The log file $logFile was created within $(hostname) to show the details of the extension upgrades"
'
    done
} # f_post_upgrade_extension_upgrade


# Post-upgrade task: Vacuumdb for analyze only
f_post_upgrade_vacuumdb_analyze() {
     for CLUSTER_NAME in $(echo "$CLUSTER_NAME_LIST"); do
        echo
        echo "Post-upgrade task for $CLUSTER_NAME: Running vacuumdb with analyze-only..."
        echo "Get the primary pod of $CLUSTER_NAME"

        # Get the cluster's primary pod
        pod1=$(kc get pods --selector="$PGO_FQDN/cluster=$CLUSTER_NAME,$PGO_FQDN/role=master" -o name)
        return_code=$?
        if [ "$return_code" -ne 0 ] || [ -z "$pod1" ]; then
            echo "error from ${FUNCNAME[0]}: error finding the primary pod of $CLUSTER_NAME. The cluster may be down or is not healthy."  >&2
            exit "$return_code"
        fi
        f_log_debug "Primary pod is $pod1"

        # Run the command 'vacuumdb for all databases only analyzing data' within the primary pod.
        # Run it in a background process so that Viya Update process does not have to wait for the analyze to complete.
        # Do not use '-it' for exec. It is not interactive.
        kc exec $pod1 -c database -- /bin/bash -c 'nohup vacuumdb --all --analyze-only >/pgdata/vacuumdb-analyze-only.log 2>&1 &'
        echo "vacuumdb with --analyze-only was submitted as a background job within $pod1, creating the log file /pgdata/vacuumdb-analyze-only.log within the pod"
    done
} # f_post_upgrade_vacuumdb_analyze


##############################################################
# Main body
##############################################################

# Check if there are Crunchy 4 CR. 
set +o pipefail
cr4_count=$(kc get pgcluster -o jsonpath="{.items[*].metadata.name}" 2>/dev/null | wc -w)
set -o pipefail
if [ "$cr4_count" -ne 0 ]; then
    echo "error: pgcluster CR is found. Upgrading directly from Crunchy 4 (2022.09 LTS) is not allowed. Upgrade to more recent LTS first and retry."  >&2
    exit 1
fi

if [ -n "$CLUSTER_NAME_PARM" ]; then
    # Use the passed-in cluster name
    echo "WARNING: Pass in the cluster name as a parameter with caution. Use that option only for debugging or patching upgrade."
    echo "         Running the script 'return's after defining functions but not invoking them."
    echo "         So, that option is meaningful only when this script is sourced by '.' or 'source' and each function is manually invoked."
    echo "         The functions such as f_apply_pgo, f_start_pgcluster applying CRs,  f_create_pgupgrade_cr, and f_delete_pgupgrade_cr_annotation affect both clusters."
    DEFINE_FUNCTIONS_ONLY="true"
    CLUSTER_NAME_LIST="$CLUSTER_NAME_PARM"
    CR_COUNT=1
else
    # Get postgrescluster CR count
    f_log_debug 'k get postgrescluster -o jsonpath="{.items[*].metadata.name}" | wc -w'
    set +o pipefail
    CR_COUNT=$(kc get postgrescluster -o jsonpath="{.items[*].metadata.name}" | wc -w)
    set -o pipefail

    # Make a cluster name list
    DEFINE_FUNCTIONS_ONLY="false"
    if [ "$CR_COUNT" -eq 1 ]; then
        CLUSTER_NAME_LIST="sas-crunchy-platform-postgres"
    elif [ "$CR_COUNT" -eq 2 ]; then
        CLUSTER_NAME_LIST="sas-crunchy-platform-postgres sas-crunchy-cds-postgres"
    else
        echo "error: unexpected PostgresCluster CustomResource count. Check 'kc get PostgresCluster'"  >&2
        exit 1
    fi
fi
f_log_debug "CLUSTER_NAME_LIST: $CLUSTER_NAME_LIST"

# If a cluster name was passed in, then return after defining functions so that the functions may be invoked manually to patch the upgrade process
if [[ $DEFINE_FUNCTIONS_ONLY == "true" ]]; then
    return 0  # return, not exit, in this case because we are sourcing this script to define functions and exit from the script. 'exit' terminates the current process. Then, all the defined functions will go away.
fi

# Ensure that the Postgres is at the 'from' version
f_check_pgversion "$fromPostgresVersion"

# Delete PGUpgrade CRs and annotations if exists
f_delete_pgupgrade_cr_annotation

# Shutdown Data Server Operator
f_shutdown_dso

# Drop replicas from the Postgres clusters
f_drop_replicas

# Apply Crunchy CRDs
f_apply_crd

# Apply PGO
f_apply_pgo

# Backup the Postgres clusters
# f_backup_pgcluster
# Skip this because of sporadic failure. Just document the requirement for backup.

# Apply PGUpgrade CRs
f_create_pgupgrade_cr

# Shutdown the Postgres clusters.
f_shutdown_pgcluster

# Annotate to start the pgupgrade
f_annotate_pgupgrade

# Wait for the completion of the pgupgrade job
f_wait_pgupgrade

# Check the PGUpgrade status
f_check_pgupgrade_status

# Start the Postgres clusters with the new Postgres images
f_start_pgcluster

# Start back Data Server Operator
f_start_dso

# Ensure that the Postgres is now at the 'to' version
f_check_pgversion "$toPostgresVersion"

# Do not delete the PGUpgrade CR; let users decide when to delete.
# If it is left behind until next upgrade, it will be deleted at the top of this script.
# f_delete_pgupgrade_cr_annotation
# Document it to be deleted by users after everything is completed

# Post-upgrade task: Upgrade extensions
f_post_upgrade_extension_upgrade

# Post-upgrade task: Kick off the vacuumdb command to the background process
f_post_upgrade_vacuumdb_analyze
