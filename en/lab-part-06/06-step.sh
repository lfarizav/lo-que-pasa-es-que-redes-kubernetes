#!/usr/bin/env bash
# lab-part-06 step 6 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p05
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"

bash ~/ckne-lab/p05/inyectar-falla.sh
sleep 15

# El orden de lectura del Capitulo 18: el codigo que vio el cliente, la linea del registro de acceso
# con su bandera y su motivo, y despues el estado de cada objeto que esa linea senala.
{
  echo "== 1. lo que vio el cliente"
  $K -n externo exec sondeo -- curl -s -o /dev/null -w "consigna %{http_code}\n" -H "Host: consigna.torre.test" http://entrada-trazas-istio.trazado/get
  sleep 5
  echo "== 2. la linea del registro de acceso de la entrada"
  $K -n trazado logs deploy/entrada-trazas-istio | grep '^{' | jq -c 'select(.nombre == "consigna.torre.test")' | tail -1
  echo "== 3. el estado de los objetos que la linea senala"
  $K -n trazado get httproute ruta-consigna -o json | jq -r '.status.parents[0].conditions[] | "ruta \(.type) \(.status) \(.reason)"'
  $K -n trazado get endpointslices -l kubernetes.io/service-name=consigna -o json | jq -r '"extremos listos de consigna: \([.items[].endpoints[]? | select(.conditions.ready)] | length)"'
  $K -n trazado get service consigna -o json | jq -r '"la Service pide: \(.spec.selector | to_entries | map("\(.key)=\(.value)") | join(","))"'
  $K -n trazado get pods -l app=consigna -o json | jq -r '.items[] | "Pod \(.metadata.name): app=\(.metadata.labels.app) \(.status.phase)"'
} | tee 06-diagnostico.txt

# La reparacion: la Service vuelve a pedir la etiqueta que llevan los Pods de consigna.
$K -n trazado patch service consigna --type=merge -p '{"spec":{"selector":{"app":"consigna"}}}'
sleep 10
echo "DESPUES DE REPARAR:"
$K -n trazado get endpointslices -l kubernetes.io/service-name=consigna -o json | jq -r '"extremos listos de consigna: \([.items[].endpoints[]? | select(.conditions.ready)] | length)"'
$K -n externo exec sondeo -- curl -s -o /dev/null -w "consigna %{http_code}\n" -H "Host: consigna.torre.test" http://entrada-trazas-istio.trazado/get

# The answer file the lab asks you to type, from the diagnosis above:
D="$HOME/ckne-lab/p05"
cat > "$D/06-respuesta.txt" <<RESP
CODIGO_DEL_CLIENTE=$(sed -n '/^== 1\./,/^== 2\./p' "$D/06-diagnostico.txt" | awk '$1=="consigna" {print $2}')
BANDERA=$(sed -n '/^== 2\./,/^== 3\./p' "$D/06-diagnostico.txt" | grep '^{' | jq -r '.bandera')
MOTIVO=$(sed -n '/^== 2\./,/^== 3\./p' "$D/06-diagnostico.txt" | grep '^{' | jq -r '.motivo')
OBJETO_REPARADO=service/consigna
VALOR_QUE_LA_FALLA_DEJO=$(sed -n 's/^la Service pide: //p' "$D/06-diagnostico.txt")
RESP
cat "$D/06-respuesta.txt"
