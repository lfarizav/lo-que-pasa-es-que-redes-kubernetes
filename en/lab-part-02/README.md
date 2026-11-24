# Part II - Lab: a terminal with a broken runway, the packet inspector who finds the fault, and a second boarding door with Multus

- Time: 60 min
- Points: 60

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the step's command sequence lives in its cmd field for you to reveal after trying on your own. The exception is Step 6: it states the objective only, no command is published anywhere in the repository, and its check depends on a token and a subnet that are different on every run. What gets built: Step 1 sets up the desk (Chapter 3): a kind cluster named ckne-lab1 with one control plane and two workers, no default CNI, with Calico v3.33.0, and with tcpdump installed inside every node (Chapter 5), because kind's node image does not ship it. Step 2 places two neighbor Pods on different terminals, checks that they talk, and then runs inyectar-falla.sh, a script that breaks one node's network blindly: its content is encoded on purpose, as a courtesy blindfold and not as a real secret, and the answer key sits at the end in the answers file. Step 3 is the diagnosis (Chapter 5): with docker exec into the node and tcpdump you have to see where the packets arrive and where they stop showing up. Step 4 repairs the cause and not the symptom (Chapter 3): the check demands that Calico's tunnel is still the same, so changing the pool's mode to dodge the fault does not count. Step 5 adds a second interface with Multus v4.3.2 (Chapter 4): a NetworkAttachmentDefinition with the bridge plugin and host-local IPAM, and traffic proven over net1 between two Pods. Step 6 is the exam in miniature: another extra network with a subnet and a token that change on every run, with no published command.

## Prerequisites

