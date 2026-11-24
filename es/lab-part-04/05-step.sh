#!/usr/bin/env bash
# lab-part-04 step 5 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p03
D="$HOME/ckne-lab/p03"
K1="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-uno"
K2="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-dos"
NODO=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5

# 1) Dos clusteres mas, con rangos de Pods y de Services que no se pisan entre si.
for C in uno:31:32 dos:41:42; do
  N=${C%%:*}; P=$(echo $C | cut -d: -f2); S=${C##*:}
  cat > kind-lab3-$N.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  kubeProxyMode: none
  podSubnet: "10.$P.0.0/16"
  serviceSubnet: "10.$S.0.0/16"
nodes:
- role: control-plane
- role: worker
EOF
  kind create cluster --name ckne-lab3-$N --kubeconfig "$D/kubeconfig" --image "$NODO" --config kind-lab3-$N.yaml
done

# 2) Los valores de Cilium de cada uno: nombre e id distintos, la malla por un clustermesh-apiserver
#    expuesto en NodePort (32379 por defecto), el API de MCS y CoreDNS configurado para clusterset.local.
U=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ckne-lab3-uno-control-plane)
S=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ckne-lab3-dos-control-plane)
for C in uno:1 dos:2; do
  N=${C%%:*}; I=${C##*:}
  cat > cilium-$N.yaml <<EOF
cluster:
  name: ckne-lab3-$N
  id: $I
ipam:
  mode: kubernetes
kubeProxyReplacement: true
k8sServiceHost: ckne-lab3-$N-control-plane
k8sServicePort: 6443
clustermesh:
  useAPIServer: true
  config:
    enabled: true
    clusters:
      ckne-lab3-uno: {ips: [$U], port: 32379}
      ckne-lab3-dos: {ips: [$S], port: 32379}
  apiserver:
    service: {type: NodePort}
    tls: {auto: {enabled: true, method: cronJob}}
  mcsapi:
    enabled: true
    corednsAutoConfigure: {enabled: true}
EOF
done

# 3) Cilium en uno; su autoridad certificadora se copia a dos antes de instalar alli, para que las
#    dos mallas confien la una en la otra.
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  --kubeconfig "$D/kubeconfig" --kube-context kind-ckne-lab3-uno -n kube-system -f cilium-uno.yaml >/dev/null
$K1 -n kube-system get secret cilium-ca -o yaml | $K2 create -f -
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  --kubeconfig "$D/kubeconfig" --kube-context kind-ckne-lab3-dos -n kube-system -f cilium-dos.yaml >/dev/null
for KK in "$K1" "$K2"; do
  $KK -n kube-system rollout status daemonset/cilium --timeout=300s
  $KK -n kube-system rollout status deployment/clustermesh-apiserver --timeout=300s
done

# 4) Esperar a que cada agente vea al otro cluster, y leerlo de los dos lados.
for KK in "$K1" "$K2"; do
  until $KK -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status 2>/dev/null | grep -q "1/1 remote"; do sleep 5; done
done
for KK in "$K1" "$K2"; do
  $KK -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep "^ClusterMesh" | tr -s " "
  $KK -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg status | head -2
done
$K1 -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep -E "clusterset|multicluster"

# The answer file the lab asks you to type, written from the live clusters:
D="$HOME/ckne-lab/p03"
cat > "$D/05-respuesta.txt" <<RESP
ID_DE_UNO=$($K1 -n kube-system get configmap cilium-config -o jsonpath='{.data.cluster-id}')
ID_DE_DOS=$($K2 -n kube-system get configmap cilium-config -o jsonpath='{.data.cluster-id}')
PUERTO_DE_LA_MALLA=$($K2 -n kube-system get service clustermesh-apiserver -o jsonpath='{.spec.ports[0].nodePort}')
ZONA_ENTRE_CLUSTERES=clusterset.local
RESP
cat "$D/05-respuesta.txt"
