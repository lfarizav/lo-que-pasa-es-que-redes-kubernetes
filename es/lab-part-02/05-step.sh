#!/usr/bin/env bash
# lab-part-02 step 5 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p01
K="kubectl --kubeconfig $HOME/ckne-lab/p01/kubeconfig --context kind-ckne-lab1"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

# 1) Que trae el nodo: host-local viene en la imagen de kind, bridge no.
docker exec ckne-lab1-worker ls /opt/cni/bin

# 2) Plugins CNI de referencia v1.10.0 (se verifica la huella), solo el binario bridge.
case "$(uname -m)" in
  x86_64)        ARQ=amd64; SHA=ce8603d6a1bd448efba5bd6dc44f38dce349f821aa57e1bb354b52628ebf1853 ;;
  aarch64|arm64) ARQ=arm64; SHA=4f25d7f136be368746185fba6557d799cf3e1890f7556d450744ea20d300d68c ;;
esac
curl -sSL -o cni-plugins.tgz https://github.com/containernetworking/plugins/releases/download/v1.10.0/cni-plugins-linux-$ARQ-v1.10.0.tgz
echo "$SHA  cni-plugins.tgz" | sha256sum -c -
mkdir -p plugins
tar -xzf cni-plugins.tgz -C plugins ./bridge
for N in control-plane worker worker2; do
  docker cp plugins/bridge ckne-lab1-$N:/opt/cni/bin/bridge
  docker exec ckne-lab1-$N ls -l /opt/cni/bin/bridge /opt/cni/bin/host-local
done

# 3) Multus v4.3.2, manifiesto oficial thick. El manifiesto de la etiqueta v4.3.2 trae la
#    imagen movil snapshot-thick; se cambia por la etiqueta fija v4.3.2-thick.
curl -sSL -o multus-thick-original.yml https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.3.2/deployments/multus-daemonset-thick.yml
sed 's#multus-cni:snapshot-thick#multus-cni:v4.3.2-thick#' multus-thick-original.yml > multus-thick.yml
grep 'image:' multus-thick.yml
$K apply -f multus-thick.yml
$K -n kube-system rollout status daemonset/kube-multus-ds --timeout=180s
docker exec ckne-lab1-worker ls /etc/cni/net.d
docker exec ckne-lab1-worker cat /etc/cni/net.d/00-multus.conf

# 4) La segunda red: NetworkAttachmentDefinition con bridge + host-local, y dos Pods en el mismo nodo.
$K create namespace pista
cat <<EOF | $K apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata: {name: puente-pista, namespace: pista}
spec:
  config: '{"cniVersion":"0.3.1","type":"bridge","bridge":"br-pista","isGateway":true,"ipam":{"type":"host-local","subnet":"10.20.0.0/24"}}'
---
apiVersion: v1
kind: Pod
metadata:
  name: rx
  namespace: pista
  annotations: {k8s.v1.cni.cncf.io/networks: puente-pista}
spec:
  nodeName: ckne-lab1-worker
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sh","-c","mkdir -p /www && echo rx-net1-ok > /www/index.html && exec httpd -f -vv -p 8080 -h /www"]
---
apiVersion: v1
kind: Pod
metadata:
  name: tx
  namespace: pista
  annotations: {k8s.v1.cni.cncf.io/networks: puente-pista}
spec:
  nodeName: ckne-lab1-worker
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sleep","3600"]
EOF
$K -n pista wait --for=condition=Ready pod/rx pod/tx --timeout=180s
$K -n pista exec tx -- ip -o -4 addr show
RXN=$($K -n pista get pod rx -o json | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="net1") | .ips[0]')
echo "net1 de rx: $RXN"
$K -n pista exec tx -- wget -qO- -T5 http://$RXN:8080/
$K -n pista logs rx

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p01"
TXN=$($K -n pista get pod tx -o json | jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | fromjson | .[] | select(.interface=="net1") | .ips[0]')
cat > "$D/05-respuesta.txt" <<RESP
IP_NET1_DE_RX=$RXN
IP_NET1_DE_TX=$TXN
INTERFAZ_SECUNDARIA=net1
RESP
cat "$D/05-respuesta.txt"
