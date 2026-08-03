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