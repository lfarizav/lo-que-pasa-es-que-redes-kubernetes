#!/usr/bin/env bash
# lab-part-03 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p02
K="kubectl --kubeconfig $HOME/ckne-lab/p02/kubeconfig --context kind-ckne-lab2"

$K -n kube-system get deployment coredns -o jsonpath='{range .spec.template.spec.containers[0].ports[*]}{.name} {.protocol} {.containerPort}{"\n"}{end}'
$K -n kube-system get service kube-dns -o jsonpath='{range .spec.ports[*]}{.name} {.protocol} {.port} -> {.targetPort}{"\n"}{end}'

$K -n kube-system patch service kube-dns --type=json \
  -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":53}]'
$K -n kube-system get service kube-dns -o jsonpath='{range .spec.ports[*]}{.name} {.protocol} {.port} -> {.targetPort}{"\n"}{end}'
sleep 3

docker exec ckne-lab2-worker iptables-save -t nat 2>/dev/null | grep -F '"kube-system/kube-dns:dns"' | grep -F -- '-j DNAT'
$K -n cabina exec piloto -- nslookup meteo.cabina.svc.cluster.local
$K -n cabina exec piloto -- wget -qO- -T5 http://meteo.cabina.svc.cluster.local/

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p02"
if [ "$($K -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.corefile.sha256")" ]; then INTACTO=si; else INTACTO=no; fi
cat > "$D/04-respuesta.txt" <<RESP
PUERTO_DESTINO_RESTAURADO=$($K -n kube-system get service kube-dns -o jsonpath='{.spec.ports[?(@.name=="dns")].targetPort}')
IP_DEL_DIRECTORIO=$($K -n kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}')
COREFILE_INTACTO=$INTACTO
RESP
cat "$D/04-respuesta.txt"
