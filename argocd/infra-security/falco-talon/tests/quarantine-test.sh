#!/usr/bin/env bash
# Controlled test for the Falco Talon -> label -> Cilium quarantine path.
# Run only after Argo has synced infra-falco-talon and the Podinfo ApplicationSet.
set -euo pipefail

namespace="${1:-lab-a-dev}"
selector='app.kubernetes.io/name=podinfo'
pod="$(kubectl -n "$namespace" get pods -l "$selector" -o jsonpath='{.items[0].metadata.name}')"
client_namespace="security-zap"
client_pod="$(kubectl -n "$client_namespace" get pods -l app.kubernetes.io/name=security-zap -o jsonpath='{.items[0].metadata.name}')"

cleanup() {
  if kubectl -n "$namespace" get pod "$pod" >/dev/null 2>&1; then
    kubectl -n "$namespace" label pod "$pod" security.no-name.win/quarantined-
  fi
}
trap cleanup EXIT

echo "Target: $namespace/$pod"
echo "Using the existing allowlisted security-zap Pod: $client_pod"
echo "Baseline: the allowlisted DAST identity reaches Podinfo."
kubectl -n "$client_namespace" exec "$client_pod" -- curl --fail --connect-timeout 3 --max-time 5 \
  "http://podinfo.$namespace.svc.cluster.local:9898/"

echo "Sending one synthetic Reverse Shell event directly to Talon."
kubectl -n "$client_namespace" exec "$client_pod" -- curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  -X POST http://falco-talon.falco.svc:2803/ \
  --data "{\"output\":\"controlled Talon test\",\"priority\":\"CRITICAL\",\"rule\":\"Reverse Shell\",\"hostname\":\"controlled-test\",\"source\":\"syscall\",\"output_fields\":{\"k8s.ns.name\":\"$namespace\",\"k8s.pod.name\":\"$pod\"},\"tags\":[\"controlled-test\"]}"

echo "Expected label: quarantined=true"
test "$(kubectl -n "$namespace" get pod "$pod" -o jsonpath='{.metadata.labels.security\.no-name\.win/quarantined}')" = "true"

echo "Expected: Cilium now denies that same client identity."
if kubectl -n "$client_namespace" exec "$client_pod" -- curl --fail --connect-timeout 3 --max-time 5 \
  "http://podinfo.$namespace.svc.cluster.local:9898/"; then
  echo "ERROR: Podinfo remained reachable while quarantined." >&2
  exit 1
fi

echo "Removing the response label and verifying recovery."
kubectl -n "$namespace" label pod "$pod" security.no-name.win/quarantined-
kubectl -n "$client_namespace" exec "$client_pod" -- curl --fail --connect-timeout 3 --max-time 5 \
  "http://podinfo.$namespace.svc.cluster.local:9898/"
echo "PASS: Talon labeled the Pod, Cilium contained it, and access recovered after label removal."
