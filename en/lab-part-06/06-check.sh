#!/usr/bin/env bash
# lab-part-06 step 6 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
test -f "$D/.falla-aplicada" || exit 1
test -f "$D/06-diagnostico.txt" || exit 1
test "$D/06-diagnostico.txt" -nt "$D/.falla-aplicada" || exit 1
test -f "$D/06-respuesta.txt" || exit 1
CLAVE=$(cat "$D/.falla-clave" 2>/dev/null)
test -n "$CLAVE" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre || exit 1
# El diagnostico es de esta falla: el codigo del cliente, la linea del registro con su bandera y su motivo, y el objeto que la explica.
grep -q '^== 1\.' "$D/06-diagnostico.txt" || exit 1
grep -q '^== 2\.' "$D/06-diagnostico.txt" || exit 1
grep -q '^== 3\.' "$D/06-diagnostico.txt" || exit 1
sed -n '/^== 1\./,/^== 2\./p' "$D/06-diagnostico.txt" | grep -qw 503 || exit 1
L=$(sed -n '/^== 2\./,/^== 3\./p' "$D/06-diagnostico.txt" | grep '^{' | tail -1)
echo "$L" | jq -e '(.nombre=="consigna.torre.test") and (.respuesta==503) and (.bandera=="UH") and (.motivo=="no_healthy_upstream")' >/dev/null 2>&1 || exit 1
# Esa linea existe de verdad en el registro de la entrada: la misma traza, con el 503 y el nombre de consigna.
TRZ=$(echo "$L" | jq -r '.traza // empty')
test -n "$TRZ" || exit 1
test "$TRZ" != "-" || exit 1
$K -n trazado logs deploy/entrada-trazas-istio 2>/dev/null | grep '^{' | jq -e --arg t "$TRZ" 'select((.traza==$t) and (.respuesta==503) and (.nombre=="consigna.torre.test") and (.bandera=="UH"))' >/dev/null 2>&1 || exit 1
sed -n '/^== 3\./,$p' "$D/06-diagnostico.txt" | grep -qF "$CLAVE" || exit 1
# La Service es la misma que se rompio, no una nueva, y ahora lleva a los Pods de consigna.
SVC=$($K -n trazado get service consigna -o json 2>/dev/null)
test -n "$SVC" || exit 1
test "$(echo "$SVC" | jq -r '.metadata.uid')" = "$(cat "$D/.falla-uid" 2>/dev/null)" || exit 1
echo "$SVC" | jq -e '(.spec.selector=={"app":"consigna"}) and (.spec.ports[0].port==80) and (.spec.ports[0].targetPort==8080)' >/dev/null || exit 1
# El Deployment y la ruta siguen como los dejo la falla.
$K -n trazado get deployment consigna -o json 2>/dev/null | jq -e '(.spec.replicas==1) and (.spec.template.metadata.labels=={"app":"consigna"}) and (.spec.template.spec.containers[0].image=="mccutchen/go-httpbin:2.26.0") and (.status.readyReplicas==1)' >/dev/null || exit 1
$K -n trazado get httproute ruta-consigna -o json 2>/dev/null | jq -e '(.spec.parentRefs[0].name=="entrada-trazas") and (.spec.hostnames==["consigna.torre.test"]) and (.spec.rules[0].backendRefs==[{"group":"","kind":"Service","name":"consigna","port":80,"weight":1}])' >/dev/null || exit 1
$K -n trazado get endpointslices -l kubernetes.io/service-name=consigna -o json 2>/dev/null | jq -e '[.items[].endpoints[]? | select(.conditions.ready==true) | .targetRef.name | startswith("consigna-")] | (length >= 1 and all)' >/dev/null || exit 1
test "$($K -n externo exec sondeo -- curl -s -o /dev/null -m 5 -w '%{http_code}' -H 'Host: consigna.torre.test' http://entrada-trazas-istio.trazado/get 2>/dev/null)" = "200" || exit 1
grep -qxF "CODIGO_DEL_CLIENTE=503" "$D/06-respuesta.txt" || exit 1
grep -qxF "BANDERA=UH" "$D/06-respuesta.txt" || exit 1
grep -qxF "MOTIVO=no_healthy_upstream" "$D/06-respuesta.txt" || exit 1
grep -qxF "OBJETO_REPARADO=service/consigna" "$D/06-respuesta.txt" || exit 1
grep -qxF "VALOR_QUE_LA_FALLA_DEJO=app=$CLAVE" "$D/06-respuesta.txt" || exit 1
echo ok
