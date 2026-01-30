#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Generates individual umbrella Helm charts for each workload from folded leap-deploy configuration.

.DESCRIPTION
    Takes the folded configuration JSON and generates a separate umbrella chart for each workload.
    Each chart wraps the aspnetcore chart as a dependency with alias "aspnetcore".

    Output structure:
    out/charts/
    ├── demo-api/
    │   ├── Chart.yaml
    │   └── values.yaml
    └── workleap-sample-worker/
        ├── Chart.yaml
        └── values.yaml

    This allows deploying each workload as a separate Helm release:
    helm upgrade --install demo-api out/charts/demo-api

.PARAMETER ChartRegistry
    The Helm chart repository URL (e.g., https://workleap.github.io/gsoft-helm-charts).

.PARAMETER ChartName
    The name of the Helm chart to use as dependency (e.g., aspnetcore).

.PARAMETER ChartVersion
    The version of the dependency chart to use.

.PARAMETER ProductName
    The product name. Used for referencing the workload identity service account.

.PARAMETER FoldedConfigJson
    The folded configuration JSON string containing workload definitions.

.PARAMETER InfraConfigJson
    The infrastructure configuration JSON string.

.PARAMETER Environment
    The environment name (e.g., dev, staging, prod).

.PARAMETER Region
    The Azure region name.

.PARAMETER OutputDirectory
    The directory where the generated files will be written. Each workload will have its own subdirectory.
    Defaults to "./out/charts" if not specified.

.EXAMPLE
    ./generate-multiple-charts.ps1 -ChartRegistry 'https://workleap.github.io/gsoft-helm-charts' -ChartName 'aspnetcore' -ChartVersion '3.2.2' -ProductName 'foobar' -FoldedConfigJson '{"workloads": {...}}' -InfraConfigJson '{}' -Environment 'prod' -Region 'eastus'

    # Then deploy each workload separately:
    helm dependency build out/charts/demo-api && helm upgrade --install demo-api out/charts/demo-api
    helm dependency build out/charts/workleap-sample-worker && helm upgrade --install workleap-sample-worker out/charts/workleap-sample-worker
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ChartRegistry,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ChartName,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$ChartVersion,

    [Parameter(Mandatory = $true, Position = 3)]
    [string]$ProductName,

    [Parameter(Mandatory = $true, Position = 4)]
    [string]$FoldedConfigJson,

    [Parameter(Mandatory = $true, Position = 5)]
    [string]$InfraConfigJson,

    [Parameter(Mandatory = $true, Position = 6)]
    [string]$Environment,

    [Parameter(Mandatory = $false, Position = 7)]
    [string]$Region,

    [Parameter(Mandatory = $false, Position = 8)]
    [string]$OutputDirectory = "./out/charts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Module version constants
$POWERSHELL_YAML_VERSION = "0.4.12"

# Annotation constants
$ANNOTATION_GITHUB_REPO = "workleap.github.com/repo"
$ANNOTATION_GITHUB_RUN_ID = "workleap.github.com/run-id"
$ANNOTATION_GITHUB_WORKFLOW_REF = "workleap.github.com/workflow"
$ANNOTATION_GITHUB_SHA = "workleap.github.com/commit-sha"
$ANNOTATION_GITHUB_ACTOR = "workleap.github.com/actor"
$ANNOTATION_WORKLEAP_GENERATED_BY = "apps.workleap.com/generated-by"

# ========================================
# Module Installation and Import
# ========================================
try {
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-Host "Installing powershell-yaml module..."
        Install-Module -Name powershell-yaml -RequiredVersion $POWERSHELL_YAML_VERSION -Force -Scope CurrentUser -Repository PSGallery
    }
    Import-Module powershell-yaml
} catch {
    Write-Error "Failed to install or import required PowerShell modules: $_"
    exit 1
}

# ========================================
# Helper Functions
# ========================================

function Get-ChartVersion {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if ($Version -ne "latest") {
        return $Version
    }

    $scriptDir = Split-Path -Parent $PSCommandPath
    $chartFilePath = Join-Path $scriptDir "Chart.yaml"

    if (-not (Test-Path $chartFilePath)) {
        throw "ChartVersion is 'latest' but Chart.yaml not found at: $chartFilePath"
    }

    $chartContent = Get-Content $chartFilePath -Raw | ConvertFrom-Yaml
    $resolvedVersion = $chartContent.version

    Write-Host "Resolved 'latest' chart version to: $resolvedVersion"
    return $resolvedVersion
}

