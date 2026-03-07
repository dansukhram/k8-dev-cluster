# k8-dev-cluster — Standard Operating Procedure

**Last verified:** 2026-03-06  
**Result:** 3 control-plane + 5 worker nodes, all `Ready`, Kubernetes v1.31.14

---

## Overview

This project provisions a production-style Kubernetes cluster on Proxmox VE using:
- **Terraform** — clones VMs from a cloud-init template
- **Ansible** — configures OS, installs containerd + Kubernetes, forms the cluster
- **Flux** — GitOps controller that reconciles your Git repo to the cluster

```
zadig (your workstation)
  │
  ├── Terraform ──────────► Proxmox k8-dev (172.16.1.2)
  │                              └── Clones template 9002 → 8 VMs
  │
  ├── Ansible ─────────────► 8 VMs (172.16.1.20–27)
  │                              ├── containerd runtime
  │                              ├── kubeadm / kubelet / kubectl
  │                              ├── kubeadm init (master1)
  │                              ├── HA join (master2, master3)
  │                              └── Worker join (worker1–5)
  │
  └── Flux ────────────────► GitHub → Cluster (GitOps sync)
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

# kubectl (requires Kubernetes apt repo — not in default Ubuntu repos)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | \
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
```

---

## Part 2 — One-Time Proxmox Setup (per Proxmox host)

### 2a — Create API token

```bash
ssh root@172.16.1.2
pveum user token add root@pam terraform --privsep=0
# Save the "value" from the output table — that is your token secret
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

Terraform clones template 9002 into 8 VMs with static IPs and your SSH key injected.

```bash
make init     # Download bpg/proxmox provider
make plan     # Preview: should show "8 to add, 0 to change"
make apply    # Create all 8 VMs (~5-10 minutes)
```

Expected output:
```
all_node_ips = {
  "k8-master1-dev" = "172.16.1.20/24"
  "k8-master2-dev" = "172.16.1.21/24"
  "k8-master3-dev" = "172.16.1.22/24"
  "k8-worker1-dev" = "172.16.1.23/24"
  "k8-worker2-dev" = "172.16.1.24/24"
  "k8-worker3-dev" = "172.16.1.25/24"
  "k8-worker4-dev" = "172.16.1.26/24"
  "k8-worker5-dev" = "172.16.1.27/24"
}
```

### Step 4 — Accept SSH host keys (prevents interactive prompts in Ansible)

```bash
for ip in 172.16.1.20 172.16.1.21 172.16.1.22 \
          172.16.1.23 172.16.1.24 172.16.1.25 \
          172.16.1.26 172.16.1.27; do
  ssh-keyscan -H $ip >> ~/.ssh/known_hosts
done
```

### Step 5 — Verify all nodes are reachable

```bash
make ping
# All 8 nodes must return "pong" before continuing
```

### Step 6 — Configure the cluster with Ansible

Runs all 6 playbooks in sequence. Total time: ~15 minutes.

```bash
cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

| Playbook | Time | What it does |
|---|---|---|
| `01-common.yml` | ~2 min | Packages (incl. conntrack), swap off, kernel modules, sysctl |
| `02-containerd.yml` | ~2 min | containerd from Docker repo, `SystemdCgroup=true` |
| `03-kubernetes.yml` | ~2 min | kubeadm + kubelet + kubectl v1.31, version-pinned |
| `04-masters.yml` | ~6 min | `kubeadm init` on master1, Flannel CNI, HA join master2+3 |
| `05-workers.yml` | ~2 min | Fetch fresh join token from master1, join all 5 workers |
| `06-post-install.yml` | ~1 min | Fetch kubeconfig locally, validate all nodes `Ready` |

When complete you'll see:
```
msg:
  - NAME             STATUS   ROLES           AGE   VERSION
  - k8-master1-dev   Ready    control-plane   19m   v1.31.14
  - k8-master2-dev   Ready    control-plane   16m   v1.31.14
  - k8-master3-dev   Ready    control-plane   16m   v1.31.14
  - k8-worker1-dev   Ready    <none>          2m    v1.31.14
  - k8-worker2-dev   Ready    <none>          2m    v1.31.14
  - k8-worker3-dev   Ready    <none>          2m    v1.31.14
  - k8-worker4-dev   Ready    <none>          2m    v1.31.14
  - k8-worker5-dev   Ready    <none>          2m    v1.31.14
```

### Step 7 — Set up kubectl on your workstation

```bash
export KUBECONFIG=~/Downloads/k8-dev/k8-dev-cluster/kubeconfig

# Make it permanent across sessions
echo 'export KUBECONFIG=~/Downloads/k8-dev/k8-dev-cluster/kubeconfig' >> ~/.bashrc

kubectl get nodes
```

### Step 8 — Bootstrap Flux GitOps

```bash
# Create a GitHub Personal Access Token (classic) with 'repo' scope:
# https://github.com/settings/tokens

export GITHUB_TOKEN=ghp_yourTokenHere
make flux
```

