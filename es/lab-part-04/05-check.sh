#!/usr/bin/env bash
# lab-part-04 step 5 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p03"
test -f "$D/05-respuesta.txt" || exit 1
for C in uno:1:31 dos:2:41; do
  N=${C%%:*}; I=$(echo $C | cut -d: -f2); P=${C##*:}
  KK="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-$N"
  kind get clusters 2>/dev/null | grep -qx "ckne-lab3-$N" || exit 1
  NODOS=$($KK get nodes -o json 2>/dev/null)
  test "$(echo "$NODOS" | jq '.items | length')" -eq 2 || exit 1
  echo "$NODOS" | jq -e '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 2' >/dev/null || exit 1
  echo "$NODOS" | jq -e --arg p "10.$P." '[.items[].spec.podCIDR | startswith($p)] | all' >/dev/null || exit 1
  $KK -n kube-system get daemonset kube-proxy >/dev/null 2>&1 && exit 1
  IMG=$($KK -n kube-system get daemonset cilium -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  case "$IMG" in *:v1.20.5*) ;; *) exit 1 ;; esac
  test "$($KK -n kube-system get daemonset cilium -o jsonpath='{.status.numberReady}')" = "2" || exit 1
  $KK -n kube-system get configmap cilium-config -o json | jq -e --arg n "ckne-lab3-$N" --arg i "$I" '.data["cluster-name"]==$n and .data["cluster-id"]==$i and .data["kube-proxy-replacement"]=="true"' >/dev/null || exit 1
  test "$($KK -n kube-system get deployment clustermesh-apiserver -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
  $KK -n kube-system get service clustermesh-apiserver -o json | jq -e '.spec.type=="NodePort" and .spec.ports[0].nodePort==32379' >/dev/null || exit 1
  $KK get crd serviceimports.multicluster.x-k8s.io >/dev/null 2>&1 || exit 1
  $KK -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep -qE '^ *multicluster clusterset\.local$' || exit 1
  $KK -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status 2>/dev/null | grep -qE '^ClusterMesh: +1/1 remote clusters ready' || exit 1
  OTRO=ckne-lab3-dos; [ "$N" = dos ] && OTRO=ckne-lab3-uno
  KV=$($KK -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg status 2>/dev/null)
  echo "$KV" | grep -qE '^KVStoreMesh:[[:space:]]+1/1 remote clusters ready' || exit 1
  echo "$KV" | grep -qE "^ +$OTRO: ready," || exit 1
done
CA1=$(kubectl --kubeconfig "$D/kubeconfig" --context kind-ckne-lab3-uno -n kube-system get secret cilium-ca -o jsonpath='{.data.ca\.crt}')
CA2=$(kubectl --kubeconfig "$D/kubeconfig" --context kind-ckne-lab3-dos -n kube-system get secret cilium-ca -o jsonpath='{.data.ca\.crt}')
test -n "$CA1" && test "$CA1" = "$CA2" || exit 1
grep -qxF "ID_DE_UNO=1" "$D/05-respuesta.txt" || exit 1
grep -qxF "ID_DE_DOS=2" "$D/05-respuesta.txt" || exit 1
grep -qxF "PUERTO_DE_LA_MALLA=32379" "$D/05-respuesta.txt" || exit 1
grep -qxF "ZONA_ENTRE_CLUSTERES=clusterset.local" "$D/05-respuesta.txt" || exit 1
echo ok
