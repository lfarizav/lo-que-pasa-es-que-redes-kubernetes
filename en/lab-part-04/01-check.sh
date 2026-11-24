#!/usr/bin/env bash
# lab-part-04 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c
test -f "$D/01-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab3 || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
test "$(echo "$NODOS" | jq '.items | length')" -eq 3 || exit 1
echo "$NODOS" | jq -e '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 3' >/dev/null || exit 1
echo "$NODOS" | jq -e '[.items[].status.nodeInfo.kubeletVersion] | unique == ["v1.37.0"]' >/dev/null || exit 1
$K -n kube-system get daemonset kube-proxy >/dev/null 2>&1 && exit 1
$K -n kube-system get daemonset kindnet >/dev/null 2>&1 && exit 1
IMG=$($K -n kube-system get daemonset cilium -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$IMG" in *:v1.20.5*) ;; *) exit 1 ;; esac
test "$($K -n kube-system get daemonset cilium -o jsonpath='{.status.numberReady}')" = "3" || exit 1
CFG=$($K -n kube-system get configmap cilium-config -o json 2>/dev/null)
echo "$CFG" | jq -e '.data["kube-proxy-replacement"]=="true" and .data["enable-egress-gateway"]=="true" and .data["enable-bpf-masquerade"]=="true"' >/dev/null || exit 1
test "$($K get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null)" = "v1.6.1" || exit 1
$K get crd inferencepools.inference.networking.k8s.io >/dev/null 2>&1 || exit 1
ISTIOD=$($K -n istio-system get deployment istiod -o json 2>/dev/null)
echo "$ISTIOD" | jq -e '(.spec.template.spec.containers[0].image | endswith(":1.32.0")) and .status.readyReplicas==1' >/dev/null || exit 1
echo "$ISTIOD" | jq -e '[.spec.template.spec.containers[0].env[] | select(.name=="ENABLE_GATEWAY_API_INFERENCE_EXTENSION" and .value=="true")] | length == 1' >/dev/null || exit 1
test "$($K -n imprenta get deployment redactor -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "2" || exit 1
OCU=$($K -n imprenta get deployment redactor-ocupado -o json 2>/dev/null)
echo "$OCU" | jq -e '.spec.replicas==1 and .status.readyReplicas==1 and (.spec.template.spec.containers[0].args | index("--fake-metrics") != null) and (.spec.template.spec.containers[0].args | join(" ") | test("\"waiting-requests\":30"))' >/dev/null || exit 1
PODS=$($K -n imprenta get pods -l grupo=redaccion -o json 2>/dev/null)
echo "$PODS" | jq -e '[.items[] | select(.status.phase=="Running" and .metadata.deletionTimestamp==null)] | length == 3' >/dev/null || exit 1
OCUPADO=$(echo "$PODS" | jq -r '[.items[] | select(.metadata.labels.app=="redactor-ocupado" and .status.phase=="Running")][0].metadata.name')
test -n "$OCUPADO" && test "$OCUPADO" != "null" || exit 1
LIBRES=$(echo "$PODS" | jq -r '[.items[] | select(.metadata.labels.app=="redactor") | .metadata.name] | join(" ")')
POOL=$($K -n imprenta get inferencepool redaccion -o json 2>/dev/null)
echo "$POOL" | jq -e '.spec.selector.matchLabels == {"grupo":"redaccion"} and .spec.targetPorts[0].number==8000 and .spec.endpointPickerRef.name=="elector" and .spec.endpointPickerRef.port.number==9002' >/dev/null || exit 1
echo "$POOL" | jq -e '[.status.parents[].conditions[] | select((.type=="Accepted" or .type=="ResolvedRefs") and .status=="True")] | length == 2' >/dev/null || exit 1
test "$($K -n imprenta get deployment elector -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
$K -n imprenta get gateway portico -o json 2>/dev/null | jq -e '.spec.gatewayClassName=="istio" and any(.status.conditions[]; .type=="Programmed" and .status=="True")' >/dev/null || exit 1
$K -n imprenta get httproute por-el-grupo -o json 2>/dev/null | jq -e '.spec.hostnames==["grupo.imprenta.example"] and .spec.rules[0].backendRefs[0].kind=="InferencePool" and .spec.rules[0].backendRefs[0].name=="redaccion" and ([.status.parents[].conditions[] | select((.type=="Accepted" or .type=="ResolvedRefs") and .status=="True")] | length == 2)' >/dev/null || exit 1
$K -n imprenta get httproute por-la-service -o json 2>/dev/null | jq -e '.spec.hostnames==["service.imprenta.example"] and .spec.rules[0].backendRefs[0].name=="redactores" and ([.status.parents[].conditions[] | select((.type=="Accepted" or .type=="ResolvedRefs") and .status=="True")] | length == 2)' >/dev/null || exit 1
GIP=$($K -n imprenta get service portico-istio -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
test -n "$GIP" || exit 1
sonda() { # host repeticiones
  local S="sonda-$RANDOM$RANDOM"
  local P="for i in \$(seq $2); do curl -s -m 5 -o /dev/null -w '%header{x-inference-pod} %{http_code}\n' -H 'Host: $1' -d '{\"model\":\"redaccion\",\"prompt\":\"sonda\"}' http://$GIP/v1/completions; done"
  $K -n imprenta run "$S" --image=$CURL --restart=Never --command -- sh -c "$P" >/dev/null 2>&1 || return 1
  $K -n imprenta wait --for=jsonpath='{.status.phase}'=Succeeded pod/$S --timeout=120s >/dev/null 2>&1
  $K -n imprenta logs "$S" 2>/dev/null
  $K -n imprenta delete pod "$S" --ignore-not-found >/dev/null 2>&1
}
G=$(sonda grupo.imprenta.example 16)
test "$(echo "$G" | grep -c ' 200$')" = "16" || exit 1
echo "$G" | grep -qF "$OCUPADO" && exit 1
for L in $LIBRES; do echo "$G" | grep -qF "$L " || exit 1; done
S=$(sonda service.imprenta.example 24)
test "$(echo "$S" | grep -c ' 200$')" = "24" || exit 1
echo "$S" | grep -qF "$OCUPADO " || exit 1
grep -qxF "SERVICE_DEL_PORTICO=portico-istio" "$D/01-respuesta.txt" || exit 1
grep -qxF "POD_QUE_EL_ELECTOR_EVITA=$OCUPADO" "$D/01-respuesta.txt" || exit 1
grep -qxF "PUERTO_DEL_ELECTOR=9002" "$D/01-respuesta.txt" || exit 1
echo ok
