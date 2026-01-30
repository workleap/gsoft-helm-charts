# Leap Deploy Generate Chart

**Action Path:** `.github/actions/generate-chart`

Generates a Helm chart (Chart.yaml and values.yaml) from a folded [leap-deploy](https://github.com/workleap/wl-leap-deploy) configuration, enabling atomic deployment of multiple workloads to Kubernetes. The generated chart creates a dependency on the [aspnetcore Helm Chart](https://github.com/workleap/gsoft-helm-charts/tree/main/charts/aspnetcore) for each workload.

## Features

- **Helm Chart Generation**: Creates a complete Helm chart structure with aspnetcore subchart dependencies for each workload
- **aspnetcore Integration**: Generated values.yaml conforms to the aspnetcore Helm Chart schema
- **Values Transformation**: Converts folded leap-deploy configuration into aspnetcore chart values format
- **Multi-Workload Support**: Generates subcharts for each workload (APIs, workers) defined in the configuration
- **Infrastructure Integration**: Incorporates infrastructure details (ACR registry name from infra-config) into chart values
- **Atomic Deployment**: Enables deploying all workloads together as a single Helm release

## Inputs

| Input                | Required | Default | Description                                                                                                  |
| -------------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------ |
| `chart-registry`     | Yes      | -       | The Helm chart repository URL for the aspnetcore chart (e.g., https://workleap.github.io/gsoft-helm-charts) |
| `chart-name`         | Yes      | -       | The name of the aspnetcore chart to use for workloads                                                        |
| `chart-version`      | No       | latest  | The version of the aspnetcore chart to use for workloads                                                     |
| `product-name`       | Yes      | -       | The product name                                                                                             |
| `leap-deploy-config` | Yes      | -       | The folded Leap Deploy configuration for the target environment/region                                       |
| `infra-config`       | Yes      | -       | The infrastructure configuration JSON string                                                                 |
| `environment`        | Yes      | -       | The environment name (e.g., dev, staging, prod)                                                              |
| `region`             | No       | -       | The region name (e.g., na, eu, etc.)                                                                         |

## Outputs

| Output            | Description                                                                  |
| ----------------- | ---------------------------------------------------------------------------- |
| `chart-directory` | The directory path containing the generated Chart.yaml and values.yaml files |

## Usage

### Basic Chart Generation

```yaml
- name: Generate Helm chart
  id: generate-chart
  uses: workleap/wl-leap-deploy/.github/actions/generate-chart@main
  with:
    chart-registry: https://workleap.github.io/gsoft-helm-charts
    chart-name: aspnetcore
    chart-version: "3.2.2"
    product-name: my-product
    leap-deploy-config: ${{ steps.fold.outputs.folded-config }}
    infra-config: ${{ steps.get-infra.outputs.infra-config }}
    environment: dev
    region: na

- name: View generated chart
  run: |
    ls -la ${{ steps.generate-chart.outputs.chart-directory }}
    cat ${{ steps.generate-chart.outputs.chart-directory }}/Chart.yaml
    cat ${{ steps.generate-chart.outputs.chart-directory }}/values.yaml
```

### Complete Deployment Pipeline

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Fold leap-deploy configuration
        id: fold
        uses: workleap/wl-leap-deploy/.github/actions/fold-config@main
        with:
          file-path: devops/leap-deploy.yaml
          environment: dev
          region: na

      - name: Generate Helm chart
        id: generate
        uses: workleap/wl-leap-deploy/.github/actions/generate-chart@main
        with:
          chart-registry: https://workleap.github.io/gsoft-helm-charts
          chart-name: aspnetcore
          chart-version: "3.2.2"
          product-name: ${{ vars.PRODUCT_NAME }}
          leap-deploy-config: ${{ steps.fold.outputs.folded-config }}
          infra-config: ${{ vars.INFRA_CONFIG }}
          environment: dev
          region: na

      - name: Deploy with Helm
        run: |
          helm upgrade --install my-release \
            ${{ steps.generate.outputs.chart-directory }} \
            --namespace my-namespace \
            --create-namespace \
            --wait
```

### Using Generated Chart in Subsequent Jobs

```yaml
jobs:
  generate:
    runs-on: ubuntu-latest
    outputs:
      chart-path: ${{ steps.generate.outputs.chart-directory }}
    steps:
      - name: Generate chart
        id: generate
        uses: workleap/wl-leap-deploy/.github/actions/generate-chart@main
        with:
          chart-registry: https://workleap.github.io/gsoft-helm-charts
          chart-name: aspnetcore
          chart-version: "3.2.2"
          product-name: my-product
          leap-deploy-config: ${{ steps.fold.outputs.folded-config }}
          infra-config: ${{ vars.INFRA_CONFIG }}
          environment: prod
          region: na

      - name: Upload chart artifact
        uses: actions/upload-artifact@v6
        with:
          name: helm-chart
          path: ${{ steps.generate.outputs.chart-directory }}

  deploy:
    needs: generate
    runs-on: ubuntu-latest
    steps:
      - name: Download chart
        uses: actions/download-artifact@v7
        with:
          name: helm-chart
          path: ./chart

      - name: Deploy
        run: helm upgrade --install my-release ./chart
```

## Generated Chart Structure

The action generates a Helm chart with the following structure:

```
chart-directory/
├── Chart.yaml          # Helm chart metadata with aspnetcore subchart dependencies
└── values.yaml         # Values conforming to aspnetcore chart schema
```

### How It Works

The generated chart creates a dependency on the [aspnetcore Helm Chart](https://github.com/workleap/gsoft-helm-charts/tree/main/charts/aspnetcore) for each workload defined in your leap-deploy configuration.

Each workload becomes a subchart with values that conform to the aspnetcore chart's schema. The action transforms the leap-deploy configuration into aspnetcore chart values:

| Leap-Deploy Schema | Aspnetcore Chart Values |
|-------------------|------------------------|
| `workload.replicas` | `replicaCount` |
| `workload.image.*` | `image.*` |
| `workload.ingress.fqdn` | `ingress.hostname` |
| `workload.ingress.pathPrefix` | `ingress.path` |
| `workload.kind == "api"` | `ingress.create = true` |
| `workload.kind == "worker"` | `ingress.create = false` |
| `workload.probes.*` | `readinessProbe`, `livenessProbe`, `startupProbe` |
| `workload.envVars` (object) | `extraEnvVars` (array) |
| `workload.autoscaling.horizontal.*` | `autoscaling.*` |
| `workload.labels` | `commonLabels` |
| `workload.annotations` | `commonAnnotations` |

### Chart.yaml Example

```yaml
apiVersion: v2
name: leap-deploy.generated
description: Leap Deploy Generated Chart
version: 1.0.0
dependencies:
  - name: aspnetcore
    repository: https://workleap.github.io/gsoft-helm-charts
    version: 3.2.2
    alias: demo-api
  - name: aspnetcore
    repository: https://workleap.github.io/gsoft-helm-charts
    version: 3.2.2
    alias: workleap-sample-worker
```

### values.yaml Example

```yaml
demo-api:
  environment: dev
  replicaCount: 3
  image:
    registry: myregistry.azurecr.io
    repository: my-app-api
    tag: v1.2.3
  ingress:
    create: true
    hostname: api.example.com
    path: /api
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
  commonAnnotations:
    apps.workleap.com/generated-by: wl-leap-deploy/generate-chart.ps1@abc1234

workleap-sample-worker:
  environment: dev
  replicaCount: 2
  image:
    registry: myregistry.azurecr.io
    repository: my-app-worker
    tag: v1.2.3
  ingress:
    create: false
  commonAnnotations:
    apps.workleap.com/generated-by: wl-leap-deploy/generate-chart.ps1@abc1234
```

## Input Requirements

### leap-deploy-config Format

Must be a folded configuration JSON (output from fold-config):

```json
{
  "id": "my-app",
  "workloads": {
    "api": {
      "kind": "api",
      "image": { "repository": "my-app", "tag": "v1.0.0" },
      "replicas": 3,
      "resources": { "requests": { "cpu": "200m", "memory": "256Mi" } }
    }
  }
}
```

### infra-config Format

Infrastructure configuration JSON. Currently used for future extensibility:

```json
{}
```

Note: Image registry should be specified directly in the workload configuration under `image.registry`.

## Troubleshooting

**PowerShell module errors:**

- The action automatically installs the `powershell-yaml` module if needed
- Ensure the runner has internet access to download PowerShell modules

**Invalid JSON inputs:**

- Verify that `leap-deploy-config` is valid JSON (use `jq` to validate)
- Check that the input contains all required fields

**Chart directory not found:**

- The action creates a temporary directory for the chart
- Access the chart immediately after generation or upload as an artifact
- The directory path is available via `chart-directory` output
