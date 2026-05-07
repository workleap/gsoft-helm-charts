# Workleap generic Helm charts

This repository contains generic Helm charts available through GitHub Pages.


## Generic Helm chart for ASP.NET Core (and other HTTP workloads)

Despite its name, the [`aspnetcore`](charts/aspnetcore/) chart is a workload-agnostic chart for any HTTP service. Its defaults are tuned for ASP.NET Core (it bootstraps the [official ASP.NET Core sample application](https://hub.docker.com/_/microsoft-dotnet-samples) by default), but two flags — `aspnetcore.injectEnvVars` and `image.containerPort` — make it equally usable for Node.js, Python, Go, or any other HTTP workload.

The full reference for every value lives in [`charts/aspnetcore/values.yaml`](charts/aspnetcore/values.yaml).


### Resources deployed

The chart deploys the following resources:

| Resource                        | Created when                                                              | Notes                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `Deployment`                    | Always                                                                    | Single container, port `image.containerPort` (default `8080`).                                 |
| `Service`                       | Always                                                                    | `ClusterIP` on `service.port` (default `80`), targets the container port.                      |
| `HorizontalPodAutoscaler`       | `autoscaling.enabled` (default `true`)                                    | CPU-based; `minReplicas` / `maxReplicas` / `targetCPUUtilizationPercentage` configurable.      |
| `HTTPRoute` (Gateway API)       | `httpRoute.create` (default `true`)                                       | Requires `httpRoute.parentRefs`. Replaces the NGINX `Ingress` from earlier majors.             |
| `PodDisruptionBudget`           | Automatic in `Production` / `DR` when effective replicas > 1              | Fixed `maxUnavailable: 50%`. See [Automatic behaviors](#automatic-behaviors).                  |
| `ServiceAccount`                | `serviceAccount.create` (default `false`)                                 | Supports Azure Workload Identity via `azureWorkloadIdentity.enabled` + `clientId`.             |
| `AzureIdentityBinding`          | `aadPodIdentityBinding.create` (default `false`)                          | Deprecated — use Azure Workload Identity instead.                                              |


### Automatic behaviors

The chart applies a few opinionated defaults so callers don't have to reason about availability primitives manually.

- **Environment enum validation.** `environment` must be one of `Development`, `Staging`, `Production`, `DR`. Helm fails the render on any other value (enforced via `values.schema.json`).
- **Production / DR replica precheck.** If `environment` is `Production` or `DR` and effective replicas (autoscaling.minReplicas when HPA is enabled, otherwise `replicaCount`) are ≤ 1, the render fails with a clear message. Note: the `Deployment.spec.replicas` is always set from `replicaCount`, so when HPA is enabled you should keep `replicaCount` ≥ `autoscaling.minReplicas` to avoid initially rolling out a single replica before the HPA reconciles.
- **Automatic PodDisruptionBudget.** A `PodDisruptionBudget` with `maxUnavailable: 50%` is created automatically when `environment` is `Production` or `DR` and effective replicas > 1. No PDB is created in `Development` or `Staging`. There is no manual `podDisruptionBudget` block to configure.
- **Default node-spread topology.** When `topologySpreadConstraints` is unset, the `presets.spreadAcrossNodes` preset (enabled by default) applies a best-effort `maxSkew: 1` constraint on `kubernetes.io/hostname`. Setting `topologySpreadConstraints` explicitly overrides the preset.
- **Conditional .NET env injection.** When `aspnetcore.injectEnvVars` is `true` (default), the chart injects `DOTNET_ENVIRONMENT` (from `environment`) and `ASPNETCORE_URLS` (computed from `image.containerPort`) into the container. Set it to `false` for non-.NET workloads — the env block is omitted entirely if no `extraEnvVars` are provided either.


### Installing the chart

The recommended way is to add this chart [as a dependency of your chart](https://helm.sh/docs/helm/helm_dependency/):

```yaml
apiVersion: v2
name: your-chart
description: Your chart description
version: 1.0.0
dependencies:
  - name: aspnetcore
    alias: aspnetcore
    version: 5.1.0
    repository: https://workleap.github.io/gsoft-helm-charts
```

Then, in your `values.yaml` file, override the default values (see the sections below). Finally, deploy your chart using the `--dependency-update` flag:

```bash
helm upgrade --install --atomic --cleanup-on-fail --debug --dependency-update [...more options] ./your-chart/
```


### ASP.NET Core usage

A minimal `values.yaml` for an ASP.NET Core service:

```yaml
aspnetcore:
  environment: Production
  image:
    registry: your-registry.com
    repository: your-repository
    tag: "1.0.0"
  httpRoute:
    hostname: api.example.com
    parentRefs:
      - name: shared-gateway
        namespace: istio-system
```

`DOTNET_ENVIRONMENT` (set to `Production`) and `ASPNETCORE_URLS` (set to `http://+:8080`) are injected automatically — you do not need to configure them.


### Non-.NET workloads

For non-.NET workloads, disable the .NET env injection and set the container port your app listens on. The chart still creates an `HTTPRoute` by default, so configure `httpRoute.parentRefs` (or set `httpRoute.create: false` if your routing is managed elsewhere):

```yaml
aspnetcore:
  aspnetcore:
    injectEnvVars: false
  image:
    registry: your-registry.com
    repository: your-repository
    tag: "1.0.0"
    containerPort: 3000
  httpRoute:
    hostname: api.example.com
    parentRefs:
      - name: shared-gateway
        namespace: istio-system
```

Callers typically also configure their own `readinessProbe` / `livenessProbe` and `extraEnvVars`. A full working example (Node.js HTTP echo server) is at [`charts/aspnetcore/tests/values-nondotnet.yaml`](charts/aspnetcore/tests/values-nondotnet.yaml).


### Most-used values

A curated reference for the values most commonly set. The full list — including probes, volumes, certificate store, security context, migration helpers, and more — is documented inline in [`charts/aspnetcore/values.yaml`](charts/aspnetcore/values.yaml).

#### Image

| Key                  | Default                  | Description                                                                 |
| -------------------- | ------------------------ | --------------------------------------------------------------------------- |
| `image.registry`     | `mcr.microsoft.com`      | Image registry.                                                             |
| `image.repository`   | `dotnet/samples`         | Image repository.                                                           |
| `image.tag`          | `aspnetapp`              | Image tag (immutable tags are recommended).                                 |
| `image.pullPolicy`   | `IfNotPresent`           | Image pull policy.                                                          |
| `image.containerPort`| `8080`                   | Port the container listens on. Used by the Service and `ASPNETCORE_URLS`.   |

#### Workload

| Key                          | Default       | Description                                                                                          |
| ---------------------------- | ------------- | ---------------------------------------------------------------------------------------------------- |
| `replicaCount`               | `2`           | Replicas when HPA is disabled. Required ≥ 2 in `Production` / `DR` (or use `autoscaling.minReplicas`). |
| `environment`                | `Development` | One of `Development`, `Staging`, `Production`, `DR`. Drives PDB creation and `DOTNET_ENVIRONMENT`.   |
| `aspnetcore.injectEnvVars`   | `true`        | Inject `DOTNET_ENVIRONMENT` and `ASPNETCORE_URLS`. Set `false` for non-.NET workloads.               |
| `extraEnvVars`               | `[]`          | Additional env vars. Only `name` / `value` entries are rendered today (`valueFrom` is permitted by the schema but not emitted by the template). |
| `resources`                  | see values    | Container requests/limits. Defaults: `50m` CPU request, `128Mi` memory request and limit.           |

#### Networking

| Key                       | Default                    | Description                                                                                                  |
| ------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `service.port`            | `80`                       | Service port; targets the container port.                                                                    |
| `httpRoute.create`        | `true`                     | Create the Gateway API `HTTPRoute`.                                                                          |
| `httpRoute.hostname`      | `aspnetcore.example.local` | Hostname for the route.                                                                                      |
| `httpRoute.parentRefs`    | `[]`                       | **Required when `create` is `true`.** List of parent Gateways (`name`, optional `namespace`, `sectionName`). |
| `httpRoute.path`          | `/`                        | Default path match.                                                                                          |
| `httpRoute.pathType`      | `PathPrefix`               | One of `Exact`, `PathPrefix`, `RegularExpression`.                                                            |
| `httpRoute.timeout`       | `""`                       | Request timeout in Gateway API duration format (e.g. `60s`, `5m`). Empty uses the gateway/mesh defaults.     |

#### Scaling and availability

| Key                                            | Default | Description                                                                |
| ---------------------------------------------- | ------- | -------------------------------------------------------------------------- |
| `autoscaling.enabled`                          | `true`  | Create the `HorizontalPodAutoscaler`.                                       |
| `autoscaling.minReplicas`                      | `2`     | Minimum replicas. Required when `autoscaling.enabled` is `true`.           |
| `autoscaling.maxReplicas`                      | `3`     | Maximum replicas.                                                           |
| `autoscaling.targetCPUUtilizationPercentage`   | `80`    | CPU utilization target.                                                     |

PDB creation is automatic and not configurable via values — see [Automatic behaviors](#automatic-behaviors).

#### Identity

| Key                                | Default | Description                                                                                       |
| ---------------------------------- | ------- | ------------------------------------------------------------------------------------------------- |
| `serviceAccount.create`            | `false` | Create a `ServiceAccount`.                                                                        |
| `azureWorkloadIdentity.enabled`    | `false` | Add the `azure.workload.identity/use` pod label and (when `serviceAccount.create: true`) annotate the chart-managed ServiceAccount with the workload identity client ID. The chart's documented usage assumes `serviceAccount.create: true`. |
| `azureWorkloadIdentity.clientId`   | `""`    | Azure AD application client ID for the workload identity.                                         |


### Values schema

The chart includes a JSON schema file [`charts/aspnetcore/values.schema.json`](charts/aspnetcore/values.schema.json) that defines the structure and validation rules for the values, including type validation, enum constraints (e.g. `environment`), and property descriptions.

> **Important**: When making changes to the values definition in `values.yaml`, ensure that the corresponding `values.schema.json` file is updated to maintain consistency and proper validation.


### Migration

See [`charts/aspnetcore/MIGRATION.md`](charts/aspnetcore/MIGRATION.md) for upgrade notes between major versions.


## Release and versioning process

* Commit your changes on a new branch.
* In the same branch, manually bump the version property in `charts/<affected-chartname>/Chart.yaml` by following [SemVer](https://semver.org/) guidelines.
* Create a pull request and go through the review process.
* When the pull request is merged back in the main branch, the following workflows are automatically triggered:
  1. [Release charts](.github/workflows/release-charts.yml): packages the updated chart, creates a GitHub release and updates the public Helm [index.yaml](pages/index.yaml) repository file. This has no effect if no chart version was changed.
  2. [Deploy pages](.github/workflows/deploy-pages.yml): deploy the latest [index.yaml](https://workleap.github.io/gsoft-helm-charts/index.yaml) file to GitHub Pages.


## License

Copyright © 2025, Workleap Technologies. This code is licensed under the Apache License, Version 2.0.
