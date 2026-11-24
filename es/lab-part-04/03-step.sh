#!/usr/bin/env bash
# lab-part-04 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p03
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"
NGINX=nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c

# 1) La red de docker donde viven los nodos, y la direccion fija que va a usar la salida:
#    la .250 del mismo segmento que el gateway de esa red.
RED=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' | grep -E '^[0-9.]+/[0-9]+$')
PREFIJO=${RED#*/}
GW=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -E '^[0-9.]+$')
IP_FIJA="${GW%.*}.250"
echo "red $RED, direccion fija $IP_FIJA"

# 2) Un servidor fuera del cluster, en la misma red: un contenedor nginx que anota quien llega.
docker run -d --name ckne-lab3-buzon --network kind "$NGINX" >/dev/null
BUZON=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ckne-lab3-buzon)
echo "buzon en $BUZON"

# 3) Dos Pods en el mismo trabajador: remitente (turno=noche) y testigo (sin esa etiqueta).
$K create namespace envios
for P in remitente testigo; do
  $K -n envios run $P --image=$CURL --overrides='{"spec":{"nodeName":"ckne-lab3-worker"}}' --command -- sleep 7200
done
$K -n envios label pod remitente turno=noche
$K -n envios wait --for=condition=Ready pod/remitente pod/testigo --timeout=180s

# 4) Antes de la politica: los dos salen con la IP de su nodo.
for P in remitente testigo; do
  $K -n envios exec $P -- curl -s -o /dev/null -w "$P %{http_code}\n" http://$BUZON/antes-$P
done
docker logs ckne-lab3-buzon 2>/dev/null | grep -E '/antes-' | awk '{print $1, $7}'

# 5) El nodo puerta: ckne-lab3-worker2 recibe la direccion fija en eth0 y la etiqueta egreso=si.
docker exec ckne-lab3-worker2 ip addr add "$IP_FIJA/$PREFIJO" dev eth0
docker exec ckne-lab3-worker2 ip -4 -o addr show eth0 | awk '{print $4}'
$K label node ckne-lab3-worker2 egreso=si

# 6) La politica: los Pods turno=noche de envios, hacia el buzon, salen por worker2 con IP_FIJA.
cat <<EOF | $K apply -f -
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: noche-con-ip-fija
spec:
  selectors:
  - podSelector:
      matchLabels:
        turno: noche
        io.kubernetes.pod.namespace: envios
  destinationCIDRs: ["$BUZON/32"]
  egressGateway:
    nodeSelector:
      matchLabels: {egreso: si}
    egressIP: $IP_FIJA
EOF
sleep 5

# 7) Despues de la politica, comprobado en el destino y no en la politica.
for P in remitente testigo; do
  $K -n envios exec $P -- curl -s -o /dev/null -w "$P %{http_code}\n" http://$BUZON/despues-$P
done
docker logs ckne-lab3-buzon 2>/dev/null | grep -E '/despues-' | awk '{print $1, $7}'
AGENTE=$($K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=ckne-lab3-worker2 -o name)
$K -n kube-system exec "$AGENTE" -c cilium-agent -- cilium-dbg bpf egress list

# The answer file the lab asks you to type, from what the destination recorded:
D="$HOME/ckne-lab/p03"
cat > "$D/03-respuesta.txt" <<RESP
IP_FIJA=$IP_FIJA
ORIGEN_DEL_TESTIGO_EN_EL_DESTINO=$(docker logs ckne-lab3-buzon 2>/dev/null | awk '$7=="/despues-testigo" {print $1}' | tail -1)
NODO_PUERTA=$($K get nodes -l egreso=si -o jsonpath='{.items[0].metadata.name}')
RESP
cat "$D/03-respuesta.txt"
