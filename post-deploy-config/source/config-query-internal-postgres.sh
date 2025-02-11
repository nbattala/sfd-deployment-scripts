#!/usr/bin/env bash

config-query-internal-postgres () {
  pgHostName=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.registrations[0].host}')
  pgPortNum=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.registrations[0].port}')
  pgDbName=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.databases[0].name}')
  pgTlsEnabled=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.ssl}')
  pgCredSecret=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.users[0].credentials.input.secretRef.name}')
  pgUserNameKey=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.users[0].credentials.input.usernameKey}')
  pgPasswordKey=$(oc get dataserver -n ${project} sas-platform-postgres -o jsonpath='{.spec.users[0].credentials.input.passwordKey}')
  pgUserName=$(oc get secret -n ${project} ${pgCredSecret} -o jsonpath="{.data.${pgUserNameKey}}" | base64 -d)
  pgPassword=$(oc get secret -n ${project} ${pgCredSecret} -o jsonpath="{.data.${pgPasswordKey}}" | base64 -d)

# Modify the internal postgres data
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
    name: query-internal-postgres-data
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
          PGPASSWORD=${pgPassword} psql -h ${pgHostName} -p ${pgPortNum} -U ${pgUserName} -d ${pgDbName} -c "SELECT * FROM logon.identity_provider;"
      restartPolicy: Never
EOF

}