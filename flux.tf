# FluxCD Bootstrap & GitOps Configuration

resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux-tk-cluster-02"
  repository = var.github_repository
  key        = tls_private_key.flux.public_key_openssh
  read_only  = false
}

resource "flux_bootstrap_git" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    talos_cluster_kubeconfig.this,
    terraform_data.wait_for_k8s_api,
    github_repository_deploy_key.flux,
    helm_release.democratic_csi_nfs,
    helm_release.democratic_csi_nvmeof,
    terraform_data.truenas_static_volumes,
    helm_release.envoy_gateway_config
  ]

  path = var.flux_target_path
}
