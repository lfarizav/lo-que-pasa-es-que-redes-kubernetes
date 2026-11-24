#!/usr/bin/env bash
# lab-part-01 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p00"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab0"
test -f "$D/02-respuesta.txt" || exit 1
DS=$($K -n kube-system get daemonset calico-node -o json 2>/dev/null)
test -n "$DS" || exit 1
test "$(echo "$DS" | jq '.status.desiredNumberScheduled')" -eq 3 || exit 1
test "$(echo "$DS" | jq '.status.numberReady')" -eq 3 || exit 1
IMG=$(echo "$DS" | jq -r '.spec.template.spec.containers[0].image')
case "$IMG" in *:v3.33.0) ;; *) exit 1;; esac
test "$($K -n kube-system get deployment calico-kube-controllers -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
test "$(echo "$NODOS" | jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length')" -eq 3 || exit 1
CP=$($K -n kube-system get pods -l k8s-app=calico-node -o json 2>/dev/null)
echo "$CP" | jq -e '(.items | length == 3) and ([.items[].spec.nodeName] | unique | length == 3) and all(.items[]; .status.phase == "Running" and (all(.status.containerStatuses[]; .ready == true)) and (.spec.containers[0].image | endswith(":v3.33.0")))' >/dev/null || exit 1
PODSUBNET=$($K -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | awk '/podSubnet:/{print $2}')
test "$PODSUBNET" = "192.168.0.0/16" || exit 1
POOLS=$($K get ippools.crd.projectcalico.org -o json 2>/dev/null | jq -r '[.items[].spec.cidr] | join(" ")')
test "$POOLS" = "$PODSUBNET" || exit 1
for N in ckne-lab0-control-plane ckne-lab0-worker ckne-lab0-worker2; do
  docker exec "$N" test -f /etc/cni/net.d/10-calico.conflist || exit 1
done
$K -n kube-system get daemonset kindnet >/dev/null 2>&1 && exit 1
DNSPODS=$($K -n kube-system get pods -l k8s-app=kube-dns -o json 2>/dev/null)
test "$(echo "$DNSPODS" | jq '[.items[] | select(.status.phase == "Running")] | length')" -ge 2 || exit 1
echo "$DNSPODS" | jq -e 'all(.items[]; (.status.podIP | startswith("192.168.")))' >/dev/null || exit 1
grep -qxF "VERSION_DE_CALICO=${IMG##*:}" "$D/02-respuesta.txt" || exit 1
grep -qxF "POOL_DE_IPS=$POOLS" "$D/02-respuesta.txt" || exit 1
grep -qxF "NODOS_LISTOS=3" "$D/02-respuesta.txt" || exit 1
echo ok
