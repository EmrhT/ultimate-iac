environment  = "dev"
project_name = "platform"

libvirt_uri       = "qemu+sshcmd://libvirt-dev-host/system" # configure ~/.ssh/config and use ssh-add
bridge_name       = "br0"
storage_pool_path = "/var/lib/libvirt/images/k8s-dev"

network_cidr = "192.168.122.0/24"
gateway_host = 1
dns_servers  = ["192.168.122.1", "1.1.1.1"]

ssh_public_key_path = "~/.ssh/id_4demo.pub"
admin_user          = "ubuntu"
timezone            = "Europe/Istanbul"

control_plane_count    = 1
worker_count           = 3
control_plane_ip_start = 31
worker_ip_start        = 41

kube_vip_host           = 30
metallb_pool_start_host = 120
metallb_pool_end_host   = 129

control_plane_vcpu      = 2
control_plane_memory_mb = 4096
control_plane_disk_gib  = 30

worker_vcpu      = 4
worker_memory_mb = 10240
worker_disk_gib  = 30