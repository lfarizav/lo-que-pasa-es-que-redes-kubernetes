# Part V - Lab: who gets into a zone, what travels encrypted between nodes, a padlock cert-manager issues and every Pod's identity

- Time: 60 min
- Points: 70

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the step's command sequence lives in its cmd field for you to reveal after trying on your own. The exception is Step 7: it states the objective only, no command is published anywhere in the repository, and its check depends on a token that is different on every run. What gets built, in four independent kind clusters: Step 1 sets up `ckne-lab5-red` (Calico 3.33.1) and lets only the workshop's operators reach the warehouse stock (Chapter 13). Step 2 adds the administrator's layer on top: an Admin-tier ClusterNetworkPolicy that closes a namespace even though a NetworkPolicy leaves it open (Chapter 13). Step 3 sets up `ckne-lab5-cifra` (Cilium 1.20.5), turns on transparent WireGuard encryption and tests it with captures on the node, not with what the agent says (Chapter 14). Step 4 sets up `ckne-lab5-sello` (Istio 1.32.0, Gateway API 1.6.1, cert-manager v1.21.3) and gives an HTTPS listener whose certificate cert-manager issues from a Gateway annotation (Chapter 15). Step 5 runs `inyectar-falla.sh`, a script that blindly breaks another listener of that Gateway: its content is encoded on purpose, as a courtesy blindfold and not as a real secret; you diagnose in Chapter 15's order and repair it (Chapter 15). Step 6 sets up `ckne-lab5-id` (SPIRE 1.16.0 through chart 0.31.0, Istio 1.32.0) and reads a server's identity, its registration and a Pod's pass (Chapter 16). Step 7 is the exam in miniature: a service in that mesh that only one identity can read, with no published command (Chapter 16).

## Prerequisites

- A Linux machine with kind, kubectl, docker, helm, jq, curl, tar, sha256sum, base64, od and openssl on PATH, and with at least 14 GB of free RAM: the lab brings up nine kind nodes in four clusters (`ckne-lab5-red`, `ckne-lab5-cifra`, `ckne-lab5-sello` and `ckne-lab5-id`) and deletes them all in the teardown.
- ISOLATION. This lab's clusters NEVER touch your everyday kubeconfig: they are created with --kubeconfig ~/ckne-lab/p04/kubeconfig from the very first command, and every kubectl, helm and istioctl in the lab passes that file and an explicit context. Helm is used with --repo, so no repositories are added to your configuration either. If you already have other kind clusters, this lab does not see them, modify them or delete them. The setup prints kind get clusters before starting so you can check.
- Step 3 encrypts with WireGuard, and kind nodes share the host's kernel: the module has to be loaded there before you start (sudo modprobe wireguard). The setup checks it and stops with a message if it is missing. It is the only thing in the lab that needs administrator rights on the host.
- Internet access throughout the lab: kind pulls the node image; Step 1 pulls the Calico manifest from raw.githubusercontent.com; Helm pulls Cilium from helm.cilium.io, cert-manager from quay.io and SPIRE from spiffe.github.io; Step 4 pulls the Gateway API CRDs and the istioctl binary from github.com; the Pods pull nginx, curl, netshoot and busybox pinned by digest or version. The 60-minute estimate assumes the images are already downloaded; on a first run the download time is added. The guided path of Steps 1 to 6 took 9 minutes of machine time (562 s) in the verification run; the rest is reading, the deliverables and Step 7, which was not timed with a person. The 14 GB of RAM is an estimate, not a measurement.
- A new cluster for each of the four topics, with names the chapters do not use: neither the namespaces, nor the Pods, nor the Gateways of those pages repeat here. What does repeat are the tools and versions: Calico 3.33.1, Cilium 1.20.5, cert-manager v1.21.3, Istio 1.32.0 and SPIRE 1.16.0.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 13: Only the workshop's operators reach the stock (10 pts)

