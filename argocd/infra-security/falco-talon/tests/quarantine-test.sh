#!/usr/bin/env bash
# Controlled test for the Falco Talon -> label -> Cilium quarantine path.
# Run only after Argo has synced infra-falco-talon and the Podinfo ApplicationSet.
set -euo pipefail

namespace="${1:-lab-a-dev}"
selector="${2:-app.kubernetes.io/name=podinfo}"
pod="$(kubectl -n "$namespace" get pods -l "$selector" -o jsonpath='{.items[0].metadata.name}')"
client_namespace="security-zap"
client_pod="$(kubectl -n "$client_namespace" get pods -l app.kubernetes.io/name=security-zap -o jsonpath='{.items[0].metadata.name}')"

# Discover the HTTP endpoint from the same workload label instead of embedding
# an application Service name or port. Ambiguity is an error: silently choosing
# one of several Services or TCP ports could produce a misleading test result.
service_endpoint="$(
  kubectl -n "$namespace" get services -l "$selector" -o json |
    jq -er '
      [.items[] | select(.spec.clusterIP != "None")] as $services
      | if ($services | length) != 1 then
          error("expected exactly one non-headless matching Service")
        else
          $services[0] as $service
          | [$service.spec.ports[] | select(.protocol == "TCP")] as $ports
          | if ($ports | length) != 1 then
              error("expected exactly one TCP Service port")
            else
              [$service.metadata.name, ($ports[0].port | tostring)] | @tsv
            end
        end
    '
)"
IFS=$'\t' read -r service service_port <<<"$service_endpoint"
target_url="http://$service.$namespace.svc.cluster.local:$service_port/"

cleanup() {
  if kubectl -n "$namespace" get pod "$pod" >/dev/null 2>&1; then
    kubectl -n "$namespace" label pod "$pod" security.no-name.win/quarantined-
  fi
}
trap cleanup EXIT

can_reach_target() {
  kubectl -n "$client_namespace" exec "$client_pod" -- curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 \
    "$target_url" >/dev/null 2>&1
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

  echo "ERROR: expected $namespace/$service to be $expected within 60 seconds." >&2
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
echo "Discovered endpoint: $target_url"
echo "Using the existing allowlisted security-zap Pod: $client_pod"
echo "Baseline: the allowlisted DAST identity reaches the target workload."
wait_for_reachability reachable

echo "Triggering the real Falco Container Escape Behavior rule with a denied unshare attempt."
if ! kubectl -n "$namespace" exec "$pod" -- sh -c 'command -v unshare >/dev/null'; then
  echo "ERROR: the target image does not contain unshare." >&2
  exit 1
fi

# execve succeeds, so Falco sees the escape tool execution, but the kernel
# denies namespace creation because Podinfo has no required capability.
if kubectl -n "$namespace" exec "$pod" -- unshare --mount /bin/true; then
  echo "ERROR: the controlled unshare unexpectedly succeeded." >&2
  exit 1
fi

echo "Expected label: quarantined=true"
wait_for_quarantine_label

echo "Waiting for Cilium to deny that same client identity."
wait_for_reachability blocked

echo "Removing the response label and verifying recovery."
kubectl -n "$namespace" label pod "$pod" security.no-name.win/quarantined-
wait_for_reachability reachable
echo "PASS: Talon labeled the Pod, Cilium contained it, and access recovered after label removal."
