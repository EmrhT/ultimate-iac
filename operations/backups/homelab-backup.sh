#!/usr/bin/env bash
set -Eeuo pipefail

umask 077
export PATH=/usr/local/bin:/usr/bin:/bin
export KUBECONFIG="${KUBECONFIG:-/home/iacuser/.kube/config}"

# Defaults can be overridden by the systemd service or an interactive run.
BACKUP_ROOT="${BACKUP_ROOT:-/home/iacuser/homelab-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
VAULT_PORT="${VAULT_PORT:-18200}"
# UTC keeps filenames unambiguous across daylight-saving or timezone changes.
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
VAULT_DIR="${BACKUP_ROOT}/vault"
KEYCLOAK_DIR="${BACKUP_ROOT}/keycloak"
VAULT_FILE="${VAULT_DIR}/vault-${TIMESTAMP}.snap"
KEYCLOAK_FILE="${KEYCLOAK_DIR}/keycloak-${TIMESTAMP}.dump"

# Always stop the port-forward and remove incomplete backup files.
cleanup() {
  if [[ -n "${port_pid:-}" ]]; then
    kill "${port_pid}" 2>/dev/null || true
    wait "${port_pid}" 2>/dev/null || true
  fi
  rm -f "${VAULT_FILE}.partial" "${KEYCLOAK_FILE}.partial"
  unset vault_token
}
trap cleanup EXIT

# Owner-only directories protect the Vault snapshot and Keycloak database dump.
install -d -m 0700 "${BACKUP_ROOT}" "${VAULT_DIR}" "${KEYCLOAK_DIR}"
# File-descriptor locking prevents overlapping timer and manual executions.
exec 9>"${BACKUP_ROOT}/.backup.lock"
flock -n 9 || { echo "Another backup is already running" >&2; exit 1; }

# Fail before creating files when the Kubernetes API is unavailable.
kubectl --request-timeout=20s get --raw=/readyz >/dev/null

echo "Creating Vault Raft snapshot"
kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=120s >/dev/null
# Keep Vault private: reach its ClusterIP through a localhost-only port-forward.
kubectl -n vault port-forward service/vault "${VAULT_PORT}:8200" >/dev/null 2>&1 &
port_pid=$!

# Give kubectl up to 30 seconds to establish the port-forward.
for _ in {1..30}; do
  curl -fsS --max-time 2 \
    "http://127.0.0.1:${VAULT_PORT}/v1/sys/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS --max-time 2 \
  "http://127.0.0.1:${VAULT_PORT}/v1/sys/health" >/dev/null

# Exchange a ten-minute ServiceAccount JWT for a least-privilege Vault token.
vault_token="$(
  kubectl -n vault create token vault-backup --audience=vault --duration=10m |
    jq -R '{role: "vault-backup", jwt: .}' |
    curl -fsS --max-time 30 \
      --header 'Content-Type: application/json' --data @- \
      "http://127.0.0.1:${VAULT_PORT}/v1/auth/kubernetes/login" |
    jq -er '.auth.client_token'
)"

# Write to a partial file so an interrupted download never looks complete.
curl -fsS --max-time 600 \
  --header "X-Vault-Token: ${vault_token}" \
  "http://127.0.0.1:${VAULT_PORT}/v1/sys/storage/raft/snapshot" \
  --output "${VAULT_FILE}.partial"
unset vault_token
# A Vault Raft snapshot is a gzip archive; reject malformed responses.
gzip -t "${VAULT_FILE}.partial"
mv "${VAULT_FILE}.partial" "${VAULT_FILE}"
cd "${VAULT_DIR}"
sha256sum "$(basename "${VAULT_FILE}")" >"$(basename "${VAULT_FILE}").sha256"
cd - >/dev/null

# The Vault connection and token are no longer needed for the database backup.
kill "${port_pid}" 2>/dev/null || true
wait "${port_pid}" 2>/dev/null || true
port_pid=""

echo "Creating Keycloak PostgreSQL dump"
kubectl -n keycloak wait --for=condition=Ready \
  pod/keycloak-postgresql-0 --timeout=120s >/dev/null
# Stream a portable custom-format dump directly to iac-controller.
kubectl -n keycloak exec keycloak-postgresql-0 -- \
  pg_dump --username=keycloak --dbname=keycloak --format=custom \
    --compress=6 --no-owner --no-acl >"${KEYCLOAK_FILE}.partial"
# Parse the archive catalog before promoting the partial file to a backup.
kubectl -n keycloak exec -i keycloak-postgresql-0 -- \
  pg_restore --list <"${KEYCLOAK_FILE}.partial" >/dev/null
mv "${KEYCLOAK_FILE}.partial" "${KEYCLOAK_FILE}"
cd "${KEYCLOAK_DIR}"
sha256sum "$(basename "${KEYCLOAK_FILE}")" \
  >"$(basename "${KEYCLOAK_FILE}").sha256"
cd - >/dev/null

# Delete expired backup/checksum pairs only after both new backups succeed.
find "${VAULT_DIR}" -maxdepth 1 -type f \
  \( -name 'vault-*.snap' -o -name 'vault-*.snap.sha256' \) \
  -mtime "+${RETENTION_DAYS}" -delete
find "${KEYCLOAK_DIR}" -maxdepth 1 -type f \
  \( -name 'keycloak-*.dump' -o -name 'keycloak-*.dump.sha256' \) \
  -mtime "+${RETENTION_DAYS}" -delete

echo "Created ${VAULT_FILE}"
echo "Created ${KEYCLOAK_FILE}"
