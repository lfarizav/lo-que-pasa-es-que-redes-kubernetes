#!/usr/bin/env bash
# lab-part-04 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

for C in ckne-lab3 ckne-lab3-uno ckne-lab3-dos; do
  kind delete cluster --name "$C" --kubeconfig ~/ckne-lab/p03/kubeconfig
done
docker rm -f ckne-lab3-buzon ckne-lab3-frontera >/dev/null 2>&1 || true

rm -rf ~/ckne-lab/p03

echo "clusteres ckne-lab3, ckne-lab3-uno y ckne-lab3-dos eliminados, contenedores y workspace borrados"
echo "sus otros clusteres de kind siguen intactos:"
kind get clusters
