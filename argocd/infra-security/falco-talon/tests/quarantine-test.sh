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

can_reach_target() {
  kubectl -n "$client_namespace" exec "$client_pod" -- curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "http://podinfo.$namespace.svc.cluster.local:9898/" >/dev/null 2>&1
}

wait_for_reachability() {
  local expected="$1"
  local attempt

  # A Pod label changes its Cilium security identity asynchronously. Allow the
  # agent to allocate the identity and regenerate the endpoint policy.
  for attempt in {1..12}; do
    if can_reach_target; then
      if [[ "$expected" == "reachable" ]]; then
        return 0
      fi
    elif [[ "$expected" == "blocked" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: expected Podinfo to be $expected within 60 seconds." >&2
  return 1
}

wait_for_quarantine_label() {
  local attempt

  for attempt in {1..12}; do
    if [[ "$(kubectl -n "$namespace" get pod "$pod" -o jsonpath='{.metadata.labels.security\.no-name\.win/quarantined}')" == "true" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: Talon did not apply the quarantine label within 60 seconds." >&2
  return 1
}


echo "Target: $namespace/$pod"
echo "Using the existing allowlisted security-zap Pod: $client_pod"
echo "Baseline: the allowlisted DAST identity reaches Podinfo."
wait_for_reachability reachable

echo "Sending one synthetic Reverse Shell event directly to Talon."
kubectl -n "$client_namespace" exec "$client_pod" -- curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  -X POST http://falco-talon.falco.svc:2803/ \
  --data "{\"output\":\"controlled Talon test\",\"priority\":\"CRITICAL\",\"rule\":\"Reverse Shell\",\"hostname\":\"controlled-test\",\"source\":\"syscall\",\"output_fields\":{\"k8s.ns.name\":\"$namespace\",\"k8s.pod.name\":\"$pod\"},\"tags\":[\"controlled-test\"]}"

echo "Expected label: quarantined=true"
wait_for_quarantine_label

echo "Waiting for Cilium to deny that same client identity."
wait_for_reachability blocked

echo "Removing the response label and verifying recovery."
kubectl -n "$namespace" label pod "$pod" security.no-name.win/quarantined-
wait_for_reachability reachable
echo "PASS: Talon labeled the Pod, Cilium contained it, and access recovered after label removal."
