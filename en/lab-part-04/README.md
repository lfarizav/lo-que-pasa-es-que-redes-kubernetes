# Part IV - Lab: a pool of models with its picker, a shift that leaves with a fixed address, a route announced over BGP and two clusters sharing a Service

- Time: 60 min
- Points: 70

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the step's command sequence lives in its cmd field for you to reveal after trying on your own. The exception is Step 7: it states the objective only, no command is published anywhere in the repository, and its check depends on a token that is different on every run. What gets built: Step 1 sets up the cluster ckne-lab3 (one control plane and two workers, Cilium 1.20.5 without kube-proxy) with Istio 1.32.0 and the Inference Extension v1.0.1, three simulated model servers (one of them saturated on purpose), the `redaccion` pool with its picker and the `portico` entrance with two routes, and compares how the pool route spreads requests with how a plain Service does (Chapter 10). Step 2 runs inyectar-falla.sh, a script that blindly breaks one piece of the path of model requests: its content is encoded on purpose, as a courtesy blindfold and not as a real secret, and the answer key sits at the end in the answers file; you have to locate the fault by reading in Chapter 10's order (the picker's score, the endpoints the entrance's Envoy receives and, last, the model servers) and repair it without getting the saturated server out of the way (Chapter 10). Step 3 makes the Pods of one shift leave toward a server outside the cluster with a fixed source address, and confirms it in the destination's log (Chapter 11). Step 4 installs MetalLB 0.16.2, makes it speak BGP with a neighboring FRR router and confirms a LoadBalancer Service's route in that neighbor's table (Chapter 11). Step 5 creates the clusters ckne-lab3-uno and ckne-lab3-dos and joins them with Cilium Cluster Mesh and the MCS API (Chapter 12). Step 6 exports the same Service from both, measures the spread across clusters and switches off one cluster's clustermesh-apiserver for a while to read what the Cilium agent and KVStoreMesh say at the same time (Chapter 12). Step 7 is the exam in miniature: a Service that only one cluster contributes and that the other must reach by its cluster-set name, with no published command.

## Prerequisites

