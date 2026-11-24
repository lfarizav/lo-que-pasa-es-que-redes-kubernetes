#!/usr/bin/env bash
# lab-part-05 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

for C in ckne-lab5-red ckne-lab5-cifra ckne-lab5-sello ckne-lab5-id; do
  kind delete cluster --name "$C" --kubeconfig ~/ckne-lab/p04/kubeconfig
done

rm -rf ~/ckne-lab/p04

echo "clusteres ckne-lab5-red, ckne-lab5-cifra, ckne-lab5-sello y ckne-lab5-id eliminados y workspace borrado"
echo "sus otros clusteres de kind siguen intactos:"
kind get clusters
