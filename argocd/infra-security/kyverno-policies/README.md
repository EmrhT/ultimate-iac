# Kyverno policies

This application owns policy definitions separately from the Kyverno Helm release.

## Rollout safety

- Every policy uses `validationActions: [Audit]`; violations create reports and warnings only.
- Every policy uses `failurePolicy: Ignore`; an unavailable or failing webhook does not block workloads.
- Image signature and attestation checks run only in background scans, avoiding registry calls in admission.
- No mutating, generating, or deleting policy is installed.
- Moving any policy to `Deny` requires a separate reviewed change after the audit reports are clean.

## Reviewing findings

```bash
kubectl get policyreports -A
kubectl get clusterpolicyreports
kubectl describe policyreport -n <namespace> <report-name>
```

The image trust policy expects Podinfo images to be keylessly signed by the
`EmrhT/podinfo-emrah` GitHub Actions workflow and to carry signed SLSA provenance.
Until signing is added to CI, those checks intentionally report failures without blocking deployment.
