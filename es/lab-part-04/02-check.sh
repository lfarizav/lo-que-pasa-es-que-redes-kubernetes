#!/usr/bin/env bash
# lab-part-04 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c
test -f "$D/.falla-aplicada" || exit 1
test -f "$D/02-diagnostico.txt" || exit 1
test "$D/02-diagnostico.txt" -nt "$D/.falla-aplicada" || exit 1
test -f "$D/02-respuesta.txt" || exit 1
OCU=$($K -n imprenta get deployment redactor-ocupado -o json 2>/dev/null)
echo "$OCU" | jq -e '.spec.replicas==1 and .status.readyReplicas==1 and (.spec.template.metadata.labels=={"app":"redactor-ocupado","grupo":"redaccion"}) and (.spec.template.spec.containers[0].args | join(" ") | test("\"waiting-requests\":30"))' >/dev/null || exit 1
test "$($K -n imprenta get deployment redactor -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "2" || exit 1
POOL=$($K -n imprenta get inferencepool redaccion -o json 2>/dev/null)
test -n "$POOL" || exit 1
SEL=$(echo "$POOL" | jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')
test -n "$SEL" || exit 1
ELEGIDOS=$($K -n imprenta get pods -l "$SEL" -o json 2>/dev/null | jq -c '[.items[] | select(.status.phase=="Running" and .metadata.deletionTimestamp==null) | .metadata.labels.app] | sort')
test "$ELEGIDOS" = '["redactor","redactor","redactor-ocupado"]' || exit 1
echo "$POOL" | jq -e '.spec.endpointPickerRef.name=="elector" and ([.status.parents[].conditions[] | select((.type=="Accepted" or .type=="ResolvedRefs") and .status=="True")] | length == 2)' >/dev/null || exit 1
test "$($K -n imprenta get deployment elector -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
$K -n imprenta get httproute por-el-grupo -o json 2>/dev/null | jq -e '.spec.rules[0].backendRefs[0].kind=="InferencePool" and .spec.rules[0].backendRefs[0].name=="redaccion"' >/dev/null || exit 1
PODS=$($K -n imprenta get pods -l grupo=redaccion -o json)
OCUPADO=$(echo "$PODS" | jq -r '[.items[] | select(.metadata.labels.app=="redactor-ocupado")][0].metadata.name')
OIP=$(echo "$PODS" | jq -r '[.items[] | select(.metadata.labels.app=="redactor-ocupado")][0].status.podIP')
LIBRES=$(echo "$PODS" | jq -r '[.items[] | select(.metadata.labels.app=="redactor") | .metadata.name] | join(" ")')
# El diagnostico tiene que ser de este cluster y de la falla: el elector solo puntuo al ocupado
# y el Envoy recibio un solo extremo para el grupo, el del ocupado.
PUNT=$(sed -n '/^== 1\./,/^== 2\./p' "$D/02-diagnostico.txt")
echo "$PUNT" | grep -qE "^queue $OCUPADO [0-9]+$" || exit 1
for L in $LIBRES; do echo "$PUNT" | grep -qF " $L " && exit 1; done
ENV=$(sed -n '/^== 2\./,/^== 3\./p' "$D/02-diagnostico.txt" | grep -F 'redaccion-ip')
test "$(echo "$ENV" | grep -c .)" = "1" || exit 1
echo "$ENV" | grep -qE "^$OIP:8000 " || exit 1
GIP=$($K -n imprenta get service portico-istio -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
test -n "$GIP" || exit 1
sonda() { # host repeticiones
  local S="sonda-$RANDOM$RANDOM"
  local P="for i in \$(seq $2); do curl -s -m 5 -o /dev/null -w '%header{x-inference-pod} %{http_code}\n' -H 'Host: $1' -d '{\"model\":\"redaccion\",\"prompt\":\"sonda\"}' http://$GIP/v1/completions; done"
  $K -n imprenta run "$S" --image=$CURL --restart=Never --command -- sh -c "$P" >/dev/null 2>&1 || return 1
  $K -n imprenta wait --for=jsonpath='{.status.phase}'=Succeeded pod/$S --timeout=120s >/dev/null 2>&1
  $K -n imprenta logs "$S" 2>/dev/null
  $K -n imprenta delete pod "$S" --ignore-not-found >/dev/null 2>&1
}
G=$(sonda grupo.imprenta.example 16)
test "$(echo "$G" | grep -c ' 200$')" = "16" || exit 1
echo "$G" | grep -qF "$OCUPADO" && exit 1
for L in $LIBRES; do echo "$G" | grep -qF "$L " || exit 1; done
S=$(sonda service.imprenta.example 24)
echo "$S" | grep -qF "$OCUPADO " || exit 1
grep -qxF "POD_QUE_RECIBIA_TODO=$OCUPADO" "$D/02-respuesta.txt" || exit 1
grep -qxF "PODS_PUNTUADOS_DURANTE_LA_FALLA=1" "$D/02-respuesta.txt" || exit 1
grep -qxF "OBJETO_CON_LA_FALLA=InferencePool" "$D/02-respuesta.txt" || exit 1
grep -qxF "CAMPO_CON_LA_FALLA=selector" "$D/02-respuesta.txt" || exit 1
echo ok