Objective: in the `ckne-lab5-red` cluster (one control plane and one worker, Calico 3.33.1 and no kindnet), three namespaces with the label zona equal to their name: `deposito`, with the `existencias` Service (nginx, port 80); `maestranza`, with the operario Pod (rol=operario) and the novato Pod (rol=novato); and afuera, with another operario Pod (rol=operario). A NetworkPolicy named `solo-operarios` in `deposito` so that `existencias` receives only from the rol=operario Pods of the `zona=maestranza` namespaces. Deliverable: 01-respuesta.txt with PASA (who gets 200) and SIN_RESPUESTA (who does not, comma-separated and in alphabetical order).

Chapter 13 left a method: each rule is tested from a Pod that should get through and from one that should not. This matrix has two Pods that must not get through for different reasons: one because it has the wrong role in the right namespace, the other because it has the right role in the wrong namespace. A rule that lets either of them through is badly written, even if the one that was supposed to pass does.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is removing the Pods in the way or relabeling them. The check closes that: it demands the two-node cluster Ready at v1.37.0 with Calico v3.33.1 ready; the three namespaces with their zona label equal to their name; the `existencias` Service in the warehouse with its replica ready; the three Pods Running with their original rol labels; at least one NetworkPolicy in the warehouse (the `solo-operarios` name in the objective is not checked). Then it asks live from each Pod: `maestranza/operario` has to get 200 and the other two must not. Finally it compares 01-respuesta.txt with what the matrix says.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to `kind-ckne-lab5-red`, Calico v3.33.1's calico-node daemonset ends with successfully rolled out and both nodes report condition met. Before the policy, the matrix shows 200 in all three rows: everyone gets through. After applying `solo-operarios`, `maestranza/operario` gets 200 and the other two rows, `maestranza/novato` and afuera/operario, stay at 000 exit 28 (the request times out, it is not rejected). The trick is in the policy's shape: a single from element with the namespace's label AND the Pod's label together. With two elements it would read as OR and let any Pod of the workshop and any operator of any namespace through. 01-respuesta.txt ends up with `PASA=maestranza/operario` and `SIN_RESPUESTA=afuera/operario,maestranza/novato`.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 13: The administrator's layer closes what a NetworkPolicy left open (10 pts)

Objective: in `ckne-lab5-red`, the `verbena` namespace (label `zona=verbena`) with the `mostrario` Service (nginx, port 80) and an `abre-a-todos` NetworkPolicy that lets all traffic in. On top, a ClusterNetworkPolicy named `cierre-de-afuera`, Admin tier and priority 10, whose subject is the `zona=verbena` namespace and that denies ingress from the zona=afuera namespaces. The workshop's Pods must keep getting through. Deliverable: 02-respuesta.txt.

The cluster administrator cannot depend on every team closing its namespace well. Chapter 13 showed where its layer is evaluated relative to the teams' NetworkPolicies; this step checks it with a NetworkPolicy that, on purpose, leaves everything open.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is deleting or rewriting the `abre-a-todos` NetworkPolicy to close afuera. The check closes that: it demands that `abre-a-todos` keeps its original spec and is `verbena`'s only NetworkPolicy; that the `cierre-de-afuera` ClusterNetworkPolicy exists with tier Admin, a single ingress with action Deny, priority 10, and the subject and origin by zone label; and the two live reads (`maestranza` gets through, afuera does not).

</details>

<details>
<summary>What you should see</summary>

The `verbena` namespace is created with its label, the `mostrario` Service with one replica and the `abre-a-todos` NetworkPolicy, which allows all ingress. Before the administrator's layer, both rows give 200. After applying `cierre-de-afuera`, `maestranza/operario` stays at 200 and afuera/operario drops to 000 exit 28, even though `abre-a-todos` is still there: the Admin tier is evaluated before any NetworkPolicy. 02-respuesta.txt ends up with NIVEL=Admin, ACCION=Deny and NETWORKPOLICY_INTACTA=si.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 14: Encrypting between nodes with WireGuard, confirmed by a capture on the node (10 pts)