- A Linux machine with kind, kubectl, docker, jq, curl and tar on PATH, and at least 4 GB of free RAM for three nodes. The lab creates its own kind cluster named ckne-lab1 and deletes it in the teardown.
- ISOLATION. This lab's cluster NEVER touches your everyday kubeconfig: it is created with --kubeconfig ~/ckne-lab/p01/kubeconfig from the very first command, and every kubectl in the lab passes an explicit --kubeconfig and --context. If you already have other kind clusters, this lab does not see them, modify them or delete them. The setup prints kind get clusters before starting so you can check.
- Internet access throughout the lab: kind pulls the node image; Step 1 downloads Calico's manifest from raw.githubusercontent.com, its images from quay.io and the tcpdump package from Debian's repositories inside each node; Step 5 downloads the reference CNI plugins from github.com and Multus from raw.githubusercontent.com and ghcr.io; the Pods pull a digest-pinned busybox image from docker.io.
- PINNED VERSIONS, verified on 2026-11-13 on this same machine. kind v0.33.0 (minimum v0.33.0). kubectl v1.37.0. Node image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Calico v3.33.0 with the manifest https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml (IPIP mode Always by default in the pool). Multus v4.3.2 with the manifest https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.3.2/deployments/multus-daemonset-thick.yml and the image ghcr.io/k8snetworkplumbingwg/multus-cni:v4.3.2-thick (that tag's manifest ships snapshot-thick, a moving tag, and Step 5 swaps it for the fixed one). Reference CNI plugins v1.10.0 from github.com/containernetworking/plugins: kind's node image ships host-local but NOT bridge, so Step 5 installs the bridge binary after verifying its SHA-256. Pod image busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. tcpdump comes from the node's Debian repository and is not version-pinned (Step 1 prints the one you got). A tag is mutable and a digest is not. Confirm what you actually got with kind version and kubectl version, never from memory.
- Having read Chapters 3, 4 and 5. This lab does not re-explain how the kubelet reads /etc/cni/net.d, what a secondary network is, or how to read a capture; it makes you operate them against a real cluster and grades the end state. The steps depend on each other: Step 2 needs the cluster from Step 1, Steps 3 and 4 need the Pods and the fault from Step 2, and Steps 5 and 6 need the cluster from Step 1 (and are done with the network already repaired).

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 3: The desk with Calico's runways, and the packet inspector installed on every terminal (10 pts)

This is the network exam's practice desk: a disposable cluster, the Pod network already laid and the diagnostic tools inside every terminal. The only thing you build from scratch here is the part the exam hands you ready-made and that in real life somebody had to leave set up. Notice a detail from Chapter 5 that this step settles in advance: a kind node is a minimal container and does not ship tcpdump. In a real cluster the tool is usually on the node or you use an ephemeral Pod that has it. Here it is installed with the node's own apt, and every time the node is recreated you have to repeat it.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is leaving kind's default CNI or installing another Calico version. The check closes that: it demands that the kindnet DaemonSet not exist, that calico-node's image carry the tag v3.33.0 with its three Pods ready, that the pool be 192.168.0.0/16 in Always mode, and that tcpdump answer inside all three nodes (the inspector has to be on every terminal before the fault). The lines in 01-respuesta.txt are compared with the live cluster, not with what you remember.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to kind-ckne-lab1. Calico's create makes the manifest's objects and both rollout status commands end with successfully rolled out. get nodes shows three nodes Ready at version v1.37.0. On each node, the loop prints the tcpdump version that got installed. The last command prints the pool's CIDR, 192.168.0.0/16, and its IPIP mode, Always: that Always is the fact that matters for the rest of the lab, because with it the packets between Pods on different nodes travel encapsulated IP-in-IP. Save in 01-respuesta.txt the lines VERSION_DE_CALICO=, NODOS_LISTOS=, POOL_DE_IPS= and MODO_IPIP= with what you just saw.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 3: Two neighbors on different terminals, and the fault injected blindly (10 pts)

Up to here everything worked, and that is what makes a fault useful: you have a reference for what the healthy network looks like. The two neighbors are on different nodes on purpose, because two Pods on the same node talk over the local bridge and would never touch the broken path. The injection script is not a secret: it can be read, and it is encoded only so you do not find the fault served up in the text and put the diagnosis on autopilot. Treat it as the courtesy blindfold it is. What is real is the symptom, and it is the one every operator meets: something that worked yesterday now just waits and ends in a timeout, with no error message saying why.

<details>
<summary>Grader hint (check_hint)</summary>

This check holds at two moments: with the fault in place and after repairing it. It demands both Pods on their nodes, with no hostNetwork, and that the mark showing the fault was applied exists. Then it measures the real state and cross-checks it with the cause: if the rule that drops IP-in-IP packets is present on the node, vecino-a CANNOT reach vecino-b; if the rule is gone, it CAN. A mix of the two (fault in place but reachable, or repaired but unreachable) fails, so faking the symptom or hiding it does not work. The lines in 02-respuesta.txt are compared with vecino-b's live IP.

</details>

<details>
<summary>What you should see</summary>

get pods shows vecino-a on ckne-lab1-worker and vecino-b on ckne-lab1-worker2, both Running, with IPs inside 192.168.0.0/16. BEFORE THE FAULT, wget returns vecino-b-ok: the two neighbors talk through Calico's tunnel. Then inyectar-falla.sh runs and prints falla inyectada. AFTER THE FAULT, wget returns nothing and ends with download timed out (the || true keeps the error from cutting the script). Save in 02-respuesta.txt the lines IP_DE_VECINO_B= (the real IP), ANTES=responde and DESPUES=agota-tiempo.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 5: The packet inspector inside the terminal, and the capture that locates the fault (10 pts)

Here begins the lesson of Chapter 5: a timeout does not say where the packet was lost, and the inspector does. The technique is a baggage tracer's: you do not look at the final destination or the origin, you look at the middle point where the packet has to show up, and you move toward where it stops being seen. There are three points that matter on a node with IP-in-IP tunnels: the network card the encapsulated packet arrives on (eth0), the interface where the envelope is opened (tunl0), and the Pod's virtual interface (the one named cali...). That the packet shows up on the first and not on the second narrows the fault to a short stretch, and the short stretch is full of rules: iptables.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is guessing the cause without looking at the wire. The check demands evidence from this run, not an answer from memory: the eth0 file has to carry at least two encapsulated packets going from the real IP of vecino-a's node to the real IP of vecino-b's node, and inside them vecino-a's live IP to vecino-b's live IP on port 8080; the tunl0 file has to be a real capture of that interface that ended in 0 packets captured. Captures from another run or typed by hand with other IPs do not match the live cluster. The lines in 03-respuesta.txt summarize what the evidence says.

</details>

<details>
<summary>What you should see</summary>

Both tcpdumps run inside ckne-lab1-worker2 while vecino-a retries the wget, which times out. The eth0 capture (filtered with ip proto 4, that is IP-in-IP) shows several packets from node ckne-lab1-worker to node ckne-lab1-worker2 that carry inside a packet from vecino-a's IP to vecino-b's IP on port 8080, with the connection-start flag (SYN), the same attempt repeated every second because nobody answers it: the packets DO reach the node. The tunl0 capture, the interface where Calico decapsulates, ends with 0 packets captured: nothing shows up there. Between eth0 and tunl0 something drops the packets. The last two commands list the node's interfaces and iptables rules so you can look for the culprit. Save in 03-respuesta.txt the lines NODO_CON_FALLA=, PROTOCOLO_IP= (the IP protocol number the tunnel uses), LLEGA_A_ETH0= and LLEGA_A_TUNL0=.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 3 and 5: Repair the cause and not the symptom, and prove the reply comes back through the tunnel (10 pts)

A repair has two halves: removing the cause and proving that it removed the symptom. The half that is easy to forget is the second, and the capture makes it visible: before, you saw the request go in and nothing come out; now you see the whole trip, out and back. There is also a craft reason to leave Calico's pool as it was. If the Pod network rests on a tunnel and one node will not let it through, the right thing is to give the tunnel its way back; turning off the tunnel for everyone because one node fails is plugging a leak with an architecture change, and later someone pays the bill without knowing where it comes from.

<details>
<summary>Grader hint (check_hint)</summary>

The shortcuts it closes: switching Calico's pool to another encapsulation mode (or none) so traffic sidesteps the tunnel, which leaves the fault on the node and changes everyone's network; inserting an ACCEPT rule above the dropping one and leaving the cause alive (the check walks iptables-save on all three nodes and tolerates no rule dropping protocol 4 outside Calico's chains); and declaring the repair without proving it (it launches a fresh probe on another node and asks vecino-b, and demands that the saved capture show vecino-b's reply going back to vecino-a through tunl0). The control stays in force: the pool must be the same 192.168.0.0/16 in Always and all three calico-node must be ready.

</details>

<details>
<summary>What you should see</summary>

The first command lists the rules of the node's raw table PREROUTING chain: Calico's rule and an extra rule that drops protocol 4 appear. The second removes it and the third shows it is gone. vecino-a's wget now returns vecino-b-ok. The tunl0 capture (with traffic this time) shows the request entering through the tunnel and, the important part, the reply leaving vecino-b's IP and going back to vecino-a's IP. The last command confirms the pool's IPIP mode is still Always: the cause was repaired, not sidestepped. Save in 04-respuesta.txt the lines TABLA_DE_LA_REGLA=, CADENA_DE_LA_REGLA= and MODO_IPIP_INTACTO=.

</details>

```bash
./04-step.sh
./04-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 5. Ch. 4: The second boarding door with Multus, the bridge plugin and host-local IPAM (10 pts)

Chapter 4 talks about a house with two doors: one is the usual one (eth0, the Pod network Calico sustains) and the other is an extra network that you define. Multus does not replace Calico: it puts itself first in the alphabetical list of /etc/cni/net.d, calls Calico for eth0 and, if the Pod asks for it with an annotation, calls other plugins for net1, net2 and so on. Two facts from this step are worth keeping. The first: the bridge plugin was not on the node, and learning to check which binaries exist in /opt/cni/bin before writing a definition is an exam skill, because the definition is accepted by the API even if nobody can run it. The second: a bridge is local to each node and host-local hands out addresses per node without talking to the others, so two Pods talk over net1 only if they are on the same node. That is why rx and tx share a node, and so does the check's probe.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is declaring the second interface without testing it, or sending traffic over the wrong interface. The check launches a fresh probe with the extra network's annotation on the same node, asks rx's net1 for a path with a unique mark, and reads rx's log: the source has to be the probe's net1, inside 10.20.0.0/24; if the traffic went over eth0 the source would be an IP from 192.168.0.0/16 and it fails. It also demands the bridge plugin executable on all three nodes, the exact image v4.3.2-thick with its three Pods ready, the definition with the bridge plugin and host-local IPAM (and no trace of macvlan), the br-pista bridge existing on the node, and rx's eth0 still being Calico's network. The lines in 05-respuesta.txt are compared with the live IPs.

</details>

<details>
<summary>What you should see</summary>

The first command lists the node's /opt/cni/bin: host-local shows up (it ships in kind's image) and bridge does NOT, which is this step's finding. The download is verified with sha256sum -c and says OK; after copying the binary, ls -l shows bridge and host-local executable on all three nodes. The manifest grep shows both images with the fixed tag v4.3.2-thick. rollout status of kube-multus-ds ends with successfully rolled out. In the node's /etc/cni/net.d, 00-multus.conf appears beside 10-calico.conflist, and 00-multus.conf's content points at 10-calico.conflist as the main network (clusterNetwork): Multus puts itself ahead of Calico in alphabetical order and hands it the eth0 job. Pods rx and tx end up Running on the same node; ip -o -4 addr show in tx shows eth0 with an IP from 192.168.0.0/16 and net1 with an IP from 10.20.0.0/24; tx's wget to rx's net1 returns rx-net1-ok and rx's log shows tx's net1 (10.20.0.x) as the source, not its eth0. Save in 05-respuesta.txt the lines IP_NET1_DE_RX=, IP_NET1_DE_TX= and INTERFAZ_SECUNDARIA=.

</details>

```bash
./05-step.sh
./05-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 6. Ch. 4: The cargo dock, with the objective only (unsolved point) (10 pts)

The exam does not give you the command: it gives you a task written as an objective and a clock. This step is that situation in miniature. Everything you need you have from Step 5: how an extra network definition is written, how a Pod is annotated to use it, how net1's IP is read, and why both ends have to be on the same node. What you do not have is a recipe that already knows the order, nor the subnet or the token: the setup left both in files that change on every run, like the datum the exam puts in the statement and that you have to carry to the right place. There is no answer file either: what is graded is the state of the cluster.

Read the objective calmly, write down in one line each condition that must hold, and build the end state one piece at a time. If you get stuck, the step's cmd only prints the run's two data: the hints are in the check_hint, which says which shortcuts are closed but not how it is done.

<details>
<summary>Grader hint (check_hint)</summary>

This is the unsolved point: the check fails on the guided state of Steps 1 to 5 because the muelle namespace does not even exist, until you solve it. The shortcuts it closes: a definition with another subnet or with macvlan, a faro on another node or with hostNetwork, serving the token over eth0 and not net1, and editing the token or the subnet (they are compared with a fingerprint the setup stored separately). The decisive part is that it launches a fresh probe with the carga annotation on the faro's node itself and asks for the faro's net1 IP: if the answer is not exactly this run's token, or the probe does not get a net1 inside this run's subnet, it fails, so copying a token from another run does not work. And tearing down Multus or Calico to make something work does not count. To move forward without a published solution: start from the objective, write down the state you need and compare it with what you did in Step 5.

</details>

<details>
<summary>What you should see</summary>

This step's command sequence is not published: it is the unsolved point. The correct end state: in the muelle namespace there is a NetworkAttachmentDefinition named carga with the bridge plugin and host-local IPAM, with the exact subnet from subred-del-muelle.txt; a Pod faro Running on ckne-lab1-worker, with no hostNetwork, with eth0 on Calico's network and a net1 with an IP inside that subnet; and a request made from a fresh probe on the same node, annotated with the carga network, to http://<faro's net1 IP>:8080/ returns as its body exactly this run's token. What you just practiced in Step 5 is everything needed.

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
  **What to do:** It is the host's inotify limit, shared with the nodes because a kind node is a container. Raise fs.inotify.max_user_instances with sysctl (the setup prints the current value), delete the half-built cluster with kind delete cluster --name ckne-lab1 --kubeconfig ~/ckne-lab/p01/kubeconfig and repeat.

- **Symptom (step 1):** The loop prints an empty line instead of the tcpdump version
  **What to do:** apt-get could not fetch the package: the node has no internet egress or the host's DNS fails inside Docker. Get into the node with docker exec -it ckne-lab1-worker bash, run apt-get update in plain sight and read the error. If the host network filters Debian's repositories the lab cannot continue: say what the block is instead of skipping Step 3.

- **Symptom (step 2):** The BEFORE THE FAULT wget already times out
  **What to do:** The network was not healthy before injecting anything. Check that all three calico-node Pods are ready (kubectl -n kube-system get pods -l k8s-app=calico-node) and that vecino-a and vecino-b are on different nodes with get pods -o wide. Do not run inyectar-falla.sh until the BEFORE wget answers.

- **Symptom (step 2):** inyectar-falla.sh says it cannot find the container
  **What to do:** The Step 1 cluster does not exist or is named differently. Check with docker ps --format '{{.Names}}' that ckne-lab1-worker2 is running; if not, repeat Step 1.

- **Symptom (step 3):** The eth0 capture comes out empty
  **What to do:** Either tcpdump did not start before the wget (raise the sleep) or it captured on the wrong interface: traffic between kind nodes enters through the node container's eth0, not one of the host's. Verify with docker exec ckne-lab1-worker2 ip -br link and ask for -i eth0. If you already repaired the fault, traffic arrives and shows up the same on eth0, but there will be no timeout.

- **Symptom (step 3):** The tunl0 capture does not end with 0 packets captured
  **What to do:** Then tunl0 did see packets: either the fault is not in place (fix the order: Step 2 before Step 3) or you captured with another filter. The exact text expected is the summary line tcpdump prints when it ends on the timeout, with the number 0 at the start.

- **Symptom (step 4):** The delete-rule command says the rule does not exist (Bad rule or does a matching rule exist)
  **What to do:** The rule is not written the same way it was injected, or it is in another table or chain. Look at the first command's list and copy the rule as iptables -S prints it, changing -A to -D. The check accepts any way of leaving it out, as long as it remains on no node.

- **Symptom (step 4):** The repair works for a moment and fails again
  **What to do:** Another dropping rule is left (the injection may have been repeated if you ran inyectar-falla.sh again). Read iptables-save | grep -- '-p 4' on the three nodes again: Calico's rules live in chains named cali-... and are legitimate; the extra one hangs directly from PREROUTING, INPUT, FORWARD, OUTPUT or POSTROUTING.

- **Symptom (step 5):** Pods rx and tx stay in ContainerCreating with an event mentioning failed to find plugin bridge
  **What to do:** The bridge binary is not in /opt/cni/bin on the node where the Pod runs. Check with docker exec ckne-lab1-worker ls /opt/cni/bin and repeat the docker cp on the node that is missing it. The NetworkAttachmentDefinition was accepted because the API does not know which plugins each node has: the error only shows up when the Pod is created.

- **Symptom (step 5):** New Pods across the whole network, even without an annotation, never get created
  **What to do:** Multus got misconfigured and is now the first plugin of every Pod. Look at kubectl -n kube-system logs ds/kube-multus-ds and at whether 00-multus.conf points at 10-calico.conflist. If you installed another variant (thin) by mistake, delete with the same manifest and apply this step's thick one.

- **Symptom (step 6):** My faro answers over net1 but the check says no
  **What to do:** Compare what it answers with the exact content of ~/ckne-lab/p01/ficha-del-muelle.txt: a trailing newline does not matter, but any other character does. Check that the carga definition's subnet is exactly the one in subred-del-muelle.txt, that the faro is on ckne-lab1-worker, and that its network-status annotation lists the net1 interface.

## Going further

- Test the bridge rule by hand: put rx on ckne-lab1-worker and tx on ckne-lab1-worker2 with the same puente-pista definition and ask tx for rx's net1. Note what happens and why (each node has its own br-pista and its own host-local with the same range). Then look at docker exec ckne-lab1-worker ip -d link show br-pista and the neighbor table with ip neigh to see the extra network's MACs. It is the preview of why an extra network between nodes needs another kind of plugin, which is the subject of the following chapters.
- Repeat Step 3 in the other direction: capture on ckne-lab1-worker while vecino-b asks vecino-a for something with the fault in place. Compare which direction fails and which does not, and explain why an ingress fault on one node breaks the requests that arrive at it and lets through the ones leaving it (replies to connections it opened do come back, because they are not new packets). To put the fault back, run inyectar-falla.sh again.

## References

- Kubernetes Project, Cluster Networking. The statement of the network model that frames the whole lab: every Pod gets its own IP address and Pods can communicate with all other Pods without NAT. https://kubernetes.io/docs/concepts/cluster-administration/networking/
- Calico Project, Install Calico on a kind cluster. The basis of Step 1: the kind configuration with disableDefaultCNI and podSubnet, and the manifest URL pinned to v3.33.0. https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind
- Calico Project, Configure overlay networking (IP-in-IP). The explanation of why the default pool uses IP-in-IP in Always mode and what protocol 4 traffic between nodes is, the basis of Steps 3 and 4. https://docs.tigera.io/calico/latest/networking/configuring/vxlan-ipip
- tcpdump and libpcap project, tcpdump man page. The interface (-i), numeric output (-nn) and primitive filters such as ip proto used in Steps 3 and 4. https://www.tcpdump.org/manpages/tcpdump.1.html
- Multus CNI project, Quickstart Guide. The thick-plugin installation manifest used in Step 5, what the daemonset places in /opt/cni/bin and /etc/cni/net.d, and the k8s.v1.cni.cncf.io/networks annotation. https://k8snetworkplumbingwg.github.io/multus-cni/docs/quickstart.html
- Multus CNI project, release v4.3.2 and the manifest at that tag (deployments/multus-daemonset-thick.yml). The source of the exact manifest Step 5 applies, with its image swapped from snapshot-thick to v4.3.2-thick. https://github.com/k8snetworkplumbingwg/multus-cni/releases/tag/v4.3.2
- containernetworking project, CNI reference plugins v1.10.0 and the bridge plugin documentation. The source of the bridge binary Step 5 installs (the archive's SHA-256 is verified) and of the bridge and host-local configuration fields used in the NetworkAttachmentDefinition. https://github.com/containernetworking/plugins/releases/tag/v1.10.0 and https://www.cni.dev/plugins/current/main/bridge/
- kind Project, Configuration. Documents the networking section of the kind config: disableDefaultCNI, podSubnet and serviceSubnet, and the --config, --image and --kubeconfig flags used in Step 1. https://kind.sigs.k8s.io/docs/user/configuration/
- Kubernetes Project, Assigning Pods to Nodes. nodeName as the way of pinning a Pod to a node, used in Steps 2, 5 and 6 to force or avoid cross-node traffic. https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
