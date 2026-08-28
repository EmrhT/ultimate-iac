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
kubectl get reports.openreports.io -A
kubectl get clusterreports.openreports.io
kubectl describe report.openreports.io -n <namespace> <report-name>
```

Kyverno emits OpenReports for DefectDojo. A lightweight CronJob runs at
00:30, 06:30, 12:30, and 18:30 Europe/Istanbul time. It exports current
`fail`, `warn`, and `error` results for resources in `lab-a-dev` and
`lab-a-prod`, plus policy results attached to those two Namespace objects.
Reports for lab-b and other cluster resources are excluded.

The exporter reads the existing DefectDojo API token from
`kv/security/defectdojo/credentials`, materialized by Vault Secrets Operator as
`security-kyverno-defectdojo`. It reimports into product `podinfo`, engagement
`Runtime security`, and test `Kyverno policy compliance lab-a` with
`close_old_findings=true`. Temporary JSON is limited to a `16Mi` `emptyDir` and
is discarded with the Job; historical results live only in DefectDojo.

Run an immediate export and follow each stage with:

```bash
JOB="security-kyverno-manual-$(date +%s)"
kubectl -n kyverno create job \
  --from=cronjob/security-kyverno-defectdojo \
  "$JOB"
kubectl -n kyverno logs -f "job/$JOB" -c collect-openreports
kubectl -n kyverno logs -f "job/$JOB" -c select-podinfo-findings
kubectl -n kyverno logs -f "job/$JOB" -c defectdojo-uploader
```

The image trust policy expects Podinfo images to be keylessly signed by the
`EmrhT/podinfo-emrah` GitHub Actions workflow and to carry signed SLSA provenance.
Until signing is added to CI, those checks intentionally report failures without blocking deployment.
