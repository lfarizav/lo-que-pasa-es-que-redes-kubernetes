#!/usr/bin/env bash
# lab-part-06 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
test -f "$D/03-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre || exit 1
. "$D/pedido.txt"
q() { $K -n externo exec sondeo -- curl -s http://prometheus-server.vigilancia/api/v1/query --data-urlencode "query=$1" 2>/dev/null \
  | jq -r '.data.result[] | [(.metric | .[]), (.value[1] | tonumber * 1000 | round / 1000 | tostring)] | join(" ")'; }
# La politica ya no esta y la aplicacion contesta: lo que se mide es lo que quedo en los contadores.
test "$($K -n faena get networkpolicy -o name 2>/dev/null | wc -l)" = "0" || exit 1
test "$($K -n externo exec sondeo -- curl -s -o /dev/null -m 3 -w '%{http_code}' http://bodega.faena/get 2>/dev/null)" = "200" || exit 1
N=$(q 'sum(cilium_drop_count_total{direction="INGRESS",reason="Policy denied"})')
test -n "$N" || exit 1
# Cada intento deja al menos una caida: no puede haber menos caidas que intentos.
awk -v n="$N" -v i="$INTENTOS_BLOQUEADOS" 'BEGIN {exit !(n >= i)}' || exit 1
grep -qxF "CAIDAS_ENTRANTES_NEGADAS=$N" "$D/03-respuesta.txt" || exit 1
grep -qxF "CODIGO_SIN_LA_POLITICA=200" "$D/03-respuesta.txt" || exit 1
echo ok
