#!/usr/bin/env bash
# lab-part-05 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-red"
test -f "$D/01-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab5-red || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
test "$(echo "$NODOS" | jq '.items | length')" -eq 2 || exit 1
echo "$NODOS" | jq -e '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 2' >/dev/null || exit 1
echo "$NODOS" | jq -e '[.items[].status.nodeInfo.kubeletVersion] | all(. == "v1.37.0")' >/dev/null || exit 1
$K -n kube-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q ':v3.33.1' || exit 1
test "$($K -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null)" = "2" || exit 1
for ns in deposito maestranza afuera; do
  test "$($K get namespace $ns -o jsonpath='{.metadata.labels.zona}' 2>/dev/null)" = "$ns" || exit 1
done
test "$($K -n deposito get deployment existencias -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
test "$($K -n deposito get service existencias -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" = "80" || exit 1
test "$($K -n maestranza get pod operario -o jsonpath='{.metadata.labels.rol}' 2>/dev/null)" = "operario" || exit 1
test "$($K -n maestranza get pod novato -o jsonpath='{.metadata.labels.rol}' 2>/dev/null)" = "novato" || exit 1
test "$($K -n afuera get pod operario -o jsonpath='{.metadata.labels.rol}' 2>/dev/null)" = "operario" || exit 1
for p in maestranza/operario maestranza/novato afuera/operario; do
  test "$($K -n ${p%/*} get pod ${p#*/} -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" || exit 1
done
test "$($K -n deposito get networkpolicy -o name 2>/dev/null | wc -l)" -ge 1 || exit 1
# El reparto se mide en vivo: cada Pod pide la Service y se mira el codigo.
cod() { $K -n "$1" exec "$2" -- curl -s -m 3 -o /dev/null -w "%{http_code}" http://existencias.deposito/ 2>/dev/null; }
test "$(cod maestranza operario)" = "200" || exit 1
test "$(cod maestranza novato)" != "200" || exit 1
test "$(cod afuera operario)" != "200" || exit 1
grep -qxF "PASA=maestranza/operario" "$D/01-respuesta.txt" || exit 1
grep -qxF "SIN_RESPUESTA=afuera/operario,maestranza/novato" "$D/01-respuesta.txt" || exit 1
echo ok
