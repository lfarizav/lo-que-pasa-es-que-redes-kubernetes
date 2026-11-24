#!/usr/bin/env bash
# lab-part-03 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name ckne-lab2 \
  --kubeconfig ~/ckne-lab/p02/kubeconfig

rm -rf ~/ckne-lab/p02

echo "cluster ckne-lab2 eliminado y workspace borrado"
echo "sus otros clusteres de kind siguen intactos:"
kind get clusters