- A Linux machine with kind, kubectl, docker, helm, jq, curl, tar, sha256sum, base64 and od on PATH, and with at least 12 GB of free RAM: the lab brings up seven kind nodes in three clusters (ckne-lab3, ckne-lab3-uno and ckne-lab3-dos) and two containers on the kind network (`ckne-lab3-buzon` and ckne-lab3-frontera), and deletes them all in the teardown.
- ISOLATION. This lab's clusters NEVER touch your everyday kubeconfig: they are created with --kubeconfig ~/ckne-lab/p03/kubeconfig from the very first command, and every kubectl, helm and istioctl in the lab passes that file and an explicit context. Helm is used with --repo, so no repositories are added to your configuration either. If you already have other kind clusters, this lab does not see them, modify them or delete them; they share the kind docker network, and Step 3 takes the .250 address of that network. The setup prints kind get clusters before starting so you can check.
- Internet access throughout the lab: kind pulls the node image; Helm downloads Cilium from helm.cilium.io and MetalLB from metallb.github.io, with their images from quay.io; Step 1 downloads the Gateway API and Inference Extension CRDs and the istioctl binary from github.com, Istio's images from docker.io, the simulator from ghcr.io and the picker from registry.k8s.io; the Pods and containers pull busybox, curl, nginx and FRR pinned by digest. The 60-minute estimate assumes the images are already downloaded; on a first run the download time is added.
- PINNED VERSIONS, verified on 2026-11-22 on this same machine. kind v0.33.0 (minimum v0.33.0), kubectl v1.37.0, helm v4.3.0 (the options the lab uses are the same in Helm 3). Node image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Cilium 1.20.5 (Helm chart from https://helm.cilium.io). Gateway API CRDs v1.6.1, standard channel, and Inference Extension CRDs v1.0.1 (that release's manifests.yaml). Istio 1.32.0 with istioctl from https://github.com/istio/istio/releases/download/1.32.0/ (Step 1 verifies the archive's SHA-256) and the minimal profile. Simulator ghcr.io/llm-d/llm-d-inference-sim:v0.7.1@sha256:74211b5dbf27a867fcefae92067701e0a5fcee827f95156d89718bf3e1bfb845. Picker registry.k8s.io/gateway-api-inference-extension/epp:v1.0.1@sha256:50e96bc704e4823b0b9fef9739fb952a82dcc7f5b8a8f93fecf8fd07ec4b66c9. MetalLB 0.16.2 (Helm chart from https://metallb.github.io/metallb). FRR quay.io/frrouting/frr:10.7.1@sha256:e995beaa50fdc9edb35eadcfefa29b7f062cc06f2b812613789b68fa541554d2. busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0, curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c and nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de. A tag is mutable and a digest is not. Confirm what you actually got with kind version, kubectl version, helm version and istioctl version, never from memory.
- Having read Chapters 10, 11 and 12. This lab does not re-explain what an InferencePool is, what an egress gateway does, how MetalLB announces an address over BGP or what a ServiceExport is; it makes you operate them against real clusters and grades the end state. The steps depend on each other: Step 2 needs the cluster and the pool from Step 1; Steps 3 and 4 need the ckne-lab3 cluster from Step 1; Step 6 needs the two clusters from Step 5, and Step 7 needs the mesh from Step 5 and the cartas namespace from Step 6.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 10: Three model servers, a pool with its picker and two routes to compare the spread (10 pts)

Objective: in the ckne-lab3 cluster, in the imprenta namespace, two replicas of the simulated server redactor and one of redactor-ocupado, which publishes a queue of 30 requests and an almost full cache; all three with the label `grupo=redaccion` and behind the redactores Service. An InferencePool named `redaccion` that picks them by that label, with its picker (the EPP) named elector on port 9002. A Gateway named `portico` of the istio class, with a ClusterIP Service, and two HTTPRoutes: por-el-grupo, for grupo.imprenta.example, toward the InferencePool, and por-la-service, for service.imprenta.example, toward the redactores Service. Everything with its seals True.

Chapter 10 told why a request to a model is not an ordinary passenger: a Service spreads without looking at whom, and the picker reads each server's metrics before deciding. This step puts both decisions side by side, with the same saturated server in both lists. The picker writes in its log the score it gave each Pod, and that log is the first thing to read when the spread does not add up.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is accepting a pool that exists but decides nothing, or removing the saturated server so the spread looks fine. The check closes that: it demands the cluster with three nodes Ready at v1.37.0, with no kube-proxy or kindnet, Cilium v1.20.5 with kube-proxy replacement, BPF masquerading and the egress gateway enabled; the Gateway API v1.6.1 and Inference Extension CRDs; istiod 1.32.0 ready and with ENABLE_GATEWAY_API_INFERENCE_EXTENSION; two ready replicas of redactor and one of redactor-ocupado still publishing its fake queue of 30; the `redaccion` pool with the selector `grupo=redaccion`, port 8000, the picker on 9002 and both its seals True; and both routes with their seals True. Then it launches fresh probes that call `portico-istio`'s IP: through the pool route, sixteen requests with 200, none to the busy server and both free replicas present; through the Service route, twenty-four requests with 200 and at least one to the busy server, which proves it is still alive. The lines in 01-respuesta.txt are compared with the live cluster.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to kind-ckne-lab3, Cilium's rollout ends with successfully rolled out and the three nodes report condition met. The Inference Extension CRDs list inferenceobjectives.inference.networking.x-k8s.io, inferencepools.inference.networking.k8s.io and inferencepools.inference.networking.x-k8s.io; the istioctl archive's fingerprint prints OK and istioctl install ends with its installation-complete line. The three servers report condition met, the picker and `portico-istio` end with successfully rolled out, and the `redaccion` pool shows Accepted=True and ResolvedRefs=True. Through the service route the twelve requests spread over the three Pods, redactor-ocupado included; through the grupo route all twelve go to the two redactor Pods and none to the busy one, all with 200. The last lines of the picker's log show the score queue 0 and kv 10 for redactor-ocupado against 100 and 100 for the other two, and prefix 0 for all three (short texts do not reach the prefix scorer's minimum block). Save in 01-respuesta.txt the lines SERVICE_DEL_PORTICO=, POD_QUE_EL_ELECTOR_EVITA= and PUERTO_DEL_ELECTOR=.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 10: The pool that sends everything to the saturated server, read in the chapter's order (10 pts)

