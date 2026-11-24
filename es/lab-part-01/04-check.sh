#!/usr/bin/env bash
# lab-part-01 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p00"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab0"
NS=terminal
test -f "$D/04-respuesta.txt" || exit 1
SVC=$($K -n $NS get svc mostrador -o json 2>/dev/null)
test -n "$SVC" || exit 1
test "$(echo "$SVC" | jq -r '.spec.type')" = "ClusterIP" || exit 1
CIP=$(echo "$SVC" | jq -r '.spec.clusterIP')
case "$CIP" in 10.100.*) ;; *) exit 1;; esac
test "$(echo "$SVC" | jq -r '.spec.ports[0].port')" = "80" || exit 1
PODS=$($K -n $NS get pods -l "$(echo "$SVC" | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')" -o json 2>/dev/null)
LISTOS=$(echo "$PODS" | jq -c '[.items[] | select(.metadata.deletionTimestamp == null) | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))]')
test "$(echo "$LISTOS" | jq 'length')" -ge 2 || exit 1
EPS=$($K -n $NS get endpointslices -l "kubernetes.io/service-name=mostrador" -o json 2>/dev/null | jq -r '[.items[].endpoints[] | select(.conditions.ready == true) | .addresses[]] | sort | join(" ")')
PIPS=$(echo "$LISTOS" | jq -r '[.[].status.podIP] | sort | join(" ")')
test -n "$EPS" && test "$EPS" = "$PIPS" || exit 1
RES=$($K -n $NS exec emisor -- nslookup mostrador.terminal.svc.cluster.local 2>/dev/null | awk '/^Name:/{f=1} f&&/^Address/{print $NF; exit}')
test "$RES" = "$CIP" || exit 1
NOMBRES=$(echo "$LISTOS" | jq -r '[.[].metadata.name] | sort | join(" ")')
VISTOS=""
for i in $(seq 1 40); do
  VISTOS="$VISTOS
$($K -n $NS exec emisor -- wget -qO- -T3 http://mostrador.terminal.svc.cluster.local/ 2>/dev/null | tr -d '\r')"
done
DIST=$(echo "$VISTOS" | sed '/^$/d' | sort -u)
test "$(echo "$DIST" | wc -l)" -ge 2 || exit 1
for V in $DIST; do echo "$NOMBRES" | grep -qw "$V" || exit 1; done
$K -n kube-system get daemonset kube-proxy -o jsonpath='{.status.numberReady}' | grep -qx 3 || exit 1
test "$($K -n kube-system get deployment coredns -o jsonpath='{.status.readyReplicas}')" -ge 1 || exit 1
grep -qxF "CLUSTER_IP=$CIP" "$D/04-respuesta.txt" || exit 1
grep -qxF "RESUELVE_A=$RES" "$D/04-respuesta.txt" || exit 1
grep -qxF "MOSTRADORES_DISTINTOS=$(echo "$DIST" | wc -l)" "$D/04-respuesta.txt" || exit 1
echo ok
