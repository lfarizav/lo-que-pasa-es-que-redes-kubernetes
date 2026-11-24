#!/usr/bin/env bash
# lab-part-05 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p04
D="$HOME/ckne-lab/p04"
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-red"

$K create namespace verbena
$K label namespace verbena zona=verbena
cat <<YAML | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: mostrario, namespace: verbena}
spec:
  replicas: 1
  selector: {matchLabels: {app: mostrario}}
  template:
    metadata: {labels: {app: mostrario}}
    spec:
      containers:
      - name: web
        image: nginx:1.29.5-alpine
---
apiVersion: v1
kind: Service
metadata: {name: mostrario, namespace: verbena}
spec:
  selector: {app: mostrario}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: abre-a-todos, namespace: verbena}
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - {}
YAML
$K -n verbena rollout status deployment/mostrario --timeout=180s

cat > matriz-verbena.sh <<'MATRIZ'
K="kubectl --kubeconfig $HOME/ckne-lab/p04/kubeconfig --context kind-ckne-lab5-red"
for c in maestranza/operario afuera/operario; do
  printf "%-22s " $c
  $K -n ${c%/*} exec ${c#*/} -- curl -s -m 3 -o /dev/null -w "%{http_code}" http://mostrario.verbena/ 2>/dev/null
  echo " exit $?"
done
MATRIZ
sleep 10
echo "ANTES de la capa del administrador (la NetworkPolicy abre a todos):"
bash matriz-verbena.sh

# La capa del administrador: una ClusterNetworkPolicy del nivel Admin, que gana a cualquier NetworkPolicy.
cat <<YAML | $K apply -f -
apiVersion: policy.networking.k8s.io/v1alpha2
kind: ClusterNetworkPolicy
metadata: {name: cierre-de-afuera}
spec:
  tier: Admin
  priority: 10
  subject:
    namespaces:
      matchLabels: {zona: verbena}
  ingress:
  - name: sin-afuera
    action: Deny
    from:
    - namespaces:
        matchLabels: {zona: afuera}
YAML
sleep 8
echo "DESPUES de la capa del administrador:"
bash matriz-verbena.sh

# The answer file the lab asks you to type, from the objects above:
D="$HOME/ckne-lab/p04"
cat > "$D/02-respuesta.txt" <<RESP
NIVEL=$($K get clusternetworkpolicy cierre-de-afuera -o jsonpath='{.spec.tier}')
ACCION=$($K get clusternetworkpolicy cierre-de-afuera -o jsonpath='{.spec.ingress[0].action}')
NETWORKPOLICY_INTACTA=$($K -n verbena get networkpolicy abre-a-todos >/dev/null 2>&1 && echo si || echo no)
RESP
cat "$D/02-respuesta.txt"
