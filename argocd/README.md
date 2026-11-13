# Argo CD platform configuration

This directory is the GitOps entry point for the platform. One root
`ApplicationSet` creates the Argo projects and the child `ApplicationSet`
controllers. Those child sets keep cluster infrastructure/security separate
from custom workloads.

## Deployment model

```text
platform-bootstrap ApplicationSet
├── platform-projects Application
│   ├── infra-security AppProject
│   └── applications AppProject
└── platform-application-sets Application
    ├── infra-security-helm ApplicationSet
    ├── infra-security-kustomize ApplicationSet
    └── custom-applications ApplicationSet
        ├── mkdocs-lab-a-dev
        ├── podinfo-lab-a-dev
        ├── podinfo-lab-a-prod
        ├── podinfo-lab-b-dev
        └── podinfo-lab-b-prod
```

`lab-a` and `lab-b` are logical clusters simulated on the same Kubernetes API.
Every application is isolated in a namespace named
`<cluster>-<environment>-<application>`, such as `lab-a-dev-mkdocs` or
`lab-b-prod-podinfo`. Cluster-scoped operators are installed once on the
physical cluster; installing MetalLB, Longhorn, Falco, ECK, or their CRDs twice
under different namespaces would still cause cluster-wide collisions.

The custom-workload ApplicationSet discovers deployable directories matching
`applications/<application>/clusters/<cluster>/<environment>`. The current
logical clusters all use the in-cluster Kubernetes API. When real destination
clusters are introduced, combine this directory discovery with registered
Argo CD cluster metadata so each path resolves to the appropriate API server.
Infrastructure should then have one generated set per real destination
cluster.

## Directory layout

```text
argocd/
├── bootstrap/                 # the only object applied manually
├── projects/                  # RBAC and source/destination boundaries
├── appsets/
│   ├── base/                  # child ApplicationSets
│   └── overlays/dev/          # management-cluster overlay
├── infra-security/
│   ├── <helm-component>/
│   │   ├── base/values.yaml
│   │   └── overlays/dev/values.yaml
│   ├── metallb-config/        # base plus environment Kustomize overlay
│   └── elastic-stack/         # base plus environment Kustomize overlay
└── applications/
    └── podinfo/
        ├── base/
        ├── environments/{dev,prod}/
        └── clusters/{lab-a,lab-b}/{dev,prod}/
```

Helm values use a base file followed by an environment override. Kubernetes
manifests use Kustomize composition: the Podinfo base is reused by environment
overlays, and cluster overlays reuse those environment overlays. No workload
manifest is copied between environments or logical clusters.

## Managed infrastructure and security

All versions are explicit; Argo CD never follows `latest`:

| Component | Version | Purpose |
| --- | --- | --- |
| Gateway API CRDs | `v1.5.1` | Standard-channel Gateway API resources |
| cert-manager | `1.21.0` | Certificate lifecycle and Gateway integration |
| MetalLB chart | `0.16.2` | Bare-metal `LoadBalancer` implementation |
| Longhorn | `1.11.2` | Replicated persistent storage on `/var/lib/longhorn` |
| Metrics Server chart | `3.13.1` | Resource Metrics API for `kubectl top` and autoscaling |
| kube-prometheus-stack | `86.3.2` | Prometheus, Alertmanager, Grafana, and exporters |
| Traefik chart | `41.0.1` | Gateway API controller at `192.168.122.120` |
| HashiCorp Vault chart | `0.32.0` | Secret service and injector |
| Falco chart | `9.1.0` | Runtime detection with the modern eBPF driver |
| ECK operator | `3.4.0` | Elastic Stack lifecycle |
| Elasticsearch/Kibana | `9.4.9` | Single-node development search and dashboard stack |
| Podinfo | `6.14.1` | Apache-2.0 GitHub-hosted demo workload |

MetalLB owns `192.168.122.120-192.168.122.129`. Traefik requests `.120`.
Keep `.121` and `.122` available if Wazuh agent traffic and enrollment are
later exposed through separate Wazuh manager Services.

The three 10 GiB Longhorn disks provide roughly 10 GiB of usable replicated
capacity with three replicas. The development values request approximately
8 GiB before filesystem, snapshot, and free-space overhead. Increase the
worker Longhorn disks before treating this as a durable observability/SIEM
environment.

