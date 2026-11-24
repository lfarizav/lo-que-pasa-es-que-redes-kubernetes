#!/usr/bin/env bash
# lab-part-06 step 5 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
test -f "$D/05-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre || exit 1
MARCA=$(cat "$D/marca.txt" 2>/dev/null)
test -n "$MARCA" || exit 1
T=$(sed -n 's/^TRAZA=//p' "$D/05-respuesta.txt")
echo "$T" | grep -Eqx '[0-9a-f]{32}' || exit 1
# La malla sigue trazando todo y escribiendo el registro de acceso con el proveedor del Paso 1.
$K -n istio-system get telemetry todo-el-trafico -o json 2>/dev/null | jq -e '(.spec.tracing[0].providers[0].name=="trazador") and (.spec.tracing[0].randomSamplingPercentage==100) and (.spec.accessLogging[0].providers[0].name=="registro-json") and (.spec.selector == null)' >/dev/null || exit 1
# paquetes es de la malla: su proxy va entre los contenedores de inicio.
$K -n trazado get pods -l app=paquetes -o json 2>/dev/null | jq -e '[.items[] | select(.status.phase=="Running") | [.spec.initContainers[]?.name] | index("istio-proxy") != null] | (length >= 1 and all)' >/dev/null || exit 1
# La linea del registro de la entrada para la peticion con la marca de esta corrida lleva ese numero de traza.
$K -n trazado logs deploy/entrada-trazas-istio 2>/dev/null | grep '^{' | jq -e -s --arg m "$MARCA" --arg t "$T" '[.[] | select((.ruta | endswith($m)) and .traza == $t and .respuesta == 200)] | length >= 1' >/dev/null || exit 1
# El sidecar de paquetes escribio su propia linea con el mismo numero.
$K -n trazado logs deploy/paquetes -c istio-proxy 2>/dev/null | grep '^{' | jq -e -s --arg t "$T" '[.[] | select(.traza == $t)] | length >= 1' >/dev/null || exit 1
# Jaeger guarda esa traza: un tramo raiz sin padre en la entrada y un tramo servidor de paquetes cuyo padre es un tramo cliente de la entrada.
J=$($K -n externo exec sondeo -- curl -s http://jaeger.registro:16686/api/v3/traces/$T 2>/dev/null)
S=$(echo "$J" | jq -c '[.result.resourceSpans[] | (.resource.attributes[] | select(.key=="service.name") | .value.stringValue) as $s | .scopeSpans[].spans[] | {s: $s, k: .kind, id: .spanId, p: (.parentSpanId // ""), t: .traceId}]' 2>/dev/null)
test -n "$S" || exit 1
N=$(echo "$S" | jq 'length')
R=$(echo "$S" | jq -r '[.[] | select(.p=="")] | if length==1 then .[0].id else "" end')
test -n "$R" || exit 1
echo "$S" | jq -e '. as $a | [.[] | select(.s=="paquetes.trazado" and .k==2) | .p as $p | $a[] | select(.id==$p and .k==3 and .s=="entrada-trazas-istio.trazado")] | length >= 1' >/dev/null || exit 1
grep -qxF "TRAMOS=$N" "$D/05-respuesta.txt" || exit 1
grep -qxF "TRAMO_RAIZ=$R" "$D/05-respuesta.txt" || exit 1
echo ok
