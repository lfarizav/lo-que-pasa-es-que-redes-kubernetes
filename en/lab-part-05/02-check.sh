#!/usr/bin/env bash
# lab-part-05 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-red"
test -f "$D/02-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab5-red || exit 1
test "$($K get namespace verbena -o jsonpath='{.metadata.labels.zona}' 2>/dev/null)" = "verbena" || exit 1
test "$($K -n verbena get deployment mostrario -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
test "$($K -n verbena get service mostrario -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" = "80" || exit 1
# La NetworkPolicy que abre a todos tiene que seguir intacta: el cierre lo pone la capa del administrador.
$K -n verbena get networkpolicy abre-a-todos -o json 2>/dev/null | jq -e '(.spec.podSelector=={}) and (.spec.policyTypes==["Ingress"]) and (.spec.ingress==[{}])' >/dev/null || exit 1
test "$($K -n verbena get networkpolicy -o name 2>/dev/null | wc -l)" = "1" || exit 1
CNP=$($K get clusternetworkpolicy cierre-de-afuera -o json 2>/dev/null)
test -n "$CNP" || exit 1
echo "$CNP" | jq -e '.spec.tier=="Admin" and (.spec.priority==10) and (.spec.subject.namespaces.matchLabels=={"zona":"verbena"}) and (.spec.ingress | length==1) and (.spec.ingress[0].action=="Deny") and (.spec.ingress[0].from[0].namespaces.matchLabels=={"zona":"afuera"})' >/dev/null || exit 1
for ns in maestranza afuera; do
  test "$($K get namespace $ns -o jsonpath='{.metadata.labels.zona}' 2>/dev/null)" = "$ns" || exit 1
done
cod() { $K -n "$1" exec "$2" -- curl -s -m 3 -o /dev/null -w "%{http_code}" http://mostrario.verbena/ 2>/dev/null; }
test "$(cod maestranza operario)" = "200" || exit 1
test "$(cod afuera operario)" != "200" || exit 1
grep -qxF "NIVEL=Admin" "$D/02-respuesta.txt" || exit 1
grep -qxF "ACCION=Deny" "$D/02-respuesta.txt" || exit 1
grep -qxF "NETWORKPOLICY_INTACTA=si" "$D/02-respuesta.txt" || exit 1
echo ok
