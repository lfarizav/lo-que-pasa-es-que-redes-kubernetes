#!/usr/bin/env bash
# lab-part-05 step 7 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-id"
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c
FICHA=$(cat "$D/ficha-del-cofre.txt" 2>/dev/null)
test -n "$FICHA" || exit 1
test "$(echo -n "$FICHA" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.ficha.sha256" 2>/dev/null)" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab5-id || exit 1
test "$($K get namespace bahia -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)" = "enabled" || exit 1
$K -n bahia get serviceaccount jefe-de-bahia >/dev/null 2>&1 || exit 1
SVC=$($K -n bahia get service cofre -o json 2>/dev/null)
echo "$SVC" | jq -e '(.spec.type=="ClusterIP") and (.spec.ports[0].port==80) and ((.spec.selector // {}) | length > 0)' >/dev/null || exit 1
EPS=$($K -n bahia get endpointslices -l kubernetes.io/service-name=cofre -o json 2>/dev/null)
echo "$EPS" | jq -e '[.items[].endpoints[]? | select(.conditions.ready==true)] | length >= 1' >/dev/null || exit 1
# Los Pods del cofre son de la malla y llevan la identidad de SPIRE.
PODS=$($K -n bahia get pods -l "$(echo "$SVC" | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')" -o json 2>/dev/null)
echo "$PODS" | jq -e '[.items[] | select(.status.phase=="Running")] | length >= 1' >/dev/null || exit 1
echo "$PODS" | jq -e '[.items[] | select(.status.phase=="Running") | ([.spec.containers[].name, .spec.initContainers[]?.name] | index("istio-proxy")) != null and ([.spec.volumes[]? | select(.csi.driver=="csi.spiffe.io")] | length==1)] | all' >/dev/null || exit 1
# Las sondas las crea la comprobacion: una con la identidad que debe pasar, otra de otra identidad en el mismo espacio y otra en un espacio ajeno.
GN=sonda-ajena
cleanup() {
  $K -n bahia delete pod sonda-jefe sonda-otra --ignore-not-found --wait=false >/dev/null 2>&1
  $K -n bahia delete serviceaccount visitante-lab --ignore-not-found >/dev/null 2>&1
  $K delete namespace $GN --ignore-not-found --wait=false >/dev/null 2>&1
}
trap cleanup EXIT
$K delete namespace $GN --ignore-not-found --wait=true >/dev/null 2>&1
$K -n bahia delete pod sonda-jefe sonda-otra --ignore-not-found --wait=true >/dev/null 2>&1
$K create namespace $GN >/dev/null 2>&1 || exit 1
$K label namespace $GN istio-injection=enabled >/dev/null 2>&1 || exit 1
$K -n bahia create serviceaccount visitante-lab >/dev/null 2>&1 || exit 1
sonda() { # espacio nombre serviceaccount
  cat <<YAML | $K apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $2
  namespace: $1
  annotations:
    inject.istio.io/templates: "sidecar,spire"
spec:
  serviceAccountName: $3
  containers:
  - name: sh
    image: $CURL
    command: ["sleep", "600"]
YAML
}
sonda bahia sonda-jefe jefe-de-bahia || exit 1
sonda bahia sonda-otra visitante-lab || exit 1
sonda $GN sonda-ajena default || exit 1
for p in bahia/sonda-jefe bahia/sonda-otra $GN/sonda-ajena; do
  $K -n ${p%/*} wait --for=condition=Ready pod/${p#*/} --timeout=240s >/dev/null 2>&1 || exit 1
done
# La regla tarda unos segundos en llegar a los proxies: se repite la peticion con el tiempo a la vista.
pide() { # espacio pod -> "codigo cuerpo"
  $K -n "$1" exec "$2" -c sh -- curl -s -m 4 -w ' %{http_code}' http://cofre.bahia/ 2>/dev/null
}
espera() { # espacio pod esperado(codigo)
  local R i
  for i in $(seq 18); do
    R=$(pide "$1" "$2")
    [ "${R##* }" = "$3" ] && { echo "$R"; return 0; }
    sleep 5
  done
  echo "$R"; return 1
}
R=$(espera bahia sonda-jefe 200) || exit 1
test "$(echo "${R% *}" | tr -d '\n')" = "$FICHA" || exit 1
espera bahia sonda-otra 403 >/dev/null || exit 1
espera $GN sonda-ajena 403 >/dev/null || exit 1
# El resultado tiene que sostenerse: una segunda lectura de cada sonda.
test "${R##* }" = "200" || exit 1
test "$(pide bahia sonda-otra | awk '{print $NF}')" = "403" || exit 1
test "$(pide $GN sonda-ajena | awk '{print $NF}')" = "403" || exit 1
R2=$(pide bahia sonda-jefe)
test "$(echo "${R2% *}" | tr -d '\n')" = "$FICHA" || exit 1
echo ok
