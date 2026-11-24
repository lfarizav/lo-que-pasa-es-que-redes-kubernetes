#!/usr/bin/env bash
# lab-part-02 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab1"
test -f "$D/04-captura-tunl0.txt" || exit 1
test -f "$D/04-respuesta.txt" || exit 1
for N in ckne-lab1-control-plane ckne-lab1-worker ckne-lab1-worker2; do
  R=$(docker exec "$N" iptables-save 2>/dev/null)
  grep -qE -- '^-A (PREROUTING|INPUT|FORWARD|OUTPUT|POSTROUTING) .*-p 4 .*-j (DROP|REJECT)' <<<"$R" && exit 1
done
POOL=$($K get ippools.crd.projectcalico.org -o json 2>/dev/null)
test "$(echo "$POOL" | jq -r '.items[0].spec.cidr')" = "192.168.0.0/16" || exit 1
test "$(echo "$POOL" | jq -r '.items[0].spec.ipipMode')" = "Always" || exit 1
$K -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
IPA=$($K -n vecinos get pod vecino-a -o jsonpath='{.status.podIP}' 2>/dev/null)
IPB=$($K -n vecinos get pod vecino-b -o jsonpath='{.status.podIP}' 2>/dev/null)
test -n "$IPA" && test -n "$IPB" || exit 1
R=$($K -n vecinos exec vecino-a -- wget -qO- -T5 "http://$IPB:8080/" 2>/dev/null | tr -d '\r\n')
test "$R" = "vecino-b-ok" || exit 1
SONDA="sonda-$RANDOM$RANDOM"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
cat <<EOF | $K apply -f - >/dev/null || exit 1
apiVersion: v1
kind: Pod
metadata: {name: $SONDA, namespace: vecinos}
spec:
  restartPolicy: Never
  nodeName: ckne-lab1-worker
  containers:
  - name: c
    image: $BUSYBOX
    command: ["wget","-qO-","-T5","http://$IPB:8080/"]
EOF
$K -n vecinos wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
RP=$($K -n vecinos logs "$SONDA" 2>/dev/null | tr -d '\r\n')
$K -n vecinos delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
test "$RP" = "vecino-b-ok" || exit 1
grep -qF "IP $IPB.8080 > $IPA." "$D/04-captura-tunl0.txt" || exit 1
grep -qxF "TABLA_DE_LA_REGLA=raw" "$D/04-respuesta.txt" || exit 1
grep -qxF "CADENA_DE_LA_REGLA=PREROUTING" "$D/04-respuesta.txt" || exit 1
grep -qxF "MODO_IPIP_INTACTO=Always" "$D/04-respuesta.txt" || exit 1
echo ok
