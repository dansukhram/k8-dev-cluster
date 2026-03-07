#!/usr/bin/env bash
# ============================================================
# Create Ubuntu 24.04 LTS cloud-init template on Proxmox
# Run this script on the Proxmox HOST (k8-dev)
# ============================================================
set -euo pipefail

TEMPLATE_ID=9002
TEMPLATE_NAME="ubuntu-2404-cloudinit"
STORAGE="local-lvm"
BRIDGE="vmbr0"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_PATH="/tmp/noble-server-cloudimg-amd64.img"

echo "==> [1/6] Checking for existing template..."
if qm status ${TEMPLATE_ID} &>/dev/null; then
  echo "Template ${TEMPLATE_ID} already exists. Exiting."
  exit 0
fi

echo "==> [2/6] Installing libguestfs-tools (for image customisation)..."
apt-get install -y libguestfs-tools wget

echo "==> [3/6] Downloading Ubuntu 24.04 Noble cloud image..."
wget -q --show-progress -O "${IMAGE_PATH}" "${IMAGE_URL}"

echo "==> [4/6] Customising image (installing qemu-guest-agent)..."
virt-customize -a "${IMAGE_PATH}" \
  --install qemu-guest-agent,curl,wget \
  --truncate /etc/machine-id \
  --run-command 'systemctl enable qemu-guest-agent'

echo "==> [5/6] Creating VM ${TEMPLATE_ID}..."
qm create ${TEMPLATE_ID} \
  --name "${TEMPLATE_NAME}" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=${BRIDGE} \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --machine q35 \
  --ostype l26 \
  --cpu cputype=x86-64-v2-AES \
  --scsihw virtio-scsi-pci

qm importdisk ${TEMPLATE_ID} "${IMAGE_PATH}" ${STORAGE}

qm set ${TEMPLATE_ID} \
  --scsi0 ${STORAGE}:vm-${TEMPLATE_ID}-disk-0,discard=on,iothread=on,cache=writethrough \
  --ide2 ${STORAGE}:cloudinit \
  --boot order=scsi0 \
  --ciuser ubuntu \
  --ipconfig0 ip=dhcp \
  --tags "template,ubuntu-2404"

echo "==> [6/6] Converting to template..."
qm template ${TEMPLATE_ID}

rm -f "${IMAGE_PATH}"
echo ""
echo "✅ Template ${TEMPLATE_ID} (${TEMPLATE_NAME}) created successfully!"
echo "   Use template_vm_id = ${TEMPLATE_ID} in your terraform.tfvars"
