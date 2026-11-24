# Part III - Lab: the cabina namespace with its endpoint list, the dispatcher that copies it on every node, a directory that stops answering and an entrance with the Gateway API

- Time: 60 min
- Points: 60

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the step's command sequence lives in its cmd field for you to reveal after trying on your own. The exception is Step 6: it states the objective only, no command is published anywhere in the repository, and its check depends on a token, a host name and a path that are different on every run. What gets built: Step 1 sets up the cluster ckne-lab2 (one control plane, two workers, Calico v3.33.0) and the cabina namespace with the meteo Deployment of three replicas with a readiness probe, its Service and its EndpointSlice (Chapter 6). Step 2 opens a NodePort Service on a fixed port, tests it from the host machine and follows that same connection through the rules kube-proxy wrote on the node and through the record left in conntrack (Chapters 6 and 7). Step 3 runs inyectar-falla.sh, a script that blindly breaks one piece of the name path: its content is encoded on purpose, as a courtesy blindfold and not as a real secret, and the answer key sits at the end in the answers file; with nslookup, the EndpointSlice and the node's rules you have to locate where it breaks (Chapters 6, 7 and 8). Step 4 repairs the cause and not the symptom: the check demands that the Corefile, the directory's IP and the Pods' DNS configuration stay as they were (Chapter 8). Step 5 installs the Gateway API v1.6.1 and Istio 1.32.0, brings up the rampa entrance and an HTTPRoute to meteo (Chapter 9). Step 6 is the exam in miniature: a route that crosses namespaces with data that change on every run, with no published command.

## Prerequisites

- A Linux machine with kind, kubectl, docker, jq, curl, tar, sha256sum and base64 on PATH, and at least 6 GB of free RAM for three nodes with Istio. The lab creates its own kind cluster named ckne-lab2 and deletes it in the teardown.
- ISOLATION. This lab's cluster NEVER touches your everyday kubeconfig: it is created with --kubeconfig ~/ckne-lab/p02/kubeconfig from the very first command, and every kubectl and istioctl in the lab passes an explicit --kubeconfig. If you already have other kind clusters, this lab does not see them, modify them or delete them. The setup prints kind get clusters before starting so you can check.
- Internet access throughout the lab: kind pulls the node image; Step 1 downloads Calico's manifest from raw.githubusercontent.com and its images from quay.io; Step 5 downloads the Gateway API CRDs and the istioctl binary from github.com, and Istio's images from docker.io; the Pods pull a digest-pinned busybox image from docker.io.
- PINNED VERSIONS, verified on 2026-11-19 on this same machine. kind v0.33.0 (minimum v0.33.0). kubectl v1.37.0. Node image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Calico v3.33.0 with the manifest https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml. Gateway API CRDs v1.6.1, standard channel, from https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml (the version the Istio 1.32 Gateway API task installs). Istio 1.32.0 with istioctl from https://github.com/istio/istio/releases/download/1.32.0/ (Step 5 verifies the archive's SHA-256) and the minimal profile. Pod image busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. A tag is mutable and a digest is not. Confirm what you actually got with kind version, kubectl version and istioctl version, never from memory.
- Having read Chapters 6, 7, 8 and 9. This lab does not re-explain what an EndpointSlice is, how kube-proxy writes its rules, how a Pod resolves a name or what an HTTPRoute is; it makes you operate them against a real cluster and grades the end state. The steps depend on each other: Steps 2 and 3 need the cluster and meteo from Step 1, Step 4 needs the fault from Step 3, and Steps 5 and 6 need the cluster from Step 1 with the directory already repaired in Step 4.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 6: The cabina namespace with three ready replicas, its Service and the endpoint list behind it (10 pts)