Objective: in `ckne-lab5-cifra` (one control plane and two workers, Cilium 1.20.5 with the usual kube-proxy), the `faro` namespace with the origen Pod (netshoot, on the first worker), the destino Pod (nginx, on the second) and the `puente` Pod (nginx with hostNetwork, also on the second). Transparent encryption between nodes with WireGuard, and a test that does not depend on what the agent reports: a new token in a request from origen to destino, looked for in a capture of the origin node's eth0. Deliverable: 03-respuesta.txt.

The way of testing that Chapter 14 left works here: put text in the request that exists nowhere else and look for it in a capture on the node. This lab's token is that text (the chapter's secret pass, under another name). An agent can report Wireguard and still have traffic that crosses readable over the nodes' network: that is why there is a third Pod, `puente`, which is on the node's network and not on the Pods' network, and why it is measured too.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is trusting what an agent says, or putting both Pods on the same node. The check closes that: it demands the three-node cluster Ready with Cilium v1.20.5 ready on all three; origen on `ckne-lab5-cifra-worker` and destino on `ckne-lab5-cifra-worker2`, without hostNetwork, and `puente` with hostNetwork; all three agents saying Wireguard. Then it makes its own captures with a new token: from origen to destino the token cannot be readable on eth0 and there have to be UDP 51871 packets, and the reading toward `puente` is compared with the one you wrote. The numbers in 03-respuesta.txt have to be the ones that capture measures.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to `kind-ckne-lab5-cifra`, Cilium v1.20.5 ends with successfully rolled out and the three nodes report condition met. The Pods origen (on `ckne-lab5-cifra-worker`), destino (on `ckne-lab5-cifra-worker2`) and `puente` (hostNetwork, on `ckne-lab5-cifra-worker2`) end up Running. Before encrypting, the capture from origen to destino gives ficha-legible 1 and udp-8472 with packets: it travels encapsulated in VXLAN but unencrypted. After the helm upgrade and the agents' restart, all three say Encryption: Wireguard; the capture from origen to destino gives ficha-legible 0 and udp-51871 with packets. The capture toward `puente` gives ficha-legible 1: that traffic goes over the nodes' network, not the Pods' network, and the agents print NodeEncryption: Disabled. 03-respuesta.txt ends up with AGENTES_CON_WIREGUARD=3, FICHA_LEGIBLE_ENTRE_PODS=0, UDP_51871_ENTRE_PODS=si and FICHA_LEGIBLE_HACIA_EL_PUENTE=1.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 15: An HTTPS listener whose certificate cert-manager issues, read from a client that holds the root (10 pts)

Objective: in `ckne-lab5-sello` (one control plane and one worker), Istio 1.32.0 with the minimal profile, Gateway API v1.6.1 and cert-manager v1.21.3 with the Gateway API enabled; a root of your own (`raiz-lab`) and a `casa-emisora` ClusterIssuer that signs with it; the `letrero` application in the `ribera` namespace, the `entrada-lab` Gateway in the `dique` namespace and a `cliente-tls` client holding the root. Then, on `entrada-lab`, an HTTPS listener on 443 for `letrero.lab.example` whose certificate cert-manager requests from `casa-emisora` through the Gateway annotation, with a validity of 2 hours and renewal at 1 hour. Deliverable: 04-respuesta.txt.

