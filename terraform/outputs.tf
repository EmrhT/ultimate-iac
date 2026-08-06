output "nodes" {
  description = "Provisioned nodes with their Kubernetes roles and addresses."
  value = {
    for name, node in local.nodes : name => {
      role       = node.role
      ip_address = node.ip_address
    }
  }
}

output "kube_vip_address" {
  description = "Reserved virtual IP for kube-apiserver."
  value       = local.kube_vip_address
}

output "metallb_address_pool" {
  description = "Reserved MetalLB address range."
  value       = local.metallb_address_pool
}

output "longhorn_data_disks" {
  description = "Dedicated Longhorn data disks attached to worker nodes."
  value = {
    for name, volume in libvirt_volume.longhorn_data : name => {
      volume_name  = volume.name
      capacity_gib = var.worker_longhorn_disk_gib
      guest_device = "/dev/vdb"
    }
  }
}

output "kubespray_inventory_file" {
  description = "Generated Kubespray inventory."
  value       = local_file.kubespray_inventory.filename
}