Objective: make the pool route avoid the saturated server again, without taking it out of the pool or the Service, after locating the fault inyectar-falla.sh leaves. Deliverables: 02-diagnostico.txt with what you read in each piece, and 02-respuesta.txt.

A fault that returns no errors is the hardest to see: every request answers 200 and yet the spread ended up in the worst possible place. The reading order Chapter 10 left is useful precisely here. First the picker's score (Chapter 10's coordinator), which says among whom it chose; then the endpoints the entrance's Envoy received, which say whom it could send to; only at the end the model servers. When the first two readings count fewer candidates than there are running, follow the trail to the object that produces them.

<details>
<summary>Grader hint (check_hint)</summary>

The shortcuts it closes: deleting, scaling to zero or relabeling redactor-ocupado so the pool has nobody to choose badly (the busy server has to keep one ready replica, its labels app=redactor-ocupado and `grupo=redaccion` and its fake queue of 30); and sending the route to the Service (por-el-grupo has to keep pointing at the `redaccion` InferencePool). It demands that the pool end up with the three Running servers, two redactor and the busy one, that both its seals be True and that the picker be ready. The file 02-diagnostico.txt has to belong to this fault in this cluster: scores only for this cluster's busy server and a single pool endpoint in the Envoy, with that Pod's IP, and it has to be written after the fault was injected. A fresh probe makes sixteen requests through the pool route (none to the busy server, both free replicas present) and another makes twenty-four through the Service route, where the busy server has to show up.

</details>

<details>
<summary>What you should see</summary>

inyectar-falla.sh runs and prints falla inyectada. THE SYMPTOM: the twelve requests through the pool route all go to redactor-ocupado, with 200; nothing fails, but the pool chose precisely the one with the full queue. The diagnosis, saved in 02-diagnostico.txt, reads in Chapter 10's order. 1: the picker's log only carries scores for redactor-ocupado (queue 100 and kv 10): the picker has nobody else to compare it with. 2: `portico`'s Envoy receives for the pool (the cluster of the `redaccion-ip-...` Service on port 54321) a single endpoint, the busy server's IP on 8000, while the redactores Service still has three. 3: the three servers are ready. 4: the pool picks by app=redactor-ocupado instead of `grupo=redaccion`. After giving the pool its selector back, the twenty requests spread again over the two free redactor Pods. Save in 02-respuesta.txt the lines POD_QUE_RECIBIA_TODO=, PODS_PUNTUADOS_DURANTE_LA_FALLA=, OBJETO_CON_LA_FALLA= and CAMPO_CON_LA_FALLA=.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 11: A shift that always leaves with the same address, confirmed at the destination (10 pts)

Objective: in ckne-lab3, make the Pods of the `envios` namespace with the label turno=noche reach the `ckne-lab3-buzon` container (outside the cluster, on the kind network) with the fixed address, the .250 of the kind network's segment, leaving through ckne-lab3-worker2, which carries the label egreso=si and that address on eth0. The policy is named noche-con-ip-fija. The remitente (turno=noche) and testigo (no label) Pods run on ckne-lab3-worker. Deliverable: 03-respuesta.txt.

Chapter 11 left a habit: the source address is confirmed at the destination, not in the policy. A policy accepted by the API may be doing nothing, and the only thing that does not lie is what the server that received the connection recorded. On kind, the fixed address is a secondary address on the interface of a node that is a container, and the `buzon` is another container on the same network: the mechanism is the same as with a real network card, but the setting is smaller.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is looking at the policy and calling it done, or putting the Pods on the node's network. The check closes that: it demands the CiliumEgressGatewayPolicy noche-con-ip-fija with a single selector (turno=noche in `envios`), the `buzon` /32 among its destinations and the fixed address as egressIP; a nodeSelector that picks only ckne-lab3-worker2, which has the fixed address on eth0; and remitente (with turno=noche) and testigo (without that label) Running on ckne-lab3-worker, without hostNetwork. Then it confirms it at the destination: it makes each one request a unique path and looks that path up in the `buzon`'s log, where remitente has to arrive with the fixed address and testigo with its node's IP; it launches two fresh probes on the same worker, one with the label and one without, with the same result; and it reads the gateway table live in ckne-lab3-worker2's agent.

