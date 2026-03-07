# k8-dev-cluster

Production-style Kubernetes cluster on Proxmox VE using **Terraform**, **Ansible**, and **Flux GitOps**.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Proxmox Host: k8-dev (172.16.1.2)  bridge: vmbr0        │
│                                                           │
│  ┌─────────────────┐  ┌─────────────────┐                │
│  │ k8-master1-dev  │  │ k8-master2-dev  │  k8-master3    │
│  │ 172.16.1.20     │  │ 172.16.1.21     │  172.16.1.22   │
│  │ 2 vCPU / 4 GB   │  │ 2 vCPU / 4 GB   │  2vCPU / 4GB  │
│  └─────────────────┘  └─────────────────┘                │
│                                                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ ┌─────┐│
│  │ worker1  │ │ worker2  │ │ worker3  │ │  w4  │ │  w5 ││
│  │ .23      │ │ .24      │ │ .25      │ │  .26 │ │  .27││
│  └──────────┘ └──────────┘ └──────────┘ └──────┘ └─────┘│
└──────────────────────────────────────────────────────────┘

Container runtime : containerd (SystemdCgroup=true)
CNI               : Flannel  (10.244.0.0/16)
GitOps            : Flux v2
```

---

## Prerequisites — install on `zadig` (172.16.1.108)

### Terraform ≥ 1.6
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

### Ansible ≥ 2.15 + collections
```bash
sudo apt install ansible python3-pip
cd ansible && ansible-galaxy collection install -r requirements.yml
```

### Flux CLI
```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```

### GitHub CLI
```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
  sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install gh
```

---

## Step 1 — Fix Proxmox API token permissions

Your token (`root@pam!terraform`) was created with **Privilege Separation = Yes**, which means it needs explicit ACLs. Run this **on the Proxmox host**:

```bash
pveum acl modify / -token 'root@pam!terraform' -role Administrator
```

Or via the UI: **Datacenter → Permissions → Add → API Token Permissions**
- Path: `/`
- Token: `root@pam!terraform`
- Role: `Administrator`

---

## Step 2 — Create Ubuntu 24.04 Cloud-Init Template

Copy the script to your Proxmox host and run it:

```bash
scp scripts/create-ubuntu-template.sh root@172.16.1.2:/tmp/
ssh root@172.16.1.2 'bash /tmp/create-ubuntu-template.sh'
```

This will:
1. Download Ubuntu 24.04 Noble cloud image
2. Install `qemu-guest-agent` into the image
3. Create VM **9002** and convert it to a template

> ⏱ Takes ~3-5 minutes depending on download speed.

---

## Step 3 — Create the GitHub repository

```bash
gh auth login
gh repo create dansukhram/k8-dev-cluster --public --description "K8s cluster on Proxmox via Terraform + Ansible + Flux"
cd /path/to/this/repo
git init
git remote add origin https://github.com/dansukhram/k8-dev-cluster.git
git add .
git commit -m "feat: initial cluster scaffold"
git push -u origin main
```

> ⚠️ `secrets.tfvars` and `terraform.tfvars` are gitignored — they contain your API token. Keep them local only.

---

## Step 4 — Provision VMs with Terraform

```bash
# Initialise providers
make init

# Review what will be created
make plan

# Provision all 8 VMs
make apply
```

Terraform will clone the Ubuntu 24.04 template into:
- 3× control-plane VMs (200, 201, 202)
- 5× worker VMs (203, 204, 205, 206, 207)

All get static IPs, your SSH key, and the correct cloud-init configuration.

> ⏱ Takes ~5-10 minutes for all clones to complete and VMs to boot.

---

## Step 5 — Verify VMs are reachable

```bash
# Wait ~60s after Terraform finishes, then:
make ping
```

Expected output: all 8 nodes respond with `pong`.

If any node fails, check:
```bash
ssh ubuntu@172.16.1.20   # test manually
```

---

## Step 6 — Configure cluster with Ansible

```bash
make ansible
```

This runs 6 playbooks in order:

| Playbook | What it does |
|---|---|
| `01-common.yml` | Timezone, packages, swap off, kernel modules, sysctl |
| `02-containerd.yml` | Install containerd from Docker repo, configure SystemdCgroup |
| `03-kubernetes.yml` | Install kubeadm / kubelet / kubectl, hold versions |
| `04-masters.yml` | `kubeadm init` on master1, join master2+3, install Flannel CNI |
| `05-workers.yml` | Join all 5 workers to the cluster |
| `06-post-install.yml` | Fetch kubeconfig, validate all nodes are Ready |

> ⏱ Takes ~10-15 minutes end to end.

When complete, `kubeconfig` will be written to the repo root (gitignored).

---

## Step 7 — Verify the cluster

```bash
export KUBECONFIG=./kubeconfig

