# Kubernetes cluster with Kubespray

This directory contains the site-specific Ansible inventory and prerequisite
playbooks for the development Kubernetes cluster.
The official Kubespray source is kept separately in `upstream/` so local
configuration does not modify the upstream project.

The intended installation is repeatable and uses the normal Kubespray
`cluster.yml` entry point. A fresh cluster does not require a separate CNI
installation or a custom wrapper script.

## Cluster design

| Component | Configuration |
| --- | --- |
| Kubernetes | `v1.35.4` |
| Topology | One control-plane/etcd node and three workers |
| Container runtime | containerd |
| etcd | Host deployment on the control-plane node |
| CNI | Cilium, with kube-proxy retained in IPVS mode |
| Cluster DNS | CoreDNS with NodeLocal DNSCache |
| API virtual IP | kube-vip at `192.168.122.30:6443` |
| Planned LoadBalancer addresses | GitOps-managed MetalLB pool `192.168.122.120-192.168.122.129` |
| Package manager | Helm |
| GitOps controller | Argo CD |
| Persistent storage | Dedicated `/dev/vdb` worker disks prepared for Longhorn |

The API server on `platform-dev-cp-01` advertises its real node address,
`192.168.122.31`. Clients use the kube-vip address, `192.168.122.30`. This is
intentional: each API server must retain its own node address while kube-vip
provides the stable endpoint shared by current and future control-plane nodes.

The current single control-plane and single etcd member are not highly
available. The inventory and kube-vip endpoint are structured so two more
control-plane/etcd members can be added later.

## Directory layout

```text
kubespray/
├── README.md
├── ansible-prereq/
│   ├── preflight.yml
│   └── prepare-longhorn-hosts.yml
├── inventory/
│   └── dev/
│       ├── hosts.yml
│       ├── artifacts/                  # generated; ignored by Git
│       └── group_vars/
│           ├── all/
│           │   ├── all.yml
│           │   └── etcd.yml
│           └── k8s_cluster/
│               ├── addons.yml
│               └── k8s-cluster.yml
└── upstream/                           # official v2.31.0; ignored by Git
```

## Implementation details

### Inventory

`inventory/dev/hosts.yml` defines:

- `platform-dev-cp-01` (`192.168.122.31`) in `kube_control_plane` and
  `etcd`.
- `platform-dev-worker-01` through `platform-dev-worker-03`
  (`192.168.122.41-43`) in `kube_node`.
- Both groups as children of `k8s_cluster`.

Terraform also generates `terraform/inventory-dev.yaml`. After changing VM
counts or addresses, copy that generated inventory into this directory before
running Ansible:

```bash
cp ../terraform/inventory-dev.yaml inventory/dev/hosts.yml
```

`group_vars/all/all.yml` selects the `ubuntu` SSH user and Python 3. It also
asks Kubespray to download `kubectl` and the administrator kubeconfig to the
local `inventory/dev/artifacts/` directory.

### Kubernetes and networking

`group_vars/k8s_cluster/k8s-cluster.yml` contains the core cluster settings:

- Kubernetes `1.35.4`, containerd, and host-based etcd.
- Cilium as the CNI.
- kube-proxy retained in IPVS mode; Cilium kube-proxy replacement is disabled.
- Pod CIDR `10.233.64.0/18` and service CIDR `10.233.0.0/18`.
- CoreDNS and NodeLocal DNSCache.
- Automatic certificate renewal.
- Anonymous API authentication enabled because Kubespray v2.31.0 performs an
  unauthenticated `/healthz` request during control-plane bootstrap. Disabling
  it makes that bootstrap handler receive HTTP 401.

`group_vars/k8s_cluster/addons.yml` configures the cluster addons:

- kube-vip owns only the Kubernetes API VIP. Service VIP management is
  disabled in kube-vip.
- Helm and Argo CD are enabled.
- MetalLB and the CSI snapshot controller are disabled in Kubespray. Their
  installation and configuration are deferred to the future top-level GitOps
  configuration.
- Kubespray's bundled cert-manager is disabled because that version does not
  support Kubernetes 1.35. cert-manager deployment is deferred to the future
  top-level GitOps configuration.

No cert-manager or Longhorn Kubernetes Application is defined here. The
Longhorn prerequisite playbook prepares the hosts and disks; both applications
will subsequently be managed by the separate top-level GitOps configuration.

### Preflight validation

`ansible-prereq/preflight.yml` is read-only. It fails before provisioning if
the environment does not satisfy the expected topology and host requirements.
It validates:

- SSH access and passwordless sudo.
- Control-plane, worker, and odd-member etcd topology.
- Unique addresses and hostnames.
- Hostname, static address, and `eth0` inventory consistency.
- Architecture, kernel, CPU, memory, and root filesystem free space.
- Inter-node connectivity, DNS, and registry HTTPS access.
- Inactive UFW for this development deployment.
- `/dev/vdb` presence and a minimum size of 10 GiB on every worker.
- multipathd state, with remediation deferred to Longhorn preparation.

### Longhorn host preparation

`ansible-prereq/prepare-longhorn-hosts.yml` performs idempotent host changes:

- Stops, disables, and masks multipathd because these libvirt guests do not
  use multipath storage.