</details>

<details>
<summary>What you should see</summary>

The command prints the kind network (172.18.0.0/16 on this machine; on yours it may be another one) and the fixed address, which is the .250 of its gateway's segment. The `ckne-lab3-buzon` container sits on the kind network with its own IP, and the remitente and testigo Pods report condition met on ckne-lab3-worker. Before the policy, the `buzon`'s log records both requests with ckne-lab3-worker's IP: Cilium's masquerading replaced the Pod's IP with its node's. ckne-lab3-worker2 shows two addresses on eth0, its own and the fixed one, and the policy is created. Afterwards, the `buzon` records remitente with the fixed address and testigo again with ckne-lab3-worker's IP: the policy acts by label, not by node. The Cilium agent of ckne-lab3-worker2 lists an entry with remitente's IP, the `buzon` /32 and the fixed address as Egress IP. Both curls print 404, which comes from nginx (the requested path does not exist): what matters is who arrived. Save in 03-respuesta.txt the lines IP_FIJA=, ORIGEN_DEL_TESTIGO_EN_EL_DESTINO= and NODO_PUERTA=.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 11: An address announced over BGP, read in the neighboring router's table (10 pts)

Objective: in ckne-lab3, MetalLB 0.16.2 in metallb-system, with an IPAddressPool named rango-lab (198.51.100.10-198.51.100.20), a BGPPeer named frontera (cluster AS 64601, neighbor AS 64600) toward the FRR container ckne-lab3-frontera and a BGPAdvertisement of that range; and the vitrina Service, of type LoadBalancer, in the `envios` namespace with two replicas that answer their name. Deliverable: 04-respuesta.txt.

The second half of Chapter 11's habit: an announced route is confirmed in the neighboring router's table, not in the Service status. The Service can show an external IP that nobody outside the cluster knows how to reach. This step's neighbor accepts sessions from any address of the kind network, so the nodes' IPs do not have to be known in advance; each node that announces the address shows up as a hop in its table. 198.51.100.0/24 is a block reserved for documentation (TEST-NET-2), so it does not clash with any real network.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is trusting the IP the Service shows, or writing a static route into the neighbor by hand. The check closes that: it demands the MetalLB v0.16.2 controller ready; the rango-lab range with 198.51.100.10-198.51.100.20, the frontera BGPPeer with ASes 64601 and 64600 toward the ckne-lab3-frontera container's IP, and an advertisement of that range; the vitrina Service of type LoadBalancer with two ready replicas and an IP from that range assigned by MetalLB. Then it reads the neighbor's table: the /32 route of that IP has to have been learned over BGP, be selected and have both workers as its hops, and the FRR configuration cannot hold any static route. Finally it requests the IP from the frontera and demands that a live vitrina replica answer.

</details>

<details>
<summary>What you should see</summary>

Helm installs MetalLB (it may print a warning unrecognized format "cidr", which does not stop the installation) and the metallb-system Pods end up Running: the controller, one speaker and one frr-k8s per node and the statuscleaner. The ckne-lab3-frontera container sits on the kind network with its IP, and rango-lab, frontera and anuncio-lab are created. vitrina gets 198.51.100.10, the first one in the range. The frontera's BGP summary shows three dynamic neighbors (marked with *) in AS 64601, one per node: the control plane with 0 received prefixes and both workers with 1, because kind marks the control plane with the label node.kubernetes.io/exclude-from-external-load-balancers. The routing table shows B>* 198.51.100.10/32 with two hops, one per worker, and the wget from the frontera returns the name of a vitrina replica. Save in 04-respuesta.txt the lines IP_ANUNCIADA=, SALTOS_HACIA_LA_IP= and AS_DEL_CLUSTER=.

</details>