kubectl get nodes
# NAME               STATUS   ROLES           AGE   VERSION
# k8-master1-dev     Ready    control-plane   5m    v1.31.x
# k8-master2-dev     Ready    control-plane   4m    v1.31.x
# k8-master3-dev     Ready    control-plane   3m    v1.31.x
# k8-worker1-dev     Ready    <none>          2m    v1.31.x
# k8-worker2-dev     Ready    <none>          2m    v1.31.x
# k8-worker3-dev     Ready    <none>          2m    v1.31.x
# k8-worker4-dev     Ready    <none>          2m    v1.31.x
# k8-worker5-dev     Ready    <none>          2m    v1.31.x

kubectl get pods -A
```

---

## Step 8 — Bootstrap Flux GitOps

Create a GitHub Personal Access Token (classic) with `repo` scope at:
https://github.com/settings/tokens

```bash
export GITHUB_TOKEN=ghp_yourTokenHere
make flux
```

Flux will:
1. Install its controllers into the `flux-system` namespace
2. Configure a `GitRepository` pointing to `dansukhram/k8-dev-cluster`
3. Begin reconciling `flux/clusters/k8-dev/` on every push to `main`

Verify:
```bash
flux get all -A
kubectl get pods -n flux-system
```

---

## Step 9 — Deploy your first app via GitOps

Create app manifests and commit — Flux handles the rest:

```bash
# Example: deploy nginx
mkdir -p flux/apps/k8-dev/nginx
cat > flux/apps/k8-dev/nginx/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
EOF

git add flux/apps/k8-dev/nginx/
git commit -m "feat: add nginx deployment"
git push

# Watch Flux pick it up (within ~1 minute)
flux get kustomizations -w
```

---

## Daily Operations

```bash
# SSH to a node
ssh ubuntu@172.16.1.20

# Watch cluster events
kubectl get events -A --sort-by='.lastTimestamp'

# Upgrade Kubernetes (edit kubernetes_version in group_vars/all.yml, then)
cd ansible && ansible-playbook playbooks/03-kubernetes.yml

# Destroy everything
make destroy
```

---

## Future Improvements

- **HA Load Balancer** — You already have `k8-lb1-dev` and `k8-lb2-dev` VMs (IDs 111/112) in Proxmox. Configure HAProxy + Keepalived on them, create a VIP (e.g. `172.16.1.19`), and update `control_plane_endpoint` in `ansible/inventory/group_vars/all.yml` before first init.
- **Persistent Storage** — Add Longhorn or NFS provisioner for PersistentVolumes
- **Ingress** — Deploy ingress-nginx or Traefik via Flux
- **Cert-Manager** — TLS for ingress with Let's Encrypt
- **Monitoring** — kube-prometheus-stack via Flux HelmRelease

---

## Repository Structure

```
k8-dev-cluster/
├── Makefile                          ← One-command operations
├── scripts/
│   ├── create-ubuntu-template.sh    ← Run on Proxmox to create template
│   └── bootstrap-flux.sh            ← Bootstrap Flux GitOps
├── terraform/
│   ├── main.tf                      ← Master/worker node modules
│   ├── variables.tf / outputs.tf
│   ├── terraform.tfvars             ← Node config (gitignored)
│   ├── secrets.tfvars               ← API token (gitignored)
│   └── modules/proxmox-vm/          ← Reusable VM module
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml                ← All 8 nodes
│   │   └── group_vars/              ← Cluster-wide variables
│   ├── playbooks/                   ← Ordered execution playbooks
│   │   ├── site.yml                 ← Entry point
│   │   ├── 01-common.yml
│   │   ├── 02-containerd.yml
│   │   ├── 03-kubernetes.yml
│   │   ├── 04-masters.yml           ← kubeadm init + HA join
│   │   ├── 05-workers.yml           ← Worker join
│   │   └── 06-post-install.yml      ← Fetch kubeconfig, validate
│   └── roles/
│       ├── common/                  ← OS hardening, sysctl, modules
│       ├── containerd/              ← containerd + SystemdCgroup config
│       ├── kubernetes/              ← kubeadm/kubelet/kubectl install
│       ├── k8s-master/              ← kubeadm config template
│       └── k8s-worker/
└── flux/
    ├── clusters/k8-dev/             ← Flux sync config (auto-managed)
    └── apps/
        ├── base/                    ← Reusable app bases
        └── k8-dev/                  ← Cluster-specific overlays
```
