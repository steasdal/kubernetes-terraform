resource "helm_release" "envoy_gateway" {
  name             = "eg"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = "v1.9.2"
  namespace        = "envoy-gateway-system"
  create_namespace = true
  wait             = true
  timeout          = 300

  set {
    name  = "config.envoyGateway.extensionApis.enableBackend"
    value = "true"
  }

  depends_on = [
    talos_machine_bootstrap.this,
    talos_cluster_kubeconfig.this,
    terraform_data.wait_for_k8s_api
  ]
}

resource "helm_release" "envoy_gateway_config" {
  name      = "eg-config"
  chart     = "${path.module}/charts/envoy-gateway-config"
  namespace = "envoy-gateway-system"
  wait      = true

  depends_on = [
    helm_release.envoy_gateway
  ]
}
