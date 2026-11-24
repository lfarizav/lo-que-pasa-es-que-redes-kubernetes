#!/usr/bin/env bash
# lab-part-01 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p00
K="kubectl --kubeconfig $HOME/ckne-lab/p00/kubeconfig --context kind-ckne-lab0"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

$K create namespace terminal

cat <<EOF | $K apply -f -
apiVersion: v1
kind: Pod
metadata: {name: emisor, namespace: terminal}
spec:
  nodeName: ckne-lab0-worker
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sleep","3600"]
---
apiVersion: v1
kind: Pod
metadata: {name: receptor, namespace: terminal}
spec:
  nodeName: ckne-lab0-worker2
  containers:
  - name: c
    image: $BUSYBOX
    command: ["httpd","-f","-vv","-p","8080","-h","/tmp"]
EOF

$K -n terminal wait --for=condition=Ready pod/emisor pod/receptor --timeout=180s
$K -n terminal get pods -o wide

RX=$($K -n terminal get pod receptor -o jsonpath='{.status.podIP}')
$K -n terminal exec emisor -- wget -qO- -T5 http://$RX:8080/mi-sonda || true
$K -n terminal logs receptor
$K -n terminal get pod emisor -o jsonpath='{.status.podIP}{"\n"}'

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p00"
IPE=$($K -n terminal get pod emisor -o jsonpath='{.status.podIP}')
VISTA=$($K -n terminal logs receptor | grep -F mi-sonda | tail -1 | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)
cat > "$D/03-respuesta.txt" <<RESP
IP_DEL_EMISOR=$IPE
IP_QUE_VIO_EL_RECEPTOR=$VISTA
RESP
cat "$D/03-respuesta.txt"
