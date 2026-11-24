#!/usr/bin/env bash
# lab-part-05 step 5 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-sello"
test -f "$D/.falla-aplicada" || exit 1
test -f "$D/05-diagnostico.txt" || exit 1
test "$D/05-diagnostico.txt" -nt "$D/.falla-aplicada" || exit 1
test -f "$D/05-respuesta.txt" || exit 1
CLAVE=$(cat "$D/.falla-clave" 2>/dev/null)
test -n "$CLAVE" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab5-sello || exit 1
# El diagnostico tiene que ser de esta falla: el listener con su condicion en False y el evento del Certificate.
grep -q '^== 1\.' "$D/05-diagnostico.txt" || exit 1
grep -q '^== 2\.' "$D/05-diagnostico.txt" || exit 1
grep -q '^== 3\.' "$D/05-diagnostico.txt" || exit 1
sed -n '/^== 1\./,/^== 2\./p' "$D/05-diagnostico.txt" | grep -qE '^https ResolvedRefs=False ' || exit 1
sed -n '/^== 2\./,/^== 3\./p' "$D/05-diagnostico.txt" | grep -qF "$CLAVE" || exit 1
GW=$($K -n dique get gateway embarcadero -o json 2>/dev/null)
test -n "$GW" || exit 1
# El Gateway es el mismo que se rompio, no uno nuevo.
test "$(echo "$GW" | jq -r '.metadata.uid')" = "$(cat "$D/.falla-uid" 2>/dev/null)" || exit 1
echo "$GW" | jq -e '.metadata.annotations["cert-manager.io/cluster-issuer"]=="casa-emisora"' >/dev/null || exit 1
echo "$GW" | jq -e '[.spec.listeners[] | select(.name=="https" and .protocol=="HTTPS" and .port==443 and .hostname=="embarcadero.lab.example" and .tls.mode=="Terminate" and ([.tls.certificateRefs[].name]==["embarcadero-tls"]))] | length==1' >/dev/null || exit 1
echo "$GW" | jq -e '([.status.listeners[].conditions[] | select(.type=="Accepted" or .type=="Programmed" or .type=="ResolvedRefs") | select(.status!="True")] | length==0) and ([.status.listeners[]] | length==1)' >/dev/null || exit 1
CERT=$($K -n dique get certificate embarcadero-tls -o json 2>/dev/null)
test -n "$CERT" || exit 1
echo "$CERT" | jq -e '([.metadata.ownerReferences[]? | select(.kind=="Gateway" and .name=="embarcadero")] | length==1) and (.spec.issuerRef.name=="casa-emisora") and (.spec.issuerRef.kind=="ClusterIssuer") and (.spec.dnsNames==["embarcadero.lab.example"]) and ([.status.conditions[] | select(.type=="Ready" and .status=="True")] | length==1)' >/dev/null || exit 1
$K -n ribera get httproute embarcadero -o json 2>/dev/null | jq -e '(.spec.parentRefs[0].name=="embarcadero") and (.spec.parentRefs[0].namespace=="dique") and (.spec.rules[0].backendRefs[0].name=="letrero")' >/dev/null || exit 1
RAIZ=$($K -n cert-manager get secret raiz-lab -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d)
test -n "$RAIZ" || exit 1
echo "$RAIZ" | $K -n ribera exec -i cliente-tls -- sh -c 'cat > /tmp/raiz-grader.crt' || exit 1
VER=$($K -n ribera exec cliente-tls -- sh -c "openssl s_client -connect embarcadero-istio.dique:443 -servername embarcadero.lab.example -CAfile /tmp/raiz-grader.crt -verify_hostname embarcadero.lab.example -verify_return_error </dev/null 2>&1" 2>/dev/null)
echo "$VER" | grep -q 'Verify return code: 0 (ok)' || exit 1
CUERPO=$($K -n ribera exec cliente-tls -- curl -s -m 5 --cacert /tmp/raiz-grader.crt --connect-to embarcadero.lab.example:443:embarcadero-istio.dique:443 https://embarcadero.lab.example/ 2>/dev/null)
$K -n ribera exec cliente-tls -- rm -f /tmp/raiz-grader.crt >/dev/null 2>&1
test "$CUERPO" = "letrero: salida 7 puntual" || exit 1
grep -qxF "LISTENER_QUE_NO_CIFRABA=https" "$D/05-respuesta.txt" || exit 1
grep -qxF "CONDICION_QUE_LO_DELATABA=ResolvedRefs" "$D/05-respuesta.txt" || exit 1
grep -qxF "EMISOR_QUE_NO_EXISTIA=$CLAVE" "$D/05-respuesta.txt" || exit 1
grep -qxF "EMISOR_CORRECTO=casa-emisora" "$D/05-respuesta.txt" || exit 1
echo ok
