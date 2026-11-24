#!/usr/bin/env bash
# lab-part-01 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p00
K="kubectl --kubeconfig $HOME/ckne-lab/p00/kubeconfig --context kind-ckne-lab0"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

cat <<EOF | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: mostrador, namespace: terminal}
spec:
  replicas: 2
  selector: {matchLabels: {app: mostrador}}
  template:
    metadata: {labels: {app: mostrador}}
    spec:
      containers:
      - name: c
        image: $BUSYBOX
        command: ["sh","-c","mkdir -p /www && echo \$HOSTNAME > /www/index.html && exec httpd -f -p 8080 -h /www"]
---
apiVersion: v1
kind: Service
metadata: {name: mostrador, namespace: terminal}
spec:
  selector: {app: mostrador}
  ports:
  - {port: 80, targetPort: 8080}
EOF

$K -n terminal rollout status deployment/mostrador --timeout=180s
$K -n terminal get svc,endpointslices -o wide
$K -n terminal exec emisor -- nslookup mostrador.terminal.svc.cluster.local
for i in 1 2 3 4 5 6 7 8; do
  $K -n terminal exec emisor -- wget -qO- -T3 http://mostrador.terminal.svc.cluster.local/
done

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p00"
CIP=$($K -n terminal get svc mostrador -o jsonpath='{.spec.clusterIP}')
RES=$($K -n terminal exec emisor -- nslookup mostrador.terminal.svc.cluster.local | awk '/^Name:/{f=1} f&&/^Address/{print $NF; exit}')
N=$(for i in $(seq 1 40); do $K -n terminal exec emisor -- wget -qO- -T3 http://mostrador.terminal.svc.cluster.local/; done | tr -d '\r' | sort -u | wc -l)
cat > "$D/04-respuesta.txt" <<RESP
CLUSTER_IP=$CIP
RESUELVE_A=$RES
MOSTRADORES_DISTINTOS=$N
RESP
cat "$D/04-respuesta.txt"