function Get-JsonContent {
    [OutputType([PSCustomObject])]
    param([string]$JsonInput)

    if ([string]::IsNullOrWhiteSpace($JsonInput)) {
        throw "JSON input is null or empty"
    }

    if (Test-Path $JsonInput -PathType Leaf) {
        $content = Get-Content $JsonInput -Raw
        return $content | ConvertFrom-Json
    } else {
        return $JsonInput | ConvertFrom-Json
    }
}

function Add-EnvironmentAnnotation {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AnnotationObject,

        [Parameter(Mandatory = $true)]
        [string]$AnnotationKey,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentVariableName,

        [Parameter(Mandatory = $false)]
        [string]$WarningMessage
    )

    $value = [Environment]::GetEnvironmentVariable($EnvironmentVariableName)
    if (-not $value) {
        if ($WarningMessage) {
            Write-Warning $WarningMessage
        } else {
            Write-Warning "$EnvironmentVariableName environment variable is not set. $AnnotationKey annotation will be omitted."
        }
    } else {
        $AnnotationObject | Add-Member -NotePropertyName $AnnotationKey -NotePropertyValue $value
    }
}

function Get-CommonAnnotations {
    [OutputType([PSCustomObject])]
    param()

    $annotations = [PSCustomObject]@{}

    $annotations | Add-Member -NotePropertyName $ANNOTATION_WORKLEAP_GENERATED_BY -NotePropertyValue "wl-leap-deploy/${scriptName}@${scriptHash}"

    $githubServerUrl = $env:GITHUB_SERVER_URL
    $githubRepository = $env:GITHUB_REPOSITORY

    if (-not $githubServerUrl -or -not $githubRepository) {
        if (-not $githubServerUrl) {
            Write-Warning "GITHUB_SERVER_URL environment variable is not set. Repository annotation will be omitted."
        }
        if (-not $githubRepository) {
            Write-Warning "GITHUB_REPOSITORY environment variable is not set. Repository annotation will be omitted."
        }
    } else {
        $repoUrl = "$githubServerUrl/$githubRepository"
        $annotations | Add-Member -NotePropertyName $ANNOTATION_GITHUB_REPO -NotePropertyValue $repoUrl
    }

    Add-EnvironmentAnnotation -AnnotationObject $annotations -AnnotationKey $ANNOTATION_GITHUB_RUN_ID -EnvironmentVariableName 'GITHUB_RUN_ID'
    Add-EnvironmentAnnotation -AnnotationObject $annotations -AnnotationKey $ANNOTATION_GITHUB_WORKFLOW_REF -EnvironmentVariableName 'GITHUB_WORKFLOW_REF'
    Add-EnvironmentAnnotation -AnnotationObject $annotations -AnnotationKey $ANNOTATION_GITHUB_SHA -EnvironmentVariableName 'GITHUB_SHA'
    Add-EnvironmentAnnotation -AnnotationObject $annotations -AnnotationKey $ANNOTATION_GITHUB_ACTOR -EnvironmentVariableName 'GITHUB_ACTOR'

    return $annotations
}

# Function to create an umbrella Chart.yaml for a single workload
function New-WorkloadChart {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkloadName,

        [Parameter(Mandatory = $true)]
        [string]$ChartName,

        [Parameter(Mandatory = $true)]
        [string]$ChartVersion,

        [Parameter(Mandatory = $true)]
        [string]$ChartRegistry
    )

    $chartObject = [PSCustomObject]@{
        apiVersion   = "v2"
        name         = $WorkloadName
        description  = "Workleap chart for ASP.NET Core web API"
        version      = "1.0.0"
        dependencies = @(
            [PSCustomObject]@{
                name       = $ChartName
                alias      = "aspnetcore"
                version    = $ChartVersion
                repository = $ChartRegistry
            }
        )
    }

    return $chartObject
}

