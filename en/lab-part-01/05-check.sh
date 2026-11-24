#!/usr/bin/env bash
# lab-part-01 step 5 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p00"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab0"
NS=torre
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/ficha-de-vuelo.txt" || exit 1
FICHA=$(tr -d '\r\n' < "$D/ficha-de-vuelo.txt")
test -n "$FICHA" || exit 1
test "$(printf %s "$FICHA" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.ficha.sha256")" || exit 1
SVC=$($K -n $NS get svc radar -o json 2>/dev/null)
test -n "$SVC" || exit 1
test "$(echo "$SVC" | jq -r '.spec.type')" = "ClusterIP" || exit 1
CIP=$(echo "$SVC" | jq -r '.spec.clusterIP')
case "$CIP" in 10.100.*) ;; *) exit 1;; esac
test "$(echo "$SVC" | jq -r '.spec.ports[0].port')" = "80" || exit 1
EPIPS=$($K -n $NS get endpointslices -l "kubernetes.io/service-name=radar" -o json 2>/dev/null | jq -r '[.items[].endpoints[] | select(.conditions.ready == true) | .addresses[]] | join(" ")')
test -n "$EPIPS" || exit 1
OK=0
for PIP in $EPIPS; do
  POD=$($K -n $NS get pods -o json | jq -c --arg ip "$PIP" '[.items[] | select(.status.podIP == $ip)][0] // empty')
  test -n "$POD" || continue
  test "$(echo "$POD" | jq -r '.spec.nodeName')" = "ckne-lab0-worker2" || continue
  test "$(echo "$POD" | jq -r '.spec.hostNetwork // false')" = "false" || continue
  test "$(echo "$POD" | jq -r '.status.phase')" = "Running" || continue
  case "$PIP" in 192.168.*) OK=1;; esac
done
test "$OK" = 1 || exit 1
SONDA="sonda-$RANDOM$RANDOM"
$K -n $NS delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
cat <<EOF | $K apply -f - >/dev/null || exit 1
apiVersion: v1
kind: Pod
metadata: {name: $SONDA, namespace: $NS}
spec:
  restartPolicy: Never
  nodeName: ckne-lab0-worker
  containers:
  - name: c
    image: $BUSYBOX
    command: ["wget","-qO-","-T5","http://radar.torre.svc.cluster.local/"]
EOF
$K -n $NS wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
RESP=$($K -n $NS logs "$SONDA" 2>/dev/null | tr -d '\r\n')
$K -n $NS delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
test "$RESP" = "$FICHA" || exit 1
$K -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
$K -n kube-system get daemonset kube-proxy -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
echo ok
