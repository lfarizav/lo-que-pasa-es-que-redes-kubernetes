#!/usr/bin/env bash
# lab-part-06 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
test -f "$D/01-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre || exit 1
$K get nodes -o json 2>/dev/null | jq -e '(.items | length == 2) and ([.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 2) and ([.items[].status.nodeInfo.kubeletVersion] | all(. == "v1.37.0"))' >/dev/null || exit 1
$K -n kube-system get daemonset cilium -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q ':v1.20.5' || exit 1
test "$($K -n kube-system get daemonset cilium -o jsonpath='{.status.numberReady}' 2>/dev/null)" = "2" || exit 1
$K -n istio-system get deployment istiod -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q ':1.32.0' || exit 1
$K get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null | grep -qx 'v1.6.1' || exit 1
helm list -n vigilancia -o json --kubeconfig "$D/kubeconfig" --kube-context kind-ckne-lab6-torre 2>/dev/null | jq -e '.[0].chart=="prometheus-29.48.0"' >/dev/null || exit 1
$K -n faena get deployment bodega -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qx 1 || exit 1
test "$($K -n faena get gateway entrada-torre -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)" = "True" || exit 1
$K -n externo get pod sondeo -o jsonpath='{.status.phase}' 2>/dev/null | grep -qx Running || exit 1
q() { $K -n externo exec sondeo -- curl -s http://prometheus-server.vigilancia/api/v1/query --data-urlencode "query=$1" 2>/dev/null \
  | jq -r '.data.result[] | [(.metric | .[]), (.value[1] | tonumber * 1000 | round / 1000 | tostring)] | join(" ")'; }
KP=$(q 'count(up{job="kube-proxy"} == 1)')
test "$KP" = "2" || exit 1
for m in coredns_build_info cilium_version prometheus_build_info; do test "$(q "count($m)")" -ge 1 || exit 1; done
test "$(q 'count(istio_build)')" -ge 1 || exit 1
P=$(q 'count by (version) (prometheus_build_info)' | awk '{print $1}')
C=$(q 'count by (version) (coredns_build_info)' | awk '{print $1}')
test "$P" = "3.16.0" || exit 1
test -n "$C" || exit 1
# La configuracion de la malla declara los dos proveedores que usan los Pasos 5 y 7.
MESH=$($K -n istio-system get configmap istio -o jsonpath='{.data.mesh}' 2>/dev/null)
echo "$MESH" | grep -qE 'name: trazador$' || exit 1
echo "$MESH" | grep -q 'service: colector.registro.svc.cluster.local' || exit 1
echo "$MESH" | grep -qE 'port: 4317$' || exit 1
echo "$MESH" | grep -qE 'name: registro-json$' || exit 1
echo "$MESH" | grep -q 'path: /dev/stdout' || exit 1
for CL in respuesta bandera motivo nombre ruta traza ms; do echo "$MESH" | grep -qE "^ +$CL: " || exit 1; done
grep -qxF "PROMETHEUS=3.16.0" "$D/01-respuesta.txt" || exit 1
grep -qxF "COREDNS=$C" "$D/01-respuesta.txt" || exit 1
grep -qxF "CILIUM=1.20.5" "$D/01-respuesta.txt" || exit 1
grep -qxF "ISTIO=1.32.0" "$D/01-respuesta.txt" || exit 1
grep -qxF "OBJETIVOS_KUBE_PROXY=2" "$D/01-respuesta.txt" || exit 1
echo ok
