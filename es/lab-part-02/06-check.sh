#!/usr/bin/env bash
# lab-part-02 step 6 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab1"
NS=muelle
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/ficha-del-muelle.txt" || exit 1
test -f "$D/subred-del-muelle.txt" || exit 1
FICHA=$(tr -d '\r\n' < "$D/ficha-del-muelle.txt")
SUBRED=$(tr -d '\r\n' < "$D/subred-del-muelle.txt")
test -n "$FICHA" && test -n "$SUBRED" || exit 1
test "$(printf %s "$FICHA" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.ficha.sha256")" || exit 1
test "$(printf %s "$SUBRED" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.subred.sha256")" || exit 1
PREFIJO=${SUBRED%.0/24}
NAD=$($K -n $NS get network-attachment-definitions carga -o json 2>/dev/null)
test -n "$NAD" || exit 1
CONF=$(echo "$NAD" | jq -r '.spec.config')
test "$(echo "$CONF" | jq -r '.type')" = "bridge" || exit 1
test "$(echo "$CONF" | jq -r '.ipam.type')" = "host-local" || exit 1
test "$(echo "$CONF" | jq -r '.ipam.subnet // .ipam.ranges[0][0].subnet')" = "$SUBRED" || exit 1
echo "$CONF" | grep -qi macvlan && exit 1
FARO=$($K -n $NS get pod faro -o json 2>/dev/null)
test -n "$FARO" || exit 1
test "$(echo "$FARO" | jq -r '.status.phase')" = "Running" || exit 1
test "$(echo "$FARO" | jq -r '.spec.nodeName')" = "ckne-lab1-worker" || exit 1
test "$(echo "$FARO" | jq -r '.spec.hostNetwork // false')" = "false" || exit 1
FE=$(echo "$FARO" | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="eth0") | .ips[0]')
FN=$(echo "$FARO" | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="net1") | .ips[0]')
case "$FE" in 192.168.*) ;; *) exit 1;; esac
case "$FN" in $PREFIJO.*) ;; *) exit 1;; esac
SONDA="sonda-$RANDOM$RANDOM"
cat <<EOF | $K apply -f - >/dev/null || exit 1
apiVersion: v1
kind: Pod
metadata:
  name: $SONDA
  namespace: $NS
  annotations: {k8s.v1.cni.cncf.io/networks: carga}
spec:
  restartPolicy: Never
  nodeName: ckne-lab1-worker
  containers:
  - name: c
    image: $BUSYBOX
    command: ["wget","-qO-","-T5","http://$FN:8080/"]
EOF
$K -n $NS wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
SN=$($K -n $NS get pod $SONDA -o json | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="net1") | .ips[0]')
RESP=$($K -n $NS logs "$SONDA" 2>/dev/null | tr -d '\r\n')
$K -n $NS delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
test "$RESP" = "$FICHA" || exit 1
case "$SN" in $PREFIJO.*) ;; *) exit 1;; esac
$K -n kube-system get daemonset kube-multus-ds -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
$K -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
echo ok