Chapter 6 separated two things that in practice get mixed up: the Service is a fixed number that announces a port, and the EndpointSlice is the list of who is serving right now and on which real port. This step puts both in plain view. Notice that the Service points at a named port (web) and not at a number: if the container changes its port tomorrow, the Service is not touched. The readiness probe is what decides who gets into the list, and it is why the rollout waits for each replica to answer before counting it as ready.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is accepting a Service that exists but has nobody behind it. The check closes that: it demands the cluster with three nodes Ready at v1.37.0, Calico v3.33.0 and no kindnet; the meteo Deployment with three ready replicas and a readiness probe; the meteo Service of type ClusterIP with the selector app=meteo and port 80; the piloto Pod Running; and an EndpointSlice with three ready=true endpoints and port 8080. Then it launches a fresh probe that asks the Service's IP (not its name, so it does not depend on DNS) and demands that one of meteo's live replicas answer. The lines in 01-respuesta.txt are compared with the live cluster.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to kind-ckne-lab2. calico-node's rollout status ends with successfully rolled out, the wait leaves the three nodes with condition met and CoreDNS gets deployed. Then the cabina namespace, the meteo Deployment, the meteo Service and the piloto Pod are created, and meteo's rollout ends with its three replicas available. get svc shows meteo as ClusterIP with an IP from the Service range (10.96.0.0/16 on kind) and port 80/TCP. The EndpointSlice lists three endpoints, each with an IP from 192.168.0.0/16, the name of its meteo Pod and ready=true; its ports say name http and port 8080: the Service announces 80, but the list keeps the container's real port, which the Service named web. piloto's wget returns the name of one of the replicas. Save in 01-respuesta.txt the lines CLUSTER_IP_DE_METEO=, EXTREMOS_LISTOS= and PUERTO_DE_LOS_EXTREMOS= with what you just saw.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 6 and 7: A door to the street on a fixed port, the dispatcher's notebook and the recorded conversation (10 pts)

A NodePort is the same Service with one more door: a port opened on every node that leads to the same endpoint list. The interesting part from Chapter 7 is who opens that door. It is not a process listening on 30380: it is kube-proxy, which wrote rules into each node's kernel, and the kernel translates the packet's destination on the fly. That is why the port also answers on a node that has no meteo Pod. The DNAT rules carrying the Service's comment are the dispatcher's notebook; conntrack is what the kernel recorded about each conversation already dispatched, and it is where you see which Pod a specific connection ended up at.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is opening port 30380 outside kube-proxy, with hostNetwork or hostPort on meteo's Pods, or counting the rules from memory. The check demands a NodePort Service named meteo-calle with the selector app=meteo and nodePort 30380, no meteo Pod with hostNetwork or hostPort, and an answer from a live replica from the host machine on BOTH workers. It reads kube-proxy's mode from its ConfigMap and counts on the node the DNAT rules of cabina/meteo:http, which must be as many as the list's ready endpoints. The file 02-conntrack.txt has to carry a conversation toward 30380 whose reply left the IP of a live meteo replica on port 8080, and on top of that the check makes its own call to 30380 on ckne-lab2-worker and reads conntrack live on that node, so a hand-typed file is not enough.

</details>

<details>
<summary>What you should see</summary>

The apply creates service/meteo-calle. Both curls from the host machine, one to each worker's IP on port 30380, return the name of a meteo replica: the node port opens on every node, whether or not it has a meteo Pod. The grep of kube-proxy's ConfigMap prints mode: iptables. The grep of iptables-save on ckne-lab2-worker shows three DNAT rules with the comment cabina/meteo:http, one per endpoint, each toward a Pod IP on port 8080: it is Step 1's list copied into the node's notebook. Finally, conntrack lists one or more TIME_WAIT connections with dport=30380 whose reply half comes from a Pod IP with sport=8080: the translation the dispatcher recorded for that conversation. Save in 02-respuesta.txt the lines MODO_DE_KUBE_PROXY=, CADENAS_DE_EXTREMO= and PUERTO_DE_NODO=.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 6, 7 and 8: The directory that stops answering, and where the path of a name gets cut (10 pts)

A name that does not resolve is the vaguest complaint of all, and that is why it pays to split the path into stretches, as in Chapter 8. The Pod asks the IP its resolv.conf gave it; that IP is a Service; the Service has an endpoint list; kube-proxy copied that list into the node's rules; and at the end there is a CoreDNS Pod listening on a port. Asking the CoreDNS Pod directly skips every stretch in the middle: if it answers there, the directory is healthy and the problem lies between the client and it. The exact word of the error is a clue too. A timeout, an NXDOMAIN and a rejection say different things: the NXDOMAIN is an answer from someone who knows the name does not exist; the rejection is the destination machine's kernel saying nobody listens on that port.

