#!/usr/bin/env bash

config-enable-consul-ui() {
    echo "Entering ${FUNCNAME[0]}"
    #create sas-consul-ui service
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: sas-consul-ui
  labels:
    app: sas-consul-ui
spec:
  ports:
  - port: 443
    name: http
    targetPort: http
  selector:
    app.kubernetes.io/name: sas-consul-server
    sas.com/deployment: sas-viya
  sessionAffinity: None
  type: ClusterIP
EOF


cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /consul/$2
    cert-manager.io/cluster-issuer: sas-viya-issuer
    nginx.ingress.kubernetes.io/affinity: cookie
    nginx.ingress.kubernetes.io/affinity-mode: persistent
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    nginx.ingress.kubernetes.io/proxy-body-size: 2048m
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/session-cookie-name: sas-ingress-nginx
    nginx.ingress.kubernetes.io/session-cookie-path: /consul/
    nginx.ingress.kubernetes.io/session-cookie-samesite: Lax
  name: sas-consul-ui
  labels:
    app: sas-consul-ui
spec:
  ingressClassName: nginx
  rules:
  - host: sas-nabatt-sfdeastus2-rg.eastus2.cloudapp.azure.com
    http:
      paths:
      - backend:
          service:
            name: sas-consul-ui
            port: 
              number: 443
        path: /consul(/|$)(.*)
        pathType: ImplementationSpecific
  - host: '*.sas-nabatt-sfdeastus2-rg.eastus2.cloudapp.azure.com'
    http:
      paths:
      - backend:
          service:
            name: sas-consul-ui
            port: 
              number: 443
        path: /consul(/|$)(.*)
        pathType: ImplementationSpecific
  tls:
  - hosts:
    - sas-nabatt-sfdeastus2-rg.eastus2.cloudapp.azure.com
    - '*.sas-nabatt-sfdeastus2-rg.eastus2.cloudapp.azure.com'
    secretName: sas-ingress-certificate
EOF
}