```bash
./04-step.sh
./04-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 5. Ch. 12: Two clusters that recognize each other in a mesh (10 pts)

Objective: two kind clusters, ckne-lab3-uno (Pods 10.31.0.0/16, Services 10.32.0.0/16) and ckne-lab3-dos (Pods 10.41.0.0/16, Services 10.42.0.0/16), with one control plane and one worker each, without kube-proxy, with Cilium 1.20.5 named after the cluster and with ids 1 and 2, joined by Cluster Mesh through a clustermesh-apiserver on NodePort 32379, with the same certificate authority, the MCS API enabled and CoreDNS configured for clusterset.local. Deliverable: 05-respuesta.txt.

Chapter 12 showed that a mesh has two levels worth reading separately: the Cilium agent of each node and KVStoreMesh, which keeps inside the clustermesh-apiserver a local copy of what the other cluster publishes. The agents talk to that copy, not to the other cluster. This step leaves both levels at 1/1, so the next one can watch them split. The Pod ranges do not overlap between clusters: it is a condition of the mesh.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is calling a mesh joined because both Ciliums are installed. The check closes that: in each cluster it demands two Ready nodes with their Pod range (10.31 in uno, 10.41 in dos), no kube-proxy, Cilium v1.20.5 ready on both nodes with the name ckne-lab3-uno or ckne-lab3-dos and id 1 or 2, kube-proxy replacement, the clustermesh-apiserver ready behind a NodePort Service on 32379, the ServiceImport CRD and the line multicluster clusterset.local in the Corefile. Then it asks live: the Cilium agent on each side has to say 1/1 and KVStoreMesh on each side has to say 1/1 with the other cluster ready. Both clusters have to share the same certificate authority. The lines in 05-respuesta.txt are compared with what is expected.

</details>

<details>
<summary>What you should see</summary>

Both kind create commands end with Set kubectl context to kind-ckne-lab3-uno and kind-ckne-lab3-dos. Helm may print a warning that clustermesh.config.clusters is a table and the empty default value is ignored: it is harmless, the file's values win. secret/cilium-ca is created in dos, both Cilium and clustermesh-apiserver rollouts end with successfully rolled out, and within one to two minutes each agent says ClusterMesh: 1/1 remote clusters ready. Each side's KVStoreMesh says 1/1 and names the other cluster as ready, with 2 nodes and 0 services. uno's Corefile carries clusterset.local on the kubernetes line and the line multicluster clusterset.local that CoreDNS auto-configuration wrote. Save in 05-respuesta.txt the lines ID_DE_UNO=, ID_DE_DOS=, PUERTO_DE_LA_MALLA= and ZONA_ENTRE_CLUSTERES=.

</details>

```bash
./05-step.sh
./05-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 6. Ch. 12: The same Service in both clusters, and what the agent and KVStoreMesh say during an outage (10 pts)

Objective: in both clusters, the cartas namespace with a relevo Deployment of two replicas that answer their cluster's name, its relevo Service (port 80) and a relevo ServiceExport; the explorador Pod in uno's cartas. Then a controlled outage: dos's clustermesh-apiserver at zero replicas while you read uno's agent, uno's KVStoreMesh and the spread, and then back to one replica. Deliverables: 06-caida.txt and 06-respuesta.txt.

The two checks Chapter 12 left for this practice are here. The first: without its ServiceExport, a cluster contributes no Pods to the cluster-set name, even if it has the same Service. The second: the Cilium agent and KVStoreMesh can say different things at the same time, and that gap is the first piece of data. This outage is different from the chapter's: dos's nodes stay on and only the server that publishes its state goes off, so you see how long uno's local copy holds.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is exporting in only one cluster, or writing 06-caida.txt without switching anything off. The check closes that: in both clusters it demands the relevo Service with the selector app=relevo, two ready replicas, its ServiceExport with Valid and Ready True, a ServiceImport that names both clusters and the agent at 1/1. The outage has to have happened and ended: dos's clustermesh-apiserver Deployment has to have changed its replica count (its generation) and be back at one ready, and uno's KVStoreMesh has to count at least one reconnection with dos, now ready. 06-caida.txt has to carry the agent's 1/1 line, KVStoreMesh's 0/1 line with ckne-lab3-dos not-ready and answers from dos during the outage. A fresh probe in uno makes twenty requests to the clusterset.local name and both clusters have to answer.

