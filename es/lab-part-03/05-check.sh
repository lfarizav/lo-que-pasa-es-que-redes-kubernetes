#!/usr/bin/env bash
# lab-part-03 step 5 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p02"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab2"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/05-respuesta.txt" || exit 1
for C in gateways httproutes gatewayclasses; do
  test "$($K get crd $C.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null)" = "v1.6.1" || exit 1
done
IMG=$($K -n istio-system get deployment istiod -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
test "${IMG##*:}" = "1.32.0" || exit 1
test "$($K -n istio-system get deployment istiod -o jsonpath='{.status.readyReplicas}')" = "1" || exit 1
$K get gatewayclass istio -o json | jq -e '.status.conditions[] | select(.type=="Accepted" and .status=="True")' >/dev/null || exit 1
GW=$($K -n cabina get gateway rampa -o json 2>/dev/null)
test -n "$GW" || exit 1
test "$(echo "$GW" | jq -r '.spec.gatewayClassName')" = "istio" || exit 1
echo "$GW" | jq -e '.status.conditions[] | select(.type=="Programmed" and .status=="True")' >/dev/null || exit 1
echo "$GW" | jq -e '[.spec.listeners[] | select(.port==80 and .protocol=="HTTP" and .hostname=="*.cabina.example" and ((.allowedRoutes.namespaces.from // "Same")=="Same"))] | length == 1' >/dev/null || exit 1
test "$($K -n cabina get service rampa-istio -o jsonpath='{.spec.type}' 2>/dev/null)" = "ClusterIP" || exit 1
GIP=$($K -n cabina get service rampa-istio -o jsonpath='{.spec.clusterIP}')
RT=$($K -n cabina get httproute meteo -o json 2>/dev/null)
test -n "$RT" || exit 1
echo "$RT" | jq -e '.spec.parentRefs[0].name=="rampa" and (.spec.hostnames==["meteo.cabina.example"]) and (.spec.rules[0].backendRefs[0].name=="meteo") and (.spec.rules[0].backendRefs[0].port==80)' >/dev/null || exit 1
echo "$RT" | jq -e '[.status.parents[].conditions[] | select((.type=="Accepted" or .type=="ResolvedRefs") and .status=="True")] | length == 2' >/dev/null || exit 1
VIVOS=$($K -n cabina get pods -l app=meteo -o jsonpath='{.items[*].metadata.name}')
SONDA="sonda-$RANDOM$RANDOM"
cat <<EOF | $K apply -f - >/dev/null || exit 1
apiVersion: v1
kind: Pod
metadata: {name: $SONDA, namespace: cabina}
spec:
  restartPolicy: Never
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sh","-c","echo A=\$(wget -qO- -T5 --header 'Host: meteo.cabina.example' http://$GIP/); wget -qO- -T5 --header 'Host: sin-ruta.cabina.example' http://$GIP/ 2>&1 | grep -o '404 Not Found' | head -1 | sed 's/^/B=/'"]
EOF
$K -n cabina wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
SALIDA=$($K -n cabina logs "$SONDA" 2>/dev/null)
$K -n cabina delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
A=$(echo "$SALIDA" | sed -n 's/^A=//p' | tr -d '\r')
test -n "$A" || exit 1
echo " $VIVOS " | grep -qF " $A " || exit 1
echo "$SALIDA" | grep -qxF "B=404 Not Found" || exit 1
grep -qxF "SERVICIO_DE_LA_ENTRADA=rampa-istio" "$D/05-respuesta.txt" || exit 1
grep -qxF "CLASE_DE_LA_ENTRADA=istio" "$D/05-respuesta.txt" || exit 1
grep -qxF "RUTA_ACEPTADA=True" "$D/05-respuesta.txt" || exit 1
echo ok
