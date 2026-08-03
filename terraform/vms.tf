resource "libvirt_domain" "node" {
  for_each = local.nodes

  name        = each.key
  type        = "kvm"
  memory      = each.value.memory_mb
  memory_unit = "MiB"
  vcpu        = each.value.vcpu
  running     = true
  autostart   = true

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [
      {
        dev = "hd"
      }
    ]
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.os_disk[each.key].pool
            volume = libvirt_volume.os_disk[each.key].name
          }
        }

        target = {
          dev = "vda"
          bus = "virtio"
        }

        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"

        source = {
          volume = {
            pool   = libvirt_volume.cloudinit[each.key].pool
            volume = libvirt_volume.cloudinit[each.key].name
          }
        }

        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        type = "bridge"

        mac = {
          address = local.node_mac_addresses[each.key]
        }

        model = {
          type = "virtio"
        }

        source = {
          bridge = {
            bridge = var.bridge_name
          }
        }
      }
    ]
  }
}
