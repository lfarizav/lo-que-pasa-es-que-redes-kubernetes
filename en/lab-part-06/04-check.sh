#!/usr/bin/env bash
# lab-part-06 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
test -f "$D/04-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre || exit 1
. "$D/pedido.txt"
q() { $K -n externo exec sondeo -- curl -s http://prometheus-server.vigilancia/api/v1/query --data-urlencode "query=$1" 2>/dev/null \
  | jq -r '.data.result[] | [(.metric | .[]), (.value[1] | tonumber * 1000 | round / 1000 | tostring)] | join(" ")'; }
# La bascula sigue detras de la misma entrada, con su propio nombre.
$K -n faena get deployment pesaje -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qx 1 || exit 1
$K -n faena get httproute ruta-pesaje -o json 2>/dev/null | jq -e '(.spec.parentRefs[0].name=="entrada-torre") and (.spec.hostnames==["pesaje.torre.test"]) and (.spec.rules[0].backendRefs[0].name=="pesaje")' >/dev/null || exit 1
C=$(q 'sum by (le) (istio_request_duration_milliseconds_bucket{reporter="source",destination_service_name="pesaje"})')
H1=$(echo "$C" | awk '$1=="1000.0" {print $2}')
H2=$(echo "$C" | awk '$1=="2500.0" {print $2}')
T=$(echo "$C" | awk '$1=="+Inf" {print $2}')
# Las cubetas tienen que contar exactamente el pesaje de esta corrida: las rapidas hasta 1000 ms y las lentas entre 1000 y 2500.
test "$H1" = "$PESAJES_RAPIDOS" || exit 1
test "$T" = "$((PESAJES_RAPIDOS + PESAJES_LENTOS))" || exit 1
test "$((H2 - H1))" = "$PESAJES_LENTOS" || exit 1
grep -qxF "HASTA_1000_MS=$H1" "$D/04-respuesta.txt" || exit 1
grep -qxF "HASTA_2500_MS=$H2" "$D/04-respuesta.txt" || exit 1
grep -qxF "ENTRE_1000_Y_2500_MS=$((H2 - H1))" "$D/04-respuesta.txt" || exit 1
grep -qxF "OBSERVACIONES=$T" "$D/04-respuesta.txt" || exit 1
echo ok
