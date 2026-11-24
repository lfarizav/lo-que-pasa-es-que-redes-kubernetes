#!/usr/bin/env bash
# lab-part-05 step 6 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-id"
test -f "$D/06-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab5-id || exit 1
$K get nodes -o json 2>/dev/null | jq -e '(.items | length == 2) and ([.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 2)' >/dev/null || exit 1
test "$($K -n spire-server get statefulset spire-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
test "$($K -n spire-server get daemonset spire-agent -o jsonpath='{.status.numberReady}' 2>/dev/null)" -ge 1 || exit 1
test "$($K -n spire-server get configmap spire-server -o jsonpath='{.data.server\.conf}' 2>/dev/null | jq -r '.server.trust_domain')" = "lab.test" || exit 1
$K -n istio-system get deployment istiod -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q ':1.32.0' || exit 1
$K -n istio-system get configmap istio -o jsonpath='{.data.mesh}' 2>/dev/null | grep -q 'trustDomain: lab.test' || exit 1
test "$($K get namespace cubierta -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)" = "enabled" || exit 1
for sa in capitan invitado bascula; do $K -n cubierta get serviceaccount $sa >/dev/null 2>&1 || exit 1; done
test "$($K -n cubierta get deployment bascula -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
test "$($K -n cubierta get deployment bascula -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)" = "bascula" || exit 1
test "$($K -n cubierta get deployment bascula -o jsonpath='{.spec.template.metadata.annotations.inject\.istio\.io/templates}' 2>/dev/null)" = "sidecar,spire" || exit 1
BP=$($K -n cubierta get pod -l app=bascula -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
BUID=$($K -n cubierta get pod "$BP" -o jsonpath='{.metadata.uid}' 2>/dev/null)
test -n "$BP" && test -n "$BUID" || exit 1
# El documento que tiene el sidecar ahora mismo: de SPIRE y con el URI del dominio de confianza del laboratorio.
CERT=$("$D/bin/istioctl" --kubeconfig "$D/kubeconfig" --context kind-ckne-lab5-id proxy-config secret -n cubierta "$BP" -o json 2>/dev/null | jq -r '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d 2>/dev/null)
test -n "$CERT" || exit 1
echo "$CERT" | openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -qF 'URI:spiffe://lab.test/ns/cubierta/sa/bascula' || exit 1
echo "$CERT" | openssl x509 -noout -subject 2>/dev/null | grep -qE 'O ?= ?SPIRE' || exit 1
ENT=$($K -n spire-server exec spire-server-0 -c spire-server -- spire-server entry show -output json 2>/dev/null)
echo "$ENT" | jq -e --arg u "k8s:pod-uid:$BUID" '[.entries[] | select(.spiffe_id.path=="/ns/cubierta/sa/bascula" and (.selectors[] | select((.type + ":" + .value)==$u)))] | length==1' >/dev/null || exit 1
test "$($K -n cubierta get pod portador -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)" = "capitan" || exit 1
$K -n cubierta get pod portador -o json 2>/dev/null | jq -e '[.spec.volumes[] | .projected.sources[]? | .serviceAccountToken // empty | select(.audience=="bascula" and .expirationSeconds==900)] | length==1' >/dev/null || exit 1
TOK=$($K -n cubierta exec portador -c sh -- cat /var/run/pase/token 2>/dev/null | jq -R 'split(".")[1] | @base64d | fromjson')
echo "$TOK" | jq -e '(.aud==["bascula"]) and (.sub=="system:serviceaccount:cubierta:capitan") and ((.exp - .iat)==900)' >/dev/null || exit 1
N=$(echo "$ENT" | jq '[.entries[] | select(.spiffe_id.path | startswith("/ns/cubierta/"))] | length')
grep -qxF "ID_DE_LA_BASCULA=spiffe://lab.test/ns/cubierta/sa/bascula" "$D/06-respuesta.txt" || exit 1
grep -qxF "EMISOR_DE_LA_IDENTIDAD=SPIRE" "$D/06-respuesta.txt" || exit 1
grep -qxF "AUDIENCIA_DEL_PASE=bascula" "$D/06-respuesta.txt" || exit 1
grep -qxF "VIDA_DEL_PASE=900" "$D/06-respuesta.txt" || exit 1
grep -qxF "ENTRADAS_DE_CUBIERTA=$N" "$D/06-respuesta.txt" || exit 1
echo ok
