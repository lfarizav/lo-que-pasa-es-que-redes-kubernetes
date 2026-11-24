#!/usr/bin/env bash
# lab-part-05 step 5 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p04
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-sello"

bash ~/ckne-lab/p04/inyectar-falla.sh
sleep 25

echo "EL SINTOMA: el cliente pide el nombre por HTTPS con la raiz en la mano"
$K -n ribera exec cliente-tls -- curl -sS -m 5 --cacert /raiz.crt --connect-to embarcadero.lab.example:443:embarcadero-istio.dique:443 https://embarcadero.lab.example/ 2>&1 | head -3

# El orden de lectura del Capitulo 15 para un listener que no cifra: sus condiciones y el mensaje,
# despues el Certificate y sus eventos y, al final, la cadena vista desde un cliente con la raiz.
{
  echo "== 1. el listener y su mensaje"
  $K -n dique get gateway embarcadero -o json | jq -r -f conds.jq
  $K -n dique get gateway embarcadero -o json | jq -r '.status.listeners[0].conditions[] | select(.type=="ResolvedRefs") | .message'
  echo "== 2. el Certificate y sus eventos"
  $K -n dique get certificate
  $K -n dique get certificaterequest
  $K -n dique get events -o json | jq -r '.items[] | select(.involvedObject.name | startswith("embarcadero")) | .reason + ": " + .message' | sort -u
  echo "== 3. la cadena vista desde un cliente que tiene la raiz"
  $K -n ribera exec cliente-tls -- sh -c "openssl s_client -connect embarcadero-istio.dique:443 -servername embarcadero.lab.example -CAfile /raiz.crt </dev/null 2>&1" | grep -E "^depth|Verify|no peer|alert|errno|connect" | head -4
  echo "== 4. de donde sale el certificado del listener"
  $K -n dique get gateway embarcadero -o json | jq -r '.metadata.annotations | to_entries[] | select(.key | startswith("cert-manager.io/")) | "\(.key)=\(.value)"'
  $K get clusterissuer -o custom-columns=NOMBRE:.metadata.name
} | tee 05-diagnostico.txt

# La reparacion: el Gateway pide el certificado al emisor que si existe.
$K -n dique annotate gateway embarcadero cert-manager.io/cluster-issuer=casa-emisora --overwrite
$K -n dique wait certificate/embarcadero-tls --for=condition=Ready --timeout=180s
sleep 10
echo "DESPUES DE REPARAR:"
$K -n dique get gateway embarcadero -o json | jq -r -f conds.jq
$K -n ribera exec cliente-tls -- curl -s -m 5 --cacert /raiz.crt --connect-to embarcadero.lab.example:443:embarcadero-istio.dique:443 https://embarcadero.lab.example/

# The answer file the lab asks you to type, from the diagnosis above:
D="$HOME/ckne-lab/p04"
cat > "$D/05-respuesta.txt" <<RESP
LISTENER_QUE_NO_CIFRABA=$($K -n dique get gateway embarcadero -o jsonpath='{.spec.listeners[0].name}')
CONDICION_QUE_LO_DELATABA=$(sed -n '/^== 1\./,/^== 2\./p' "$D/05-diagnostico.txt" | awk '$2 ~ /^ResolvedRefs=False/ {sub(/=.*/, "", $2); print $2}' | head -1)
EMISOR_QUE_NO_EXISTIA=$(sed -n '/^== 2\./,/^== 3\./p' "$D/05-diagnostico.txt" | grep -o 'casa-emisora-[a-z]*' | head -1)
EMISOR_CORRECTO=$($K -n dique get certificate embarcadero-tls -o jsonpath='{.spec.issuerRef.name}')
RESP
cat "$D/05-respuesta.txt"
