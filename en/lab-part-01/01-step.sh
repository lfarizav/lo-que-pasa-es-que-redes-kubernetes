#!/usr/bin/env bash
# lab-part-01 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p00

cat > kind-aeropuerto.yaml <<'EOF'
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

kind create cluster --name ckne-lab0 \
  --kubeconfig ~/ckne-lab/p00/kubeconfig \
  --image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5 \
  --config kind-aeropuerto.yaml

K="kubectl --kubeconfig $HOME/ckne-lab/p00/kubeconfig --context kind-ckne-lab0"

$K get nodes -o wide
$K -n kube-system get daemonsets
$K get nodes -o custom-columns=NODO:.metadata.name,PODCIDR:.spec.podCIDR
$K -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep -E 'podSubnet|serviceSubnet'
docker exec ckne-lab0-worker ls /etc/cni/net.d

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p00"
CFG=$($K -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}')
cat > "$D/01-respuesta.txt" <<RESP
PODSUBNET=$(echo "$CFG" | awk '/podSubnet:/{print $2}')
SERVICESUBNET=$(echo "$CFG" | awk '/serviceSubnet:/{print $2}')
NODOS=$($K get nodes --no-headers | wc -l)
PODCIDR_DEL_TRABAJADOR=$($K get node ckne-lab0-worker -o jsonpath='{.spec.podCIDR}')
RESP
cat "$D/01-respuesta.txt"