<details>
<summary>Grader hint (check_hint)</summary>

This check holds at two moments: with the fault in place and after repairing it. It demands that the mark showing the fault was applied exists and that 03-diagnostico.txt is evidence from this run: the rejection toward kube-dns's live IP, a correct answer from a Pod IP carrying meteo's live IP, the Service's dns UDP port pointing at 5353 and the DNAT rule of kube-system/kube-dns:dns toward that port. Then it measures the real state and cross-checks it with the cause: if the Service still points at the wrong port, a fresh probe CANNOT resolve meteo; if it was repaired, it CAN. A mix of the two fails, so faking the symptom or hiding it does not work. The shortcut of guessing without looking is closed by the lines in 03-respuesta.txt, which summarize what the evidence says.

</details>

<details>
<summary>What you should see</summary>

BEFORE THE FAULT, nslookup answers from server 10.96.0.10 with the meteo Service's IP. inyectar-falla.sh runs and prints falla inyectada. AFTER THE FAULT, the wget by name ends with bad address: the name no longer resolves. The diagnosis, saved in 03-diagnostico.txt, separates the pieces. Through the directory's Service, nslookup prints two lines: write to '10.96.0.10': Connection refused, which is the cause, and ;; connection timed out; no servers could be reached, which is its summary once it runs out of servers. It is not an NXDOMAIN nor a timeout caused by silence: somebody rejected the packet. Straight to the IP of a CoreDNS Pod, the same question answers fine: CoreDNS is healthy. The kube-dns Service shows that its dns UDP port 53 points at 5353, while dns-tcp is still on 53; the endpoint list repeats that 5353 for dns; and the node's notebook has the DNAT rules of kube-system/kube-dns:dns toward Pod IPs on port 5353, where CoreDNS does not listen. Save in 03-respuesta.txt the lines SERVICIO_CON_FALLA=, PROTOCOLO_QUE_FALLA=, PUERTO_EN_LA_LISTA=, PUERTO_DE_COREDNS= and RESPUESTA_DEL_CLIENTE= (rechazada, agotada or nxdomain).

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 8: Repair the directory at the cause, without touching the Corefile or the IP every Pod knows (10 pts)

There are two ways to make it work again and only one repairs. The other changes the rest of the airport to fit the broken piece: moving CoreDNS to another port, inventing another IP for the directory or writing a server by hand into every Pod. Each of those leaves a silent difference that somebody will find months later. The craft rule is the same as in Chapter 8: the directory has an address the whole cluster knows, and the kubelet writes it into the resolv.conf of every Pod that is born; what gets fixed is the stretch that went astray, and it is proven with a new Pod, which carries no exception.

<details>
<summary>Grader hint (check_hint)</summary>

The shortcuts it closes: making CoreDNS listen on 5353 to match the broken Service (the Corefile is compared with the fingerprint inyectar-falla.sh saved before breaking anything); recreating kube-dns with another IP (the IP has to stay 10.96.0.10, the one the kubelet on all three nodes writes into every Pod); and giving piloto a dnsConfig with a CoreDNS Pod's IP (piloto has to keep dnsPolicy ClusterFirst and no dnsConfig, and on top of that the check launches a fresh probe with the default configuration). It demands kube-dns's three ports toward 53, 53 and 9153 with the selector intact, the endpoint list with dns UDP 53, both CoreDNS replicas ready, no DNAT rule toward 5353 on the nodes, and that the probe resolve meteo from 10.96.0.10 and get an answer from a live replica.

</details>

<details>
<summary>What you should see</summary>

The first command lists the ports CoreDNS's container declares: dns UDP 53, dns-tcp TCP 53 and metrics TCP 9153, plus liveness-probe TCP 8080 and readiness-probe TCP 8181, which its probes use. The second shows the Service with dns UDP diverted to 5353. The patch returns service/kube-dns patched and the new list shows the three ports again toward 53, 53 and 9153. The node's notebook, a few seconds later, already has the DNAT rules of kube-system/kube-dns:dns toward port 53 of the CoreDNS Pods. nslookup from piloto answers from 10.96.0.10 with meteo's IP, and the wget by name returns a replica's name. The Service was repaired, the directory was not changed: the Corefile and the IP 10.96.0.10, which the kubelet writes into every Pod's resolv.conf, stay the same. Save in 04-respuesta.txt the lines PUERTO_DESTINO_RESTAURADO=, IP_DEL_DIRECTORIO= and COREFILE_INTACTO=.

