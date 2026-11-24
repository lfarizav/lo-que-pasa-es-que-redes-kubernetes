#!/usr/bin/env bash
# lab-part-04 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p03
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"

bash ~/ckne-lab/p03/inyectar-falla.sh
sleep 15

echo "EL SINTOMA: doce peticiones por la ruta del grupo"
for i in $(seq 12); do sh pregunta.sh grupo "nota $i"; done | sort | uniq -c

# El orden de lectura del Capitulo 10: el puntaje del elector, lo que recibe el Envoy de la
# entrada y, solo entonces, los servidores de modelo.
{
  echo "== 1. el puntaje en el registro del elector"
  $K -n imprenta logs deploy/elector --tail=300 | jq -r -f marcador.jq | tail -6
  echo "== 2. los extremos que recibe el Envoy de portico"
  ./bin/istioctl --kubeconfig "$D/kubeconfig" --context kind-ckne-lab3 \
    proxy-config endpoint deploy/portico-istio -n imprenta | grep -E 'ENDPOINT|redaccion-ip|redactores'
  echo "== 3. los servidores de modelo"
  $K -n imprenta get pods -l grupo=redaccion \
    -o custom-columns=POD:.metadata.name,LISTO:.status.containerStatuses[0].ready,IP:.status.podIP
  echo "== 4. a quien elige el grupo"
  $K -n imprenta get inferencepool redaccion -o jsonpath='{.spec.selector.matchLabels}{"\n"}'
} | tee 02-diagnostico.txt

# La reparacion: el grupo vuelve a elegir a los tres servidores por su etiqueta comun.
$K -n imprenta patch inferencepool redaccion --type=json \
  -p '[{"op":"replace","path":"/spec/selector/matchLabels","value":{"grupo":"redaccion"}}]'
sleep 15
echo "DESPUES DE REPARAR: veinte peticiones por la ruta del grupo"
for i in $(seq 20); do sh pregunta.sh grupo "nota $i"; done | sort | uniq -c

# The answer file the lab asks you to type, from what the diagnosis above showed:
D="$HOME/ckne-lab/p03"
cat > "$D/02-respuesta.txt" <<RESP
POD_QUE_RECIBIA_TODO=$(sed -n '/^== 1\./,/^== 2\./p' "$D/02-diagnostico.txt" | awk '$1=="queue" {print $2}' | sort -u | head -1)
PODS_PUNTUADOS_DURANTE_LA_FALLA=$(sed -n '/^== 1\./,/^== 2\./p' "$D/02-diagnostico.txt" | awk '$1=="queue" {print $2}' | sort -u | wc -l)
OBJETO_CON_LA_FALLA=InferencePool
CAMPO_CON_LA_FALLA=selector
RESP
cat "$D/02-respuesta.txt"
