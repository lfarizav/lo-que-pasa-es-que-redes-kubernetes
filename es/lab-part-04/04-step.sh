#!/usr/bin/env bash
# lab-part-04 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p03
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"
FRR=quay.io/frrouting/frr:10.7.1@sha256:e995beaa50fdc9edb35eadcfefa29b7f062cc06f2b812613789b68fa541554d2
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

# 1) MetalLB 0.16.2 (su paquete de Helm trae FRR-K8s como motor de BGP).
helm install metallb metallb --repo https://metallb.github.io/metallb --version 0.16.2 \
  --kubeconfig "$D/kubeconfig" --kube-context kind-ckne-lab3 \
  -n metallb-system --create-namespace --wait --timeout 300s >/dev/null
$K -n metallb-system get pods -o custom-columns=POD:.metadata.name,FASE:.status.phase

# 2) El enrutador vecino: un contenedor FRR (AS 64600) que acepta sesiones de cualquier
#    direccion de la red kind y las trata como el AS 64601 del cluster.
RED=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' | grep -E '^[0-9.]+/[0-9]+$')
mkdir -p frontera
printf 'zebra=yes\nbgpd=yes\n' > frontera/daemons
: > frontera/vtysh.conf
cat > frontera/frr.conf <<EOF
frr defaults traditional
hostname frontera
router bgp 64600
 no bgp ebgp-requires-policy
 neighbor NODOS peer-group
 neighbor NODOS remote-as 64601
 bgp listen range $RED peer-group NODOS
EOF
docker run -d --name ckne-lab3-frontera --network kind --privileged \
  -v "$D/frontera/frr.conf:/etc/frr/frr.conf" -v "$D/frontera/daemons:/etc/frr/daemons" \
  -v "$D/frontera/vtysh.conf:/etc/frr/vtysh.conf" "$FRR" >/dev/null
FRONTERA=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ckne-lab3-frontera)
echo "frontera en $FRONTERA"

# 3) El rango que MetalLB reparte (198.51.100.0/24 es TEST-NET-2, RFC 5737), el vecino y el anuncio.
cat <<EOF | $K apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: rango-lab, namespace: metallb-system}
spec:
  addresses: ["198.51.100.10-198.51.100.20"]
---
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata: {name: frontera, namespace: metallb-system}
spec:
  myASN: 64601
  peerASN: 64600
  peerAddress: $FRONTERA
---
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata: {name: anuncio-lab, namespace: metallb-system}
spec:
  ipAddressPools: [rango-lab]
EOF

# 4) Una Service LoadBalancer, vitrina, con dos replicas que contestan su nombre.
cat <<EOF | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: vitrina, namespace: envios}
spec:
  replicas: 2
  selector: {matchLabels: {app: vitrina}}
  template:
    metadata: {labels: {app: vitrina}}
    spec:
      containers:
      - name: web
        image: $BUSYBOX
        command: ["sh", "-c", "mkdir -p /www && hostname > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: vitrina, namespace: envios}
spec:
  type: LoadBalancer
  selector: {app: vitrina}
  ports: [{port: 80, targetPort: 8080}]
EOF
$K -n envios rollout status deployment/vitrina --timeout=180s
sleep 20
LB=$($K -n envios get service vitrina -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "vitrina en $LB"

# 5) La ruta se comprueba en la tabla del vecino, no en el estado de la Service.
sleep 20
docker exec ckne-lab3-frontera vtysh -c "show bgp summary" | awk '/^\*[0-9]/ {print $1, $3, $10}'
docker exec ckne-lab3-frontera vtysh -c "show ip route bgp" | grep -E "198\.51\.100|via"
docker exec ckne-lab3-frontera wget -qO- -T5 "http://$LB/"
$K get nodes -o custom-columns=NODO:.metadata.name,IP:.status.addresses[0].address

# The answer file the lab asks you to type, from the neighbor's table:
D="$HOME/ckne-lab/p03"
cat > "$D/04-respuesta.txt" <<RESP
IP_ANUNCIADA=$LB
SALTOS_HACIA_LA_IP=$(docker exec ckne-lab3-frontera vtysh -c "show ip route $LB/32 json" | jq --arg p "$LB/32" '.[$p][0].nexthops | length')
AS_DEL_CLUSTER=$($K -n metallb-system get bgppeer.v1beta2.metallb.io frontera -o jsonpath='{.spec.myASN}')
RESP
cat "$D/04-respuesta.txt"
