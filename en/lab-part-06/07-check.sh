#!/usr/bin/env bash
# lab-part-06 step 7 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
FICHA=$(cat "$D/ficha-de-la-bitacora.txt" 2>/dev/null)
test -n "$FICHA" || exit 1
test "$(echo -n "$FICHA" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.ficha.sha256" 2>/dev/null)" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre || exit 1
# La Telemetry de toda la malla sigue como la dejo el Paso 5.
$K -n istio-system get telemetry todo-el-trafico -o json 2>/dev/null | jq -e '(.spec.tracing[0].providers[0].name=="trazador") and (.spec.tracing[0].randomSamplingPercentage==100) and (.spec.accessLogging[0].providers[0].name=="registro-json") and (.spec.selector == null)' >/dev/null || exit 1
SIETE='["bandera","motivo","ms","nombre","respuesta","ruta","traza"]'
OCHO='["bandera","ficha","motivo","ms","nombre","respuesta","ruta","traza"]'
pide() { # host ruta ficha
  $K -n externo exec sondeo -- curl -s -o /dev/null -m 5 -w '%{http_code}' -H "Host: $1" -H "x-ficha: $3" "http://entrada-trazas-istio.trazado$2" 2>/dev/null
}
linea() { # espacio deployment contenedor ruta -> la ultima linea JSON de esa ruta
  $K -n "$1" logs "deploy/$2" ${3:+-c $3} --since=10m 2>/dev/null | grep '^{' | jq -c --arg r "$4" 'select(.ruta == $r)' 2>/dev/null | tail -1
}
# 1. Una ficha nueva de la comprobacion: el proxy de paquetes la escribe con las ocho claves. Se repite con el tiempo a la vista.
OK=0
for i in $(seq 18); do
  G="sonda-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  test "$(pide paquetes.torre.test /anything/$G $G)" = "200" || { sleep 5; continue; }
  sleep 4
  L=$(linea trazado paquetes istio-proxy /anything/$G)
  if echo "$L" | jq -e --arg g "$G" --argjson k "$OCHO" '(keys==$k) and (.ficha==$g) and (.respuesta==200)' >/dev/null 2>&1; then OK=1; break; fi
  sleep 5
done
test "$OK" = 1 || exit 1
# 2. La misma peticion, en la entrada: siete claves, sin ficha.
L=$(linea trazado entrada-trazas-istio "" /anything/$G)
echo "$L" | jq -e --argjson k "$SIETE" 'keys==$k' >/dev/null 2>&1 || exit 1
# 3. consigna, de la misma malla y del mismo espacio, tampoco escribe la ficha.
C="consigna-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
test "$(pide consigna.torre.test /anything/$C $C)" = "200" || exit 1
sleep 4
L=$(linea trazado consigna istio-proxy /anything/$C)
echo "$L" | jq -e --argjson k "$SIETE" 'keys==$k' >/dev/null 2>&1 || exit 1
L=$(linea trazado entrada-trazas-istio "" /anything/$C)
echo "$L" | jq -e --argjson k "$SIETE" 'keys==$k' >/dev/null 2>&1 || exit 1
# 4. La otra entrada, la del Paso 1, tampoco. El nombre no tiene ruta (404), asi la sonda no suma a los contadores de los Pasos 2 y 4.
P="torre-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
test "$($K -n externo exec sondeo -- curl -s -o /dev/null -m 5 -w '%{http_code}' -H 'Host: sin-ruta.torre.test' -H "x-ficha: $P" "http://entrada-torre-istio.faena/anything/$P" 2>/dev/null)" = "404" || exit 1
sleep 4
L=$(linea faena entrada-torre-istio "" /anything/$P)
echo "$L" | jq -e --argjson k "$SIETE" 'keys==$k' >/dev/null 2>&1 || exit 1
# 5. La peticion de usted: una linea del proxy de paquetes con la ficha de esta corrida, y su traza en Jaeger con un tramo de paquetes.
T=$($K -n trazado logs deploy/paquetes -c istio-proxy 2>/dev/null | grep '^{' | jq -r --arg f "$FICHA" 'select(.ficha == $f and .respuesta == 200) | .traza' 2>/dev/null | tail -1)
echo "$T" | grep -Eqx '[0-9a-f]{32}' || exit 1
$K -n externo exec sondeo -- curl -s http://jaeger.registro:16686/api/v3/traces/$T 2>/dev/null \
  | jq -e '[.result.resourceSpans[] | select(any(.resource.attributes[]; .key=="service.name" and .value.stringValue=="paquetes.trazado"))] | length >= 1' >/dev/null || exit 1
echo ok
