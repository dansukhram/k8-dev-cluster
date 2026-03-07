# k8-dev-cluster — Standard Operating Procedure

**Last verified:** 2026-03-06  
**Result:** 3 control-plane + 5 worker nodes, all `Ready`, Kubernetes v1.33.9 + Flux v2.8.1

---

## Overview

This project provisions a production-style Kubernetes cluster on Proxmox VE using:
- **Terraform** — clones VMs from a cloud-init template
- **Ansible** — configures OS, installs containerd + Kubernetes, forms the cluster
- **Flux v2** — GitOps controller that reconciles your Git repo to the cluster
```
zadig (your workstation)
  │
  ├── Terraform ──────────► Proxmox k8-dev (172.16.1.2)
  │                              └── Clones template 9002 → 8 VMs
  │
  ├── Ansible ─────────────► 8 VMs (172.16.1.20–27)
  │                              ├── containerd 2.2.1 runtime
  │                              ├── kubeadm / kubelet / kubectl
  │                              ├── kubeadm init (master1)
  │                              ├── HA join (master2, master3)
  │                              └── Worker join (worker1–5)
  │
  └── Flux ────────────────► GitHub (dansukhram/k8-dev-cluster)
                                  └── Reconciles flux/clusters/k8-dev/
```

---

## Part 1 — One-Time Workstation Setup

Install required tools on `zadig`. Skip any already installed.
```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# Ansible
sudo apt install -y ansible

# kubectl (requires Kubernetes apt repo — NOT in default Ubuntu repos)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install -y kubectl

# Ansible collections
cd ~/Downloads/k8-dev/k8-dev-cluster
ansible-galaxy collection install -r ansible/requirements.yml

# Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
  sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" | \
  sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install -y gh

# Set KUBECONFIG permanently
echo 'export KUBECONFIG=~/Downloads/k8-dev/k8-dev-cluster/kubeconfig' >> ~/.bashrc
source ~/.bashrc
```

---

## Part 2 — One-Time Proxmox Setup (per Proxmox host)

### 2a — Create API token
```bash
ssh root@172.16.1.2
pveum user token add root@pam terraform --privsep=0
# Save the "value" from the output — that is your token secret
exit
```

### 2b — Create Ubuntu 24.04 cloud-init template (VM 9002)
```bash
# From your workstation in the repo directory:
scp scripts/create-ubuntu-template.sh root@172.16.1.2:/tmp/
ssh root@172.16.1.2 'bash /tmp/create-ubuntu-template.sh'
# Takes ~5 minutes. Safe to re-run — exits if 9002 already exists.
```

---

## Part 3 — Full Cluster Deployment

Run these steps every time you want to build the cluster from scratch.

### Step 1 — Clone the repo
```bash
git clone https://github.com/dansukhram/k8-dev-cluster.git
cd k8-dev-cluster
```

### Step 2 — Create secrets file (gitignored — must be created manually)
```bash
cat > terraform/secrets.tfvars << 'EOF'
proxmox_api_token = "root@pam!terraform=YOUR-TOKEN-SECRET"
EOF
```

### Step 3 — Provision VMs with Terraform
```bash
make init     # Download bpg/proxmox provider
make plan     # Preview: should show "8 to add, 0 to change"
make apply    # Create all 8 VMs (~5-10 minutes)
```

Expected output:
```
all_node_ips = {
  "k8-master1-dev" = "172.16.1.20/24"
  ...
  "k8-worker5-dev" = "172.16.1.27/24"
}
```

> ⚠️ VMs need ~60 seconds after Terraform completes to finish cloud-init boot. Wait before continuing.

### Step 4 — Accept SSH host keys
```bash
for ip in 172.16.1.20 172.16.1.21 172.16.1.22 \
          172.16.1.23 172.16.1.24 172.16.1.25 \
          172.16.1.26 172.16.1.27; do
  ssh-keyscan -H $ip >> ~/.ssh/known_hosts
done
```

### Step 5 — Verify connectivity
```bash
make ping
# All 8 nodes must return "pong" before continuing
```

### Step 6 — Configure cluster with Ansible (~15 minutes)
```bash
cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

| Playbook | Time | What it does |
|---|---|---|
| `01-common.yml` | ~2 min | Packages (incl. conntrack), swap off, kernel modules, sysctl |
| `02-containerd.yml` | ~2 min | containerd from Docker repo, `SystemdCgroup=true` |
| `03-kubernetes.yml` | ~2 min | kubeadm + kubelet + kubectl v1.33, version-pinned |
| `04-masters.yml` | ~6 min | `kubeadm init` on master1, Flannel CNI, HA join master2+3 |
| `05-workers.yml` | ~2 min | Fetch fresh join token from master1, join all 5 workers |
| `06-post-install.yml` | ~1 min | Fetch kubeconfig locally, validate all nodes `Ready` |

### Step 7 — Verify cluster
```bash
cd ~/Downloads/k8-dev/k8-dev-cluster
export KUBECONFIG=~/Downloads/k8-dev/k8-dev-cluster/kubeconfig
kubectl get nodes
```

Expected:
```
NAME             STATUS   ROLES           AGE   VERSION
k8-master1-dev   Ready    control-plane   5m    v1.33.9
k8-master2-dev   Ready    control-plane   3m    v1.33.9
k8-master3-dev   Ready    control-plane   3m    v1.33.9
k8-worker1-dev   Ready    <none>          2m    v1.33.9
...
k8-worker5-dev   Ready    <none>          2m    v1.33.9
```

### Step 7b — Label worker nodes (optional, cosmetic)

Worker nodes show `<none>` for ROLES — this is normal. To add a label:
```bash
for i in 1 2 3 4 5; do
  kubectl label node k8-worker${i}-dev node-role.kubernetes.io/worker=worker
