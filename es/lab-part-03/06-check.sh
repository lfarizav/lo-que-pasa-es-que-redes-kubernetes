#!/usr/bin/env bash
# lab-part-03 step 6 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p02"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab2"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
for F in ficha anfitrion ruta; do test -f "$D/$F-del-deposito.txt" || exit 1; done
FICHA=$(tr -d '\r\n' < "$D/ficha-del-deposito.txt")
HOSTN=$(tr -d '\r\n' < "$D/anfitrion-del-deposito.txt")
RUTA=$(tr -d '\r\n' < "$D/ruta-del-deposito.txt")
test -n "$FICHA" && test -n "$HOSTN" && test -n "$RUTA" || exit 1
test "$(printf %s "$FICHA" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.ficha.sha256")" || exit 1
test "$(printf %s "$HOSTN" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.anfitrion.sha256")" || exit 1
test "$(printf %s "$RUTA" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.ruta.sha256")" || exit 1
GW=$($K -n cabina get gateway rampa -o json 2>/dev/null)
test -n "$GW" || exit 1
echo "$GW" | jq -e '[.spec.listeners[]] | length == 1' >/dev/null || exit 1
echo "$GW" | jq -e '.spec.listeners[0] | .port==80 and .hostname=="*.cabina.example" and ((.allowedRoutes.namespaces.from // "Same")=="Same")' >/dev/null || exit 1
PSVC=$($K -n deposito get service planilla -o json 2>/dev/null)
test -n "$PSVC" || exit 1
echo "$PSVC" | jq -e '.spec.type=="ClusterIP" and ((.spec.clusterIP // "None") != "None") and ((.spec.selector // {}) | length > 0) and any(.spec.ports[]; .port==80)' >/dev/null || exit 1
SEL=$(echo "$PSVC" | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')
PODS=$($K -n deposito get pods -l "$SEL" -o json 2>/dev/null | jq -c '[.items[] | select(.status.phase=="Running") | {n: .metadata.name, ip: .status.podIP}]')
test -n "$PODS" || exit 1
$K -n deposito get endpointslice -l kubernetes.io/service-name=planilla -o json 2>/dev/null | jq -e --argjson p "$PODS" '[.items[].endpoints[]? | select(.conditions.ready==true and .targetRef.kind=="Pod" and ((.targetRef.namespace // "deposito")=="deposito")) | {n: .targetRef.name, ip: .addresses[0]} | select(. as $e | any($p[]; . == $e))] | length >= 1' >/dev/null || exit 1
RT=$($K -n cabina get httproute planilla -o json 2>/dev/null)
test -n "$RT" || exit 1
echo "$RT" | jq -e --arg h "$HOSTN" '.spec.parentRefs[0].name=="rampa" and ((.spec.parentRefs[0].namespace // "cabina")=="cabina") and (.spec.hostnames | index($h) != null)' >/dev/null || exit 1
echo "$RT" | jq -e --arg r "$RUTA" '[.spec.rules[] | select(any(.matches[]?; .path.type=="PathPrefix" and .path.value==$r)) | .backendRefs[]? | select(.name=="planilla" and .namespace=="deposito" and .port==80)] | length >= 1' >/dev/null || exit 1
echo "$RT" | jq -e '[.status.parents[].conditions[] | select((.type=="Accepted" or .type=="ResolvedRefs") and .status=="True")] | length == 2' >/dev/null || exit 1
GIP=$($K -n cabina get service rampa-istio -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
test -n "$GIP" || exit 1
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
    command: ["sh","-c","wget -qO- -T5 --header 'Host: $HOSTN' http://$GIP$RUTA; true"]
EOF
$K -n cabina wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
RESP=$($K -n cabina logs "$SONDA" 2>/dev/null | tr -d '\r\n')
$K -n cabina delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
test "$RESP" = "$FICHA" || exit 1
$K -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
echo ok
