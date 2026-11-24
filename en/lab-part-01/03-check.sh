#!/usr/bin/env bash
# lab-part-01 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p00"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab0"
NS=terminal
test -f "$D/03-respuesta.txt" || exit 1
E=$($K -n $NS get pod emisor -o json 2>/dev/null)
R=$($K -n $NS get pod receptor -o json 2>/dev/null)
test -n "$E" && test -n "$R" || exit 1
test "$(echo "$E" | jq -r '.status.phase')" = "Running" || exit 1
test "$(echo "$R" | jq -r '.status.phase')" = "Running" || exit 1
NE=$(echo "$E" | jq -r '.spec.nodeName')
NR=$(echo "$R" | jq -r '.spec.nodeName')
test -n "$NE" && test -n "$NR" && test "$NE" != "$NR" || exit 1
test "$(echo "$E" | jq -r '.spec.hostNetwork // false')" = "false" || exit 1
test "$(echo "$R" | jq -r '.spec.hostNetwork // false')" = "false" || exit 1
IPE=$(echo "$E" | jq -r '.status.podIP')
IPR=$(echo "$R" | jq -r '.status.podIP')
case "$IPE" in 192.168.*) ;; *) exit 1;; esac
case "$IPR" in 192.168.*) ;; *) exit 1;; esac
test "$IPE" != "$IPR" || exit 1
MARCA="sonda-$RANDOM$RANDOM"
$K -n $NS exec emisor -- wget -qO- -T5 "http://$IPR:8080/$MARCA" >/dev/null 2>&1
sleep 1
LINEA=$($K -n $NS logs receptor 2>/dev/null | grep -F "$MARCA" | head -1)
test -n "$LINEA" || exit 1
echo "$LINEA" | grep -qF "$IPE" || exit 1
echo "$LINEA" | grep -q '172\.18\.' && exit 1
VISTA=$(echo "$LINEA" | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)
test "$VISTA" = "$IPE" || exit 1
grep -qxF "IP_DEL_EMISOR=$IPE" "$D/03-respuesta.txt" || exit 1
grep -qxF "IP_QUE_VIO_EL_RECEPTOR=$VISTA" "$D/03-respuesta.txt" || exit 1
echo ok
