resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = var.control_plane_nodes

  depends_on = [proxmox_virtual_environment_vm.control_plane]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip

  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${each.value.ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
              vip = {
                ip = var.cluster_vip
              }
            }
          ]
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = "factory.talos.dev/installer/${var.talos_schematic_id}:${var.talos_version}"
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"/dev/sda\""
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ResolverConfig"
      nameservers = [for ns in var.nameservers : { address = ns }]
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.worker_nodes

  depends_on = [proxmox_virtual_environment_vm.worker]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip

  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${each.value.ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = "factory.talos.dev/installer/${var.talos_schematic_id}:${var.talos_version}"
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"/dev/sda\""
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ResolverConfig"
      nameservers = [for ns in var.nameservers : { address = ns }]
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_nodes["cp1"].ip
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_nodes["cp1"].ip
  endpoint             = var.cluster_vip
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.control_plane_nodes : v.ip]
  endpoints            = [var.cluster_vip]
}
