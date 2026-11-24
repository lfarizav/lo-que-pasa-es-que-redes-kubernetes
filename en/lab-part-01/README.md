# Part I - Lab: build the practice airport with three terminals and no runways, lay Calico's corridors, and prove the network rulebook holds between terminals

- Time: 50 min
- Points: 50

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the step's command sequence lives in its cmd field for you to reveal after trying on your own. The exception is Step 5: it states the objective only, no command is published anywhere in the repository, and its check depends on a flight token that is different on every run. What gets built: Step 1 sets up the exam desk (Chapter 1): a kind cluster named ckne-lab0 with one control plane and two workers, the default CNI disabled (disableDefaultCNI), and both the Pod subnet and the Service subnet written out explicitly. Those nodes stay without runways until Step 2. Step 2 installs Calico v3.33.0 from that version's official manifest and demands that all three nodes become Ready and that Calico's IP pool match the Pod subnet you declared (Chapter 2). Step 3 proves the first rule of the network model: two Pods on different nodes with IPs from the Pod subnet, and the receiver sees the sender's Pod IP as the source, with no NAT on the way (Chapter 2). Step 4 proves the Service rule: a ClusterIP that CoreDNS resolves by name and that spreads requests across two replicas (Chapter 2). Step 5 is the miniature exam: a Pod and a Service with a requirement written only as an objective. No check reads your history: all of them re-query the live cluster at grading time, and those of Steps 3, 4 and 5 fire fresh requests with markers you cannot know in advance.

## Prerequisites

- A Linux machine with kind, kubectl, docker and jq on PATH, and at least 4 GB of free RAM for three nodes. The lab creates its own kind cluster named ckne-lab0 and deletes it in the teardown.
- ISOLATION. This lab's cluster NEVER touches your everyday kubeconfig: it is created with --kubeconfig ~/ckne-lab/p00/kubeconfig from the very first command, and every kubectl in the lab passes an explicit --kubeconfig and --context. If you already have other kind clusters, this lab does not see them, modify them or delete them. The setup prints kind get clusters before starting so you can check.
- Internet access throughout the lab: kind pulls the node image, Step 2 downloads Calico's manifest from raw.githubusercontent.com and its images from quay.io, and the Pods of Steps 3 to 5 pull a digest-pinned busybox image from docker.io.
- PINNED VERSIONS, verified on 2026-11-13 on this same machine. kind v0.33.0 (minimum v0.33.0). kubectl v1.37.0. Node image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Calico v3.33.0 with the manifest https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml. Pod image busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. A tag is mutable and a digest is not. Confirm what you actually got with kind version and kubectl version, never from memory.
- Having read Chapters 1 and 2. This lab does not re-explain the exam format or the network model's rules; it makes you operate them against a real cluster and grades the end state. The steps depend on each other: Step 2 needs the cluster from Step 1, and Steps 3, 4 and 5 need Calico from Step 2.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 1: The exam desk is set up before you start, and the airport opens with no runways (10 pts)

Chapter 1 explained that the exam is performance-based: you work against real clusters, with a desk that comes already laid out and a counted clock. Here you build the practice desk, and the first thing you decide is what kind of airport it is. A kind cluster is an airport made of three Docker containers acting as terminals: one for control and two for work. By default kind installs some basic taxiways called kindnet, so everything works without you deciding anything. In this book we do not want them, because half of the exam is knowing how to install and inspect the CNI, so they are turned off with disableDefaultCNI.

There are two numbers worth writing by hand instead of inheriting: the Pod subnet and the Service subnet. The first is the range of gate numbers shared out among the terminals: the control plane records a slice for each node (a /24, the podCIDR) and the CNI decides how to use the range: Calico, as you will see, hands out Pod IPs from its own pool. The second is the range of the Services' virtual addresses, which sit on no network interface: kube-proxy resolves them with rules on the node. Writing them explicitly forces you to know what they are, and later Calico has to match the first one.