Metrics Server is assigned wave `-15`: cert-manager and the core storage and
network services have lower waves, while the observability stack has wave
`-10`. Its aggregated API certificate is issued by cert-manager. Kubelet
serving-certificate rotation is enabled in the Kubespray inventory so Metrics
Server can validate kubelets without `--kubelet-insecure-tls`. Apply that host
configuration by rerunning Kubespray `cluster.yml` before expecting node and
pod metrics to become available.

## Bootstrap

Argo CD fetches `main` from GitHub, so commit and push this directory before
bootstrapping. Then run from the repository root with the Kubespray-generated
kubeconfig:

```bash
export KUBECONFIG="$PWD/kubespray/inventory/dev/artifacts/admin.conf"

kubectl apply -k argocd/bootstrap
```

No wrapper script is required. Inspect reconciliation with:

```bash
kubectl get applicationsets -n argocd
kubectl get applications -n argocd
kubectl get applications -n argocd -L platform.example/group
kubectl get pods -A
```

The generated Applications use retries and `SkipDryRunOnMissingResource` so
operator/CRD dependencies converge after their controllers become available.
The wave annotations document dependency intent, but waves do not serialize
the independent auto-sync operations of Applications generated by an
ApplicationSet.

Test the four Podinfo routes through Traefik's MetalLB address:

```bash
curl -H 'Host: podinfo-lab-a-dev.no-name.win' http://192.168.122.120
curl -H 'Host: podinfo-lab-a-prod.no-name.win' http://192.168.122.120
curl -H 'Host: podinfo-lab-b-dev.no-name.win' http://192.168.122.120
curl -H 'Host: podinfo-lab-b-prod.no-name.win' http://192.168.122.120
```

## Operational boundaries still requiring design

- Vault is deliberately installed in non-dev standalone mode, but its current
  in-cluster listener has TLS disabled and must not be exposed outside the
  cluster. Its initial operator initialization and unseal cannot safely be
  committed to Git. Before production use, add authenticated TLS plus an
  external trust root or auto-unseal provider; do not store unseal keys or a
  root token in this repository.
- ECK generates the Elasticsearch administrator password in a Kubernetes
  Secret. Plaintext credentials are not stored here.
- Falco currently emits JSON events locally. Forwarding through
  Falcosidekick requires an authenticated Elastic destination and will be
  added after secret delivery is designed.
- The Wazuh node agents cannot send directly to Elasticsearch. A Wazuh manager
  and its authenticated shipper are still required between the agents and the
  search backend; this repository does not deploy that manager yet.

## Licensing note

The exact component list contains two exceptions to a strict OSI-open-source
binary policy. HashiCorp Vault uses the Business Source License, and the
official Elasticsearch images deployed by ECK use Elastic License 2.0 even
though Elasticsearch source is also offered under AGPLv3. If the requirement
means OSI-approved artifacts only, replace Vault with OpenBao and Elastic with
OpenSearch/Wazuh Indexer before deployment.

## Adding an application, environment, or logical cluster

The `custom-applications` ApplicationSet uses a Git directory generator. Every
committed leaf matching this convention becomes one Argo CD Application:

```text
applications/<application>/clusters/<cluster>/<environment>/
    -> Application: <application>-<cluster>-<environment>
    -> Namespace:   <cluster>-<environment>-<application>
```

To add an application, create its reusable base and environment overlays, then
add a thin Kustomization at each cluster/environment leaf where it should run.
For example, committing
`applications/example/clusters/lab-a/dev/kustomization.yaml` generates
`example-lab-a-dev` and deploys it into namespace `lab-a-dev-example`.

Any external namespace-bound integration must authorize that generated
namespace before the leaf is synchronized. In particular, update the
corresponding Vault Kubernetes authentication role and add any required
namespace-scoped human RoleBinding. Do not replace an existing Vault role's
namespace list when adding the new namespace; preserve its other consumers.

To add an environment or another simulated cluster, add the corresponding
leaf Kustomizations for the applications that should run there. The
ApplicationSet itself does not need editing. Empty directories are not
discoverable by Git, so every leaf must contain a committed file. Removing a
leaf removes its generated Application and can delete its managed resources;
review such deletions before syncing them.

All current leaves target `https://kubernetes.default.svc`. Applications with
the same cluster/environment segments use separate application-specific
namespaces. Supporting real destination clusters requires registered Argo CD
cluster metadata in addition to the directory generator.
