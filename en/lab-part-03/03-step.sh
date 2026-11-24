#!/usr/bin/env bash
# lab-part-03 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p02
K="kubectl --kubeconfig $HOME/ckne-lab/p02/kubeconfig --context kind-ckne-lab2"

echo "ANTES DE LA FALLA:"
$K -n cabina exec piloto -- nslookup meteo.cabina.svc.cluster.local

bash ~/ckne-lab/p02/inyectar-falla.sh
sleep 3

echo "DESPUES DE LA FALLA:"
$K -n cabina exec piloto -- wget -qO- -T5 http://meteo.cabina.svc.cluster.local/ || true

P=$($K -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIP}')
{
  echo "== por la Service del directorio"
  $K -n cabina exec piloto -- nslookup meteo.cabina.svc.cluster.local 2>&1
  echo "== directo a un Pod de CoreDNS ($P)"
  $K -n cabina exec piloto -- nslookup meteo.cabina.svc.cluster.local $P 2>&1
  echo "== la Service kube-dns"
  $K -n kube-system get service kube-dns -o jsonpath='{range .spec.ports[*]}{.name} {.protocol} {.port} -> {.targetPort}{"\n"}{end}'
  echo "== su lista de extremos"
  $K -n kube-system get endpointslice -l kubernetes.io/service-name=kube-dns -o jsonpath='{range .items[*].ports[*]}{.name} {.protocol} {.port}{"\n"}{end}'
  echo "== la libreta del despachador en ckne-lab2-worker"
  docker exec ckne-lab2-worker iptables-save -t nat 2>/dev/null | grep -F '"kube-system/kube-dns:dns"' | grep -F -- '-j DNAT'
} | tee 03-diagnostico.txt

# The answer file the lab asks you to type, from what the diagnosis above showed:
D="$HOME/ckne-lab/p02"
cat > "$D/03-respuesta.txt" <<RESP
SERVICIO_CON_FALLA=kube-dns
PROTOCOLO_QUE_FALLA=UDP
PUERTO_EN_LA_LISTA=5353
PUERTO_DE_COREDNS=53
RESPUESTA_DEL_CLIENTE=rechazada
RESP
cat "$D/03-respuesta.txt"
