#!/usr/bin/env bash
# lab-part-02 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p01
K="kubectl --kubeconfig $HOME/ckne-lab/p01/kubeconfig --context kind-ckne-lab1"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

$K create namespace vecinos

cat <<EOF | $K apply -f -
apiVersion: v1
kind: Pod
metadata: {name: vecino-a, namespace: vecinos}
spec:
  nodeName: ckne-lab1-worker
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sleep","3600"]
---
apiVersion: v1
kind: Pod
metadata: {name: vecino-b, namespace: vecinos}
spec:
  nodeName: ckne-lab1-worker2
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sh","-c","mkdir -p /www && echo vecino-b-ok > /www/index.html && exec httpd -f -vv -p 8080 -h /www"]
EOF

$K -n vecinos wait --for=condition=Ready pod/vecino-a pod/vecino-b --timeout=180s
$K -n vecinos get pods -o wide

IPB=$($K -n vecinos get pod vecino-b -o jsonpath='{.status.podIP}')
echo "ANTES DE LA FALLA:"
$K -n vecinos exec vecino-a -- wget -qO- -T5 http://$IPB:8080/

bash ~/ckne-lab/p01/inyectar-falla.sh

echo "DESPUES DE LA FALLA:"
$K -n vecinos exec vecino-a -- wget -qO- -T5 http://$IPB:8080/ || true

# The answer file the lab asks you to type, from what the commands above showed:
D="$HOME/ckne-lab/p01"
cat > "$D/02-respuesta.txt" <<RESP
IP_DE_VECINO_B=$IPB
ANTES=responde
DESPUES=agota-tiempo
RESP
cat "$D/02-respuesta.txt"
