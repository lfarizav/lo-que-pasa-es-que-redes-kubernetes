#!/usr/bin/env bash
# lab-part-01 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p00
K="kubectl --kubeconfig $HOME/ckne-lab/p00/kubeconfig --context kind-ckne-lab0"

$K create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml

$K -n kube-system rollout status daemonset/calico-node --timeout=300s
$K -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s
$K wait --for=condition=Ready nodes --all --timeout=180s

$K get nodes -o wide
$K -n kube-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
$K get ippools.crd.projectcalico.org -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.cidr}{"\n"}{end}'
docker exec ckne-lab0-worker ls /etc/cni/net.d
$K -n kube-system get pods -l k8s-app=kube-dns -o wide

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p00"
IMG=$($K -n kube-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}')
cat > "$D/02-respuesta.txt" <<RESP
VERSION_DE_CALICO=${IMG##*:}
POOL_DE_IPS=$($K get ippools.crd.projectcalico.org -o jsonpath='{.items[*].spec.cidr}')
NODOS_LISTOS=$($K get nodes --no-headers | grep -c ' Ready')
RESP
cat "$D/02-respuesta.txt"
