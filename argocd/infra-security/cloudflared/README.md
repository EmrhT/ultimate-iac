# Cloudflare Tunnel connector

The `cloudflared` Deployment connects the cluster to the remotely managed
Cloudflare Tunnel. Argo CD manages the connector workload, but the tunnel token
must not be stored in Git.

Before the first sync, create the expected Secret in the destination namespace:

```bash
kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -
read -rsp 'Cloudflare tunnel token: ' CLOUDFLARED_TUNNEL_TOKEN
printf '%s' "$CLOUDFLARED_TUNNEL_TOKEN" | kubectl -n cloudflare create secret \
  generic cloudflared-token --from-file=token=/dev/stdin
unset CLOUDFLARED_TUNNEL_TOKEN
```

The Secret must contain the key `token`. If it is absent, the Deployment remains
unavailable until the Secret is created. A future external-secret integration can
replace this manual bootstrap without changing the Deployment.
