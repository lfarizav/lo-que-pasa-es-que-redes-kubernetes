#!/usr/bin/env bash
# lab-part-03 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p02
K="kubectl --kubeconfig $HOME/ckne-lab/p02/kubeconfig --context kind-ckne-lab2"

cat <<'EOF' | $K apply -f -
apiVersion: v1
kind: Service
metadata: {name: meteo-calle, namespace: cabina}
spec:
  type: NodePort
  selector: {app: meteo}
  ports: [{name: http, port: 80, targetPort: web, nodePort: 30380}]
EOF

W1=$($K get node ckne-lab2-worker -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
W2=$($K get node ckne-lab2-worker2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
sleep 2
curl -s -m5 http://$W1:30380/
curl -s -m5 http://$W2:30380/

$K -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' | grep '^mode:'
docker exec ckne-lab2-worker iptables-save -t nat 2>/dev/null | grep -F '"cabina/meteo:http"' | grep -F -- '-j DNAT'

curl -s -m5 http://$W1:30380/
docker exec ckne-lab2-worker conntrack -L -p tcp --dport 30380 2>&1 | tee 02-conntrack.txt

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p02"
cat > "$D/02-respuesta.txt" <<RESP
MODO_DE_KUBE_PROXY=$($K -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' | sed -n 's/^mode: *//p')
CADENAS_DE_EXTREMO=$(docker exec ckne-lab2-worker iptables-save -t nat 2>/dev/null | grep -F '"cabina/meteo:http"' | grep -cF -- '-j DNAT')
PUERTO_DE_NODO=$($K -n cabina get service meteo-calle -o jsonpath='{.spec.ports[0].nodePort}')
RESP
cat "$D/02-respuesta.txt"
