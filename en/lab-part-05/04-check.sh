#!/usr/bin/env bash
# lab-part-05 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-sello"
test -f "$D/04-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab5-sello || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
echo "$NODOS" | jq -e '(.items | length == 2) and ([.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 2)' >/dev/null || exit 1
$K -n istio-system get deployment istiod -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q ':1.32.0' || exit 1
$K -n cert-manager get deployment cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q ':v1.21.3' || exit 1
$K get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null | grep -qx 'v1.6.1' || exit 1
test "$($K get clusterissuer casa-emisora -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" || exit 1
test "$($K -n cert-manager get certificate raiz-lab -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" || exit 1
test "$($K -n ribera get deployment letrero -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
GW=$($K -n dique get gateway entrada-lab -o json 2>/dev/null)
test -n "$GW" || exit 1
echo "$GW" | jq -e '.metadata.annotations["cert-manager.io/cluster-issuer"]=="casa-emisora" and .metadata.annotations["cert-manager.io/duration"]=="2h" and .metadata.annotations["cert-manager.io/renew-before"]=="1h"' >/dev/null || exit 1
echo "$GW" | jq -e '[.spec.listeners[] | select(.protocol=="HTTPS" and .port==443 and .hostname=="letrero.lab.example" and .tls.mode=="Terminate" and ([.tls.certificateRefs[].name]==["letrero-tls"]))] | length==1' >/dev/null || exit 1
echo "$GW" | jq -e '([.status.listeners[].conditions[] | select(.type=="Accepted" or .type=="Programmed" or .type=="ResolvedRefs") | select(.status!="True")] | length==0) and ([.status.listeners[]] | length==2)' >/dev/null || exit 1
CERT=$($K -n dique get certificate letrero-tls -o json 2>/dev/null)
test -n "$CERT" || exit 1
# El Certificate lo tiene que haber creado cert-manager por la anotacion: el Gateway es su dueno.
echo "$CERT" | jq -e '([.metadata.ownerReferences[]? | select(.kind=="Gateway" and .name=="entrada-lab")] | length==1) and (.spec.secretName=="letrero-tls") and (.spec.issuerRef.name=="casa-emisora") and (.spec.issuerRef.kind=="ClusterIssuer") and (.spec.dnsNames==["letrero.lab.example"]) and (.spec.duration=="2h0m0s") and (.spec.renewBefore=="1h0m0s") and ([.status.conditions[] | select(.type=="Ready" and .status=="True")] | length==1)' >/dev/null || exit 1
# La cadena se mira desde un cliente que lleva solo la raiz de cert-manager, copiada en este momento.
RAIZ=$($K -n cert-manager get secret raiz-lab -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d)
test -n "$RAIZ" || exit 1
echo "$RAIZ" | $K -n ribera exec -i cliente-tls -- sh -c 'cat > /tmp/raiz-grader.crt' || exit 1
VER=$($K -n ribera exec cliente-tls -- sh -c "openssl s_client -connect entrada-lab-istio.dique:443 -servername letrero.lab.example -CAfile /tmp/raiz-grader.crt -verify_hostname letrero.lab.example -verify_return_error </dev/null 2>&1" 2>/dev/null)
echo "$VER" | grep -q 'Verify return code: 0 (ok)' || exit 1
echo "$VER" | grep -q 'Verification: OK' || exit 1
CUERPO=$($K -n ribera exec cliente-tls -- curl -s -m 5 --cacert /tmp/raiz-grader.crt --connect-to letrero.lab.example:443:entrada-lab-istio.dique:443 https://letrero.lab.example/ 2>/dev/null)
test "$CUERPO" = "letrero: salida 7 puntual" || exit 1
SERIE=$($K -n ribera exec cliente-tls -- sh -c "openssl s_client -connect entrada-lab-istio.dique:443 -servername letrero.lab.example -CAfile /tmp/raiz-grader.crt </dev/null 2>/dev/null | openssl x509 -noout -serial" 2>/dev/null | sed -n 's/^serial=//p')
test -n "$SERIE" || exit 1
$K -n ribera exec cliente-tls -- rm -f /tmp/raiz-grader.crt >/dev/null 2>&1
grep -qxF "CERTIFICADO=letrero-tls" "$D/04-respuesta.txt" || exit 1
grep -qxF "EMISOR=casa-emisora" "$D/04-respuesta.txt" || exit 1
grep -qxF "REVISION=$($K -n dique get certificate letrero-tls -o jsonpath='{.status.revision}')" "$D/04-respuesta.txt" || exit 1
grep -qxF "SERIE_SERVIDA=$SERIE" "$D/04-respuesta.txt" || exit 1
echo ok
