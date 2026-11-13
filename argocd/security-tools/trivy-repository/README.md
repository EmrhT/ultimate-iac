# Scheduled repository dependency scanning

This application scans dependency manifests in two public Git repositories even
when their CI pipelines have not run recently:

| Repository | Branch | Schedule (Europe/Istanbul) | DefectDojo engagement |
| --- | --- | --- | --- |
| `EmrhT/podinfo-emrah` | `master` | 23:00 daily | `Podinfo` |
| `EmrhT/star-dust-travel-agency` | `main` | 23:15 daily | `Star Dust Travel Agency` |

Each Job makes a shallow checkout of the configured branch into an ephemeral
directory and scans production and development dependency lock/manifests with
Trivy's `repository` command and the existing in-cluster Trivy server. The Star
Dust Job first uses the .NET 10 SDK to generate ephemeral NuGet
`packages.lock.json` files, because Trivy cannot resolve package versions from
the two `.csproj` files alone. Only the vulnerability scanner is enabled; this
flow does not
duplicate SonarQube SAST, secret scanning, configuration scanning, or runtime
image scanning.

All MEDIUM, HIGH, and CRITICAL findings are reimported into the stable
`Scheduled repository dependency scan` Test under Asset
`Application CI/CD security findings - homelab`. Score-backed UNKNOWN findings
are normalized to HIGH or CRITICAL before import. `close_old_findings=true`
closes findings that disappear from the next successful scan.

PagerDuty generation is configured per repository. It is disabled for Podinfo,
so Podinfo findings are imported into DefectDojo without paging from either the
repository scanner or Trivy Operator. It remains enabled for Star Dust: every
finding whose maximum available CVSS v2/v3/v4 score is at least 9.0 is sent
directly to PagerDuty. Its deduplication key is:

```text
trivy-repository:<repository>:<vulnerability>:<package>:<scan-date>
```

For paging-enabled repositories, retries on the same day deduplicate and an
unresolved finding creates a distinct incident after the next daily scan.
DefectDojo remains the complete historical record for every repository.

Both CronJobs are labelled `security.no-name.win/trivy-scan-excluded=true` so
Trivy Operator does not treat the scanner containers as running workloads.
Reports, repository clones, and API credential files use size-limited
`emptyDir` volumes and disappear with the Job Pod.

The application reuses the `trivy-dojo` VaultAuth in namespace
`security-trivy`. It requires these existing Vault fields:

- `kv/security/defectdojo/credentials`: `defectdojo-api-token`
- `kv/infra/monitoring/pagerduty`: `service-key`

Manual runs after Argo CD sync:

```sh
kubectl -n security-trivy create job \
  --from=cronjob/security-trivy-repository-podinfo \
  "trivy-repository-podinfo-manual-$(date +%s)"

kubectl -n security-trivy create job \
  --from=cronjob/security-trivy-repository-star-dust \
  "trivy-repository-star-dust-manual-$(date +%s)"
```
