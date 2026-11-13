# Falco findings in DefectDojo

This component collects the previous six hours of Falco JSON logs every six hours,
keeps Podinfo runtime events at `Notice` or higher for the canonical scan
deployment in `lab-a-dev-podinfo`, aggregates duplicates, and reimports them into shared Asset
`Application CI/CD security findings - homelab`, application engagement
`Podinfo`, and recurring Test `Falco runtime alerts lab-a`. `Notice` maps to DefectDojo `Low`;
`Informational` and `Debug` remain excluded.

The collector intentionally excludes raw Falco output and command-line fields so
credentials observed in process arguments cannot be copied into DefectDojo.
Reports are transient and use an `emptyDir`; DefectDojo is the persistent store.

Before the first sync, allow namespace `falco` in the Vault Kubernetes auth role
used by `vso-admin`. Preserve all existing bound service-account namespaces.

To run an ad-hoc collection after Argo CD syncs this application:

```sh
JOB="security-falco-manual-$(date +%s)"
kubectl -n falco create job --from=cronjob/security-falco-defectdojo "$JOB"
kubectl -n falco logs -f "job/$JOB" -c defectdojo-uploader
```