</details>

<details>
<summary>What you should see</summary>

In each cluster cartas, relevo and its Service are created, and the rollout ends with two replicas. explorador reports condition met in uno. Once exported in both, uno's relevo ServiceImport is of type ClusterSetIP, with an IP from uno's Service range (10.32) and both clusters in its list. The twenty requests to the name relevo.cartas.svc.clusterset.local spread over ckne-lab3-uno and ckne-lab3-dos (11 and 7 in the recorded run, plus two sin-respuesta lines with wget: download timed out: right after the ServiceImport appeared, a couple of requests toward dos ran out of their two-second limit; the grader's probe, later, demands all twenty answers). When dos's clustermesh-apiserver is scaled to zero, 06-caida.txt records the time and, at the same moment, ClusterMesh: 1/1 remote clusters ready in uno's agent and KVStoreMesh: 0/1 remote clusters ready in uno, with ckne-lab3-dos as not-ready and its data still in the copy; and the spread keeps answering from both clusters, because dos's Pods are still alive and uno keeps their endpoints. Back at one replica, uno's KVStoreMesh returns to 1/1 and its reconnection counter for dos is no longer 0, and the spread stays between the two. Save in 06-respuesta.txt the lines AGENTE_DE_UNO_EN_LA_CAIDA=, KVSTOREMESH_DE_UNO_EN_LA_CAIDA= and DOS_SIGUIO_ATENDIENDO= (si or no).

</details>

```bash
./06-step.sh
./06-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 7. Ch. 12: A Service only one cluster contributes, with the objective only (unsolved point) (10 pts)

The exam does not give you the command: it gives you a task written as an objective and a time limit. This step is that situation in small. Everything you need you have from Step 6 and from Chapter 12: how a Service is exported, what name it has in the set and how to read which cluster contributes Pods. What you do not have is a recipe, nor the token at hand: the setup left it in a file that changes on every run, like the datum the exam puts in the statement and that you have to use to reach the objective. There is no answer file either: what is graded is the state of both clusters.

The objective is written as a comment at the end of the step's cmd. Read it calmly, write on one line each condition that has to hold, and build the end state one at a time. If you get stuck, the step's cmd only prints the run's token: the hints are in the check_hint, which says which shortcuts are closed but not how it is done.

<details>
<summary>Grader hint (check_hint)</summary>

This is the unsolved point: the check fails on the guided state of Steps 1 to 6 because consigna does not even exist, until you solve it. The shortcuts it closes: serving the token from uno (there can be neither a consigna ServiceExport nor a consigna Service in uno, the ServiceImport has to name only ckne-lab3-dos and every agent in uno has to send traffic to dos's Pod IPs, 10.41.0.0/16, among them a ready consigna endpoint); a Service without a selector or with a hand-made endpoint list in dos (the list has to carry a ready resguardo Pod that the Service picks by its selector); and editing the token (it is compared with a fingerprint the setup saved separately). What settles it is the end state: a fresh probe in uno, in the cartas namespace, that resolves the cluster-set name to the ServiceImport's IP and receives the whole token five times. To move forward without a published solution: start from the objective, write one condition per line and, when something does not work, read the conditions and the state of each object: they say what is missing.

</details>

<details>
<summary>What you should see</summary>

This step's command sequence is not published: it is the unsolved point. The correct end state: in ckne-lab3-dos, in the resguardo namespace, there are Pods that answer this run's token at the root, behind a consigna Service of type ClusterIP with a selector and port 80, exported with its ServiceExport Valid and Ready; in ckne-lab3-uno there is neither a consigna ServiceExport nor a consigna Service, the consigna ServiceImport names only ckne-lab3-dos and uno's agents send traffic to dos's Pod IPs; and a fresh probe in uno's cartas namespace resolves consigna.resguardo.svc.clusterset.local to that ServiceImport's IP and receives, in five requests in a row, the whole token. With what you practiced in Step 6 and what you read in Chapter 12 you have everything you need.

</details>

```bash
./07-step.sh
./07-check.sh
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
./07-step.sh && ./07-check.sh
./99-teardown.sh               # deletes the cluster and the workspace
```

## Troubleshooting

- **Symptom (step 1):** The picker stays at 0/1 and its log says cannot list resource
  **What to do:** The picker lacks a read permission. Compare the rules of the elector Role with the resource the log names; picker v1.0.1 reads the pool, the Pods and the objectives.

- **Symptom (step 1):** The pool route answers 500
  **What to do:** The entrance does not reach the picker. Check that the elector Deployment is ready and that the elector-tls DestinationRule exists: the entrance talks to the picker over TLS.

- **Symptom (step 2):** istioctl proxy-config endpoint shows no `redaccion-ip` line
  **What to do:** Use the istioctl Step 1 downloaded (./bin/istioctl in ~/ckne-lab/p03) with --kubeconfig and --context, and point it at `deploy/portico-istio` in the imprenta namespace: that is the entrance's Envoy, not another Pod's.

- **Symptom (step 2):** After repairing, the pool route still sends something to the busy server
  **What to do:** The picker needs a few seconds to read the servers' metrics again after the repair. Wait fifteen seconds and repeat; if it persists, read the picker's log again and count how many Pods it scores.

- **Symptom (step 3):** docker exec ... ip addr add fails with File exists
  **What to do:** The address is already on ckne-lab3-worker2's eth0, from an earlier attempt. Check it with docker exec ckne-lab3-worker2 ip -4 -o addr show eth0 and go on with the rest of the step.

- **Symptom (step 3):** The `buzon` still records remitente with the node's IP
  **What to do:** Read the entry in ckne-lab3-worker2's agent with cilium-dbg bpf egress list. If remitente's IP does not show up, check its labels and the namespace the policy names; if it shows up with Egress IP 0.0.0.0, the fixed address is not on that node's eth0.

- **Symptom (step 4):** vitrina stays with EXTERNAL-IP pending
  **What to do:** MetalLB has no range to take the address from or its controller is not ready. Look at kubectl -n metallb-system get ipaddresspool and at the Service's events with describe.

- **Symptom (step 4):** The frontera's BGP summary shows no neighbors
  **What to do:** Sessions take a few seconds. If they still do not appear after a minute, compare the BGPPeer's peerAddress with the container's IP (docker inspect ckne-lab3-frontera) and the bgp listen range in frontera/frr.conf with the kind network.

- **Symptom (step 5):** The agent stays at 0/1 remote clusters ready
  **What to do:** The most frequent cause is the certificate authority: the cilium-ca secret has to be copied from uno to dos before installing Cilium in dos. If you copied it afterwards, uninstall Cilium in dos with helm uninstall, copy the secret again and repeat the installation.

- **Symptom (step 5):** kind create cluster fails on the second or third cluster with too many open files
  **What to do:** It is the host's inotify limit, shared by the seven nodes. Raise fs.inotify.max_user_instances with sysctl (the setup prints the current value), delete the half-built cluster with kind delete cluster --name <name> --kubeconfig ~/ckne-lab/p03/kubeconfig and repeat.

- **Symptom (step 6):** uno's ServiceImport names only one cluster
  **What to do:** The ServiceExport is missing in the other cluster, or has not arrived yet. Look at kubectl -n cartas get serviceexport relevo in each context and at its conditions; the ServiceImport's list changes within a few seconds.

- **Symptom (step 6):** uno's KVStoreMesh does not drop from 1/1 during the outage
  **What to do:** dos's clustermesh-apiserver Pod has not terminated yet. Wait until none is left with kubectl -n kube-system get pods -l k8s-app=clustermesh-apiserver in dos; the step's loop waits for KVStoreMesh to stop saying 1/1 before writing 06-caida.txt.

- **Symptom (step 7):** From uno, consigna's clusterset.local name does not resolve
  **What to do:** Look at the ServiceExport in dos and its conditions, and look for the consigna ServiceImport in uno, as you did with relevo in Step 6. If dos's is Valid and Ready and uno has nothing, re-read Chapter 12 and verify each condition of the objective in the cluster where you are looking.

- **Symptom (step 7):** My Service answers the token but the check says no
  **What to do:** Compare what it answers with the content of ~/ckne-lab/p03/ficha-de-la-consigna.txt: a trailing newline does not matter, but any other character does. Check that the Service is in dos and not in uno, that it has a selector and that its ServiceExport exists only in dos.

## Going further

- Repeat Step 1 with a text longer than 64 characters, the same one in eight requests in a row through the pool route, and look in the picker's log at how the prefix score changes. Explain why the spread sticks to a single Pod and what a real model server would gain from it.
- In Step 4, remove the node.kubernetes.io/exclude-from-external-load-balancers label from ckne-lab3's control plane and read the frontera's BGP summary again. Count the hops of the /32 route and explain what changed and why kind sets that label.

## References

- Gateway API Inference Extension project, overview and the InferencePool API type. The pool, its selector, targetPorts and endpointPickerRef used in Steps 1 and 2. https://gateway-api-inference-extension.sigs.k8s.io/ and https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepool/
- Gateway API Inference Extension project, v1.0.1 release and its RBAC chart template. The manifests.yaml CRDs and the permissions of the picker used in Step 1. https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/tag/v1.0.1 and https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/v1.0.1/config/charts/inferencepool/templates/rbac.yaml
- Istio Project, Gateway API Inference Extension task. The two pilot settings, the gatewayClassName istio and the DestinationRule toward the picker used in Step 1. https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api-inference-extension/
- llm-d project, llm-d-inference-sim v0.7.1 README. The --fake-metrics option and the x-inference-pod header used in Steps 1 and 2. https://github.com/llm-d/llm-d-inference-sim/blob/v0.7.1/README.md
- Cilium Project, Egress Gateway (v1.20). The CiliumEgressGatewayPolicy, its podSelector, destinationCIDRs and egressGateway fields, and cilium-dbg bpf egress list, used in Step 3. https://docs.cilium.io/en/v1.20/network/egress-gateway/egress-gateway/
- Cilium Project, Kubernetes without kube-proxy and Masquerading (v1.20). kubeProxyReplacement and bpf.masquerade, set in Step 1 and observed at the destination in Step 3. https://docs.cilium.io/en/v1.20/network/kubernetes/kubeproxy-free/ and https://docs.cilium.io/en/v1.20/network/concepts/masquerading/
- MetalLB Project, Configuration and the v0.16.2 release. IPAddressPool, BGPPeer and BGPAdvertisement used in Step 4. https://metallb.io/configuration/ and https://github.com/metallb/metallb/releases/tag/v0.16.2
- FRRouting Project, BGP. The bgp listen range dynamic neighbors and the show bgp summary and show ip route commands used in Step 4. https://docs.frrouting.org/en/latest/bgp.html
- IETF, RFC 5737, IPv4 Address Blocks Reserved for Documentation. The 198.51.100.0/24 block (TEST-NET-2) used in Step 4. https://www.rfc-editor.org/rfc/rfc5737.txt
- Cilium Project, Setting up Cluster Mesh and Troubleshooting (v1.20). `cluster.name`, `cluster.id`, the shared CA, the clustermesh-apiserver and `kvstoremesh-dbg status`, used in Steps 5 and 6. https://docs.cilium.io/en/v1.20/network/clustermesh/setup/ and https://docs.cilium.io/en/v1.20/operations/troubleshooting/
- Cilium Project, Multi-Cluster Services API (v1.20). clustermesh.mcsapi, CoreDNS auto-configuration, ServiceExport and ServiceImport, used in Steps 5, 6 and 7. https://docs.cilium.io/en/v1.20/network/clustermesh/mcsapi/
- Kubernetes SIG Multicluster, Multicluster Services API concepts. ServiceExport, ServiceImport and the clusterset.local name used in Steps 6 and 7. https://multicluster.sigs.k8s.io/concepts/multicluster-services-api/
- Cilium Project, Installation using kind (v1.20). The kind configuration with the default CNI and kube-proxy disabled, used in Steps 1 and 5. https://docs.cilium.io/en/v1.20/installation/kind/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
