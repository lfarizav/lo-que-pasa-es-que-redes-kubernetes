#!/usr/bin/env bash
# lab-part-06 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name ckne-lab6-torre --kubeconfig ~/ckne-lab/p05/kubeconfig

rm -rf ~/ckne-lab/p05

echo "cluster ckne-lab6-torre eliminado y workspace borrado"
echo "sus otros clusteres de kind siguen intactos:"
kind get clusters
