#!/usr/bin/env bash
# lab-part-02 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name ckne-lab1 \
  --kubeconfig ~/ckne-lab/p01/kubeconfig

rm -rf ~/ckne-lab/p01

echo "cluster ckne-lab1 eliminado y workspace borrado"
echo "sus otros clusteres de kind siguen intactos:"
kind get clusters
