# Homelab backups

This directory contains standalone controller-side backup automation. It has no
Kubespray or Argo CD runtime dependency beyond normal Kubernetes API access.

The daily job creates:

- a Vault integrated-storage snapshot in `~/homelab-backups/vault`;
- a custom-format Keycloak PostgreSQL dump in `~/homelab-backups/keycloak`.

Backups use owner-only permissions, receive SHA-256 checksum files, and are
retained for 14 days. The persistent timer catches a missed schedule after the
controller starts. Failed runs retry four times at 15-minute intervals.

## Install

```bash
chmod 0755 operations/backups/homelab-backup.sh
sudo systemctl link "$PWD/operations/backups/homelab-backup.service"
sudo systemctl link "$PWD/operations/backups/homelab-backup.timer"
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-backup.timer
```

Run and inspect a backup:

```bash
sudo systemctl start homelab-backup.service
systemctl status homelab-backup.service
journalctl -u homelab-backup.service
```

Verify stored checksums:

```bash
cd ~/homelab-backups/vault && sha256sum -c *.sha256
cd ~/homelab-backups/keycloak && sha256sum -c *.sha256
```

## Recovery requirements

Vault recovery requires the matching unseal keys. Keep those keys outside both
the Kubernetes cluster and this controller. Restore a snapshot only into a
fresh compatible Vault deployment using `vault operator raft snapshot restore`.

Restore the Keycloak dump into a clean compatible PostgreSQL instance with
`pg_restore`. Scale Keycloak down during database restoration, then start it
after the restore completes.