---

## Part 4 — Cluster Health Checks

Run after every deployment to confirm everything is working.

### Check 1 — All nodes Ready

```bash
kubectl get nodes -o wide
# All 8 nodes must show STATUS=Ready
```

### Check 2 — All system pods running

```bash
kubectl get pods -n kube-system
```

Expected pods and counts:
```
coredns-*              2/2  Running   ← DNS resolution
kube-flannel-ds-*      8/8  Running   ← one per node (networking)
kube-apiserver-*       3/3  Running   ← one per master
etcd-*                 3/3  Running   ← one per master (HA database)
kube-scheduler-*       3/3  Running   ← one per master
kube-controller-mgr-*  3/3  Running   ← one per master
kube-proxy-*           8/8  Running   ← one per node
```

### Check 3 — Verify containerd runtime (not Docker)

```bash
kubectl get nodes \
  -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.containerRuntimeVersion}{"\n"}{end}'

# Expected on every line:
# k8-master1-dev    containerd://1.7.x
```

### Check 4 — etcd HA health (all 3 masters)

```bash
ssh ubuntu@172.16.1.20
sudo etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  member list

# Should show 3 members, all "started"
```

### Check 5 — DNS resolution inside the cluster

```bash
kubectl run dns-test --image=busybox:1.28 --restart=Never -- \
  nslookup kubernetes.default
kubectl logs dns-test
# Should resolve kubernetes.default.svc.cluster.local
kubectl delete pod dns-test
```

### Check 6 — Deploy a real workload end-to-end

```bash
# Deploy 3 nginx replicas
kubectl create deployment nginx-test --image=nginx --replicas=3
kubectl expose deployment nginx-test --port=80 --type=NodePort

# Verify pods spread across different worker nodes
kubectl get pods -o wide

# Get the NodePort (e.g. 32345)
kubectl get svc nginx-test

# Hit it from your workstation
curl http://172.16.1.23:32345   # replace with actual NodePort

# Clean up
kubectl delete deployment nginx-test
kubectl delete svc nginx-test
```

---

## Part 5 — Deploying on a Different Proxmox Server

### Files to change

| File | What to update |
|---|---|
| `terraform/terraform.tfvars` | `proxmox_endpoint`, `proxmox_node`, all IPs, node names, `gateway`, `network_bridge`, `storage_pool` |
| `terraform/secrets.tfvars` | New `proxmox_api_token` for the new host |
| `ansible/inventory/hosts.yml` | All `ansible_host` IPs |
| `ansible/inventory/group_vars/all.yml` | `cluster_name`, `control_plane_endpoint` |
| `ansible/playbooks/06-post-install.yml` | The `replace:` line with the new master1 IP |

### What does NOT change
SSH key, Kubernetes version, pod/service CIDRs, all Ansible roles, Terraform module code, Flux structure.

---

## Part 6 — Teardown

```bash
# Destroy all 8 VMs (template 9002 is preserved)
make destroy

# To also remove the template for a full clean slate:
ssh root@172.16.1.2 'qm destroy 9002'
```

---

## Quick Reference

```bash
export KUBECONFIG=~/Downloads/k8-dev/k8-dev-cluster/kubeconfig

kubectl get nodes                                    # Node status
kubectl get pods -A                                  # All pods
kubectl get pods -n kube-system                      # System pods
kubectl describe node k8-worker1-dev                 # Node details
kubectl get events -A --sort-by='.lastTimestamp'     # Recent events
kubectl logs -n kube-system <pod-name>               # Pod logs
kubectl exec -it <pod> -- bash                       # Shell into pod
```

---

## Troubleshooting Reference

| Error | Fix |
|---|---|
| `Invalid character ";"` in variables.tf | Terraform requires newlines not semicolons — already fixed in repo |
| `provider hashicorp/proxmox not found` | Module needs its own `versions.tf` — already present in repo |
| `ACL update failed: no such token` | Token was created on a different Proxmox node — re-create on target node |
| `Host key verification failed` | Run `ssh-keyscan` loop (Step 4) |
| `role 'common' was not found` | Run playbooks from `ansible/` dir; `roles_path = roles` in `ansible.cfg` |
| `k8s_join_command undefined` | `05-workers.yml` now fetches a fresh token in Play 1 — no stale fact dependency |
| `conntrack not found` | Added to `roles/common/tasks/main.yml` — installs automatically |
| `sudo required` on localhost task | Add `become: false` to `delegate_to: localhost` tasks |
| `kubeadm: kind/apiVersion mandatory` | Use `v1beta4` in kubeadm config, no leading `---` separator |

---

## Note: Worker node ROLES showing <none>

This is **normal and expected** Kubernetes behaviour. Workers have no built-in role label.
To add a readable label:

```bash
for i in 1 2 3 4 5; do
  kubectl label node k8-worker${i}-dev node-role.kubernetes.io/worker=worker
done
```
