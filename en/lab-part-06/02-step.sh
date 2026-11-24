#!/usr/bin/env bash
# lab-part-06 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p05
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
. ./pedido.txt

# El contador crudo ANTES: dos lecturas separadas por la rafaga, y se resta.
bash pregunta.sh 'sum by (response_code) (istio_requests_total{reporter="source",destination_service_name="bodega"})' | tee antes.txt

# La rafaga que pide pedido.txt: PEDIDO_200 peticiones buenas y PEDIDO_503 con error, por la entrada.
$K -n externo exec sondeo -- sh -c "
  for i in \$(seq $PEDIDO_200); do curl -s -o /dev/null -H 'Host: bodega.torre.test' http://entrada-torre-istio.faena/get; done
  for i in \$(seq $PEDIDO_503); do curl -s -o /dev/null -H 'Host: bodega.torre.test' http://entrada-torre-istio.faena/status/503; done"
sleep 30

echo "DESPUES:"
bash pregunta.sh 'sum by (response_code) (istio_requests_total{reporter="source",destination_service_name="bodega"})' | tee despues.txt
A=$(awk '$1=="200" {print $2}' despues.txt)
B=$(awk '$1=="503" {print $2}' despues.txt)
echo "razon de errores: $(awk -v a="$A" -v b="$B" 'BEGIN {printf "%.3f", b/(a+b)}')"

# The answer file the lab asks you to type, from the raw counters above:
D="$HOME/ckne-lab/p05"
cat > "$D/02-respuesta.txt" <<RESP
PETICIONES_200=$(awk '$1=="200" {print $2}' "$D/despues.txt")
PETICIONES_503=$(awk '$1=="503" {print $2}' "$D/despues.txt")
RAZON_DE_ERRORES=$(awk -v a="$A" -v b="$B" 'BEGIN {printf "%.3f", b/(a+b)}')
RESP
cat "$D/02-respuesta.txt"
