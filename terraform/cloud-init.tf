resource "libvirt_volume" "os_disk" {
  for_each = local.nodes

  name     = "${each.key}-os.qcow2"
  pool     = libvirt_pool.kubernetes.name
  capacity = each.value.disk_gib * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.base_image.path

    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "node" {
  for_each = local.nodes

  name = "${each.key}-cloudinit"

  meta_data = yamlencode({
    "instance-id"    = each.key
    "local-hostname" = each.key
    role              = each.value.role
  })

  user_data = local.cloud_init_user_data[each.key]

  network_config = local.cloud_init_network_config[each.key]
}

resource "libvirt_volume" "cloudinit" {
  for_each = local.nodes

  name = "${each.key}-cloudinit.iso"
  pool = libvirt_pool.kubernetes.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.node[each.key].path
    }
  }

  lifecycle {
    replace_triggered_by = [
      libvirt_cloudinit_disk.node[each.key]
    ]
  }
}