#!/usr/bin/env bash
# lab-part-05 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p04
D="$HOME/ckne-lab/p04"
NODO=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-red"

cat > red-kind.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
nodes:
- role: control-plane
- role: worker
YAML
kind create cluster --name ckne-lab5-red --config red-kind.yaml --image "$NODO" --kubeconfig "$D/kubeconfig"
$K create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.1/manifests/calico.yaml >/dev/null
$K -n kube-system rollout status daemonset/calico-node --timeout=300s
$K wait --for=condition=Ready node --all --timeout=180s
$K -n kube-system rollout status deployment/coredns --timeout=180s

for ns in deposito maestranza afuera; do
  $K create namespace $ns
  $K label namespace $ns zona=$ns
done

cat <<YAML | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: existencias, namespace: deposito}
spec:
  replicas: 1
  selector: {matchLabels: {app: existencias}}
  template:
    metadata: {labels: {app: existencias}}
    spec:
      containers:
      - name: web
        image: nginx:1.29.5-alpine
---
apiVersion: v1
kind: Service
metadata: {name: existencias, namespace: deposito}
spec:
  selector: {app: existencias}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: v1
kind: Pod
metadata: {name: operario, namespace: maestranza, labels: {rol: operario}}
spec:
  containers: [{name: sh, image: $CURL, command: ["sleep", "7200"]}]
---
apiVersion: v1
kind: Pod
metadata: {name: novato, namespace: maestranza, labels: {rol: novato}}
spec:
  containers: [{name: sh, image: $CURL, command: ["sleep", "7200"]}]
---
apiVersion: v1
kind: Pod
metadata: {name: operario, namespace: afuera, labels: {rol: operario}}
spec:
  containers: [{name: sh, image: $CURL, command: ["sleep", "7200"]}]
YAML
$K -n deposito rollout status deployment/existencias --timeout=180s
$K -n maestranza wait --for=condition=Ready pod --all --timeout=180s
$K -n afuera wait --for=condition=Ready pod --all --timeout=180s

# La matriz: cada Pod pide la Service existencias; 200 es que pasa, 000 que no hubo respuesta.
cat > matriz.sh <<'MATRIZ'
K="kubectl --kubeconfig $HOME/ckne-lab/p04/kubeconfig --context kind-ckne-lab5-red"
for c in maestranza/operario maestranza/novato afuera/operario; do
  printf "%-22s " $c
  $K -n ${c%/*} exec ${c#*/} -- curl -s -m 3 -o /dev/null -w "%{http_code}" http://existencias.deposito/ 2>/dev/null
  echo " exit $?"
done
MATRIZ
sleep 10
echo "ANTES de la politica:"
bash matriz.sh

# La politica: un solo elemento en from, con el espacio Y la etiqueta del Pod juntos.
cat <<YAML | $K apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: solo-operarios, namespace: deposito}
spec:
  podSelector: {matchLabels: {app: existencias}}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {zona: maestranza}}
      podSelector: {matchLabels: {rol: operario}}
YAML
sleep 8
echo "DESPUES de la politica:"
bash matriz.sh

# The answer file the lab asks you to type, from the matrix above:
D="$HOME/ckne-lab/p04"
M=$(bash matriz.sh)
cat > "$D/01-respuesta.txt" <<RESP
PASA=$(echo "$M" | awk '$2=="200" {print $1}' | sort | paste -sd, -)
SIN_RESPUESTA=$(echo "$M" | awk '$2=="000" {print $1}' | sort | paste -sd, -)
RESP
cat "$D/01-respuesta.txt"
