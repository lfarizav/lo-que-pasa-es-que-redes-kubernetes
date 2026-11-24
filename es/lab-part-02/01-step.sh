#!/usr/bin/env bash
# lab-part-02 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p01
K="kubectl --kubeconfig $HOME/ckne-lab/p01/kubeconfig --context kind-ckne-lab1"

cat > kind-lab1.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
networking:
  disableDefaultCNI: true
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.100.0.0/16
EOF

kind create cluster --name ckne-lab1 \
  --kubeconfig ~/ckne-lab/p01/kubeconfig \
  --image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5 \
  --config kind-lab1.yaml

$K create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
$K -n kube-system rollout status daemonset/calico-node --timeout=240s
$K -n kube-system rollout status deployment/calico-kube-controllers --timeout=240s
$K wait --for=condition=Ready node --all --timeout=180s
$K get nodes -o wide

for N in control-plane worker worker2; do
  docker exec ckne-lab1-$N sh -c 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq tcpdump >/dev/null 2>&1; tcpdump --version 2>&1 | head -1'
done

$K get ippools.crd.projectcalico.org -o jsonpath='{.items[0].spec.cidr}{" "}{.items[0].spec.ipipMode}{"\n"}'

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p01"
IMG=$($K -n kube-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}')
cat > "$D/01-respuesta.txt" <<RESP
VERSION_DE_CALICO=${IMG##*:}
NODOS_LISTOS=$($K get nodes --no-headers | grep -c ' Ready')
POOL_DE_IPS=$($K get ippools.crd.projectcalico.org -o jsonpath='{.items[0].spec.cidr}')
MODO_IPIP=$($K get ippools.crd.projectcalico.org -o jsonpath='{.items[0].spec.ipipMode}')
RESP
cat "$D/01-respuesta.txt"