Chapter 15 gave the sequence for looking at a listener: its conditions and the message, then the Certificate and its events, and finally the chain seen from a client that holds the root. This step uses it from start to finish on a listener that does work, so the next one can use it on one that does not. A certificate issued by hand and put in a Secret opens the padlock all the same, but it is not what is asked: cert-manager is the one that issues and renews it.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is creating the certificate by hand and putting it in a Secret. The check closes that: it demands Istio 1.32.0, cert-manager v1.21.3 and the v1.6.1 CRDs; the root and the issuer Ready; on the `entrada-lab` Gateway the three cert-manager annotations with the `casa-emisora` issuer, 2h validity and renewal at 1h, and a single HTTPS listener on port 443 with the name `letrero.lab.example`, tls Terminate and the reference to the `letrero-tls` Secret; both listeners' conditions True; and the `letrero-tls` Certificate with the Gateway as owner, the issuer, name, validity and renewal asked for, and Ready. Then it makes its own reading from the client with the root copied at that moment: the chain has to verify with the name and the page has to arrive. The serial in 04-respuesta.txt is the one port 443 serves now.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to `kind-ckne-lab5-sello`; the Gateway API v1.6.1 CRDs are applied; the istioctl fingerprint prints OK and Istio ends with Installation complete; the helm install of cert-manager v1.21.3 with --wait ends without error. The `raiz-lab` root and the `casa-emisora` issuer end up Ready. Before the HTTPS listener, the request on port 80 returns the page `letrero: salida 7 puntual`. After applying the Gateway with the annotation, the `letrero-tls` Certificate appears, ends up Ready and both listeners' conditions are True (Accepted, Programmed, ResolvedRefs). The certificate served on port 443 carries the SAN `letrero.lab.example` and the issuer CN=Autoridad del puerto, and curl with the root prints the same page. 04-respuesta.txt ends up with `CERTIFICADO=letrero-tls`, `EMISOR=casa-emisora`, REVISION=1 and the served certificate's serial.

</details>

```bash
./04-step.sh
./04-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 5. Ch. 15: Another listener that does not encrypt, diagnosed in the chapter's order (10 pts)

Objective: in `ckne-lab5-sello`, a Gateway named `embarcadero` in the `dique` namespace, with an https listener for `embarcadero.lab.example` and a route in `ribera` toward the `letrero` application, serves this lab's certificate and the `cliente-tls` client receives the page with the root in hand. Today it does not encrypt: `inyectar-falla.sh` leaves it broken. Locate the fault by reading in Chapter 15's order, repair it without deleting or recreating the Gateway and leave the diagnosis written. Deliverables: 05-diagnostico.txt, with one section per reading (1 the listener and its message, 2 the Certificate and its events, 3 the chain seen from the client) and 05-respuesta.txt.

A listener that does not encrypt does not always return an error you can read at once: the client only sees that it does not connect. The Step 4 readings work here with other names (the Gateway is `embarcadero` and the host `embarcadero.lab.example`). The order matters because each reading narrows the next.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is deleting the Gateway and creating another one, or repairing it without having read anything. The check closes that: it demands that 05-diagnostico.txt is newer than the fault, carries the three sections, the https listener's reading with its condition at False and the exact name you found out of place; that the `embarcadero` Gateway is the same object that broke; that its https listener and its route stay as they were; that its conditions are True and that the `embarcadero-tls` Certificate was created by cert-manager (the Gateway is its owner), is Ready and ends up configured as in Step 4; and that from the client with the root the chain verifies with the name and the page arrives. The four lines in 05-respuesta.txt have to match what the fault left.

</details>

<details>
<summary>What you should see</summary>

`inyectar-falla.sh` prints falla inyectada. THE SYMPTOM: the client requests `embarcadero.lab.example` on 443 and gets curl: (7) Failed to connect: that listener is not serving. The diagnosis, saved in 05-diagnostico.txt, reads in Chapter 15's order. 1: the https listener is Accepted=True but Programmed=False (Invalid) and ResolvedRefs=False (InvalidCertificateRef), with the message secret `dique/embarcadero-tls` not found. 2: the `embarcadero-tls` Certificate exists but is not Ready; its CertificateRequest points at the `casa-emisora-nueva` issuer and the events say IssuerNotFound with that name. 3: from the client, openssl s_client gets Connection refused. A fourth reading that the cmd adds, outside the three sections the check requires: the Gateway's cert-manager.io/cluster-issuer annotation says `casa-emisora-nueva`, and the issuers that exist are `casa-emisora` and `semilla-lab`. The repair is to put in the annotation the issuer that exists: cert-manager requests the certificate again, the listener goes to Programmed and ResolvedRefs True and the client gets the page. 05-respuesta.txt ends up with the listener, the condition, the issuer that did not exist and the correct one.

</details>

```bash
./05-step.sh
./05-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 6. Ch. 16: A server's identity and a Pod's pass, read live (10 pts)

