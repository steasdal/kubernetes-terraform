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
              qid_max        = 128
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

# 5. Idempotently Ensure Named Persistent Volumes & Shares Exist on TrueNAS
#    - Creates missing datasets/zvols and NFS/NVMe-oF shares if they were manually deleted on TrueNAS.
#    - Leaves existing volumes untouched on both apply and destroy to preserve data.
resource "terraform_data" "truenas_static_volumes" {
  depends_on = [
    helm_release.democratic_csi_nfs,
    helm_release.democratic_csi_nvmeof
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      TRUENAS_URL    = "https://${var.truenas_host}/api/v2.0"
      TRUENAS_HOST   = var.truenas_host
      API_KEY        = var.truenas_api_key
      DATASET_PARENT = var.truenas_dataset_parent
    }
    command = <<-EOT
      set -euo pipefail

      ensure_nfs_volume() {
        local vol_name="$1"
        local quota_bytes="$2"
        local dataset="$${DATASET_PARENT}/$${vol_name}"
        local dataset_enc
        dataset_enc=$(printf "%s" "$${dataset}" | jq -sRr @uri)
        local mountpoint="/mnt/$${dataset}"

        echo "==> Checking TrueNAS NFS dataset $${dataset}..."
        if [ "$(curl -sk -H "Authorization: Bearer $${API_KEY}" "$${TRUENAS_URL}/pool/dataset?id=$${dataset_enc}" | jq 'length')" -eq 0 ]; then
          echo "    Creating NFS ZFS dataset $${dataset} ($${quota_bytes} bytes)..."
          curl -sk -X POST -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
            "$${TRUENAS_URL}/pool/dataset" \
            -d "{\"name\":\"$${dataset}\",\"type\":\"FILESYSTEM\",\"refquota\":$${quota_bytes},\"atime\":\"OFF\"}" >/dev/null

          curl -sk -X POST -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
            "$${TRUENAS_URL}/filesystem/setperm" \
            -d "{\"path\":\"$${mountpoint}\",\"mode\":\"0777\",\"uid\":0,\"gid\":0}" >/dev/null
        else
          echo "    Dataset $${dataset} already exists."
        fi

        local share_id
        share_id=$(curl -sk -H "Authorization: Bearer $${API_KEY}" "$${TRUENAS_URL}/sharing/nfs" | jq -r ".[] | select(.path == \"$${mountpoint}\") | .id")
        if [ -z "$${share_id}" ]; then
          echo "    Creating NFS share for $${mountpoint}..."
          share_id=$(curl -sk -X POST -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
            "$${TRUENAS_URL}/sharing/nfs" \
            -d "{\"path\":\"$${mountpoint}\",\"comment\":\"democratic-csi (tk-cluster-02-nfs): $${dataset}\",\"maproot_user\":\"root\",\"maproot_group\":\"root\",\"enabled\":true}" | jq -r '.id')
        else
          echo "    NFS share for $${mountpoint} already exists (ID $${share_id})."
        fi

        local vol_ctx="{\"node_attach_driver\":\"nfs\",\"server\":\"$${TRUENAS_HOST}\",\"share\":\"$${mountpoint}\"}"
        curl -sk -X PUT -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
          "$${TRUENAS_URL}/pool/dataset/id/$${dataset_enc}" \
          -d "{
            \"user_properties_update\": [
              {\"key\": \"democratic-csi:csi_volume_name\", \"value\": \"$${vol_name}\"},
              {\"key\": \"democratic-csi:freenas_nfs_share_id\", \"value\": \"$${share_id}\"},
              {\"key\": \"democratic-csi:managed_resource\", \"value\": \"true\"},
              {\"key\": \"democratic-csi:provision_success\", \"value\": \"true\"},
              {\"key\": \"democratic-csi:volume_context_provisioner_driver\", \"value\": \"freenas-api-nfs\"},
              {\"key\": \"democratic-csi:volume_context_provisioner_instance_id\", \"value\": \"tk-cluster-02-nfs\"},
              {\"key\": \"democratic-csi:csi_share_volume_context\", \"value\": $(printf "%s" "$${vol_ctx}" | jq -Rs .)}
            ]
          }" >/dev/null
      }

      ensure_nvmeof_volume() {
        local vol_name="$1"
        local vol_bytes="$2"
        local zvol="$${DATASET_PARENT}/$${vol_name}"
        local zvol_enc
        zvol_enc=$(printf "%s" "$${zvol}" | jq -sRr @uri)
        local asset_name="csi-$${vol_name}-tk2"

        echo "==> Checking TrueNAS NVMe-oF ZVOL $${zvol}..."
        if [ "$(curl -sk -H "Authorization: Bearer $${API_KEY}" "$${TRUENAS_URL}/pool/dataset?id=$${zvol_enc}" | jq 'length')" -eq 0 ]; then
          echo "    Creating ZVOL $${zvol} ($${vol_bytes} bytes)..."
          curl -sk -X POST -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
            "$${TRUENAS_URL}/pool/dataset" \
            -d "{\"name\":\"$${zvol}\",\"type\":\"VOLUME\",\"volsize\":$${vol_bytes},\"volblocksize\":\"16K\",\"sparse\":true}" >/dev/null
        else
          echo "    ZVOL $${zvol} already exists."
        fi

        local subsys_json subsys_id subnqn
        subsys_json=$(curl -sk -H "Authorization: Bearer $${API_KEY}" "$${TRUENAS_URL}/nvmet/subsys" | jq -c ".[] | select(.name == \"$${asset_name}\")")
        if [ -z "$${subsys_json}" ]; then
          echo "    Creating NVMe-oF subsystem $${asset_name}..."
          subsys_json=$(curl -sk -X POST -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
            "$${TRUENAS_URL}/nvmet/subsys" \
            -d "{\"name\":\"$${asset_name}\",\"allow_any_host\":true}")
        else
          echo "    NVMe-oF subsystem $${asset_name} already exists."
        fi
        subsys_id=$(printf "%s" "$${subsys_json}" | jq -r '.id')
        subnqn=$(printf "%s" "$${subsys_json}" | jq -r '.subnqn')

        local port_bound
        port_bound=$(curl -sk -H "Authorization: Bearer $${API_KEY}" "$${TRUENAS_URL}/nvmet/port_subsys" | jq -r ".[] | select(.port.id == 1 and .subsys.id == $${subsys_id}) | .id")
        if [ -z "$${port_bound}" ]; then
          echo "    Binding subsystem $${subsys_id} to NVMe-oF port 1..."
          curl -sk -X POST -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
            "$${TRUENAS_URL}/nvmet/port_subsys" \
            -d "{\"port_id\":1,\"subsys_id\":$${subsys_id}}" >/dev/null
        fi

        local ns_id
        ns_id=$(curl -sk -H "Authorization: Bearer $${API_KEY}" "$${TRUENAS_URL}/nvmet/namespace" | jq -r ".[] | select(.subsys.id == $${subsys_id} and .nsid == 1) | .id")
        if [ -z "$${ns_id}" ]; then
          echo "    Creating NVMe-oF namespace (nsid=1) for $${zvol}..."
          ns_id=$(curl -sk -X POST -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
            "$${TRUENAS_URL}/nvmet/namespace" \
            -d "{\"subsys_id\":$${subsys_id},\"device_type\":\"ZVOL\",\"device_path\":\"zvol/$${zvol}\",\"nsid\":1}" | jq -r '.id')
        else
          echo "    NVMe-oF namespace for $${zvol} already exists (ID $${ns_id})."
        fi

        local vol_ctx="{\"node_attach_driver\":\"nvmeof\",\"transport\":\"\",\"transports\":\"tcp://$${TRUENAS_HOST}:4420\",\"nqn\":\"$${subnqn}\",\"nsid\":1}"
        curl -sk -X PUT -H "Authorization: Bearer $${API_KEY}" -H "Content-Type: application/json" \
          "$${TRUENAS_URL}/pool/dataset/id/$${zvol_enc}" \
          -d "{
            \"user_properties_update\": [
              {\"key\": \"democratic-csi:csi_volume_name\", \"value\": \"$${vol_name}\"},
              {\"key\": \"democratic-csi:freenas_nvmeof_assets_name\", \"value\": \"$${asset_name}\"},
              {\"key\": \"democratic-csi:freenas_nvmeof_subsystem_id\", \"value\": \"$${subsys_id}\"},
              {\"key\": \"democratic-csi:freenas_nvmeof_namespace_id\", \"value\": \"$${ns_id}\"},
              {\"key\": \"democratic-csi:managed_resource\", \"value\": \"true\"},
              {\"key\": \"democratic-csi:provision_success\", \"value\": \"true\"},
              {\"key\": \"democratic-csi:volume_context_provisioner_driver\", \"value\": \"freenas-api-nvmeof\"},
              {\"key\": \"democratic-csi:volume_context_provisioner_instance_id\", \"value\": \"tk-cluster-02-nvmeof\"},
              {\"key\": \"democratic-csi:csi_share_volume_context\", \"value\": $(printf "%s" "$${vol_ctx}" | jq -Rs .)}
            ]
          }" >/dev/null
      }

      # Ensure all fixed-name TrueNAS volumes & shares exist:
      ensure_nfs_volume    "owncloud-data"         1649267441664  #  1.5 TiB
      ensure_nvmeof_volume "postgres-data"           21474836480  #  20 GiB
      ensure_nvmeof_volume "minio-data"              26843545600  #  25 GiB
      ensure_nvmeof_volume "redis-data"              10737418240  #  10 GiB
      ensure_nvmeof_volume "victoria-metrics-data"   21474836480  #  20 GiB

      echo "==> All static TrueNAS volumes and shares verified!"
    EOT
  }
}