Notice the signal the cluster gives when it finishes: the nodes are NotReady. That is not a failure. The kubelet does not declare a node ready until it finds a network configuration in /etc/cni/net.d, and in an airport with no runways no plane can take off yet.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is creating a kind cluster with the default CNI and declaring the airport ready. The check closes that: it demands that the kindnet DaemonSet not exist and that /etc/cni/net.d on all three nodes hold no kindnet file, and it demands that kubeadm-config say exactly podSubnet 192.168.0.0/16 and serviceSubnet 10.100.0.0/16, meaning the subnets were written explicitly and not inherited from kind's default. It also reads the nodes' podCIDR from the live API: three of them, all different, inside the Pod subnet. If the cluster already exists with another subnet there is no way to change it: delete the cluster with kind delete cluster --name ckne-lab0 --kubeconfig ~/ckne-lab/p00/kubeconfig and create it again with the config file. The control stays in force: kube-proxy has to exist. The lines in 01-respuesta.txt are compared with the live cluster, not with what you remember.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to kind-ckne-lab0. get nodes shows three nodes, one control-plane and two with no role, all three NotReady and at version v1.37.0: NotReady is correct, because there is no CNI and the kubelet will not declare ready a node that has no Pod network. get daemonsets in kube-system shows only kube-proxy: kindnet, the CNI kind installs if you do not disable it, is absent. Each node gets its own slice of the Pod subnet in the PODCIDR column (a different /24 per node, all inside 192.168.0.0/16). The grep over kubeadm-config returns both lines, podSubnet: 192.168.0.0/16 and serviceSubnet: 10.100.0.0/16, and the ls of /etc/cni/net.d prints nothing or lists no kindnet file. Save in 01-respuesta.txt the lines PODSUBNET=, SERVICESUBNET=, NODOS= and PODCIDR_DEL_TRABAJADOR= with what you just saw.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 2: Calico's corridors are laid from the official manifest, and the gate-number pool must match the one you declared (10 pts)

Chapter 2 put the contract on the table: every Pod has its own IP, and any Pod can talk to any other without address translation. But Kubernetes does not fulfil that contract by itself: it delegates to a network plugin, the CNI. Calico is one of them. In the airport, Kubernetes is the tower that gives every plane a gate, and Calico is the company that actually paves the runways and puts up the signage between terminals.

It is installed with a manifest from Calico's own official documentation for that version, pinned in the URL (v3.33.0). Notice that the URL carries the version inside it: if you used the main branch unpinned, the lab would change from one day to the next. After applying it there is nothing to guess, you wait for the DaemonSet, which runs one agent per node, and for the controller, which keeps the IPAM state.

There is one piece the manifest leaves at its default and that you must verify: the IPPool. It is the range Calico hands addresses to Pods from. In this lab's manifest the default range is 192.168.0.0/16, and that is why Step 1 chose that podSubnet. When in your real cluster the control plane's range and Calico's pool do not match, the symptoms look like network problems but the defect is in two numbers that do not look alike.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is getting the nodes to Ready with another CNI, or with a Calico version other than the pinned one. The check demands that calico-node run on all three nodes with the image tagged v3.33.0, that calico-kube-controllers be ready, that every node have the 10-calico.conflist file in its /etc/cni/net.d, and that kindnet not exist. What fails most is the subnet tie: the Calico IPPool CIDR has to be exactly the podSubnet from Step 1 (192.168.0.0/16), and it is read from the live object, not from the manifest you applied. The CoreDNS Pods have to be Running with an IP inside that subnet: if they stayed in ContainerCreating, look at the sandbox event with describe pod. If calico-node stays at 0/1 for a while, that is normal: wait for the rollout status.

</details>

<details>
<summary>What you should see</summary>

The create prints some forty created objects: CRDs, ServiceAccounts, ClusterRoles, the calico-node DaemonSet and the calico-kube-controllers Deployment. Both rollout status commands end on successfully rolled out, and the wait leaves the three nodes with condition met. get nodes now shows all three Ready: Calico wrote the network configuration into /etc/cni/net.d and the kubelet can declare the node ready. The DaemonSet's image ends in :v3.33.0. The IP pool is named default-ipv4-ippool and its CIDR is 192.168.0.0/16, equal to the podSubnet from Step 1: that is the tie you cannot forget, because a pool that does not match the range the control plane shares out leaves Pods with addresses nobody knows how to route. The ls of /etc/cni/net.d lists the 10-calico.conflist file and the calico-kubeconfig folder. The two CoreDNS Pods already have an IP inside 192.168.0.0/16. Save in 02-respuesta.txt the lines VERSION_DE_CALICO=, POOL_DE_IPS= and NODOS_LISTOS=.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 2: Two suitcases in different terminals talk to each other and nobody rewrites the origin label (10 pts)

