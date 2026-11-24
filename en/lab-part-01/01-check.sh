#!/usr/bin/env bash
# lab-part-01 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p00"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab0"
test -f "$D/01-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab0 || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
test "$(echo "$NODOS" | jq '.items | length')" -eq 3 || exit 1
test "$(echo "$NODOS" | jq '[.items[] | select(.metadata.labels["node-role.kubernetes.io/control-plane"] != null)] | length')" -eq 1 || exit 1
echo "$NODOS" | jq -e '[.items[].status.nodeInfo.kubeletVersion] | unique == ["v1.37.0"]' >/dev/null || exit 1
CFG=$($K -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null)
PODSUBNET=$(echo "$CFG" | awk '/podSubnet:/{print $2}')
SVCSUBNET=$(echo "$CFG" | awk '/serviceSubnet:/{print $2}')
test "$PODSUBNET" = "192.168.0.0/16" || exit 1
test "$SVCSUBNET" = "10.100.0.0/16" || exit 1
echo "$NODOS" | jq -e '[.items[].spec.podCIDR] | (length == 3) and (unique | length == 3) and all(.[]; startswith("192.168."))' >/dev/null || exit 1
$K -n kube-system get daemonset kindnet >/dev/null 2>&1 && exit 1
$K -n kube-system get daemonset kube-proxy >/dev/null 2>&1 || exit 1
for N in ckne-lab0-control-plane ckne-lab0-worker ckne-lab0-worker2; do
  docker exec "$N" sh -c 'ls /etc/cni/net.d 2>/dev/null' | grep -qi kindnet && exit 1
done
docker exec ckne-lab0-control-plane grep -q -e '--cluster-cidr=192.168.0.0/16' /etc/kubernetes/manifests/kube-controller-manager.yaml || exit 1
docker exec ckne-lab0-control-plane grep -q -e '--service-cluster-ip-range=10.100.0.0/16' /etc/kubernetes/manifests/kube-apiserver.yaml || exit 1
for P in kube-apiserver-ckne-lab0-control-plane kube-controller-manager-ckne-lab0-control-plane etcd-ckne-lab0-control-plane kube-scheduler-ckne-lab0-control-plane; do
  test "$($K -n kube-system get pod $P -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" || exit 1
done
test "$(kubectl --kubeconfig $D/kubeconfig config current-context)" = "kind-ckne-lab0" || exit 1
PCW=$($K get node ckne-lab0-worker -o jsonpath='{.spec.podCIDR}')
grep -qxF "PODSUBNET=$PODSUBNET" "$D/01-respuesta.txt" || exit 1
grep -qxF "SERVICESUBNET=$SVCSUBNET" "$D/01-respuesta.txt" || exit 1
grep -qxF "NODOS=3" "$D/01-respuesta.txt" || exit 1
grep -qxF "PODCIDR_DEL_TRABAJADOR=$PCW" "$D/01-respuesta.txt" || exit 1
echo ok
