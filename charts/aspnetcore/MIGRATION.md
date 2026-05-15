# Migration Guide

## v5.1 → v5.2

### Restricted security context preset, on by default (behavior change)

A new opinionated preset, `presets.restrictedSecurityContext`, is **enabled by default** in 5.2.0. When enabled, the chart applies a Pod Security Standards "Restricted" baseline to every pod and container it renders:

| Where | Field | Value |
|---|---|---|
| Pod   | `securityContext.runAsNonRoot`                | `true` |
| Container | `securityContext.allowPrivilegeEscalation` | `false` |
| Container | `securityContext.capabilities.drop`        | `["ALL"]` |

**Why this is the new default**

1. **Secure-by-default mandate.** The Infrastructure team owns this chart and the AKS clusters it deploys to. Workloads should be hardened by virtue of using the shared chart, not by every team remembering to copy a `securityContext` block into their values.
2. **Pod Security Standards alignment.** These three fields are the load-bearing part of the upstream Kubernetes PSS *Restricted* profile. Charts that already render these settings won't start failing schedule when cluster-layer Pod Security Admission turns on.
3. **Defense in depth on top of the image.** A Dockerfile `USER` directive is the primary non-root guarantee, but it's image-build-time and author-controlled. `runAsNonRoot: true` is the kubelet-enforced catch-all that refuses to start the pod if a future image accidentally drops `USER`. Dropping all capabilities removes the default container capability set (CHOWN, DAC_OVERRIDE, NET_RAW, SETUID, etc.) that HTTP workloads never need.

**What this might break**

Most modern ASP.NET Core, Node, and static-frontend images already satisfy this baseline. The two real failure modes are:

| Symptom | Cause | Fix |
|---|---|---|
| Pod fails to start: `container has runAsNonRoot and image will run as root` | The image has no `USER` directive (or `USER 0`) | Add `USER <non-root>` to the Dockerfile, or in values set `podSecurityContext: { runAsUser: <uid> }` |
| Workload can't bind its listening port | Workload binds a privileged port (<1024) and now has no `NET_BIND_SERVICE` capability | Preferred: change the workload to bind a port ≥ 1024. Alternative: in values, set `containerSecurityContext: { capabilities: { add: ["NET_BIND_SERVICE"] } }` (the chart merges this with the preset's drop-ALL) |

**How to extend, not override, the preset**

Two new passthrough values are merged on top of the preset (user keys win over preset keys):

```yaml
podSecurityContext:
  fsGroup: 2000          # added to the preset
  # runAsNonRoot: false  # would override the preset

containerSecurityContext:
  readOnlyRootFilesystem: true                # added to the preset
  capabilities:
    add: ["NET_BIND_SERVICE"]                 # merges with preset's drop: ["ALL"]
```

**How to opt out entirely**

Only with explicit justification — please document the reason in your values.yaml:

```yaml
presets:
  restrictedSecurityContext:
    enabled: false  # WHY: <reason this workload cannot run restricted>
```

The chart's existing `securityContext.enabled` (for sysctls) and `securityContext.sysctls` are unchanged and are merged into the pod-level securityContext alongside the preset.

### Migration steps

1. Run `helm template` against each consumer with v5.2.0 (`helm dependency update` + `helm template --version 5.2.0`) and diff against current output.
2. For any workload whose image runs as root, add a `USER` directive to the Dockerfile **or** add `podSecurityContext.runAsUser` in values.
3. For any workload binding a privileged port, prefer rebinding to a port ≥ 1024.
4. If a workload genuinely cannot run under the Restricted profile, set `presets.restrictedSecurityContext.enabled: false` and add an inline comment explaining why.


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
