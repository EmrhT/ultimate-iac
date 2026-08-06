variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "k8s"
}

variable "environment" {
  description = "Deployment environment selected by the environment-specific tfvars file."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "libvirt_uri" {
  description = "Remote libvirt connection URI. qemu+sshcmd respects ~/.ssh/config."
  type        = string
}

variable "bridge_name" {
  description = "Existing Linux bridge on the KVM host connected to the LAN."
  type        = string
}

variable "storage_pool_path" {
  description = "Absolute storage-pool directory on the KVM host."
  type        = string
}

variable "base_image_url" {
  description = "Cloud image used as the backing store for VM disks."
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "network_cidr" {
  description = "LAN CIDR used by the Kubernetes VMs."
  type        = string
}

variable "gateway_host" {
  description = "Host number inside network_cidr used as the default gateway."
  type        = number
  default     = 1
}

variable "dns_servers" {
  description = "DNS resolvers configured through cloud-init."
  type        = list(string)
}

variable "ssh_public_key_path" {
  description = "Public key installed for admin_user in every VM."
  type        = string
}

variable "admin_user" {
  description = "Administrative Linux user created by cloud-init."
  type        = string
  default     = "ubuntu"
}

variable "timezone" {
  description = "Timezone configured in every VM."
  type        = string
  default     = "Europe/Istanbul"
}

variable "control_plane_count" {
  description = "Control-plane and stacked-etcd node count. Change from 1 directly to 3 for HA."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5], var.control_plane_count)
    error_message = "control_plane_count must be an odd quorum size: 1, 3 or 5."
  }
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "control_plane_ip_start" {
  description = "First host number allocated to control-plane nodes."
  type        = number
}

variable "worker_ip_start" {
  description = "First host number allocated to worker nodes."
  type        = number
}

variable "kube_vip_host" {
  description = "Host number reserved for the kube-apiserver kube-vip address."
  type        = number
}

variable "metallb_pool_start_host" {
  description = "First host number reserved for MetalLB."
  type        = number
}

variable "metallb_pool_end_host" {
  description = "Last host number reserved for MetalLB."
  type        = number

  validation {
    condition     = var.metallb_pool_end_host >= var.metallb_pool_start_host
    error_message = "metallb_pool_end_host must be greater than or equal to metallb_pool_start_host."
  }
}

variable "control_plane_vcpu" {
  type = number
}

variable "control_plane_memory_mb" {
  type = number
}

variable "control_plane_disk_gib" {
  type = number
}

variable "worker_vcpu" {
  type = number
}

variable "worker_memory_mb" {
  type = number
}

variable "worker_disk_gib" {
  type = number
}

variable "worker_longhorn_disk_gib" {
  description = "Capacity of the dedicated Longhorn data disk attached to each worker."
  type        = number

  validation {
    condition     = var.worker_longhorn_disk_gib > 0
    error_message = "worker_longhorn_disk_gib must be greater than zero."
  }
}
