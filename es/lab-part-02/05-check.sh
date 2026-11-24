#!/usr/bin/env bash
# lab-part-02 step 5 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab1"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/05-respuesta.txt" || exit 1
$K -n kube-system get daemonset kube-multus-ds >/dev/null 2>&1 || exit 1
test "$($K -n kube-system get daemonset kube-multus-ds -o jsonpath='{.status.numberReady}')" = "3" || exit 1
$K -n kube-system get daemonset kube-multus-ds -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qx 'ghcr.io/k8snetworkplumbingwg/multus-cni:v4.3.2-thick' || exit 1
for N in ckne-lab1-control-plane ckne-lab1-worker ckne-lab1-worker2; do
  docker exec "$N" test -x /opt/cni/bin/bridge || exit 1
  docker exec "$N" test -x /opt/cni/bin/host-local || exit 1
  docker exec "$N" test -f /etc/cni/net.d/00-multus.conf || exit 1
done
NAD=$($K -n pista get network-attachment-definitions puente-pista -o json 2>/dev/null)
test -n "$NAD" || exit 1
CONF=$(echo "$NAD" | jq -r '.spec.config')
test "$(echo "$CONF" | jq -r '.type')" = "bridge" || exit 1
test "$(echo "$CONF" | jq -r '.ipam.type')" = "host-local" || exit 1
echo "$CONF" | grep -qi macvlan && exit 1
RX=$($K -n pista get pod rx -o json 2>/dev/null)
TX=$($K -n pista get pod tx -o json 2>/dev/null)
test -n "$RX" && test -n "$TX" || exit 1
test "$(echo "$RX" | jq -r '.status.phase')" = "Running" || exit 1
test "$(echo "$TX" | jq -r '.status.phase')" = "Running" || exit 1
NODO=$(echo "$RX" | jq -r '.spec.nodeName')
test "$NODO" = "$(echo "$TX" | jq -r '.spec.nodeName')" || exit 1
test "$(echo "$RX" | jq -r '.spec.hostNetwork // false')" = "false" || exit 1
RXE=$(echo "$RX" | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="eth0") | .ips[0]')
RXN=$(echo "$RX" | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="net1") | .ips[0]')
TXN=$(echo "$TX" | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="net1") | .ips[0]')
case "$RXE" in 192.168.*) ;; *) exit 1;; esac
case "$RXN" in 10.20.0.*) ;; *) exit 1;; esac
case "$TXN" in 10.20.0.*) ;; *) exit 1;; esac
docker exec "$NODO" ip -d link show br-pista 2>/dev/null | grep -q 'bridge' || exit 1
SONDA="sonda-$RANDOM$RANDOM"
MARCA="m$RANDOM$RANDOM"
cat <<EOF | $K apply -f - >/dev/null || exit 1
apiVersion: v1
kind: Pod
metadata:
  name: $SONDA
  namespace: pista
  annotations: {k8s.v1.cni.cncf.io/networks: puente-pista}
spec:
  restartPolicy: Never
  nodeName: $NODO
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sh","-c","wget -qO- -T5 http://$RXN:8080/$MARCA; true"]
EOF
$K -n pista wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
SN=$($K -n pista get pod $SONDA -o json | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="net1") | .ips[0]')
$K -n pista delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
sleep 1
LINEA=$($K -n pista logs rx 2>/dev/null | grep -F "$MARCA" | head -1)
test -n "$LINEA" || exit 1
VISTA=$(echo "$LINEA" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
test -n "$SN" && test "$VISTA" = "$SN" || exit 1
case "$VISTA" in 10.20.0.*) ;; *) exit 1;; esac
grep -qxF "IP_NET1_DE_RX=$RXN" "$D/05-respuesta.txt" || exit 1
grep -qxF "IP_NET1_DE_TX=$TXN" "$D/05-respuesta.txt" || exit 1
grep -qxF "INTERFAZ_SECUNDARIA=net1" "$D/05-respuesta.txt" || exit 1
echo ok
