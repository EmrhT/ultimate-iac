#!/usr/bin/env bash
# Controlled test for the Falco Talon -> label -> Cilium quarantine path.
# Run only after Argo has synced infra-falco-talon and the Podinfo ApplicationSet.
set -euo pipefail

namespace="${1:-lab-a-dev}"
selector='app.kubernetes.io/name=podinfo'
pod="$(kubectl -n "$namespace" get pods -l "$selector" -o jsonpath='{.items[0].metadata.name}')"
client_namespace="security-zap"
client_pod="falco-talon-quarantine-test"

cleanup() {
  kubectl -n "$namespace" label pod "$pod" security.no-name.win/quarantined- --ignore-not-found
  kubectl -n "$client_namespace" delete pod "$client_pod" --ignore-not-found --wait=false
}
trap cleanup EXIT

echo "Target: $namespace/$pod"
echo "Creating an allowlisted, restricted temporary client using security-zap's identity."
kubectl apply -f - <<'EOF_MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  name: falco-talon-quarantine-test
  namespace: security-zap
  labels:
    app.kubernetes.io/name: falco-talon-quarantine-test
spec:
  serviceAccountName: security-zap
  automountServiceAccountToken: false
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: curl
      image: docker.io/curlimages/curl:8.21.0@sha256:7c12af72ceb38b7432ab85e1a265cff6ae58e06f95539d539b654f2cfa64bb13
      imagePullPolicy: IfNotPresent
      command: [/bin/sh]
      args: [-ec, sleep 300]
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: [ALL]
EOF_MANIFEST
kubectl -n "$client_namespace" wait --for=condition=Ready "pod/$client_pod" --timeout=60s

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