Objective: in `ckne-lab5-id` (one control plane and one worker), SPIRE with the `lab.test` trust domain and the cluster name `ckne-lab5-id`, and Istio 1.32.0 (the istioctl Step 4 downloaded) with that same domain and the spire template; the `cubierta` namespace with injection, the `capitan`, `invitado` and `bascula` ServiceAccounts; the `bascula` Deployment (nginx, with the sidecar and spire template) and its Service; and the `portador` Pod (`capitan` ServiceAccount) with a pass of audience `bascula` and 900 seconds. Deliverable: 06-respuesta.txt, with what you read from the sidecar's document, the pass and SPIRE's registry.

For the identity part Chapter 16 asked for two checks: open the document before writing a rule and, when a rule does not seem to act, repeat the request with the elapsed time in view. This step is the first one: it leaves the document, the pass and the registry read. The pass (the chapter's passport) is one thing and the sidecar's document is another: the first is signed by Kubernetes to talk to an API, the second by SPIRE to talk between services.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is writing into 06-respuesta.txt what the chapter showed. The check closes that: it demands SPIRE (the server ready, one agent, the `lab.test` trust domain) and Istio 1.32.0 with that same domain; the `cubierta` namespace with injection and its three ServiceAccounts; `bascula` with the sidecar,spire template; and it reads live the sidecar's document (the trust domain's URI and O = SPIRE in the document's subject), the SPIRE entry with the uid of `bascula`'s current Pod and `portador`'s pass (audience `bascula`, 900 s, `capitan` ServiceAccount). The five lines in 06-respuesta.txt have to match what those readings give now, the number of entries included.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to `kind-ckne-lab5-id`; the SPIRE chart leaves spire-server-0 2/2, one spire-agent, the CSI driver and the OIDC provider; Istio ends with Installation complete. In `cubierta`, `bascula` ends up 2/2 and `portador` 2/2. The `bascula` sidecar's document carries subject=C = US, O = SPIRE and the URI `spiffe://lab.test/ns/cubierta/sa/bascula`; the issuer line comes out with the default name of SPIRE's CA (CN = example.org), and EMISOR_DE_LA_IDENTIDAD holds the O of the subject. `portador`'s pass carries sub `system:serviceaccount:cubierta:capitan`, aud `bascula` and life 900. SPIRE registers one entry per Pod, `/ns/cubierta/sa/bascula` and `/ns/cubierta/sa/capitan`, each with its k8s:pod-uid selector. 06-respuesta.txt ends up with `bascula`'s URI, SPIRE, `bascula`, 900 and 2 entries.

</details>

```bash
./06-step.sh
./06-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 7. Ch. 16: A service only one identity can read, with the objective only (unsolved point) (10 pts)

The exam does not give you the command: it gives you a task written as an objective. This step is that situation in small. Everything you need you have from Step 6 and from Chapter 16: how a Pod gets into the mesh with its identity, what the document says and how a rule is measured when it takes time to act. What you do not have is a recipe: the setup left the token in a file that changes on every run, like the datum the exam puts in the statement. There is no answer file either: what is graded is the state of the cluster.

The objective is written as a comment at the end of the step's cmd. Read it calmly, write on one line each condition that has to hold, and build the end state one at a time. When something does not work, read the state of each object and repeat the request while watching the time.

<details>
<summary>Grader hint (check_hint)</summary>

This is the unsolved point: the check fails on the guided state of Steps 1 to 6 because `bahia` does not even exist, until you solve it. The shortcuts it closes: editing the token (it is compared with a fingerprint the setup saved apart) and leaving the Pods without SPIRE's identity. The probes are new and each carries a different ServiceAccount. What is decisive is that a new probe with `jefe-de-bahia` receives the full token twice and that the other two receive 403, not a connection error.

</details>

<details>
<summary>What you should see</summary>

This step's command sequence is not published: it is the unsolved point. The correct end state: in `ckne-lab5-id` the `bahia` namespace exists with injection, the `jefe-de-bahia` ServiceAccount and a `cofre` Service of type ClusterIP with a selector and port 80, whose Pods are in the mesh with their SPIRE identity and answer this run's token at the root; and only `jefe-de-bahia`'s identity receives the token: any other, whether from the same namespace or another, gets 403. The check creates three new probes (`jefe-de-bahia`'s, one from another ServiceAccount in the same namespace and one from a foreign namespace) and repeats the request with the elapsed time in view until the rule acts.

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

- **Symptom (step 1):** kind create fails with too many open files
  **What to do:** It is the host's inotify limit, shared by all the nodes. Raise fs.inotify.max_user_instances with sysctl (the setup prints the current value), delete the half-built cluster with kind delete cluster --name `ckne-lab5-red` --kubeconfig ~/ckne-lab/p04/kubeconfig and repeat.

- **Symptom (step 1):** All three Pods return 000 even before the policy is applied
  **What to do:** Calico or CoreDNS have not finished starting. Wait for calico-node and coredns to be ready with kubectl -n kube-system get pods and repeat the matrix.

- **Symptom (step 2):** kubectl does not recognize the ClusterNetworkPolicy type
  **What to do:** The CRD is installed by Calico v3.33.1. Check with kubectl get crd | grep clusternetworkpolicies that it exists, and that the manifest's apiVersion is policy.networking.k8s.io/v1alpha2.

- **Symptom (step 2):** You applied the policy and afuera still gets 200
  **What to do:** The rules take a few seconds to reach the nodes: wait five seconds and repeat the matrix. If it persists, read the tier and the priority with kubectl get clusternetworkpolicy and compare the tier with the one Chapter 13 used.

- **Symptom (step 3):** The agents say Encryption: Disabled after the helm upgrade
  **What to do:** An agent reads its configuration at startup. Check with helm get values cilium -n kube-system that encryption was requested and restart the cilium daemonset; wait for the rollout to finish before looking again.

- **Symptom (step 3):** The capture prints ficha-legible 0 and also udp-51871 0 and udp-8472 0
  **What to do:** It captured nothing: the request did not leave through that interface. Check that origen and destino are on different nodes with kubectl -n `faro` get pods -o wide and that you captured on the origin node, not the destination one.

- **Symptom (step 4):** The `letrero-tls` Certificate does not show up
  **What to do:** cert-manager only watches Gateways if it was installed with the Gateway API enabled. Check with helm get values cert-manager -n cert-manager that gatewayAPI.enabled is true and that the Gateway carries the annotations in metadata.annotations, not in spec.

- **Symptom (step 4):** The Step 4 check fails on REVISION or SERIE_SERVIDA although you changed nothing
  **What to do:** A certificate reissue changes the revision and the serial port 443 serves (the verification run saw it when the duration was changed). Read both again and rewrite 04-respuesta.txt.

- **Symptom (step 4):** curl says unable to get local issuer certificate
  **What to do:** The client does not hold this run's root. Copy it from the `raiz-lab` Secret (key ca.crt) to /raiz.crt in `cliente-tls` and request with --cacert /raiz.crt; the certificate's name and the request's name have to be the same.

- **Symptom (step 5):** The client says Connection refused on 443
  **What to do:** The proxy does not open that listener's port. First read the listener's conditions and the message of the condition that is False, before touching any object.

- **Symptom (step 5):** After repairing, the listener's condition is still False
  **What to do:** cert-manager retries with a growing wait. Wait a minute and look again at the Certificate and its events with kubectl -n `dique` get certificate and kubectl -n `dique` events; the most recent event says where it stands.

- **Symptom (step 6):** The `cubierta` Pods stay at 1/2 or in Init
  **What to do:** The sidecar waits for SPIRE's socket. Check that the chart finished (kubectl -n spire-server get pods, with the CSI driver at 2/2) and that the spire template ended up in Istio's configuration; then delete the Pod so it is created again.

- **Symptom (step 6):** istioctl is not found
  **What to do:** Use the one Step 4 downloaded: ./bin/istioctl from ~/ckne-lab/p04, with explicit --kubeconfig and --context. This step does not download it again.

- **Symptom (step 7):** The `cofre` Pod stays at 1/2
  **What to do:** Look at the Pod's events with kubectl -n `bahia` describe pod and compare what you declared with what you did with the `cubierta` Pods in Step 6.

- **Symptom (step 7):** My Service answers the token but the check says no
  **What to do:** Compare what it answers with the content of `~/ckne-lab/p04/ficha-del-cofre.txt`: a trailing newline does not matter, but any other character does. Request with a probe of your own from each identity and look at the code as well as the body.

## Going further

- In Step 1, change the policy so that from has two elements instead of one and repeat the matrix. Count who gets through now, and explain with the three Pods' labels why it changed.
- In Step 3, also turn on node encryption with encryption.nodeEncryption and repeat the capture toward `puente` from each node. Note what each capture reads and look in Cilium's documentation for why. This may change what the Step 3 check measures: do it after checking the step.
- In Step 7, create a second Pod with the `jefe-de-bahia` ServiceAccount but in another namespace and measure whether it receives the token. Do it after checking Step 7. Explain with what the identity document says why or why not.

## References

- Kubernetes, Network Policies. The AND and OR of from selectors and the isolation model used in Steps 1 and 2. https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Calico, tiered policy and the kind installation guide (v3.33). The Calico manifest on kind and the tiers behind the Admin layer used in Steps 1 and 2. https://docs.tigera.io/calico/latest/network-policy/policy-tiers/tiered-policy and https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind
- Kubernetes SIG Network, network-policy-api. The ClusterNetworkPolicy resource with its Admin and Baseline tiers, used in Step 2. https://network-policy-api.sigs.k8s.io/
- Cilium Project, WireGuard transparent encryption (stable). encryption.type wireguard, cilium-dbg encrypt status and UDP port 51871, used in Step 3. https://docs.cilium.io/en/stable/security/network/encryption-wireguard/
- Cilium Project, Installation using kind. The kind configuration with the default CNI disabled, used in Step 3. https://docs.cilium.io/en/stable/installation/kind/
- cert-manager, Securing Gateway resources. The cert-manager.io/cluster-issuer, duration and renew-before annotations on a Gateway, used in Steps 4 and 5. https://cert-manager.io/docs/usage/gateway/
- cert-manager, CA issuer and self-signed issuer. The root and the issuer built in Step 4. https://cert-manager.io/docs/configuration/ca/ and https://cert-manager.io/docs/configuration/selfsigned/
- Gateway API, TLS guide. The HTTPS listener, tls.mode Terminate and certificateRefs used in Steps 4 and 5. https://gateway-api.sigs.k8s.io/guides/user-guides/tls/
- OpenSSL, openssl-s_client (3.5). The chain read from a client that holds the root, used in Steps 4 and 5. https://docs.openssl.org/3.5/man1/openssl-s_client/
- Istio Project, SPIRE integration. The spire sidecar template and the SPIFFE CSI socket used in Steps 6 and 7. https://istio.io/latest/docs/ops/integrations/spire/
- SPIFFE helm-charts-hardened, spire 0.31.0 release. The chart and the spire-crds chart used in Step 6. https://github.com/spiffe/helm-charts-hardened/releases/tag/spire-0.31.0
- Istio Project, AuthorizationPolicy reference. Authorization rules in the mesh, used in Step 7. https://istio.io/latest/docs/reference/config/security/authorization-policy/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