function New-AspNetCoreChartValues {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Workload,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Annotations,

        [Parameter(Mandatory = $true)]
        [string]$Environment
    )

    if (-not $Workload) {
        throw "Workload parameter cannot be null"
    }

    $values = [PSCustomObject]@{}

    # Replica count
    if ($Workload.PSObject.Properties['replicas']) {
        $values | Add-Member -NotePropertyName 'replicaCount' -NotePropertyValue $Workload.replicas
    }

    # Environment
    $values | Add-Member -NotePropertyName 'environment' -NotePropertyValue $Environment

    # Image configuration
    $image = [PSCustomObject]@{}
    if ($Workload.PSObject.Properties['image']) {
        if ($Workload.image.PSObject.Properties['repository']) {
            $image | Add-Member -NotePropertyName 'repository' -NotePropertyValue $Workload.image.repository
        }
        if ($Workload.image.PSObject.Properties['tag']) {
            $image | Add-Member -NotePropertyName 'tag' -NotePropertyValue $Workload.image.tag
        }
        if ($Workload.image.PSObject.Properties['registry']) {
            $image | Add-Member -NotePropertyName 'registry' -NotePropertyValue $Workload.image.registry
        }
    }
    if (($image.PSObject.Properties | Measure-Object).Count -gt 0) {
        $values | Add-Member -NotePropertyName 'image' -NotePropertyValue $image
    }

    # Ingress (based on kind)
    $ingress = [PSCustomObject]@{
        create = ($Workload.kind -eq 'api')
    }
    if ($Workload.PSObject.Properties['ingress'] -and $Workload.ingress) {
        if ($Workload.ingress.PSObject.Properties['fqdn']) {
            $ingress | Add-Member -NotePropertyName 'hostname' -NotePropertyValue $Workload.ingress.fqdn
        }
        if ($Workload.ingress.PSObject.Properties['pathPrefix']) {
            $ingress | Add-Member -NotePropertyName 'path' -NotePropertyValue $Workload.ingress.pathPrefix
        }
        if ($Workload.ingress.PSObject.Properties['annotations']) {
            $ingress | Add-Member -NotePropertyName 'annotations' -NotePropertyValue $Workload.ingress.annotations
        }
    }
    $values | Add-Member -NotePropertyName 'ingress' -NotePropertyValue $ingress

    # Resources
    if ($Workload.PSObject.Properties['resources']) {
        $values | Add-Member -NotePropertyName 'resources' -NotePropertyValue $Workload.resources
    }

    # Probes
    if ($Workload.PSObject.Properties['probes'] -and $Workload.probes) {
        if ($Workload.probes.PSObject.Properties['readiness']) {
            $values | Add-Member -NotePropertyName 'readinessProbe' -NotePropertyValue $Workload.probes.readiness
        }
        if ($Workload.probes.PSObject.Properties['liveness']) {
            $values | Add-Member -NotePropertyName 'livenessProbe' -NotePropertyValue $Workload.probes.liveness
        }
        if ($Workload.probes.PSObject.Properties['startup']) {
            $values | Add-Member -NotePropertyName 'startupProbe' -NotePropertyValue $Workload.probes.startup
        }
    }

    # Environment variables (transform object to array)
    if ($Workload.PSObject.Properties['envVars'] -and $Workload.envVars) {
        $extraEnvVars = @()
        foreach ($prop in $Workload.envVars.PSObject.Properties) {
            $extraEnvVars += [PSCustomObject]@{
                name  = $prop.Name
                value = $prop.Value
            }
        }
        $values | Add-Member -NotePropertyName 'extraEnvVars' -NotePropertyValue $extraEnvVars
    }

    # Autoscaling
    if ($Workload.PSObject.Properties['autoscaling'] -and $Workload.autoscaling) {
        $autoscaling = [PSCustomObject]@{}
        if ($Workload.autoscaling.PSObject.Properties['horizontal']) {
            $h = $Workload.autoscaling.horizontal
            if ($h.PSObject.Properties['enabled']) {
                $autoscaling | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $h.enabled
            }
            if ($h.PSObject.Properties['minReplicas']) {
                $autoscaling | Add-Member -NotePropertyName 'minReplicas' -NotePropertyValue $h.minReplicas
            }
            if ($h.PSObject.Properties['maxReplicas']) {
                $autoscaling | Add-Member -NotePropertyName 'maxReplicas' -NotePropertyValue $h.maxReplicas
            }
        }
        if (($autoscaling.PSObject.Properties | Measure-Object).Count -gt 0) {
            $values | Add-Member -NotePropertyName 'autoscaling' -NotePropertyValue $autoscaling
        }
    }

    # Labels -> commonLabels
    if ($Workload.PSObject.Properties['labels']) {
        $values | Add-Member -NotePropertyName 'commonLabels' -NotePropertyValue $Workload.labels
    }

    # Annotations -> commonAnnotations (merge with generated annotations)
    $commonAnnotations = [PSCustomObject]@{}
    foreach ($prop in $Annotations.PSObject.Properties) {
        $commonAnnotations | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
    }
    if ($Workload.PSObject.Properties['annotations']) {
        foreach ($prop in $Workload.annotations.PSObject.Properties) {
            if ($commonAnnotations.PSObject.Properties[$prop.Name]) {
                $commonAnnotations.($prop.Name) = $prop.Value
            } else {
                $commonAnnotations | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
            }
        }
    }
    $values | Add-Member -NotePropertyName 'commonAnnotations' -NotePropertyValue $commonAnnotations

    return $values
}

