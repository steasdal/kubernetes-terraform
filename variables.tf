variable "proxmox_endpoint" {
  description = "The Proxmox VE API endpoint URL"
  type        = string
  default     = "https://192.168.1.30:8006/"
}

variable "proxmox_api_token" {
  description = "The Proxmox API token (format: user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Talos / Kubernetes cluster name"
  type        = string
  default     = "tk-cluster-02"
}

variable "talos_version" {
  description = "Talos release version"
  type        = string
  default     = "v1.14.2"
}

variable "talos_schematic_id" {
  description = "Talos Image Factory schematic ID containing qemu-guest-agent"
  type        = string
  default     = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
}

variable "iso_file_id" {
  description = "The Proxmox volume ID for the Talos ISO"
  type        = string
  default     = "local:iso/metal-amd64.iso"
}

variable "datastore_id" {
  description = "Proxmox storage pool for virtual machine disks"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox network bridge interface"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for the Kubernetes network"
  type        = number
  default     = 60
}

variable "gateway" {
  description = "Network gateway IP address"
  type        = string
  default     = "192.168.60.1"
}

variable "nameservers" {
  description = "DNS nameservers for Talos nodes"
  type        = list(string)
  default     = ["192.168.60.1", "1.1.1.1"]
}

variable "cluster_vip" {
  description = "Virtual IP for the Kubernetes API endpoint (Layer 2 VIP)"
  type        = string
  default     = "192.168.60.5"
}

variable "control_plane_nodes" {
  description = "Configuration mapping for control plane nodes"
  type = map(object({
    vm_id       = number
    node_name   = string
    ip          = string
    mac_address = string
    cores       = number
    memory      = number
    disk_size   = number
  }))
  default = {
    "cp1" = {
      vm_id       = 200
      node_name   = "PowerEdge03"
      ip          = "192.168.60.200"
      mac_address = "52:54:00:60:02:00"
      cores       = 2
      memory      = 4096
      disk_size   = 30
    }
    "cp2" = {
      vm_id       = 202
      node_name   = "PowerEdge04"
      ip          = "192.168.60.202"
      mac_address = "52:54:00:60:02:02"
      cores       = 2
      memory      = 4096
      disk_size   = 30
    }
    "cp3" = {
      vm_id       = 204
      node_name   = "PowerEdge05"
      ip          = "192.168.60.204"
      mac_address = "52:54:00:60:02:04"
      cores       = 2
      memory      = 4096
      disk_size   = 30
    }
  }
}

variable "worker_nodes" {
  description = "Configuration mapping for worker nodes"
  type = map(object({
    vm_id       = number
    node_name   = string
    ip          = string
    mac_address = string
    cores       = number
    memory      = number
    disk_size   = number
  }))
  default = {
    "w1" = {
      vm_id       = 206
      node_name   = "PowerEdge03"
      ip          = "192.168.60.206"
      mac_address = "52:54:00:60:02:06"
      cores       = 4
      memory      = 20480
      disk_size   = 60
    }
    "w2" = {
      vm_id       = 208
      node_name   = "PowerEdge04"
      ip          = "192.168.60.208"
      mac_address = "52:54:00:60:02:08"
      cores       = 4
      memory      = 20480
      disk_size   = 60
    }
    "w3" = {
      vm_id       = 210
      node_name   = "PowerEdge05"
      ip          = "192.168.60.210"
      mac_address = "52:54:00:60:02:10"
      cores       = 4
      memory      = 20480
      disk_size   = 60
    }
  }
}
