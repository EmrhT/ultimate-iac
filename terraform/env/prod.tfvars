environment  = "prod"
project_name = "platform"

libvirt_uri       = "qemu+sshcmd://terraform@192.168.1.5/system"
bridge_name       = "br0"
storage_pool_path = "/var/lib/libvirt/images/k8s-prod"

network_cidr = "192.168.1.0/24"
gateway_host = 1
dns_servers  = ["192.168.1.1", "1.1.1.1"]

ssh_public_key_path = "~/.ssh/id_ed25519.pub"
admin_user          = "ubuntu"
timezone            = "Europe/Istanbul"

# Change this directly from 1 to 3 when adding the two HA control-plane nodes.
control_plane_count    = 1
worker_count           = 3
control_plane_ip_start = 11
worker_ip_start        = 21

kube_vip_host           = 10
metallb_pool_start_host = 100
metallb_pool_end_host   = 109

control_plane_vcpu      = 4
control_plane_memory_mb = 8192
control_plane_disk_gib  = 60

worker_vcpu      = 4
worker_memory_mb = 8192
worker_disk_gib  = 80