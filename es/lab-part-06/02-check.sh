#!/usr/bin/env bash
# lab-part-06 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
test -f "$D/02-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre || exit 1
. "$D/pedido.txt"
q() { $K -n externo exec sondeo -- curl -s http://prometheus-server.vigilancia/api/v1/query --data-urlencode "query=$1" 2>/dev/null \
  | jq -r '.data.result[] | [(.metric | .[]), (.value[1] | tonumber * 1000 | round / 1000 | tostring)] | join(" ")'; }
M=$(q 'sum by (response_code) (istio_requests_total{reporter="source",destination_service_name="bodega"})')
A=$(echo "$M" | awk '$1=="200" {print $2}')
B=$(echo "$M" | awk '$1=="503" {print $2}')
# Los contadores de la entrada tienen que decir exactamente lo que el pedido mando, ni una peticion de mas ni de menos.
test "$A" = "$PEDIDO_200" || exit 1
test "$B" = "$PEDIDO_503" || exit 1
test "$(echo "$M" | wc -l)" = "2" || exit 1
R=$(awk -v a="$A" -v b="$B" 'BEGIN {printf "%.3f", b/(a+b)}')
grep -qxF "PETICIONES_200=$A" "$D/02-respuesta.txt" || exit 1
grep -qxF "PETICIONES_503=$B" "$D/02-respuesta.txt" || exit 1
grep -qxF "RAZON_DE_ERRORES=$R" "$D/02-respuesta.txt" || exit 1
echo ok