This is the first rule of the network contract, and the one most taken for granted: Pods talk to each other, on any node, using their real IPs, with no network address translation (NAT). Think of two suitcases with the owner's tag attached: when a suitcase crosses from terminal A to terminal B, the origin tag arrives intact. If somebody on the way swapped the tag for customs', the receiver would no longer know who it came from, and no rule based on origin would work.

To prove it, the request arriving is not enough: you have to look at what origin it arrived with. That is why the receiver is a server that logs the client. And that is why the two Pods are pinned to different nodes with nodeName: a Pod talking to another on the same node would prove nothing about the network between terminals, because that traffic never crosses it.

The check is hard on purpose, because it is the one skipped most often in practice: it does not trust what you saved in the file, it sends its own request with a fresh marker and reads who was seen as the origin.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is putting both Pods on the same node, where traffic never leaves through the inter-node network, or using hostNetwork so they share the node's IP. The check demands different nodes, hostNetwork false, each Pod's IP inside the 192.168.0.0/16 Pod subnet, and then it does not settle for what you did: it fires a fresh request itself with a random marker from the emisor to the receptor, looks for that marker in the receiver's log and demands that the source IP it sees be the emisor Pod's and not a 172.18.X.X node IP. The receiver has to log requests with their source IP: busybox httpd -vv does, and any server that logs the client address will do. If the emisor's wget hangs, Calico is not routing between nodes: go back over Step 2.

</details>

<details>
<summary>What you should see</summary>

get pods -o wide shows emisor on ckne-lab0-worker and receptor on ckne-lab0-worker2, both Running, with IPs inside 192.168.0.0/16, from different blocks (Calico gives each node its own block from its pool). The wget ends with a 404 Not Found error, and that is expected: the receiver is an httpd with no page at all, and what matters is not the response but the line the request left in the receiver's log. That line has the form [::ffff:192.168.X.Y]:PORT: url:/mi-sonda, and the IP between brackets is the emisor Pod's IP, the same the last command prints. It is not the IP of the emisor's node (172.18.0.X, from the Docker network): if it were, somebody would have translated the origin on the way. Save in 03-respuesta.txt the lines IP_DEL_EMISOR= and IP_QUE_VIO_EL_RECEPTOR=, and the two must be equal.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 2: A counter number that is in no terminal, resolved by name and spread across two counters (10 pts)

Pods are born and die, and their IPs with them. If a client had to memorize a Pod's IP, the first replacement would leave it talking to an empty port. The Service is the airport's counter number: a stable address behind which one or several counters serve, and the passengers neither know nor ask which. That virtual address, the ClusterIP, sits on no interface of any node: kube-proxy writes rules on every node that rewrite the destination to one of the ready Pods.

There are two more pieces. The first, the EndpointSlice: it is the list the control plane keeps of which Pods to point at, and it includes only the ones that are ready. The second, CoreDNS: it turns the name mostrador.terminal.svc.cluster.local into the ClusterIP. The client never sees the IP, it asks for the name, and that is why the emisor Pod from Step 3 is reused here as the client.

That it spreads is not proven with one request: a single one lands on one Pod and proves nothing. That is why the check sends forty and demands to see both counters.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is making the Service headless (clusterIP: None), which resolves to the Pods' IPs and not to a virtual IP, or pointing at a single Pod. The check demands a real ClusterIP inside 10.100.0.0/16, that the EndpointSlice hold exactly the IPs of the Deployment's Ready Pods, that the Service's name resolve through CoreDNS to that same IP (it asks itself, from the emisor Pod), and that forty fresh requests by name reach all the Pods and only them. It also demands kube-proxy still be ready on all three nodes and CoreDNS still up: tearing down the piece that does the work does not count. If nslookup fails with a timeout, CoreDNS is not answering: check the kube-dns Pods from Step 2. If the EndpointSlice is empty, the Service's selector does not match the Pods' labels.