</details>

```bash
./04-step.sh
./04-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 5. Ch. 9: The rampa entrance with the Gateway API and Istio, and the route to meteo (10 pts)

Objective: in the cabina namespace, a Gateway named rampa of the istio class, with a single HTTP listener on port 80 for *.cabina.example that admits routes only from its own namespace and with a ClusterIP Service; and an HTTPRoute named meteo, attached to rampa, for the name meteo.cabina.example and with the meteo Service on port 80 as destination. Both with their seals True.

The Gateway API splits the work into three objects with different owners, as in Chapter 9: the GatewayClass says who builds the entrances, the Gateway is the entrance with its lanes, and every HTTPRoute is a sign a team hangs on it. Before testing traffic, read the seals: Programmed on the Gateway, Accepted and ResolvedRefs on the route. A sign that did not attach or a destination that does not resolve shows up there first. The Gateway's annotation asks Istio for a ClusterIP Service instead of LoadBalancer, because on kind nobody hands out external IPs; that is why every test in this step comes from inside the cluster.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is accepting the route because the object exists, or reaching meteo without going through the entrance. The check demands the CRDs with version v1.6.1 annotated, istiod 1.32.0 ready, the istio GatewayClass accepted, the rampa Gateway of that class with the Programmed=True seal and a single HTTP listener on 80 for *.cabina.example that admits routes only from its own namespace, the rampa-istio Service of type ClusterIP, and the meteo HTTPRoute with both its seals True. Then a fresh probe calls rampa-istio's IP: with Host meteo.cabina.example a live replica has to answer, and with a name no route claims it has to get 404, so an entrance that lets everything through does not work either.

</details>

<details>
<summary>What you should see</summary>

The CRD apply prints nothing and the bundle-version annotation says v1.6.1. sha256sum -c says istioctl.tar.gz: OK; istioctl version prints client version: 1.32.0, and the installation ends with Installation complete. get gatewayclass lists istio with ACCEPTED True. The apply creates the rampa Gateway and the meteo HTTPRoute; the wait leaves the Gateway with condition met (Programmed), Istio creates the rampa-istio Deployment and Service for it, and get service shows it of type ClusterIP, because of the annotation, with ports 15021 and 80. The route's conditions say Accepted=True Accepted and ResolvedRefs=True ResolvedRefs. The wget with the header Host: meteo.cabina.example returns the name of a meteo replica; with Host: otro.cabina.example it ends with server returned error: HTTP/1.1 404 Not Found, because no route claims that name. Save in 05-respuesta.txt the lines SERVICIO_DE_LA_ENTRADA=, CLASE_DE_LA_ENTRADA= and RUTA_ACEPTADA=.

</details>

```bash
./05-step.sh
./05-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 6. Ch. 9: A route that crosses namespaces, with the objective only (unsolved point) (10 pts)

The exam does not give you the command: it gives you a task written as an objective and a clock. This step is that situation in miniature. Everything you need you have from Step 5 and Chapter 9: how an HTTPRoute is written, how it attaches to a Gateway, how a host name and a path are chosen, and what the seals say when something does not attach. What you do not have is a recipe, nor those data put in the right place: the setup left the token, the name and the path in files that change on every run, like the datum the exam puts in the statement and that you have to use to reach the objective. There is no answer file either: what is graded is the state of the cluster.

The objective is written as a comment at the end of the step's cmd. Read it calmly, write down in one line each condition that must hold, and build the end state one piece at a time. If you get stuck, the step's cmd only prints the run's three data: the hints are in the check_hint, which says which shortcuts are closed but not how it is done.

<details>
<summary>Grader hint (check_hint)</summary>

