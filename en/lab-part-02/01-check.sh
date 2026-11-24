#!/usr/bin/env bash
# lab-part-02 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab1"
test -f "$D/01-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab1 || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
test "$(echo "$NODOS" | jq '.items | length')" -eq 3 || exit 1
echo "$NODOS" | jq -e '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 3' >/dev/null || exit 1
echo "$NODOS" | jq -e '[.items[].status.nodeInfo.kubeletVersion] | unique == ["v1.37.0"]' >/dev/null || exit 1
$K -n kube-system get daemonset kindnet >/dev/null 2>&1 && exit 1
IMG=$($K -n kube-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
test "${IMG##*:}" = "v3.33.0" || exit 1
$K -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
POOL=$($K get ippools.crd.projectcalico.org -o json 2>/dev/null)
test "$(echo "$POOL" | jq -r '.items[0].spec.cidr')" = "192.168.0.0/16" || exit 1
test "$(echo "$POOL" | jq -r '.items[0].spec.ipipMode')" = "Always" || exit 1
for N in ckne-lab1-control-plane ckne-lab1-worker ckne-lab1-worker2; do
  docker exec "$N" tcpdump --version >/dev/null 2>&1 || exit 1
done
grep -qxF "VERSION_DE_CALICO=v3.33.0" "$D/01-respuesta.txt" || exit 1
grep -qxF "NODOS_LISTOS=3" "$D/01-respuesta.txt" || exit 1
grep -qxF "POOL_DE_IPS=192.168.0.0/16" "$D/01-respuesta.txt" || exit 1
grep -qxF "MODO_IPIP=Always" "$D/01-respuesta.txt" || exit 1
echo ok
