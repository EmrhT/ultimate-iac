# Internal documentation platform

This application deploys three independently authenticated static MkDocs sites
to `lab-a/dev`. The existing `custom-applications` ApplicationSet discovers the
single deployment leaf at `clusters/lab-a/dev` and creates
`mkdocs-lab-a-dev` in namespace `lab-a-dev`.

| Site | Hostname | Keycloak client | Required group | Vault path |
| --- | --- | --- | --- | --- |
| General | `docs-lab-a-dev.no-name.win` | `internal-docs-general` | `/docs-readers` | `kv/dev/mkdocs/general` |
| Infrastructure | `infra-docs-lab-a-dev.no-name.win` | `internal-docs-infra` | `/infra-team` | `kv/dev/mkdocs/infra` |
| Security | `security-docs-lab-a-dev.no-name.win` | `internal-docs-security` | `/security-team` | `kv/dev/mkdocs/security` |

Browser traffic follows:

```text
browser -> Traefik websecure Gateway -> site HTTPRoute -> site OAuth2 Proxy
        -> site Nginx Service -> static MkDocs content
```

There is no external route to an Nginx Service. Each site has its own image,
search index, OAuth2 Proxy, OIDC client, session cookie and Vault-backed
credentials.

## Prerequisites before committing the deployment leaf

### Keycloak

Create the three confidential OIDC clients from the table. For each client:

- enable the authorization-code flow and PKCE S256;
- use the site's exact callback URL, for example
  `https://docs-lab-a-dev.no-name.win/oauth2/callback`;
- permit the corresponding site origin;
- add a client-scope mapper that emits full group paths in the `groups` claim
  of ID tokens; and
- create the required group and assign users explicitly.

Do not reuse a client secret between sites. A user can access multiple sites by
belonging to multiple groups.

### Vault

Each Vault KV v2 secret must contain exactly these keys:

```text
client-secret
cookie-secret
```

Generate a different cookie secret for every site. One suitable input is:

```bash
openssl rand -base64 24 | tr -d '\n'
```

Write the secrets without placing their values in Git or shell history. The
logical commands are:

```bash
vault kv put kv/dev/mkdocs/general client-secret=... cookie-secret=...
vault kv put kv/dev/mkdocs/infra client-secret=... cookie-secret=...
vault kv put kv/dev/mkdocs/security client-secret=... cookie-secret=...
```

Create one read-only policy per path. The general-site policy is:

```hcl
path "kv/data/dev/mkdocs/general" {
  capabilities = ["read"]
}
```

Name it `vso-mkdocs-general-dev`. Repeat for `infra` and `security`, changing
both the policy name and path. Bind each policy to its dedicated Kubernetes
authentication identity:

```bash
vault write auth/kubernetes/role/vso-mkdocs-general-dev \
  bound_service_account_names=mkdocs-general-vault-auth \
  bound_service_account_namespaces=lab-a-dev \
  audience=vault \
  policies=vso-mkdocs-general-dev \
  ttl=1h
```

Repeat for `vso-mkdocs-infra-dev`/`mkdocs-infra-vault-auth` and
`vso-mkdocs-security-dev`/`mkdocs-security-vault-auth`. The development Vault
is operationally suitable for this homelab but does not provide the isolation
or availability guarantees of a dedicated production Vault deployment.

### DNS, TLS and registry

- Resolve all three hostnames to the existing Traefik entry address.
- Ensure the `websecure` listener certificate covers all three hostnames.
- Ensure cluster nodes can pull the three `ghcr.io/emrht/mkdocs-content-*`
  packages. If the packages remain private, provide registry credentials using
  the cluster's existing image-pull-secret mechanism before synchronization.

## Delivery and reconciliation

The separate `EmrhT/mkdocs-content` repository builds all sites strictly,
publishes three immutable images and opens one promotion pull request that
updates the three digests in `clusters/lab-a/dev/kustomization.yaml`. Merging
that pull request causes Argo CD to reconcile all three sites atomically.

Render locally before merging:

```bash
kubectl kustomize argocd/applications/mkdocs/clusters/lab-a/dev
```

Rollback by reverting the promotion commit, which restores the previous three
digests. Do not replace digests with mutable tags.

## Authorization checks

Expected behavior:

| Test | Result |
| --- | --- |
| Anonymous request | Redirected to Keycloak |
| Authenticated without the required group | HTTP 403 |
| Member of one site group | Access only to that site |
| Member of multiple site groups | Access to the corresponding sites |
| Direct Nginx Service access from outside the cluster | Not routable |
| Request for another site's search index | Evaluated by that site's own OAuth2 Proxy |
| User removed from a group | Access can continue until token/session refresh, at most the configured refresh interval under normal operation |

After deployment, verify each `/oauth2/callback`, an ordinary page, a static
asset and `/search/search_index.json` through its public hostname.

## Troubleshooting

- OAuth redirect loops: compare the Keycloak redirect URI with the exact
  `--redirect-url` rendered in the OAuth2 Proxy Deployment.
- Authenticated user receives 403: inspect the ID token for a full-path
  `groups` claim and verify the site's `allowed_groups` value.
- OAuth2 Proxy stays pending: inspect the corresponding `VaultAuth`,
  `VaultStaticSecret`, destination Secret and Vault role bindings.
- Nginx has `ImagePullBackOff`: verify GHCR package visibility or the namespace
  image-pull credentials.
- HTTPRoute does not attach: inspect its `Accepted` and `ResolvedRefs`
  conditions and the `traefik/websecure` listener.

## Adding a fourth site

Add a dedicated content directory and image in `mkdocs-content`, then add a
dedicated Nginx Deployment/Service, OAuth2 Proxy Deployment/Service and config,
HTTPRoute, Vault identity/secret and immutable image override here. Keep its
OIDC client, cookie name, group, selectors and search index independent. Update
the delivery matrix and digest updater so all site digests are promoted in one
pull request.
