# Generate a secure 32-byte secret for the tunnel
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

# 1. Provision the Cloudflare Zero Trust Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "k8s_tunnel" {
  account_id = var.cloudflare_account_id
  name       = var.cloudflare_tunnel_name
  secret     = random_id.tunnel_secret.b64_std
  config_src = "cloudflare"
}

# 2. Configure Remote Tunnel Ingress Rules
# Traffic for *.domain_name routes internally to Envoy Gateway ClusterIP service
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "k8s_tunnel_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k8s_tunnel.id

  config {
    ingress_rule {
      hostname = "*.${var.domain_name}"
      service  = "http://envoy-gateway-ingress.envoy-gateway-system.svc.cluster.local:80"
    }

    ingress_rule {
      hostname = var.domain_name
      service  = "http://envoy-gateway-ingress.envoy-gateway-system.svc.cluster.local:80"
    }

    # Mandatory catch-all rule
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# 3. Wildcard DNS CNAME Record pointing *.domain_name to the Cloudflare Tunnel
resource "cloudflare_record" "wildcard" {
  zone_id         = var.cloudflare_zone_id
  name            = "*"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.k8s_tunnel.id}.cfargotunnel.com"
  type            = "CNAME"
  proxied         = true
  ttl             = 1
  allow_overwrite = true
}

# 4. Kubernetes in-cluster cloudflared deployment
resource "kubernetes_namespace" "cloudflare" {
  metadata {
    name = "cloudflare"
  }

  depends_on = [
    talos_machine_bootstrap.this,
    talos_cluster_kubeconfig.this
  ]
}

resource "kubernetes_secret" "cloudflared_token" {
  metadata {
    name      = "cloudflared-token"
    namespace = kubernetes_namespace.cloudflare.metadata[0].name
  }

  data = {
    "token" = cloudflare_zero_trust_tunnel_cloudflared.k8s_tunnel.tunnel_token
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.cloudflare.metadata[0].name
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"
          args = [
            "tunnel",
            "--no-autoupdate",
            "--metrics",
            "0.0.0.0:2000",
            "run",
            "--token",
            "$(TUNNEL_TOKEN)"
          ]

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cloudflared_token.metadata[0].name
                key  = "token"
              }
            }
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    cloudflare_zero_trust_tunnel_cloudflared_config.k8s_tunnel_config,
    helm_release.envoy_gateway_config
  ]
}