This is the unsolved point: the check fails on the guided state of Steps 1 to 5 because the planilla route does not even exist, until you solve it. The shortcuts it closes: opening rampa's listener to routes from other namespaces (it has to remain a single one, on 80, for *.cabina.example and with routes only from the same namespace), putting the route in the deposito namespace, serving the token from a Pod in cabina instead of deposito's planilla Service (the Service has to be a ClusterIP with a selector and its endpoint list has to carry a ready Pod of deposito, so neither an ExternalName nor a hand-made EndpointSlice works), and editing the token, the host or the path (they are compared with fingerprints the setup stored separately). The decisive part is the end state: both of the route's seals True and a fresh probe, with this run's name and path, that receives the whole token through rampa-istio. To move forward without a published solution: start from the objective, write one condition per line and, when something does not work, read the route's seals: the reason they carry says what is missing.

</details>

<details>
<summary>What you should see</summary>

This step's command sequence is not published: it is the unsolved point. The correct end state: in the deposito namespace there are Pods that answer this run's token on this run's path, behind a planilla Service with port 80; in the cabina namespace there is an HTTPRoute planilla attached to rampa, with this run's host name and a PathPrefix match equal to this run's path, whose destination is the planilla Service of the deposito namespace, with the seals Accepted=True and ResolvedRefs=True; the rampa Gateway stays the same as in Step 5; and a request made from a fresh probe to rampa-istio's IP, with that name and that path, returns the whole token as its body, with no other character. What you just practiced in Step 5 and what you read in Chapter 9 is everything needed.

</details>

