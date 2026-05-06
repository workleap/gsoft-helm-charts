# Migration Guide

## v4 → v5

### PodDisruptionBudget (breaking change)

The `podDisruptionBudget` configuration block has been removed. PDB behavior is now fully automatic.

**Before (v4):**
```yaml
podDisruptionBudget:
  minAvailable: 1
```

**After (v5):** Remove the `podDisruptionBudget:` block entirely.

A PDB is created for `Production` and `DR` environments. The budget is `maxUnavailable: "50%"` — up to half the pods can be evicted at a time, keeping at least half available. No PDB is created for `Development` or `Staging`.

**New validation:** The chart fails at render time if `environment` is `Production` or `DR` and effective replicas ≤ 1. These deployments must run at least 2 replicas (`replicaCount ≥ 2` or `autoscaling.minReplicas ≥ 2`).

### environment enum (breaking change)

The `environment` value is now restricted to four canonical values. Any other value fails schema validation.

**Before (v4):** any string was accepted (e.g. `environment: dev`, `environment: prod`, `environment: QA`).

**After (v5):**
```yaml
environment: Development  # default
environment: Staging
environment: Production
environment: DR
```

### Migration steps

1. Remove the `podDisruptionBudget:` block from your values.
2. Replace any non-standard `environment` value with the closest canonical equivalent.
3. Ensure `environment: Production` is set for production deployments.
4. Ensure `replicaCount ≥ 2` (or `autoscaling.minReplicas ≥ 2`) for production deployments.


## v3 → v4

### Ingress replaced with HTTPRoute (breaking change)

NGINX Ingress has been replaced with [Istio Gateway API](https://gateway-api.sigs.k8s.io/) `HTTPRoute`. The `ingress:` values block is removed; use `httpRoute:` instead.

**Before (v3):**
```yaml
ingress:
  create: true
  className: nginx
  hostname: my-app.example.com
  path: /
  pathType: Prefix
  annotations: {}
  proxyReadTimeout: "60"
  tls:
    enabled: false
    secretName: ""
```

**After (v4):**
```yaml
httpRoute:
  create: true
  hostname: my-app.example.com
  path: /
  pathType: PathPrefix
  annotations: {}
  timeout: "60s"
  parentRefs:
    - name: my-gateway
      namespace: istio-system
```

**Key differences:**

| Old (`ingress`)                       | New (`httpRoute`)           | Notes                                    |
|---------------------------------------|-----------------------------|------------------------------------------|
| `ingress.create`                      | `httpRoute.create`          |                                          |
| `ingress.className: nginx`            | `httpRoute.parentRefs`      | Reference your Gateway resource          |
| `ingress.hostname`                    | `httpRoute.hostname`        |                                          |
| `ingress.path`                        | `httpRoute.path`            |                                          |
| `ingress.pathType: Prefix`            | `httpRoute.pathType: PathPrefix` | New format per Gateway API          |
| `ingress.proxyReadTimeout: "60"`      | `httpRoute.timeout: "60s"`  | Gateway API duration format (e.g. `60s`, `5m`) |
| `ingress.tls`                         | _(removed)_                 | TLS is managed at the Gateway level      |

**`parentRefs` is required** when `httpRoute.create: true`. It specifies which `Gateway` resource the HTTPRoute attaches to.

**Prerequisites:**
- Istio (or another Gateway API implementation) must be installed in the cluster.
- A `Gateway` resource must exist and be referenced via `parentRefs`.

**Migration steps:**
1. Replace the `ingress:` block with `httpRoute:`.
2. Add `httpRoute.parentRefs` pointing to your Gateway (required).
3. Update `pathType: Prefix` → `pathType: PathPrefix`.
4. Replace `proxyReadTimeout: "60"` with `timeout: "60s"`.
5. Remove `ingress.tls` — configure TLS on the Gateway resource instead.
