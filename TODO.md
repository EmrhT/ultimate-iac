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

- [ ] Increase the control-plane node memory from approximately 4 GiB to 8 GiB;
      treat 6 GiB as the minimum acceptable expansion.
- [ ] Verify kube-apiserver working-set memory, overall node memory utilization,
      the `MemoryPressure` condition, and OOM events after resizing.

Current mitigation:

- The control-plane Cilium Hubble buffer is limited to 8,191 events, while
  workers retain 65,535 events.
- Continue monitoring rather than reacting to utilization percentage alone as
  long as `MemoryPressure` remains false and no OOM kills occur.
