resource "proxmox_virtual_environment_vm" "control_plane" {
  for_each = var.control_plane_nodes

  name      = each.key
  node_name = each.value.node_name
  vm_id     = each.value.vm_id

  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  boot_order = ["scsi0", "ide2"]

  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    ssd          = true
    file_format  = "raw"
    size         = each.value.disk_size
  }

  efi_disk {
    datastore_id = var.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  cdrom {
    file_id   = var.iso_file_id
    interface = "ide2"
  }

  network_device {
    bridge      = var.network_bridge
    vlan_id     = var.vlan_id
    mac_address = each.value.mac_address
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      cpu[0].affinity,
    ]
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = var.worker_nodes

  name      = each.key
  node_name = each.value.node_name
  vm_id     = each.value.vm_id

  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  boot_order = ["scsi0", "ide2"]

  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    ssd          = true
    file_format  = "raw"
    size         = each.value.disk_size
  }

  efi_disk {
    datastore_id = var.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  cdrom {
    file_id   = var.iso_file_id
    interface = "ide2"
  }

  network_device {
    bridge      = var.network_bridge
    vlan_id     = var.vlan_id
    mac_address = each.value.mac_address
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      cpu[0].affinity,
    ]
  }
}
