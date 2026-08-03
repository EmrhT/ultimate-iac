locals {
  name_prefix   = "${var.project_name}-${var.environment}"
  prefix_length = tonumber(split("/", var.network_cidr)[1])
  gateway       = cidrhost(var.network_cidr, var.gateway_host)

  control_plane_nodes = {
    for index in range(var.control_plane_count) :
    "${local.name_prefix}-cp-${format("%02d", index + 1)}" => {
      role       = "control-plane"
      ip_address = cidrhost(var.network_cidr, var.control_plane_ip_start + index)
      vcpu       = var.control_plane_vcpu
      memory_mb  = var.control_plane_memory_mb
      disk_gib   = var.control_plane_disk_gib
    }
  }

  worker_nodes = {
    for index in range(var.worker_count) :
    "${local.name_prefix}-worker-${format("%02d", index + 1)}" => {
      role       = "worker"
      ip_address = cidrhost(var.network_cidr, var.worker_ip_start + index)
      vcpu       = var.worker_vcpu
      memory_mb  = var.worker_memory_mb
      disk_gib   = var.worker_disk_gib
    }
  }

  nodes                = merge(local.control_plane_nodes, local.worker_nodes)
  kube_vip_address     = cidrhost(var.network_cidr, var.kube_vip_host)
  metallb_pool         = [for host in range(var.metallb_pool_start_host, var.metallb_pool_end_host + 1) : cidrhost(var.network_cidr, host)]
  metallb_address_pool = "${local.metallb_pool[0]}-${local.metallb_pool[length(local.metallb_pool) - 1]}"

  node_mac_addresses = {
    for name, node in local.nodes : name => format(
      "02:%s:%s:%s:%s:%s",
      substr(md5(name), 0, 2),
      substr(md5(name), 2, 2),
      substr(md5(name), 4, 2),
      substr(md5(name), 6, 2),
      substr(md5(name), 8, 2),
    )
  }

  cloud_init_user_data = {
    for name, node in local.nodes : name => join("\n", [
      "#cloud-config",
      yamlencode({
        hostname         = name
        manage_etc_hosts = true
        timezone         = var.timezone
        users = [
          "default",
          {
            name                = var.admin_user
            groups              = ["adm", "sudo"]
            shell               = "/bin/bash"
            sudo                = "ALL=(ALL) NOPASSWD:ALL"
            ssh_authorized_keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
          }
        ]
        package_update = true
        packages       = ["qemu-guest-agent", "python3"]
        runcmd = [
          ["systemctl", "enable", "--now", "qemu-guest-agent"],
        ]
      })
    ])
  }

  cloud_init_network_config = {
    for name, node in local.nodes : name => yamlencode({
      version = 2
      ethernets = {
        eth0 = {
          match = {
            macaddress = local.node_mac_addresses[name]
          }
          "set-name" = "eth0"
          addresses  = ["${node.ip_address}/${local.prefix_length}"]
          routes = [
            {
              to  = "default"
              via = local.gateway
            }
          ]
          nameservers = {
            addresses = var.dns_servers
          }
        }
      }
    })
  }
}

check "reserved_addresses_do_not_overlap_nodes" {
  assert {
    condition = alltrue([
      for node in values(local.nodes) :
      node.ip_address != local.kube_vip_address && !contains(local.metallb_pool, node.ip_address)
    ])
    error_message = "A node address overlaps the kube-vip or MetalLB address range."
  }
}
