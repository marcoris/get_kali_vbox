#!/bin/bash
set -e

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
NC="\033[0m"

# Ensure VBoxManage is available (Windows)
if [[ -z "$(command -v VBoxManage)" ]]; then
  export PATH="$PATH:/c/Program Files/Oracle/VirtualBox"
fi

# Ensure 7z exists
if [[ -z "$(command -v 7z)" ]]; then
  echo -e "${RED}[!]${NC} 7z not found. Install p7zip / 7-Zip CLI."
  exit 1
fi

# Kali URLs
base_url="https://cdimage.kali.org/current"
vbox_file=$(curl -s "${base_url}/" | grep -oE 'kali-linux-[0-9.]+[a-z]*-virtualbox-amd64\.7z' | head -n1)

if [[ -z "$vbox_file" ]]; then
  echo -e "${RED}[!]${NC} Could not detect Kali VirtualBox image."
  exit 1
fi

vbox_url="${base_url}/${vbox_file}"
sha1_url="${base_url}/SHA1SUMS"
sha1_file="SHA1SUMS"

read -p "VM name: " vm_name
vm_name=${vm_name:-kali-linux}

# Check if VM exists
if VBoxManage list vms | awk -F\" '{print $2}' | grep -xq "$vm_name"; then
  echo -e "${RED}[!]${NC} VM '${vm_name}' already exists. Abort."
  exit 1
fi

extract_dir="${vm_name}_extracted"

# Download image
if [[ ! -f "$vbox_file" ]]; then
  echo -e "${BLUE}[*]${NC} Downloading Kali VirtualBox image..."
curl -L -o "$vbox_file" "$vbox_url"
else
  echo -e "${YELLOW}[i]${NC} Kali VirtualBox already downloaded."
fi

# Download SHA1SUMS
if [[ ! -f "$sha1_file" ]]; then
  echo -e "${BLUE}[*]${NC} Downloading SHA1SUMS..."
  curl -L -o "$sha1_file" "$sha1_url"
else
  echo -e "${YELLOW}[i]${NC} SHA1SUM already downloaded."
fi

# Verify SHA1
echo -e "${BLUE}[*]${NC} Verifying SHA1..."
expected_sha=$(grep " ${vbox_file}$" "$sha1_file" | awk '{print $1}')
actual_sha=$(sha1sum "$vbox_file" | awk '{print $1}')

if [[ "$expected_sha" != "$actual_sha" ]]; then
  echo -e "${RED}[!]${NC} SHA1 checksum mismatch!"
  exit 1
fi
echo -e "${GREEN}[+]${NC} SHA1 checksum valid."

# Extract 7z
echo -e "${BLUE}[*]${NC} Extracting image..."
rm -rf "$extract_dir"
7z x "$vbox_file" -o"$extract_dir" -y >/dev/null

vbox_file=$(find "$extract_dir" -name "*.vbox" | head -n1)
if [[ -z "$vbox_file" ]]; then
  echo -e "${RED}[!]${NC} No .vbox file found."
  exit 1
fi

# Check if VM with this name already exists
echo -e "${YELLOW}[i]${NC} VM already exists. Cloning with new name."
name_only="$(basename $vbox_file)" 
vm_image_name="${name_only%.vbox}"
# Clone the VM
VBoxManage clonevm "$vm_image_name" --name "$vm_name" --register

# Select mode
echo -e "${YELLOW}[?]${NC} Select mode: (a)utomatic or (c)ustom? [A/c]: "
read -r mode
mode=${mode:-a}

if [[ "$mode" =~ ^[Aa]$ ]]; then
  ram=8192
  cpus=6
else
  read -p "RAM in MB (8192): " ram
  ram=${ram:-8192}
  read -p "CPUs (6): " cpus
  cpus=${cpus:-6}
fi

# Detect bridged adapter
active_adapter=$(VBoxManage list bridgedifs | awk '/^Name:/ {name=$2; for(i=3;i<=NF;i++) name=name " " $i}/^Status:/ {if($2=="Up") print name}')

if [[ -z "$active_adapter" ]]; then
  echo -e "${RED}[!]${NC} No active bridged adapter found."
  exit 1
fi

# Configure VM
VBoxManage modifyvm "$vm_name" \
  --memory "$ram" \
  --cpus "$cpus" \
  --nic1 nat \
  --nic2 bridged \
  --bridgeadapter2 "$active_adapter"

# Shared folder
VBoxManage sharedfolder add "$vm_name" \
  --name "Downloads" \
  --hostpath "$HOME/Downloads" \
  --automount

echo -e "${GREEN}[+]${NC} VM '$vm_name' successfully created with:"
echo "    - RAM: ${ram} MB"
echo "    - CPU: ${cpus}"
echo "    - HDD: ${disk_size} MB"
echo "    - Network: NAT + Bridged (${active_adapter})"
echo -e "${GREEN}[+]${NC} Shared folder 'Downloads' added (Host: $HOME/Downloads)"

VBoxManage storageattach "$vm_name" \
  --storagectl "IDE" \
  --port 1 \
  --device 0 \
  --type dvddrive \
  --medium "C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso"

# Start VM
echo -e "${GREEN}[+]${NC} VM '$vm_name' ready."
echo -e "${BLUE}[*]${NC} Starting VM..."
VBoxManage startvm "$vm_name" --type gui
