#!/usr/bin/env bash
# lab-part-02 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab1"
hay_falla() {
  local R; R=$(docker exec ckne-lab1-worker2 iptables-save 2>/dev/null)
  grep -qE -- '^-A (PREROUTING|INPUT|FORWARD|OUTPUT|POSTROUTING) .*-p 4 .*-j (DROP|REJECT)' <<<"$R"
}
test -f "$D/.falla-aplicada" || exit 1
test -f "$D/02-respuesta.txt" || exit 1
PA=$($K -n vecinos get pod vecino-a -o json 2>/dev/null)
PB=$($K -n vecinos get pod vecino-b -o json 2>/dev/null)
test -n "$PA" && test -n "$PB" || exit 1
test "$(echo "$PA" | jq -r '.status.phase')" = "Running" || exit 1
test "$(echo "$PB" | jq -r '.status.phase')" = "Running" || exit 1
test "$(echo "$PA" | jq -r '.spec.nodeName')" = "ckne-lab1-worker" || exit 1
test "$(echo "$PB" | jq -r '.spec.nodeName')" = "ckne-lab1-worker2" || exit 1
test "$(echo "$PA" | jq -r '.spec.hostNetwork // false')" = "false" || exit 1
test "$(echo "$PB" | jq -r '.spec.hostNetwork // false')" = "false" || exit 1
IPB=$(echo "$PB" | jq -r '.status.podIP')
case "$IPB" in 192.168.*) ;; *) exit 1;; esac
SINT=$($K -n vecinos exec vecino-a -- wget -qO- -T4 "http://$IPB:8080/" 2>/dev/null | tr -d '\r\n')
if hay_falla; then
  test -z "$SINT" || exit 1
else
  test "$SINT" = "vecino-b-ok" || exit 1
fi
grep -qxF "IP_DE_VECINO_B=$IPB" "$D/02-respuesta.txt" || exit 1
grep -qxF "ANTES=responde" "$D/02-respuesta.txt" || exit 1
grep -qxF "DESPUES=agota-tiempo" "$D/02-respuesta.txt" || exit 1
echo ok