# ========================================
# Main Script Execution
# ========================================

$scriptHash = (Get-FileHash -Path $PSCommandPath -Algorithm SHA1).Hash.Substring(0, 7)
$scriptName = [System.IO.Path]::GetFileName($PSCommandPath)
Write-Host "Running $scriptName (hash: $scriptHash)"

# Get chart version (handles "latest")
try {
    $ChartVersion = Get-ChartVersion -Version $ChartVersion
} catch {
    Write-Error "Failed to resolve chart version: $_"
    exit 1
}

# Parse JSON inputs
try {
    Write-Host "Parsing configuration inputs..."
    $foldedConfig = Get-JsonContent $FoldedConfigJson
    $infraConfig = Get-JsonContent $InfraConfigJson
    Write-Host "Configuration inputs parsed successfully."
} catch {
    Write-Error "Failed to parse JSON configuration: $_"
    exit 1
}

# Validate configuration
try {
    Write-Host "Validating configuration structure..."

    if (-not $foldedConfig.PSObject.Properties['workloads']) {
        throw "Folded config must contain 'workloads' property"
    }

    $workloadNames = @($foldedConfig.workloads.PSObject.Properties | Select-Object -ExpandProperty Name | Sort-Object)

    if ($workloadNames.Count -eq 0) {
        throw "Folded config must contain at least one workload"
    }

    Write-Host "Found $($workloadNames.Count) workload(s): $($workloadNames -join ', ')"
} catch {
    Write-Error "Configuration validation failed: $_"
    exit 1
}

# Generate umbrella charts for each workload
try {
    Write-Host "Generating umbrella charts for each workload..."

    $annotations = Get-CommonAnnotations

    # Create base output directory
    if (-not (Test-Path $OutputDirectory)) {
        Write-Host "Creating output directory: $OutputDirectory"
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    # Process each workload
    foreach ($workloadName in $workloadNames) {
        Write-Host "  Processing workload: $workloadName"

        $workload = $foldedConfig.workloads.$workloadName

        if (-not $workload) {
            throw "Workload '$workloadName' not found in folded config"
        }

        # Create workload directory
        $workloadDir = Join-Path $OutputDirectory $workloadName
        if (-not (Test-Path $workloadDir)) {
            New-Item -ItemType Directory -Path $workloadDir -Force | Out-Null
        }

        # Generate Chart.yaml for this workload
        $chartObject = New-WorkloadChart `
            -WorkloadName $workloadName `
            -ChartName $ChartName `
            -ChartVersion $ChartVersion `
            -ChartRegistry $ChartRegistry

        $chartOutputPath = Join-Path $workloadDir "Chart.yaml"
        $chartYaml = ConvertTo-Yaml $chartObject
        Set-Content -Path $chartOutputPath -Value $chartYaml
        Write-Host "    Generated: $chartOutputPath"

        # Generate values for this workload (nested under "aspnetcore" alias)
        $workloadValues = New-AspNetCoreChartValues `
            -Workload $workload `
            -Annotations $annotations `
            -Environment $Environment

        # Wrap values under the "aspnetcore" alias key
        $valuesObject = [PSCustomObject]@{
            aspnetcore = $workloadValues
        }

        # Write values.yaml
        $valuesOutputPath = Join-Path $workloadDir "values.yaml"
        $valuesYaml = ConvertTo-Yaml $valuesObject
        Set-Content -Path $valuesOutputPath -Value $valuesYaml
        Write-Host "    Generated: $valuesOutputPath"
    }

    Write-Host ""
    Write-Host "Generation completed successfully!"
    Write-Host ""
    Write-Host "To deploy each workload separately, run:"
    Write-Host ""
    foreach ($workloadName in $workloadNames) {
        Write-Host "  helm dependency build $OutputDirectory/$workloadName && helm upgrade --install $workloadName $OutputDirectory/$workloadName"
    }
    Write-Host ""

} catch {
    Write-Error "Failed to generate umbrella charts: $_"
    exit 1
}
