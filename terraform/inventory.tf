locals {
  kubespray_inventory = {
    all = {
      hosts = {
        for name, node in local.nodes : name => {
          ansible_host = node.ip_address
          ip           = node.ip_address
          access_ip    = node.ip_address
        }
      }
      children = {
        kube_control_plane = {
          hosts = {
            for name, node in local.nodes : name => {} if node.role == "control-plane"
          }
        }
        etcd = {
          hosts = {
            for name, node in local.nodes : name => {} if node.role == "control-plane"
          }
        }
        kube_node = {
          hosts = {
            for name, node in local.nodes : name => {} if node.role == "worker"
          }
        }
        k8s_cluster = {
          children = {
            kube_control_plane = {}
            kube_node          = {}
          }
        }
      }
    }
  }
}

resource "local_file" "kubespray_inventory" {
  filename        = "${path.root}/inventory-${var.environment}.yaml"
  content         = yamlencode(local.kubespray_inventory)
  file_permission = "0644"
}