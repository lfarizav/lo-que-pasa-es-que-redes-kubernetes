#!/usr/bin/env bash
# lab-part-04 step 6 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p03"
K1="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-uno"
K2="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-dos"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/06-caida.txt" || exit 1
test -f "$D/06-respuesta.txt" || exit 1
for KK in "$K1" "$K2"; do
  $KK -n cartas get service relevo -o json 2>/dev/null | jq -e '.spec.type=="ClusterIP" and .spec.selector=={"app":"relevo"} and .spec.ports[0].port==80' >/dev/null || exit 1
  test "$($KK -n cartas get deployment relevo -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "2" || exit 1
  $KK -n cartas get serviceexport relevo -o json 2>/dev/null | jq -e '[.status.conditions[] | select((.type=="Valid" or .type=="Ready") and .status=="True")] | length == 2' >/dev/null || exit 1
  test "$($KK -n cartas get serviceimport relevo -o json 2>/dev/null | jq -r '[.status.clusters[].cluster] | sort | join(" ")')" = "ckne-lab3-dos ckne-lab3-uno" || exit 1
  $KK -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status 2>/dev/null | grep -qE '^ClusterMesh: +1/1 remote clusters ready' || exit 1
done
# La caida tuvo que ocurrir y terminar: el clustermesh-apiserver de dos se escalo (generacion 3 o
# mas, una replica lista) y KVStoreMesh de uno cuenta al menos una reconexion con dos, ya lista.
$K2 -n kube-system get deployment clustermesh-apiserver -o json | jq -e '.metadata.generation >= 3 and .spec.replicas==1 and .status.readyReplicas==1' >/dev/null || exit 1
KV=$($K1 -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg status 2>/dev/null)
echo "$KV" | grep -qE '^KVStoreMesh:[[:space:]]+1/1 remote clusters ready' || exit 1
REC=$(echo "$KV" | grep -E '^ +ckne-lab3-dos: ready,' | grep -oE '[0-9]+ reconnections' | cut -d' ' -f1)
test -n "$REC" && test "$REC" -ge 1 || exit 1
grep -qE '^ClusterMesh: +1/1 remote clusters ready$' "$D/06-caida.txt" || exit 1
grep -qE '^KVStoreMesh:[[:space:]]+0/1 remote clusters ready$' "$D/06-caida.txt" || exit 1
grep -qE '^ +ckne-lab3-dos: not-ready, ' "$D/06-caida.txt" || exit 1
grep -qE '^ +[0-9]+ ckne-lab3-dos$' "$D/06-caida.txt" || exit 1
# Una sonda nueva en uno: el nombre clusterset.local reparte entre los dos clusteres.
S="sonda-$RANDOM$RANDOM"
$K1 -n cartas run "$S" --image=$BUSYBOX --restart=Never --command -- sh -c 'for i in $(seq 20); do wget -qO- -T2 http://relevo.cartas.svc.clusterset.local/ || echo sin-respuesta; done' >/dev/null 2>&1 || exit 1
$K1 -n cartas wait --for=jsonpath='{.status.phase}'=Succeeded pod/$S --timeout=120s >/dev/null 2>&1
R=$($K1 -n cartas logs "$S" 2>/dev/null)
$K1 -n cartas delete pod "$S" --ignore-not-found >/dev/null 2>&1
test "$(echo "$R" | grep -cxE 'ckne-lab3-(uno|dos)')" = "20" || exit 1
echo "$R" | grep -qx ckne-lab3-uno || exit 1
echo "$R" | grep -qx ckne-lab3-dos || exit 1
grep -qxF "AGENTE_DE_UNO_EN_LA_CAIDA=1/1" "$D/06-respuesta.txt" || exit 1
grep -qxF "KVSTOREMESH_DE_UNO_EN_LA_CAIDA=0/1" "$D/06-respuesta.txt" || exit 1
grep -qxF "DOS_SIGUIO_ATENDIENDO=si" "$D/06-respuesta.txt" || exit 1
echo ok
