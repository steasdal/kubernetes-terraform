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
    github_repository_deploy_key.flux
  ]

  path = var.flux_target_path
}
