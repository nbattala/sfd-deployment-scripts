#!/usr/bin/env bash

config-query-internal-postgres () {
  export pgHostName=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.registrations[0].host}' &) 
  export pgPortNum=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.registrations[0].port}' &) 
  export pgDbName=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.databases[0].name}' &) 
  export pgTlsEnabled=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.ssl}' &) 
  export pgCredSecret=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.users[0].credentials.input.secretRef.name}' &) 
  export pgUserNameKey=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.users[0].credentials.input.usernameKey}' &) 
  export pgPasswordKey=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.users[0].credentials.input.passwordKey}' &) 
  export pgUserName=$(oc get secret -n ${project} ${pgCredSecret} -o jsonpath="{.data.${pgUserNameKey}}" | base64 -d &) 
  export pgPassword=$(oc get secret -n ${project} ${pgCredSecret} -o jsonpath="{.data.${pgPasswordKey}}" | base64 -d &) 

  wait

  oc delete job query-internal-postgres-data

# Modify the internal postgres data
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: query-internal-postgres-data
labels:
  app: query-internal-postgres-data
spec:
  template:
    spec:
      imagePullSecrets:
      - name: $imagePullSecret
      containers:
      - name: postgres
        image: ${imageRegistry}/sas-crunchy5-postgres:1.3.5-20241206.1733500290858
        command: ["bash", "-c"]
        args:
        - |
          # Your modification commands here
          # For example, to run a SQL script:
          PGPASSWORD=${pgPassword} psql -h ${pgHostName} -p ${pgPortNum} -U ${pgUserName} -d ${pgDbName} -c "$1"
      restartPolicy: Never
EOF

oc wait --for=jsonpath='{.status.phase}'=Succeeded pod -l job-name=query-internal-postgres-data --timeout=10s
oc logs -f -l job-name=query-internal-postgres-data
}
