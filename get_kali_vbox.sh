#!/bin/bash

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
FUCHSIA="\033[1;35m"
BLUE="\033[1;34m"
NC="\033[0m"

if [[ ! $(command -v VBoxManage) ]]; then
  export PATH="$PATH:/c/Program Files/Oracle/VirtualBox"
fi

# Get current kali ISO and sha1 checksum file
base_url="https://cdimage.kali.org/current/"
iso_file=$(curl -s "${base_url}" | grep -oE 'kali-linux-[0-9.]+[a-z]*-installer-amd64\.iso' | head -n1)
iso_url="${base_url}${iso_file}"
sha1_url=$(curl -sI "${base_url}SHA1SUMS" | grep -i '^location:' | awk '{print $2}' | tr -d '\r')
sha1_file="SHA1SUMS"
read -p "VM name: " vm_name

if [ -z "$vm_name" ]; then
  vm_name="${iso_file%.iso}"
fi

# Check if VM exists
if VBoxManage list vms | awk -F\" '{print $2}' | grep -xq "${vm_name}:"; then
  echo -e "${RED}[!]${NC} VM '${vm_name}' already exists. Abort."
  exit 1
fi

echo -e "${BLUE}[*]${NC} Downloading ISO file: ${iso_file}"
curl -L -o "${iso_file}" "${iso_url}"

echo -e "${BLUE}[*]${NC} Downloading SHA1SUMS file"
curl -L -o "${sha1_file}" "${sha1_url}"

echo -e "${BLUE}[*]${NC} Check SHA1SUM..."
expected_sha=$(grep -E " ${iso_file}$" "${sha1_file}" | awk '{print $1}')
actual_sha=$(sha1sum "${iso_file}" | awk '{print $1}')

if [[ "$expected_sha" != "$actual_sha" ]]; then
  echo -e "${RED}[!]${NC} SHA1SUM does not match. Abort."
  exit 1
fi
echo -e "${GREEN}[+]${NC} SHA1SUM is valid."

# Select mode
echo -e "${YELLOW}[?]${NC} Select mode: (a)utamatic or (c)ustom? [Ac]: "
read -r mode
mode=${mode:-a}

if [[ "$mode" =~ ^[Aa]$ ]]; then
  ram=8192
  cpus=6
  disk_size=81920
else
  read -p "RAM in MB (8192): " ram
  read -p "Number of CPUs (6): " cpus
  read -p "Hard disk size in MB (81920): " disk_size
fi

# Automatically detect active network adapter
active_adapter=$(VBoxManage list bridgedifs | awk '/^Name:/ {gsub(/^Name:[ \t]*/, "", $0); name=$0}/^Status:/ && $2 == "Up" {print name; exit}')

if [[ -z "$active_adapter" ]]; then
  echo -e "${RED}[!]${NC} No active network adapter found for bridged mode. Abort."
  exit 1
fi
echo -e "${GREEN}[+]${NC} Using Bridged Adapter: $active_adapter"

# Create VM
VBoxManage createvm --name "$vm_name" --ostype "Debian_64" --register
VBoxManage modifyvm "$vm_name" --memory "$ram" --cpus "$cpus" --boot1 disk

# Set network
VBoxManage modifyvm "$vm_name" --nic1 nat
VBoxManage modifyvm "$vm_name" --nic2 bridged --bridgeadapter2 "$active_adapter"

# Create hard disk
vdi_path="${HOME}/VirtualBox VMs/${vm_name}/${vm_name}.vdi"
VBoxManage createmedium disk --filename "$vdi_path" --size "$disk_size" --format VDI
VBoxManage storagectl "$vm_name" --name "SATA Controller" --add sata --controller IntelAhci
VBoxManage storageattach "$vm_name" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$vdi_path"

# Add shared folder (downloads directory of the host)
VBoxManage sharedfolder add "$vm_name" --name "Downloads" --hostpath "$HOME/Downloads" --automount

# Bind ISO file
VBoxManage storagectl "$vm_name" --name "IDE Controller" --add ide
VBoxManage storageattach "$vm_name" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$iso_file"

echo -e "${GREEN}[+]${NC} VM '$vm_name' successfully created with:"
echo "    - RAM: ${ram} MB"
echo "    - CPU: ${cpus}"
echo "    - HDD: ${disk_size} MB"
echo "    - Network: NAT + Bridged (${active_adapter})"
echo -e "${GREEN}[+]${NC} Shared folder 'Downloads' added (Host: $HOME/Downloads)"

# Starting VM
if VBoxManage list vms | grep -q "$vm_name"; then
  echo -e "${BLUE}[*]${NC} Starting VM: ${vm_name}..."
  VBoxManage startvm "$vm_name" --type gui
else
  echo -e "${RED}[!]${NC} VM '${vm_name}' not found."
fi