</details>

<details>
<summary>What you should see</summary>

The rollout ends on successfully rolled out. get svc shows mostrador of type ClusterIP with a CLUSTER-IP inside 10.100.0.0/16 (Step 1's serviceSubnet) and port 80/TCP, no EXTERNAL-IP. The Service's EndpointSlice ends up listing two addresses (it may show only one for the first second, until the second Pod is ready), which are the IPs of the Deployment's two Pods, on port 8080. nslookup answers with two blocks: the Server is the IP of the kube-dns Service (10.100.0.10) and the answer, Name mostrador.terminal.svc.cluster.local, carries as Address the Service's CLUSTER-IP, the same you saw in get svc. And the eight wgets print Pod names, and among the eight both names of the Deployment have to show up: the Service spreads. Save in 04-respuesta.txt the lines CLUSTER_IP=, RESUELVE_A= and MOSTRADORES_DISTINTOS=.

</details>

```bash
./04-step.sh
./04-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 5. Ch. 2: The radar counter, as in the exam, with the objective only (10 pts)

The exam does not give you the command: it gives you a task written as an objective and a clock. This step is that situation in miniature. Everything you need you have from Steps 3 and 4: how to pin a Pod to a node, how to expose it with a Service, how to check name resolution from another node. What you do not have is a recipe that already knows the order.

There is one detail that changes from one run to the next: the flight token, a random text the setup left in a file. It is the equivalent of the datum the exam gives you in the statement and that you have to carry to the right place. There is no answer file either: what is graded is the state of the cluster.

Read the objective calmly, write down in one line each condition that must hold, and build the end state one piece at a time. If you get stuck, the step's cmd only prints the token: the hints are in the check_hint, which says which shortcuts are closed but not how it is done.

<details>
<summary>Grader hint (check_hint)</summary>

This is the unsolved point: the check fails on the guided state of Steps 1 to 4 because the torre namespace does not even exist, until you solve it. The shortcuts it closes: a Pod on the wrong node, hostNetwork, a Service that is not ClusterIP or is headless, an EndpointSlice that does not point at a real Pod on worker2, and editing the flight token (it is compared with a fingerprint the setup stored separately). The decisive part is that it launches a fresh probe on the other node itself and asks for the full DNS name: if the answer is not exactly this run's token it fails, so copying a token from another run does not work. And tearing down Calico or kube-proxy to make something work does not count. To move forward without a published solution: start from the objective, write down the state you need and compare it with what you did in Steps 3 and 4.

</details>

<details>
<summary>What you should see</summary>

This step's command sequence is not published: it is the unsolved point. The correct end state: in the torre namespace there is a Running and Ready Pod, on node ckne-lab0-worker2, with an IP from the Pod subnet and no hostNetwork; a Service radar of type ClusterIP with port 80 whose EndpointSlice carries that Pod's IP; and a request made from a Pod on another node to http://radar.torre.svc.cluster.local/ returns as its body exactly this run's flight token. What you just practiced in Steps 3 and 4 is everything needed.

</details>

```bash
./05-step.sh
./05-check.sh
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
./99-teardown.sh               # deletes the cluster and the workspace
```

## Troubleshooting

- **Symptom (step 1):** kind create cluster fails with too many open files or with the kubelet not starting
  **What to do:** It is the host's inotify limit, shared with the nodes because a kind node is a container. Raise fs.inotify.max_user_instances with sysctl (the setup prints the current value), delete the half-built cluster with kind delete cluster --name ckne-lab0 --kubeconfig ~/ckne-lab/p00/kubeconfig and repeat.

- **Symptom (step 1):** The nodes come up Ready before Calico is installed
  **What to do:** The default CNI got installed: disableDefaultCNI: true is missing under networking in the config file, or --config was not passed to kind create cluster. Delete the cluster and create it again.

- **Symptom (step 2):** The create fails with a CRD too large or an annotation too long
  **What to do:** It is the size limit of client-side apply. Use kubectl create -f (as in the step) or kubectl apply --server-side -f, which is what Calico's documentation indicates for this manifest. Do not use kubectl apply without --server-side.

- **Symptom (step 2):** The nodes stay NotReady and calico-node is in Init or CrashLoopBackOff
  **What to do:** Look at kubectl -n kube-system describe pod for the failing calico-node and its logs with -c upgrade-ipam or -c install-cni if it is in Init. The most common cause in kind is not being able to pull the image from quay.io: try docker pull quay.io/calico/node:v3.33.0 on the host to confirm the network.

- **Symptom (step 3):** The Pods stay in ContainerCreating
  **What to do:** Look at kubectl -n terminal describe pod emisor. If the event talks about a sandbox or a network plugin, Calico did not finish starting on that node: confirm Step 2. If it talks about the image, the node could not pull busybox from docker.io.

- **Symptom (step 3):** The receiver's log is empty although the wget went out
  **What to do:** The -vv was missing from the receiver's httpd: without that flag busybox does not log requests. Recreate the receptor Pod with the step's command. If the wget hangs and never answers, it is not the log: check that the receiver listens on port 8080.

- **Symptom (step 4):** The wget by Service name fails with bad address
  **What to do:** Resolution failed. Try nslookup from emisor and look at kubectl -n kube-system get pods -l k8s-app=kube-dns. Remember the full name: from the same namespace mostrador is enough, from another one you need mostrador.terminal.

- **Symptom (step 4):** All responses come from the same Pod
  **What to do:** Either the Deployment ended with a single ready replica, or the connection is being reused. Check get endpointslices: it has to list two addresses. Each wget opens a new connection, so with two ready replicas the spreading shows up right away.

- **Symptom (step 5):** My Service answers but the check says no
  **What to do:** Compare what it answers with the exact content of ~/ckne-lab/p00/ficha-de-vuelo.txt: a trailing newline does not matter, but any other character does. Ask for the full name radar.torre.svc.cluster.local from a Pod on the other node and look at the EndpointSlice: it has to point at a Running Pod on ckne-lab0-worker2.

## Going further

- Break Step 2 on purpose to see the full symptom. Delete Calico's IPPool and create a new Pod on a node: look at what state it ends in and what the event says, and what happens to communication between a new Pod and an old one. Then restore the pool with the same CIDR and keep the conclusion: the subnet the control plane hands out and the CNI's pool are two numbers somebody has to keep equal.
- Repeat Step 3 with a third Pod on the control-plane node and compare the three source IPs. Also compare the PODCIDR column of get nodes with the Pods' real IPs: Calico hands out blocks of its own IPPool and does not use the /24 the control plane assigned to each node. Then use docker exec on a node (docker exec ckne-lab0-worker) and look at the routing table with ip route: find the route to the other worker's /24 and find out which interface it leaves through. It is a preview of Chapter 3.

## References

- Calico Project, Install Calico on a kind cluster. The basis of Steps 1 and 2: the kind configuration with disableDefaultCNI and podSubnet, and the manifest URLs pinned to v3.33.0, including the advice to use kubectl create or replace, or apply --server-side, for the large CRD bundle. https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind
- kind Project, Configuration. Documents the networking section of the kind config: disableDefaultCNI, podSubnet and serviceSubnet, and the --config, --image and --kubeconfig flags used in Step 1. https://kind.sigs.k8s.io/docs/user/configuration/
- Kubernetes Project, Cluster Networking. The statement of the network model that Step 3 tests: every Pod gets its own IP address and Pods can communicate with all other Pods without NAT. https://kubernetes.io/docs/concepts/cluster-administration/networking/
- Kubernetes Project, Service. The basis of Step 4: ClusterIP, the virtual IP that kube-proxy implements, selectors and EndpointSlices, and headless Services as the contrast case. https://kubernetes.io/docs/concepts/services-networking/service/
- Kubernetes Project, DNS for Services and Pods. How a Service gets the name service.namespace.svc.cluster.local and how it resolves to the ClusterIP, the contract used by the checks of Steps 4 and 5. https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- Kubernetes Project, Assigning Pods to Nodes. nodeName as the way of pinning a Pod to a node, used in Steps 3 and 5 to force cross-node traffic. https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
