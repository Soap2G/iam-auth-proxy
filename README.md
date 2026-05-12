# iam-auth-proxy

A Helm chart that deploys [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) configured for [INDIGO IAM](https://indigo-iam.github.io/) (or any OIDC-compliant IdP). It sits in front of a backend Kubernetes Service and enforces authentication and optional group-based authorisation before forwarding traffic.

Authenticated identity is forwarded to the upstream as standard headers:
- `X-Forwarded-User` — email address (or OIDC `sub` if `preferEmail=false`)
- `X-Forwarded-Email` — email address
- `X-Forwarded-Groups` — comma-separated list of groups from the token

## Prerequisites

1. A running INDIGO IAM instance (e.g. `https://iam.example.org/`).
2. An OIDC client registered in IAM — see [Registering a client](#registering-a-client).
3. An Ingress controller installed in your cluster (e.g. ingress-nginx), **or** an OpenShift/OKD cluster for Route support.

## Registering a client in INDIGO IAM

1. Go to your IAM instance → **My Clients** → **New client**.
2. Set the **Client Name** (e.g. `my-app-proxy`).
3. Under the **Redirect URIs** tab, add the callback URL. The chart prints the exact value in `helm install` NOTES — it follows the pattern:
   ```
   https://<ingress.hostname><proxyPrefix>/callback
   ```
   e.g. `https://app.example.org/oauth2/callback`
4. Under the **Scopes** tab, enable `offline_access` for refresh-token support.
5. Click **Save** — IAM displays the generated `client_id` and `client_secret`.
6. Store these in the values file or a Kubernetes Secret (see [Credentials](#credentials)).

## Quick start

```bash
helm install my-proxy ./iam-auth-proxy \
  --set upstream.service.name=my-app \
  --set upstream.service.port=8080 \
  --set ingress.hostname=app.example.org \
  --set ingress.className=nginx \
  --set oidc.issuerURL=https://iam.example.org/ \
  --set oidc.clientID=<client-id-from-iam> \
  --set oidc.clientSecret=<client-secret-from-iam>
```

The chart auto-generates and persists a random 32-byte cookie secret across upgrades.

## JWT profile presets

Set `iam.profile` to match how your IAM instance is configured:

| `iam.profile` | OIDC scope | Groups claim | When to use |
|---|---|---|---|
| `iam` *(default)* | `openid profile email offline_access groups` | `groups` | Default IAM profile |
| `wlcg` | `openid profile email offline_access wlcg.groups` | `wlcg.groups` | WLCG token profile |
| `aarc` | `openid profile email offline_access eduperson_entitlement` | `eduperson_entitlement` | AARC / EduGAIN profile |
| `custom` | `authOptions.scope` (required) | `authOptions.oidcGroupsClaim` (required) | Any other IdP |

Example for WLCG with group-based access control:

```yaml
iam:
  profile: wlcg

upstream:
  service: { name: my-app, port: 8080 }

ingress:
  hostname: app.example.org
  className: nginx

oidc:
  issuerURL: https://wlcg-iam.example.org/
  clientID: my-client
  clientSecret: my-secret

authOptions:
  allowedGroups:
    - /wlcg/cms/production
    - /wlcg/cms/analysis
```

## Credentials

### Option A — inline (chart manages the Secret)

Provide credentials in `values.yaml` or `--set`. The chart creates a Secret named `<release>-iam-auth-proxy`:

```yaml
oidc:
  issuerURL: https://iam.example.org/
  clientID: my-client
  clientSecret: my-secret
```

### Option B — pre-existing Secret

Create a Secret manually and reference it. This is recommended for GitOps workflows where you don't want credentials in Helm values:

```bash
kubectl create secret generic my-oidc-secret \
  --from-literal=issuerURL=https://iam.example.org/ \
  --from-literal=clientID=my-client \
  --from-literal=clientSecret=my-secret \
  --from-literal=suggestedCookieSecret=$(openssl rand -hex 16)
```

```yaml
oidc:
  existingSecret: my-oidc-secret
```

The cookie secret must be exactly 16, 24, or 32 characters for AES session encryption.

## OpenShift / OKD

Disable the Ingress and enable the Route instead:

```yaml
ingress:
  enabled: false

route:
  enabled: true
  hostname: app.apps.mycluster.example.org
```

## Key values reference

| Value | Default | Description |
|---|---|---|
| `upstream.service.name` | `""` *(required)* | Backend Service name |
| `upstream.service.port` | `8080` | Backend Service port |
| `ingress.enabled` | `true` | Create a Kubernetes Ingress |
| `ingress.hostname` | `""` *(required)* | Public hostname |
| `ingress.className` | `""` | IngressClass (e.g. `nginx`) |
| `ingress.path` | `/` | Protected path prefix |
| `ingress.tls.enabled` | `true` | Add TLS block to Ingress |
| `ingress.tls.secretName` | `""` | TLS Secret name (empty = cluster default) |
| `route.enabled` | `false` | Create an OpenShift Route instead |
| `route.hostname` | `""` *(required if route)* | Public hostname for Route |
| `oidc.issuerURL` | `""` | IAM issuer URL |
| `oidc.clientID` | `""` | OAuth2 client ID |
| `oidc.clientSecret` | `""` | OAuth2 client secret |
| `oidc.existingSecret` | `""` | Use a pre-existing Secret instead |
| `iam.profile` | `iam` | JWT profile preset |
| `authOptions.allowedGroups` | `[]` | IAM group paths required for access (empty = any authn user) |
| `authOptions.emailDomains` | `["*"]` | Allowed email domains |
| `authOptions.preferEmail` | `true` | Use email as `X-Forwarded-User` |
| `authOptions.proxyPrefix` | `/oauth2` | Internal proxy path prefix |
| `authOptions.cookieExpire` | `12h` | Session cookie lifetime |
| `authOptions.whitelistDomains` | `[]` | Extra post-login redirect domains (e.g. `.example.org`) |
| `authOptions.scope` | `""` | OIDC scope override (required for `custom` profile) |
| `authOptions.oidcGroupsClaim` | `""` | Groups claim override (required for `custom` profile) |
| `authOptions.extraArgs` | `[]` | Extra oauth2-proxy CLI arguments (override env vars) |
| `cookie.secret` | `""` | Plain-text cookie secret (auto-generated if empty) |
| `image.repository` | `quay.io/oauth2-proxy/oauth2-proxy` | Container image |
| `image.tag` | `v7.6.0` | Image tag |
| `podSecurityContext` | `runAsNonRoot: true` + seccomp | Pod-level security context |
| `securityContext` | `allowPrivilegeEscalation: false` + caps drop | Container-level security context |

## Upgrading

The chart auto-persists the cookie secret across upgrades using a `lookup` call. When upgrading, existing sessions remain valid as long as the release name and namespace don't change.

To rotate the cookie secret (which forces all users to re-authenticate):

```bash
helm upgrade my-proxy ./iam-auth-proxy \
  --set cookie.secret=$(openssl rand -hex 16) \
  -f my-values.yaml
```

## Running unit tests

```bash
helm unittest ./iam-auth-proxy/
```

Requires the [helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin (`helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.5.2`).
