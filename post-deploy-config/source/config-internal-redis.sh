#!/bin/bash

#source ../../properties.env

config-internal-redis() {
    local redis_image="$(echo "$imageRegistry" | cut -d '/' -f1)/redis:7.0.0"
cat <<EOF | oc apply -f - 
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
data:
  redis.conf: |+
    cluster-enabled no
    cluster-require-full-coverage no
    protected-mode no
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      imagePullSecrets:
        - name: ${imagePullSecret}
      containers:
        - name: redis
          image: ${redis_image}
          ports:
            - containerPort: 6379
              name: client
          command: ["redis-server", "/conf/redis.conf"]
          env:
            - name: MASTER
              value: "true"
          volumeMounts:
            - name: conf
              mountPath: /conf
              readOnly: false
            - name: data
              mountPath: /data
              readOnly: false
      volumes:
        - name: conf
          configMap:
            name: redis-config
            defaultMode: 0755
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: ${rwoStorageClass}
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  type: ClusterIP
  ports:
    - port: 6379
      targetPort: 6379
      name: tcp
      protocol: TCP
  selector:
    app: redis
EOF
}