```bash
./06-step.sh
./06-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

## How to run it

```bash
./00-setup.sh                  # creates the cluster and sets everything up
./01-step.sh && ./01-check.sh  # do the step, check it landed
./02-step.sh && ./02-check.sh
./03-step.sh && ./03-check.sh
./04-step.sh && ./04-check.sh
./05-step.sh && ./05-check.sh
./06-step.sh && ./06-check.sh
./99-teardown.sh               # deletes the cluster and the workspace
```

## Troubleshooting

- **Symptom (step 1):** kind create cluster fails with too many open files or with the kubelet not starting
  **What to do:** It is the host's inotify limit, shared with the nodes because a kind node is a container. Raise fs.inotify.max_user_instances with sysctl (the setup prints the current value), delete the half-built cluster with kind delete cluster --name ckne-lab2 --kubeconfig ~/ckne-lab/p02/kubeconfig and repeat.

- **Symptom (step 1):** The EndpointSlice shows fewer than three ready endpoints
  **What to do:** Some replica did not pass the readiness probe or did not start. Look at kubectl -n cabina get pods -l app=meteo and at the event of the one that is not ready with describe pod; if the image did not download, the problem is the host's network and not the cluster.

- **Symptom (step 2):** The apply fails with provided port is already allocated
  **What to do:** Another Service in the cluster already has nodePort 30380. Find it with kubectl get svc -A | grep 30380 and delete it or change its port; the lab pins 30380 so the check knows where to call.

- **Symptom (step 2):** conntrack lists no connection
  **What to do:** TIME_WAIT entries do not last long. Repeat the curl toward the ckne-lab2-worker node and run conntrack right away on that same node: the conversation is recorded on the node it came in through, not on the others.

- **Symptom (step 3):** The BEFORE THE FAULT nslookup already fails
  **What to do:** The directory was not healthy before injecting anything. Check that the CoreDNS Pods are ready (kubectl -n kube-system get pods -l k8s-app=kube-dns) and always ask for the full name meteo.cabina.svc.cluster.local: busybox nslookup with a short name walks the search domains and can end with code 1 even when it found the answer. Do not run inyectar-falla.sh until the BEFORE nslookup answers.

- **Symptom (step 3):** inyectar-falla.sh says it cannot find the cluster or the kubeconfig
  **What to do:** The Step 1 cluster does not exist or was created with another kubeconfig. Check that ~/ckne-lab/p02/kubeconfig exists and that kind get clusters lists ckne-lab2; if not, repeat Step 1.

- **Symptom (step 4):** After the patch, piloto still does not resolve for a few seconds
  **What to do:** kube-proxy rewrites the rules when it sees the Service change, not instantly. Watch the node's notebook with iptables-save until the DNAT rules of kube-system/kube-dns:dns point at 53, and repeat the nslookup with the full name.

- **Symptom (step 4):** The check says the Corefile changed and you did not touch it
  **What to do:** The fingerprint is saved when inyectar-falla.sh runs. If you ran the script twice with a Corefile edited in between, the fingerprint kept the edited version. Return the Corefile to kind's original (it is in the coredns ConfigMap of kube-system on a new cluster) or redo the lab from the setup.

- **Symptom (step 5):** The Gateway wait times out without Programmed
  **What to do:** Look at the rampa-istio Pod in cabina: if it is in ImagePullBackOff, docker.io rate-limited the pull of istio/proxyv2:1.32.0 and you have to wait or authenticate. If the Gateway has no seals, istiod is not ready: kubectl -n istio-system get pods.

- **Symptom (step 5):** The wget through the entrance fails with bad address rampa-istio.cabina
  **What to do:** The directory is still broken: Step 4 was not repaired. Run its check before moving on.

- **Symptom (step 6):** The route answers 500 through rampa
  **What to do:** The route attached but its destination does not resolve. Read its seals with kubectl -n cabina get httproute planilla -o yaml and look for ResolvedRefs's reason; Chapter 9 explains what each reason means.

- **Symptom (step 6):** My route answers the token but the check says no
  **What to do:** Compare what it answers with the exact content of ~/ckne-lab/p02/ficha-del-deposito.txt: a trailing newline does not matter, but any other character does. Check that the route is in cabina, that its match is PathPrefix with the exact value of ruta-del-deposito.txt, that the host name is the one in anfitrion-del-deposito.txt and that the rampa Gateway has not changed.

## Going further

- Repeat Step 3 with dig instead of nslookup, from a Pod that ships it, and compare a normal query with a TCP one (dig +tcp) toward 10.96.0.10 with the fault in place. Explain why one works and the other does not by looking at the two ports of the kube-dns Service, and which client in your real cluster would use TCP without you asking.
- Scale meteo to 5 replicas and count again the DNAT rules of cabina/meteo:http on ckne-lab2-worker. Then go down to 1 and look in the KUBE-SVC rule at how the draw's probabilities (--probability) change between endpoints. It is Chapter 7 seen in the notebook of a node you built yourself.

## References

- Kubernetes Project, Service. ClusterIP, NodePort, named target ports and the nodePort field used in Steps 1 and 2. https://kubernetes.io/docs/concepts/services-networking/service/
- Kubernetes Project, EndpointSlices. The endpoint list with its ready condition and ports that Steps 1, 3 and 4 read. https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/
- Kubernetes Project, Virtual IPs and Service Proxies. The kube-proxy modes and how it turns a Service IP into a Pod IP on each node, the basis of Steps 2 and 3. https://kubernetes.io/docs/reference/networking/virtual-ips/
- Kubernetes Project, DNS for Services and Pods. The names of the form service.namespace.svc.cluster.local and the dnsPolicy and dnsConfig fields checked in Step 4. https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- Kubernetes Project, Debugging DNS Resolution. The method of checking the kube-dns Service, its endpoints and the CoreDNS Pods separately, used in Steps 3 and 4. https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
- conntrack-tools project, conntrack manual. The -L listing with -p and --dport filters used in Step 2. https://conntrack-tools.netfilter.org/manual.html
- Gateway API project, Getting started and the v1.6.1 release. The standard-channel install file and the Gateway and HTTPRoute objects of Steps 5 and 6. https://gateway-api.sigs.k8s.io/guides/getting-started/ and https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.1
- Istio Project, Gateway API task and the 1.32.0 release. The gatewayClassName istio and the Deployment and Service each Gateway provisions, named <Gateway name>-<GatewayClass name>, used in Step 5. https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/ and https://github.com/istio/istio/releases/tag/1.32.0
- Istio Project, Getting Started. The networking.istio.io/service-type=ClusterIP annotation on a Gateway, used in Step 5 because kind hands out no LoadBalancer addresses. https://istio.io/latest/docs/setup/additional-setup/getting-started/
- Calico Project, Install Calico on a kind cluster. The kind configuration with disableDefaultCNI and podSubnet, and the manifest URL pinned to v3.33.0, used in Step 1. https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