- Installs `open-iscsi` and `nfs-common` and enables `iscsid`.
- Creates `/dev/vdb1`, formats it as ext4 if needed, and mounts it by UUID at
  `/var/lib/longhorn` on every worker.
- Refuses to repartition `/dev/vdb` when a filesystem is detected directly on
  the whole disk.

The dedicated disk must contain no data that needs to be retained before its
first preparation run.

## Obtain Kubespray v2.31.0

The ignored `upstream/` directory must be an official Kubespray v2.31.0
checkout. From this directory, create it when it is absent:

```bash
git clone --branch v2.31.0 --depth 1 \
  https://github.com/kubernetes-sigs/kubespray.git upstream

git -C upstream describe --tags --exact-match
```

The final command must print `v2.31.0`.

## Recommended execution with the Kubespray container

The Kubespray image contains its tested Ansible and Python dependencies. Start
one interactive container from this directory and mount the inventory,
prerequisite playbooks, and SSH key:

```bash
cd ~/projects/ultimate-iac/kubespray

docker run --rm -it --network host \
  --mount type=bind,source="$PWD/inventory/dev",target=/inventory \
  --mount type=bind,source="$PWD/ansible-prereq",target=/ansible-prereq,readonly \
  --mount type=bind,source="$HOME/.ssh/id_4work",target=/root/.ssh/id_4work,readonly \
  quay.io/kubespray/kubespray:v2.31.0 bash
```

The image opens in `/kubespray`, which contains the official playbooks. Run
the following commands inside that container in this order.

### 1. Validate all hosts

```bash
ansible-playbook \
  -i /inventory/hosts.yml \
  /ansible-prereq/preflight.yml \
  --private-key /root/.ssh/id_4work
```

This playbook intentionally makes no changes. Fix every reported error before
continuing.

### 2. Prepare Longhorn hosts and disks

```bash
ansible-playbook \
  -i /inventory/hosts.yml \
  /ansible-prereq/prepare-longhorn-hosts.yml \
  --become \
  --private-key /root/.ssh/id_4work
```

### 3. Install the complete Kubernetes cluster

```bash
ansible-playbook \
  -i /inventory/hosts.yml \
  cluster.yml \
  --become \
  --private-key /root/.ssh/id_4work
```

For a fresh installation, run the complete `cluster.yml` once. Do not split
the normal installation into separate control-plane and CNI runs. Kubespray
installs the control plane, joins the workers, and installs Cilium in its own
required order.

Exit the container after the playbook completes:

```bash
exit
```

Because `/inventory` is a writable bind mount, Kubespray leaves these generated
client artifacts on the host:

```text
inventory/dev/artifacts/admin.conf
inventory/dev/artifacts/kubectl
inventory/dev/artifacts/kubectl.sh
```

## Direct execution with a local Ansible installation

If the Kubespray requirements are already installed locally, run the same
playbooks directly from this directory:

```bash
ansible-playbook -i inventory/dev/hosts.yml \
  ansible-prereq/preflight.yml \
  --private-key ~/.ssh/id_4work

ansible-playbook -i inventory/dev/hosts.yml \
  ansible-prereq/prepare-longhorn-hosts.yml \
  --become \
  --private-key ~/.ssh/id_4work

cd upstream

ansible-playbook -i ../inventory/dev/hosts.yml \
  cluster.yml \
  --become \
  --private-key ~/.ssh/id_4work

cd ..
```

Kubespray v2.31.0 pins its local Python dependencies in
`upstream/requirements.txt`; notably, it expects Ansible `11.13.0`.

## Verification

```bash
inventory/dev/artifacts/kubectl.sh get nodes -o wide
inventory/dev/artifacts/kubectl.sh get pods -A
inventory/dev/artifacts/kubectl.sh get applications -n argocd
```

Expected node state:

```text
platform-dev-cp-01       Ready   control-plane
platform-dev-worker-01   Ready   <none>
platform-dev-worker-02   Ready   <none>
platform-dev-worker-03   Ready   <none>
```

## Rerunning and resetting

All three installation playbooks are designed to be rerun. After a completed
installation, rerunning the full `cluster.yml` reconciles the declared
Kubespray configuration.

To remove Kubernetes state from all inventory nodes, run the official reset
playbook from the Kubespray checkout:

```bash
cd upstream

ansible-playbook -i ../inventory/dev/hosts.yml \
  reset.yml \
  --become \
  --private-key ~/.ssh/id_4work
```

Type `yes` at the confirmation prompt. Reset is destructive to Kubernetes and
etcd state. It is not equivalent to returning the operating system to a
pristine VM image; recreate the VMs with Terraform when that level of clean
testing is required.

After reset, use the complete normal order again:

```text
preflight.yml
    -> prepare-longhorn-hosts.yml
    -> cluster.yml
```

## Expanding the control plane

Create two additional VMs and add them to both `kube_control_plane` and `etcd`
after `platform-dev-cp-01`. Keep an odd number of etcd members. Then rerun the
full `cluster.yml`; do not use `scale.yml` to add control-plane nodes.

The new API servers advertise their own node addresses while clients continue
using `192.168.122.30:6443` through kube-vip.