done
```

### Step 8 — Bootstrap Flux GitOps
```bash
# Create a GitHub Personal Access Token (classic) with 'repo' scope:
# https://github.com/settings/tokens

export GITHUB_TOKEN=ghp_yourTokenHere
cd ~/Downloads/k8-dev/k8-dev-cluster
make flux
```

Expected final output:
```
✔ all components are healthy
✔ Flux bootstrapped successfully!
```

Verify:
```bash
flux get all -A
kubectl get pods -n flux-system
```

---

## Part 4 — Cluster Health Checks

### Check 1 — All nodes Ready
```bash
kubectl get nodes
```

### Check 2 — All system pods running
```bash
kubectl get pods -n kube-system
# Expect: 2 coredns, 3 etcd, 3 apiserver, 3 scheduler,
#         3 controller-manager, 8 kube-proxy, 8 flannel
```

### Check 3 — Flux healthy
```bash
flux get all -A
kubectl get pods -n flux-system
# Expect: helm-controller, kustomize-controller,
#         notification-controller, source-controller all Running
```

### Check 4 — containerd runtime (not Docker)
```bash
kubectl get nodes \
  -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.containerRuntimeVersion}{"\n"}{end}'
# Every node: containerd://2.2.1
```

### Check 5 — DNS inside cluster
```bash
kubectl run dns-test --image=busybox:1.28 --restart=Never -- nslookup kubernetes.default
sleep 5 && kubectl logs dns-test && kubectl delete pod dns-test
# Should resolve kubernetes.default.svc.cluster.local → 10.96.0.1
```

### Check 6 — Workload scheduling
```bash
kubectl create deployment nginx-test --image=nginx --replicas=5
kubectl get pods -o wide   # verify spread across workers
kubectl delete deployment nginx-test
```

---

## Part 5 — Deploying a New App via GitOps

Once Flux is running, deploying apps is just a `git push`:
```bash
# Create app manifests
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
EOF

git add flux/apps/k8-dev/
git commit -m "feat: deploy nginx via GitOps"
git push

# Flux picks it up within ~1 minute
flux get kustomizations -w
```

---

## Part 6 — Deploying on a Different Proxmox Server

| File | What to update |
|---|---|
| `terraform/terraform.tfvars` | `proxmox_endpoint`, `proxmox_node`, all IPs, `gateway`, `network_bridge`, `storage_pool` |
| `terraform/secrets.tfvars` | New `proxmox_api_token` |
| `ansible/inventory/hosts.yml` | All `ansible_host` IPs |
| `ansible/inventory/group_vars/all.yml` | `cluster_name`, `control_plane_endpoint` |
| `ansible/playbooks/06-post-install.yml` | Master1 IP in the `replace:` line |

Everything else (roles, modules, Flux structure) stays the same.

---

## Part 7 — Teardown
```bash
make destroy                                  # Destroy all 8 VMs
ssh root@172.16.1.2 'qm destroy 9002'        # Remove template (full clean slate)
```

---

## Quick Reference
```bash
export KUBECONFIG=~/Downloads/k8-dev/k8-dev-cluster/kubeconfig

kubectl get nodes                                 # Node status
kubectl get pods -A                               # All pods
kubectl get pods -n kube-system                   # System pods
kubectl get pods -n flux-system                   # Flux pods
flux get all -A                                   # Flux sync status
flux logs                                         # Flux controller logs
kubectl describe node k8-worker1-dev              # Node details
kubectl get events -A --sort-by='.lastTimestamp'  # Recent events
```

---

## Troubleshooting Reference

| Error | Fix |
|---|---|
| `terraform: command not found` | Install from HashiCorp apt repo (Part 1) |
| `kubectl: Unable to locate package` | Add Kubernetes apt repo first — NOT in default Ubuntu repos |
| `Invalid character ";"` in variables.tf | Fixed in repo — Terraform requires newlines not semicolons |
| `provider hashicorp/proxmox not found` | Fixed in repo — module has its own `versions.tf` |
| `ACL update failed: no such token` | Token created on wrong Proxmox node — re-create on target host |
| `Connection refused` on ping after apply | VMs still booting — wait 60s and retry |
| `Host key verification failed` | Run `ssh-keyscan` loop (Step 4) |
| `role 'common' was not found` | Run playbooks from `ansible/` dir; `roles_path = roles` in `ansible.cfg` |
| `k8s_join_command undefined` | Fixed in repo — `05-workers.yml` fetches fresh token in Play 1 |
| `conntrack not found` | Fixed in repo — added to `roles/common/tasks/main.yml` |
| `sudo required` on localhost task | Fixed in repo — `become: false` on `delegate_to: localhost` |
| `Flux: couldn't find remote ref main` | Repo was on `master` — rename: `git branch -m master main && git push -u origin main` |
| `Flux: gotk-sync.yaml not found` | Fixed in repo — removed hand-crafted flux-system files, Flux generates them |
| `Flux: Kubernetes version does not match` | Fixed — cluster upgraded to 1.33 to match Flux 2.8.1 requirements |
| `KUBECONFIG not set` | Run `export KUBECONFIG=~/Downloads/k8-dev/k8-dev-cluster/kubeconfig` or add to `~/.bashrc` |
