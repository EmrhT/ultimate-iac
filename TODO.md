# Operational TODO

This file records deliberately deferred infrastructure work that should remain
visible after the immediate incident has been mitigated.

## Worker root-disk capacity

- [ ] Increase every worker root disk from approximately 30 GiB to at least
      50 GiB; prefer 60 GiB to accommodate the security-tool image set.
- [ ] Extend the partition and filesystem after increasing each virtual disk.
- [ ] Verify `/`, `/var/lib/containerd`, node `DiskPressure`, and Longhorn node
      readiness after each worker is resized.
- [ ] Consider a dedicated filesystem for `/var/lib/containerd` if image growth
      remains significant after the root-disk expansion.

Current mitigation:

- Kubelet starts unused-image garbage collection at 75% usage and targets 65%.
- Images unused for 72 hours are eligible for age-based garbage collection.
- `DiskPressure` begins at 90% usage, leaving approximately 10% emergency space.

Operational note: kubelet does not preserve `imageMaximumGCAge` history across
restarts, so disk-usage thresholds remain the primary protection in this
frequently restarted homelab.

## Control-plane memory capacity

- [x] Increase the control-plane node memory from approximately 4 GiB to the
      minimum acceptable 6 GiB profile.
- [ ] Increase the control-plane node to 8 GiB if sustained utilization remains
      above 85%, `MemoryPressure` returns, or OOM/eviction events recur.
- [ ] Continue verifying kube-apiserver working-set memory, overall node memory
      utilization, the `MemoryPressure` condition, and OOM events across normal
      operation and cluster restarts.

Current state and mitigation:

- On 2026-11-07, the node reported approximately 5.8 GiB capacity and 4.9 GiB
  allocatable memory, 83% utilization, and `MemoryPressure=False`.
- The control-plane Cilium Hubble buffer is limited to 8,191 events, while
  workers retain 65,535 events.
- The 6 GiB expansion removed the immediate capacity blocker. Continue
  monitoring rather than resizing from utilization percentage alone while
  `MemoryPressure` remains false and no OOM kills or evictions occur.

## Kyverno enforcement hardening

- [ ] Review Kyverno PolicyReports until the current audit-only policies have
      no unexplained violations.
- [ ] Move the workload-security policies from Audit to Enforce incrementally,
      starting with new application namespaces before infrastructure namespaces.
- [ ] Reject privileged containers, host namespaces, unsafe hostPath mounts,
      added Linux capabilities, privilege escalation, root execution and missing
      RuntimeDefault seccomp profiles.
- [ ] Keep explicit, narrowly scoped PolicyExceptions in Git for workloads that
      have a documented technical requirement.
- [ ] Validate each enforcement change in a development namespace and provide a
      rollback before applying it to production or infrastructure workloads.

Current mitigation:

- All Kyverno policies remain in Audit mode, so violations generate reports and
  warnings without blocking existing workloads.

## Runtime image vulnerability scanning

- [x] Replace the custom runtime inventory/scanner scripts with Trivy Operator
      and native `VulnerabilityReport` resources.
- [x] Configure 24-hour report expiry/rescanning through the existing Trivy
      server and limit scan concurrency for the homelab.
- [x] Add native DefectDojo report ingestion and Prometheus numeric CVSS 9.0+
      detection without a custom report parser.
- [ ] Permit `security-trivy/vault-auth` in Vault Kubernetes role `vso-admin`
      and verify VSO creates
      `security-trivy-dojo-defect-dojo-api-credentials`.
- [ ] Run the observation-only controlled tests in
      `argocd/security-tools/README.md` with a real vulnerable disposable image.
- [ ] Replace the Prometheus alert label `paging: disabled` with
      `team: security` only after the controlled test passes.
- [ ] Upgrade/verify the DefectDojo Trivy Operator parser provides stable
      service identity across ReplicaSet revisions, then enable safe closure of
      old findings in the report operator.

Current mitigation:

- The Prometheus rule is active for inspection but does not carry the
  `team=security` routing label, so initial report population cannot flood
  PagerDuty during acceptance testing.
