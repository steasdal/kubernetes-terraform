# Talos Linux Kubernetes Cluster on Proxmox VE (`tk-cluster-02`)

This repository contains the Terraform configuration to provision and bootstrap a production-grade, highly available Kubernetes cluster running [Talos Linux](https://www.talos.dev/) across three physical Proxmox VE servers in a homelab environment.

The entire provisioning lifecycle—from creating virtual machines and configuring UEFI/disks in Proxmox to pushing machine configs, bootstrapping `etcd`, and exporting `kubeconfig`—is fully automated.

---

## Architecture Overview

```
                      UniFi Gateway (ucgf) - VLAN 60 (192.168.60.0/24)
                                      │
                         Floating VIP: 192.168.60.5:6443
                                      │
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                       ▼
      PowerEdge03 (pe3)       PowerEdge04 (pe4)       PowerEdge05 (pe5)
      ┌───────────────┐       ┌───────────────┐       ┌───────────────┐
      │  cp1 (VM 200) │       │  cp2 (VM 202) │       │  cp3 (VM 204) │  ◄── 3-Node HA Control Plane
      ├───────────────┤       ├───────────────┤       ├───────────────┤
      │   w1 (VM 206) │       │   w2 (VM 208) │       │   w3 (VM 210) │  ◄── Dedicated Workers
      └───────────────┘       └───────────────┘       └───────────────┘
```

* **Physical Infrastructure:** 3x Dell PowerEdge R630 servers joined in a single Proxmox VE cluster (`proxmox-cluster`).
* **Virtual Topology:** 6 Virtual Machines (3 Control Planes + 3 Workers) evenly distributed across the physical servers (1 CP and 1 Worker per physical host).
* **High Availability:** A 3-node `etcd` control plane allows any 1 physical server to fail without losing cluster quorum or causing Kubernetes API downtime.
* **Network & VIP:** Nodes communicate on dedicated VLAN `60` (`192.168.60.0/24`). Talos automatically manages a Layer-2 floating Virtual IP (`192.168.60.5`) across the control plane nodes via Gratuitous ARP, eliminating the need for an external load balancer.

---

## Node Inventory & Allocation

| VM Name | Role | Proxmox Node | VM ID | IP Address | MAC Address | Specs |
| :--- | :--- | :--- | :---: | :--- | :--- | :--- |
| **`cp1`** | Control Plane | `PowerEdge03` | `200` | `192.168.60.200` | `52:54:00:60:02:00` | 2 vCPU, 4 GB RAM, 30 GB Disk |
| **`cp2`** | Control Plane | `PowerEdge04` | `202` | `192.168.60.202` | `52:54:00:60:02:02` | 2 vCPU, 4 GB RAM, 30 GB Disk |
| **`cp3`** | Control Plane | `PowerEdge05` | `204` | `192.168.60.204` | `52:54:00:60:02:04` | 2 vCPU, 4 GB RAM, 30 GB Disk |
| **`w1`**  | Worker | `PowerEdge03` | `206` | `192.168.60.206` | `52:54:00:60:02:06` | 4 vCPU, 20 GB RAM, 60 GB Disk |
| **`w2`**  | Worker | `PowerEdge04` | `208` | `192.168.60.208` | `52:54:00:60:02:08` | 4 vCPU, 20 GB RAM, 60 GB Disk |
| **`w3`**  | Worker | `PowerEdge05` | `210` | `192.168.60.210` | `52:54:00:60:02:10` | 4 vCPU, 20 GB RAM, 60 GB Disk |
| **VIP**  | K8s API Endpoint | *Floating (CP)* | — | `192.168.60.5` | — | Port 6443 |

*Total Physical Server Allocation:* ~24 GB RAM per physical host (out of 32 GB total), leaving ~8 GB for the Proxmox hypervisor.

---

## Prerequisites

Before running Terraform, ensure the following are in place:

### 1. Talos ISO Uploaded to Proxmox
The Talos `metal-amd64.iso` must be present on the `local` storage pool on all three Proxmox hosts (`PowerEdge03`, `PowerEdge04`, `PowerEdge05`):
* Expected volume ID: `local:iso/metal-amd64.iso`

### 2. UniFi DHCP Fixed IP Reservations
When the VMs first boot from the ISO into memory, they obtain an initial IP via DHCP before Talos formats the disk and applies the permanent static configuration.

The 6 MAC-to-IP reservations **must exist** in the UniFi Network application (**Client Devices $\rightarrow$ Add Client**) on network `kube` (VLAN 60) using the MAC addresses and IPs listed in the table above.

### 3. Installed Local Tools
* [Terraform](https://developer.hashicorp.com/terraform/install) $\ge$ `1.5.0`
* [talosctl](https://github.com/siderolabs/talos/releases) matching cluster release (e.g., `v1.14.2`)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)

---

## Configuration (`terraform.tfvars`)

Copy `terraform.tfvars.example` to `terraform.tfvars`:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your Proxmox API credentials:

```hcl
proxmox_endpoint  = "https://192.168.1.30:8006/"
proxmox_api_token = "root@pam!terraform=<YOUR_TOKEN_SECRET>"
```

> [!NOTE]
> If you need to generate a new Proxmox API token, SSH into any Proxmox node and run:
> ```bash
> pveum user token add root@pam terraform --privsep 0
> ```

---

## Deployment Steps

### 1. Initialize Terraform
Downloads the required providers (`bpg/proxmox`, `siderolabs/talos`, `hashicorp/local`):
```bash
terraform init
```

### 2. Review the Plan
Inspect the resources to be created (17 resources total: 6 VMs, machine secrets, 6 machine config applies, bootstrap, kubeconfig, and local files):
```bash
terraform plan
```

### 3. Apply the Configuration
Execute the deployment:
```bash
terraform apply
```

---

## How it Works Under the Hood

1. **VM Creation (`proxmox_vms.tf`):**
   * Uses the `bpg/proxmox` provider.
   * Configures UEFI (`OVMF`), `q35` machine type, VirtIO SCSI disk on `local-lvm`, QEMU Guest Agent, and attaches `local:iso/metal-amd64.iso`.
   * Boot order is set to `["scsi0", "ide2"]`. Since `scsi0` is initially blank, UEFI falls through and boots the live Talos ISO from `ide2`.
2. **First Boot & DHCP:**
   * VMs boot the Talos live environment into RAM and request DHCP.
   * UniFi matches the pre-configured MAC addresses and assigns `192.168.60.200`–`210`.
3. **Talos Configuration & Installation (`talos.tf`):**
   * The `siderolabs/talos` provider connects to the live ISO environment over gRPC port `50000`.
   * It pushes the machine config specifying `install.disk = "/dev/sda"`, the static IP network configuration, nameservers, and VIP.
   * The installer image includes the `qemu-guest-agent` extension (`factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.14.2`).
4. **Reboot to Disk:**
   * Talos installs to disk and reboots the VM.
   * On reboot, UEFI finds the EFI bootloader on `scsi0` and boots directly from the installed disk.
5. **Cluster Bootstrap & Credentials:**
   * Terraform runs `talos_machine_bootstrap` on `cp1`, initializing `etcd`.
   * Terraform extracts the admin credentials and saves them to local files:
     * `./kubeconfig`
     * `./talosconfig`

---

## Interacting with the Cluster

### Using `kubectl`
Point to the generated `kubeconfig`:
```bash
export KUBECONFIG=$(pwd)/kubeconfig

# Check node status
kubectl get nodes -o wide

# Check cluster components
kubectl get pods -A
```

### Using `talosctl`
Administer nodes using the generated `talosconfig`:
```bash
export TALOSCONFIG=$(pwd)/talosconfig

# View real-time node dashboard
talosctl -n 192.168.60.200 dashboard

# View dmesg or container logs
talosctl -n 192.168.60.200 dmesg
talosctl -n 192.168.60.200 containers -k
```

---

## Repository Structure

```text
kubernetes-terraform/
├── .gitignore              # Ignores .tfstate, tfvars, kubeconfig, talosconfig, .terraform/
├── .terraform.lock.hcl     # Pinned provider dependency versions & hashes (commit to git)
├── versions.tf             # Provider requirements & Proxmox connection config
├── variables.tf            # Default sizing, IP mappings, MACs, VLAN, and cluster parameters
├── terraform.tfvars.example# Template for Proxmox credentials
├── terraform.tfvars        # Your actual secrets (DO NOT COMMIT)
├── proxmox_vms.tf          # Proxmox VM resource declarations for CPs and Workers
├── talos.tf                # Talos secrets, machine configs, bootstrap, and kubeconfig
├── outputs.tf              # Outputs node reservations and writes local credential files
└── README.md               # This documentation
```

---

## Destroying / Tearing Down

To decommission the entire cluster and delete the VMs from Proxmox:

```bash
terraform destroy
```
