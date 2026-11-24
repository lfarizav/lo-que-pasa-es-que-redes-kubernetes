#!/usr/bin/env bash
# lab-part-03 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p02"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab2"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/01-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab2 || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
test "$(echo "$NODOS" | jq '.items | length')" -eq 3 || exit 1
echo "$NODOS" | jq -e '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 3' >/dev/null || exit 1
echo "$NODOS" | jq -e '[.items[].status.nodeInfo.kubeletVersion] | unique == ["v1.37.0"]' >/dev/null || exit 1
$K -n kube-system get daemonset kindnet >/dev/null 2>&1 && exit 1
IMG=$($K -n kube-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
test "${IMG##*:}" = "v3.33.0" || exit 1
DEP=$($K -n cabina get deployment meteo -o json 2>/dev/null)
test -n "$DEP" || exit 1
test "$(echo "$DEP" | jq -r '.spec.replicas')" = "3" || exit 1
test "$(echo "$DEP" | jq -r '.status.readyReplicas // 0')" = "3" || exit 1
echo "$DEP" | jq -e '.spec.template.spec.containers[0].readinessProbe != null' >/dev/null || exit 1
echo "$DEP" | jq -e '.spec.template.spec.hostNetwork != true' >/dev/null || exit 1
$K -n cabina get pod piloto -o jsonpath='{.status.phase}' | grep -qx Running || exit 1
SVC=$($K -n cabina get service meteo -o json 2>/dev/null)
test -n "$SVC" || exit 1
test "$(echo "$SVC" | jq -r '.spec.type')" = "ClusterIP" || exit 1
test "$(echo "$SVC" | jq -c '.spec.selector')" = '{"app":"meteo"}' || exit 1
test "$(echo "$SVC" | jq -r '.spec.ports[0].port')" = "80" || exit 1
CIP=$(echo "$SVC" | jq -r '.spec.clusterIP')
EPS=$($K -n cabina get endpointslice -l kubernetes.io/service-name=meteo -o json 2>/dev/null)
LISTOS=$(echo "$EPS" | jq '[.items[].endpoints[] | select(.conditions.ready==true)] | length')
test "$LISTOS" = "3" || exit 1
echo "$EPS" | jq -e '[.items[].ports[] | select(.port==8080)] | length >= 1' >/dev/null || exit 1
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
    command: ["wget","-qO-","-T5","http://$CIP/"]
EOF
$K -n cabina wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
R=$($K -n cabina logs "$SONDA" 2>/dev/null | tr -d '\r\n')
$K -n cabina delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
test -n "$R" || exit 1
echo " $VIVOS " | grep -qF " $R " || exit 1
grep -qxF "CLUSTER_IP_DE_METEO=$CIP" "$D/01-respuesta.txt" || exit 1
grep -qxF "EXTREMOS_LISTOS=3" "$D/01-respuesta.txt" || exit 1
grep -qxF "PUERTO_DE_LOS_EXTREMOS=8080" "$D/01-respuesta.txt" || exit 1
echo ok
