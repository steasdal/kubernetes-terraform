# TrueNAS SCALE Democratic-CSI (NFS)
# Dynamic persistent volume provisioning backed by TrueNAS SCALE via REST API

resource "kubernetes_namespace" "democratic_csi" {
  metadata {
    name = "democratic-csi"
    labels = {
      "name"                               = "democratic-csi"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }

  depends_on = [
    talos_machine_bootstrap.this,
    talos_cluster_kubeconfig.this,
    terraform_data.wait_for_k8s_api
  ]
}

resource "helm_release" "snapshot_controller" {
  name       = "snapshot-controller"
  repository = "https://democratic-csi.github.io/charts"
  chart      = "snapshot-controller"
  version    = "0.3.0"
  namespace  = kubernetes_namespace.democratic_csi.metadata[0].name
  wait       = true
  timeout    = 300

  depends_on = [
    kubernetes_namespace.democratic_csi
  ]
}

resource "helm_release" "democratic_csi_nfs" {
  name       = "zfs-nfs"
  repository = "https://democratic-csi.github.io/charts"
  chart      = "democratic-csi"
  version    = "0.15.1"
  namespace  = kubernetes_namespace.democratic_csi.metadata[0].name
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      csiDriver = {
        name           = "org.democratic-csi.nfs"
        attachRequired = false
      }

      controller = {
        driver = {
          image = {
            tag = "v1.9.5"
          }
        }
        externalAttacher = {
          enabled = false
        }
        externalSnapshotter = {
          enabled = true
        }
      }

      node = {
        driver = {
          image = {
            tag = "v1.9.5"
          }
        }
        kubeletHostPath = "/var/lib/kubelet"
      }

      storageClasses = [
        {
          name                 = "truenas-nfs"
          defaultClass         = true
          reclaimPolicy        = "Retain"
          volumeBindingMode    = "Immediate"
          allowVolumeExpansion = true
          parameters = {
            fsType = "nfs"
          }
          mountOptions = [
            "noatime",
            "nfsvers=4.1"
          ]
        }
      ]

      volumeSnapshotClasses = [
        {
          name           = "truenas-nfs"
          deletionPolicy = "Delete"
          parameters = {
            detachedSnapshots = "false"
          }
        }
      ]

      driver = {
        config = {
          driver      = "freenas-api-nfs"
          instance_id = "tk-cluster-02-nfs"
          httpConnection = {
            protocol      = "https"
            host          = var.truenas_host
            port          = 443
            apiKey        = var.truenas_api_key
            allowInsecure = true
            apiVersion    = 2
          }
          zfs = {
            datasetParentName                  = var.truenas_dataset_parent
            detachedSnapshotsDatasetParentName = var.truenas_snapshot_parent
            datasetEnableQuotas                = true
            datasetEnableReservation           = false
            datasetPermissionsMode             = "0777"
            datasetPermissionsUser             = 0
            datasetPermissionsGroup            = 0
          }
          nfs = {
            shareHost            = var.truenas_host
            shareAlldirs         = false
            shareAllowedHosts    = []
            shareAllowedNetworks = []
            shareMaprootUser     = "root"
            shareMaprootGroup    = "root"
            shareMapallUser      = ""
            shareMapallGroup     = ""
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.democratic_csi,
    helm_release.snapshot_controller
  ]
}

resource "helm_release" "democratic_csi_nvmeof" {
  name       = "zfs-nvmeof"
  repository = "https://democratic-csi.github.io/charts"
  chart      = "democratic-csi"
  version    = "0.15.1"
  namespace  = kubernetes_namespace.democratic_csi.metadata[0].name
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      csiDriver = {
        name           = "org.democratic-csi.nvmeof"
        attachRequired = true
      }

      controller = {
        driver = {
          image = {
            tag = "v1.9.5"
          }
        }
        externalAttacher = {
          enabled = true
        }
        externalProvisioner = {
          enabled = true
        }
        externalResizer = {
          enabled = true
        }
        externalSnapshotter = {
          enabled = true
        }
      }

      node = {
        driver = {
          image = {
            tag = "v1.9.5"
          }
        }
        kubeletHostPath = "/var/lib/kubelet"
      }

      storageClasses = [
        {
          name                 = "truenas-nvmeof"
          defaultClass         = false
          reclaimPolicy        = "Retain"
          volumeBindingMode    = "Immediate"
          allowVolumeExpansion = true
          parameters = {
            fsType = "ext4"
          }
          mountOptions = []
        }
      ]

      volumeSnapshotClasses = [
        {
          name           = "truenas-nvmeof"
          deletionPolicy = "Delete"
          parameters = {
            detachedSnapshots = "false"
          }
        }
      ]

      driver = {
        config = {
          driver      = "freenas-api-nvmeof"
          instance_id = "tk-cluster-02-nvmeof"
          httpConnection = {
            protocol      = "https"
            host          = var.truenas_host
            port          = 443
            apiKey        = var.truenas_api_key
            allowInsecure = true
            apiVersion    = 2
          }
          zfs = {
            datasetParentName                  = var.truenas_dataset_parent
            detachedSnapshotsDatasetParentName = var.truenas_snapshot_parent
            zvolCompression                    = "lz4"
            zvolEnableReservation              = false
            zvolBlocksize                      = "16K"
          }
          nvmeof = {
            transports = [
              "tcp://${var.truenas_host}:4420"
            ]
            namePrefix = "csi-"
            nameSuffix = "-tk2"
            ports = [
              1
            ]
            subsystemTemplate = {
              allow_any_host = true
            }
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.democratic_csi,
    helm_release.snapshot_controller
  ]
}
