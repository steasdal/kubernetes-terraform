output "cluster_vip" {
  description = "The virtual floating IP for the Kubernetes API server"
  value       = var.cluster_vip
}

output "unifi_dhcp_reservations" {
  description = "List of MAC addresses to add as Fixed IP reservations in UniFi"
  value = merge(
    { for k, v in var.control_plane_nodes : k => {
      name        = k
      ip          = v.ip
      mac_address = v.mac_address
      role        = "control-plane"
      proxmox_node= v.node_name
      vlan        = var.vlan_id
    } },
    { for k, v in var.worker_nodes : k => {
      name        = k
      ip          = v.ip
      mac_address = v.mac_address
      role        = "worker"
      proxmox_node= v.node_name
      vlan        = var.vlan_id
    } }
  )
}

resource "local_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}

resource "local_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.module}/talosconfig"
  file_permission = "0600"
}

output "cloudflare_tunnel_id" {
  description = "Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.k8s_tunnel.id
}

output "cloudflare_tunnel_cname" {
  description = "Cloudflare Tunnel CNAME target"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.k8s_tunnel.id}.cfargotunnel.com"
}
