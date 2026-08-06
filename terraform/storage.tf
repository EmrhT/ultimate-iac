resource "libvirt_pool" "kubernetes" {
  name = "${local.name_prefix}-pool"
  type = "dir"

  target = {
    path = var.storage_pool_path
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }

  destroy = {
    delete = false
  }
}

resource "libvirt_volume" "base_image" {
  name = "ubuntu-noble-base.qcow2"
  pool = libvirt_pool.kubernetes.name

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = var.base_image_url
    }
  }
}

resource "libvirt_volume" "longhorn_data" {
  for_each = local.worker_nodes

  name     = "${each.key}-longhorn.qcow2"
  pool     = libvirt_pool.kubernetes.name
  capacity = var.worker_longhorn_disk_gib * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }
}
