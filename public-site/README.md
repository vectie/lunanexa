# NexAI public homepage

Static, mobile-friendly homepage. The 25 October 2026 live edition replaces
launch teasers with the verified general-model trial: new visitors enter the
existing registration/trial portal, while activated users can open the browser
workbench directly. The homepage itself has no login, analytics, or inference form.
On 25 October the owner explicitly authorized publishing the existing, tested
API key and its original client connection QR for a one-day public experience.
The owner chose manual homepage removal, with no new key, expiry change or
automated shutdown. Public calls share the original test account's usage attribution.
FDE and approved print-campaign brand assets remain intact. Source
is kept here so deployment is reproducible rather than a server-only fix.

The deployment is isolated from the product portals. It claims only the host root, `/index.html`, and `/nexai-assets/`; `/user/`, `/mana/`, `/docs/`, and application paths remain untouched. Run on the management role, never a GPU worker. Supply the public host, management hostname, an existing digest-pinned Nginx image, and the existing TLS secret:

```sh
node public-site/render-deployment.mjs PUBLIC_HOST MANAGEMENT_NODE NGINX_IMAGE_AT_DIGEST TLS_SECRET | kubectl apply --server-side --field-manager=nexai-landing -f -
kubectl -n lunanexa rollout status deployment/nexai-public-landing
```

Content ConfigMaps are immutable and named by content hash. Earlier ConfigMaps remain available for deployment rollback. The site runs as UID 101, with no Kubernetes token, no writable root filesystem, no egress, and ingress only from Traefik.

The approved public-key edition is released through
`tmp/model-trial-ui-20261022/release-public-test-key.mbtx`. It injects
`__PUBLIC_TRIAL_KEY__` and `__PUBLIC_TRIAL_QR__` from deployment inputs exported
from the signed-in UI; never put the live key into tracked source or this guide.
`site.js` provides clipboard feedback only and makes no network requests.
The previous immutable homepage ConfigMap is retained for manual rollback.
The published Base URL uses the owner's internal DNS/default HTTPS entry:
`https://suanli.kechuangfuwu.com/trial/v1`. The release script's `prepare` phase
regenerates the connection QR with that same address; the key, model and output
budget remain unchanged.
