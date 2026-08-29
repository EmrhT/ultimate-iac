# kube-bench cluster posture reports

Two daily schedules cover the complete homelab cluster:

- `security-kube-bench-control-plane` runs the `master` target on the
  control-plane/etcd node at 03:00 Europe/Istanbul.
- `security-kube-bench-workers` creates three parallel completions at 03:10.
  Required hostname anti-affinity and worker-only node affinity place one scan
  on each of the three workers.

Each pod uploads its JSON report to a stable per-node DefectDojo test under
product `homelab-cluster` and engagement `Cluster security posture`. Reports
are transient; DefectDojo is the persistent store. CIS failures are findings,
not Kubernetes Job failures. Scanner execution or upload failures do fail the
individual Job.

The scanner follows kube-bench's upstream Kubernetes Job model: it shares the
host PID namespace and mounts only the host paths needed for CIS inspection,
all read-only. It receives no Kubernetes API token and has no RBAC.

Before the first sync, allow namespace `security-kube-bench` in the Vault
Kubernetes auth role used by `vso-admin`, preserving the existing namespace
list.

Manual tests after Argo CD sync:

```sh
JOB="security-kube-bench-cp-manual-$(date +%s)"
kubectl -n security-kube-bench create job \
  --from=cronjob/security-kube-bench-control-plane "$JOB"
kubectl -n security-kube-bench logs -f "job/$JOB" -c defectdojo-uploader
```

```sh
JOB="security-kube-bench-workers-manual-$(date +%s)"
kubectl -n security-kube-bench create job \
  --from=cronjob/security-kube-bench-workers "$JOB"
kubectl -n security-kube-bench get pods -l job-name="$JOB" -w
```
