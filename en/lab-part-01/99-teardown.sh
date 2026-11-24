#!/usr/bin/env bash
# lab-part-01 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name ckne-lab0 \
  --kubeconfig ~/ckne-lab/p00/kubeconfig

rm -rf ~/ckne-lab/p00

echo "cluster ckne-lab0 eliminado y workspace borrado"
echo "sus otros clusteres de kind siguen intactos:"
kind get clusters
