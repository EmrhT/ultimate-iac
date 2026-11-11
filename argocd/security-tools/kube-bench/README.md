# kube-bench cluster posture reports

Two daily schedules cover the complete homelab cluster:

- `security-kube-bench-control-plane` runs the `master` target on the
  control-plane/etcd node at 03:00 Europe/Istanbul.
- `security-kube-bench-workers` creates three parallel completions at 03:10.
  Required hostname anti-affinity and worker-only node affinity place one scan
  on each of the three workers.

Each Job follows a deterministic scan-then-upload lifecycle, matching Nuclei:

1. The kube-bench `scanner` init container writes the completed JSON report to
   `/reports/kube-bench.json` on a size-limited shared `emptyDir`.
2. Kubernetes starts `defectdojo-uploader` only after that scanner exits
   successfully.
3. The uploader imports the report into a stable per-node DefectDojo test under
   Asset `Kubernetes CIS benchmark findings - homelab cluster` and engagement
   `Cluster security posture`.
4. The report volume disappears when the Job Pod is deleted; DefectDojo is the
   persistent store.

The uploader is not a concurrently running sidecar and does not need a
separate CronJob. A separate Pod could not consume this Job's `emptyDir`
without adding a PVC or external object store. CIS failures are findings, not
Kubernetes Job failures. Scanner execution or upload failures do fail the
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
