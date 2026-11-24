#!/usr/bin/env bash
# lab-part-05 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p04
D="$HOME/ckne-lab/p04"
NODO=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
NETSHOOT=nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-cifra"
H="--kubeconfig $D/kubeconfig --kube-context kind-ckne-lab5-cifra"

cat > cifra-kind.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
nodes:
- role: control-plane
- role: worker
- role: worker
YAML
kind create cluster --name ckne-lab5-cifra --config cifra-kind.yaml --image "$NODO" --kubeconfig "$D/kubeconfig"
cat > cilium-valores.yaml <<'YAML'
image:
  pullPolicy: IfNotPresent
ipam:
  mode: kubernetes
YAML
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 -n kube-system -f cilium-valores.yaml $H >/dev/null
$K -n kube-system rollout status daemonset/cilium --timeout=300s
$K wait --for=condition=Ready node --all --timeout=180s

$K create namespace faro
cat <<YAML | $K apply -f -
apiVersion: v1
kind: Pod
metadata: {name: origen, namespace: faro}
spec:
  nodeName: ckne-lab5-cifra-worker
  containers: [{name: sh, image: $NETSHOOT, command: ["sleep", "7200"]}]
---
apiVersion: v1
kind: Pod
metadata: {name: destino, namespace: faro}
spec:
  nodeName: ckne-lab5-cifra-worker2
  containers: [{name: web, image: nginx:1.29.5-alpine}]
---
apiVersion: v1
kind: Pod
metadata: {name: puente, namespace: faro}
spec:
  nodeName: ckne-lab5-cifra-worker2
  hostNetwork: true
  containers: [{name: web, image: nginx:1.29.5-alpine}]
YAML
$K -n faro wait --for=condition=Ready pod --all --timeout=180s
$K -n faro get pods -o custom-columns=NOMBRE:.metadata.name,IP:.status.podIP,NODO:.spec.nodeName

# La captura: escucha una interfaz del nodo mientras alguien pide un destino con una ficha que no existe en ninguna otra parte.
cat > captura.sh <<'CAP'
#!/usr/bin/env bash
# Uso: bash captura.sh NODO INTERFAZ ORIGEN DESTINO
# Escucha INTERFAZ de NODO mientras ORIGEN (un Pod de faro o un nodo) pide DESTINO (un Pod de faro)
# con una ficha nueva en un encabezado, y cuenta lo que quedo legible y los paquetes UDP.
D="$HOME/ckne-lab/p04"; N=$1; I=$2; O=$3; DEST=$4
NS=nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70
KK="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-cifra"
T="ficha-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
IP=$($KK -n faro get pod $DEST -o jsonpath='{.status.podIP}')
rm -f "$D/cap.pcap"
docker run -d --rm --name mirador-lab5 -v "$D":/c --network container:$N $NS \
  tcpdump -i $I -nn -U -w /c/cap.pcap >/dev/null 2>&1
sleep 3
C="curl -s -m 3 -o /dev/null -w %{http_code} -H Ficha:$T http://$IP/"
if [[ $O == ckne-lab5-cifra-* ]]; then docker exec $O $C; else $KK -n faro exec $O -- $C; fi
echo " exit $?"
sleep 2; docker stop mirador-lab5 >/dev/null
r() { docker run --rm -v "$D":/c $NS tcpdump -r /c/cap.pcap -nn "$@" 2>/dev/null; }
echo "ficha-legible $(r -A | grep -c "$T")"
echo "udp-51871 $(r udp port 51871 | wc -l)"
echo "udp-8472 $(r udp port 8472 | wc -l)"
rm -f "$D/cap.pcap"
CAP

echo "ANTES de cifrar: de origen a destino, mirando eth0 del nodo de origen"
bash captura.sh ckne-lab5-cifra-worker eth0 origen destino

# El cifrado se pide al plugin de red; los agentes lo toman al reiniciar.
cat > cifrado.yaml <<'YAML'
encryption:
  enabled: true
  type: wireguard
YAML
helm upgrade cilium cilium --repo https://helm.cilium.io --version 1.20.5 -n kube-system -f cilium-valores.yaml -f cifrado.yaml $H >/dev/null
$K -n kube-system rollout restart daemonset/cilium
$K -n kube-system rollout status daemonset/cilium --timeout=300s
sleep 20
for n in control-plane worker worker2; do
  P=$($K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=ckne-lab5-cifra-$n -o name)
  echo "$n: $($K -n kube-system exec $P -c cilium-agent -- cilium-dbg status | grep -E '^Encryption:' | tr -s ' ')"
done

echo "DESPUES de cifrar: de origen a destino, eth0 del nodo de origen"
bash captura.sh ckne-lab5-cifra-worker eth0 origen destino
echo "DESPUES de cifrar: del nodo de origen al Pod puente (red del nodo de destino), eth0"
bash captura.sh ckne-lab5-cifra-worker eth0 ckne-lab5-cifra-worker puente

# The answer file the lab asks you to type, from fresh captures and the agents:
D="$HOME/ckne-lab/p04"
M1=$(bash captura.sh ckne-lab5-cifra-worker eth0 origen destino)
M2=$(bash captura.sh ckne-lab5-cifra-worker eth0 ckne-lab5-cifra-worker puente)
N=0
for n in control-plane worker worker2; do
  P=$($K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=ckne-lab5-cifra-$n -o name)
  $K -n kube-system exec $P -c cilium-agent -- cilium-dbg status | grep -qE '^Encryption: +Wireguard' && N=$((N+1))
done
cat > "$D/03-respuesta.txt" <<RESP
AGENTES_CON_WIREGUARD=$N
FICHA_LEGIBLE_ENTRE_PODS=$(echo "$M1" | awk '$1=="ficha-legible" {print $2}')
UDP_51871_ENTRE_PODS=$(echo "$M1" | awk '$1=="udp-51871" {print ($2>0 ? "si" : "no")}')
FICHA_LEGIBLE_HACIA_EL_PUENTE=$(echo "$M2" | awk '$1=="ficha-legible" {print $2}')
RESP
cat "$D/03-respuesta.txt"
