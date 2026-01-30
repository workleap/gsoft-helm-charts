#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Generates Helm Chart.yaml and values.yaml files based on folded leap-deploy configuration.

.DESCRIPTION
    Takes the folded configuration JSON and other variables to generate:
    - A Helm Chart.yaml file with dependencies for each workload
    - A values.yaml file with configuration values for each workload subchart

.PARAMETER ChartRegistry
    The Helm chart repository URL for the aspnetcore chart (e.g., https://workleap.github.io/gsoft-helm-charts).

.PARAMETER ChartName
    The name of the aspnetcore Helm chart to use.

.PARAMETER ChartVersion
    The version of the aspnetcore chart to use.

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
    The directory where the generated files will be written. If the directory does not exist, it will be created.
    Defaults to ".generated" if not specified.

.EXAMPLE
    ./generate-chart.ps1 -ChartRegistry 'https://workleap.github.io/gsoft-helm-charts' -ChartName 'aspnetcore' -ChartVersion '3.2.2' -ProductName 'foobar' -FoldedConfigJson '{"workloads": {...}}' -InfraConfigJson '{}' -Environment 'prod' -Region 'eastus' -OutputDirectory './output'
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
    [string]$OutputDirectory = ".generated"
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
    # Ensure powershell-yaml module is available
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

# Helper function to get chart version (handles "latest" by reading from Chart.yaml)
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

# Helper function to get JSON content (from string or file)
function Get-JsonContent {
    [OutputType([PSCustomObject])]
    param([string]$JsonInput)

    if ([string]::IsNullOrWhiteSpace($JsonInput)) {
        throw "JSON input is null or empty"
    }

    # Check if input looks like a file path
    if (Test-Path $JsonInput -PathType Leaf) {
        $content = Get-Content $JsonInput -Raw
        return $content | ConvertFrom-Json
    } else {
        return $JsonInput | ConvertFrom-Json
    }
}

# Helper function to add environment variable as annotation if present
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

# Function to build common annotations from environment variables
function Get-CommonAnnotations {
    [OutputType([PSCustomObject])]
    param()

    # Build common annotations for workload charts
    $annotations = [PSCustomObject]@{}

    # Generated-by annotation
    $annotations | Add-Member -NotePropertyName $ANNOTATION_WORKLEAP_GENERATED_BY -NotePropertyValue "wl-leap-deploy/${scriptName}@${scriptHash}"

    # GitHub annotations using the helper function
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

# Functions which creates an Helm Chart for the leap-deploy folded config - Generates one aspnetcore sub-chart dependency per workload
function New-LeapDeployChart {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$WorkloadNames,

        [Parameter(Mandatory = $true)]
        [string]$ChartName,

        [Parameter(Mandatory = $true)]
        [string]$ChartVersion,

        [Parameter(Mandatory = $true)]
        [string]$ChartRegistry
    )

    if ($WorkloadNames.Count -eq 0) {
        throw "WorkloadNames array cannot be empty"
    }

    # Build Chart.yaml as PSCustomObject
    $dependencies = @()
    foreach ($workloadName in $WorkloadNames) {
        $dependencies += [PSCustomObject]@{
            name       = $ChartName
            version    = $ChartVersion
            repository = $ChartRegistry
            alias      = $workloadName
        }
    }

    $chartObject = [PSCustomObject]@{
        apiVersion   = "v2"
        name         = "leap-deploy.generated"
        description  = "Leap Deploy Generated Chart"
        version      = "1.0.0"
        dependencies = $dependencies
    }

    return $chartObject
}

# Function to generate aspnetcore chart values from leap-deploy workload config
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
    # First add generated annotations
    foreach ($prop in $Annotations.PSObject.Properties) {
        $commonAnnotations | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
    }
    # Then add workload annotations (may override)
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

# Get script information for tracking
$scriptHash = (Get-FileHash -Path $PSCommandPath -Algorithm SHA1).Hash.Substring(0, 7)
$scriptName = [System.IO.Path]::GetFileName($PSCommandPath)
Write-Host "Running $scriptName (hash: $scriptHash)"

# Get chart version (handles "latest" by reading from Chart.yaml)
try {
    $ChartVersion = Get-ChartVersion -Version $ChartVersion
} catch {
    Write-Error "Failed to resolve chart version: $_"
    exit 1
}

# Parse and validate JSON inputs
try {
    Write-Host "Parsing configuration inputs..."
    $foldedConfig = Get-JsonContent $FoldedConfigJson
    $infraConfig = Get-JsonContent $InfraConfigJson
    Write-Host "Configuration inputs parsed successfully."
} catch {
    Write-Error "Failed to parse JSON configuration: $_"
    exit 1
}

# Validate configuration structure
try {
    Write-Host "Validating configuration structure..."

    # Validate that workloads exist
    if (-not $foldedConfig.PSObject.Properties['workloads']) {
        throw "Folded config must contain 'workloads' property"
    }

    # Get workload names sorted for consistent output
    # Wrap in @() to ensure we always get an array, even with a single workload
    $workloadNames = @($foldedConfig.workloads.PSObject.Properties | Select-Object -ExpandProperty Name | Sort-Object)

    if ($workloadNames.Count -eq 0) {
        throw "Folded config must contain at least one workload"
    }

    Write-Host "Found $($workloadNames.Count) workload(s): $($workloadNames -join ', ')"

    Write-Host "Configuration validation completed successfully."
} catch {
    Write-Error "Configuration validation failed: $_"
    exit 1
}

# Generate Chart.yaml
try {
    Write-Host "Generating Chart.yaml..."
    Write-Host "Using ${ChartRegistry}/${ChartName}:${ChartVersion} for each workload..."

    # Build Chart.yaml object
    $chartObject = New-LeapDeployChart `
        -WorkloadNames $workloadNames `
        -ChartName $ChartName `
        -ChartVersion $ChartVersion `
        -ChartRegistry $ChartRegistry

    Write-Host "Chart.yaml object created successfully."
} catch {
    Write-Error "Failed to generate Chart.yaml object: $_"
    exit 1
}

# Generate values.yaml
try {
    Write-Host "Generating values.yaml..."

    # Build values.yaml as PSCustomObject
    $valuesObject = [PSCustomObject]@{}

    $annotations = Get-CommonAnnotations

    # Add each workload's values under its alias
    foreach ($workloadName in $workloadNames) {
        Write-Host "  Processing workload: $workloadName"

        # Each workload matches a subchart alias with its own set of values
        $workload = $foldedConfig.workloads.$workloadName

        if (-not $workload) {
            throw "Workload '$workloadName' not found in folded config"
        }

        # Generate aspnetcore chart values from the workload config
        $workloadValues = New-AspNetCoreChartValues `
            -Workload $workload `
            -Annotations $annotations `
            -Environment $Environment

        # Add workload to values object
        $valuesObject | Add-Member -NotePropertyName $workloadName -NotePropertyValue $workloadValues
    }

    Write-Host "values.yaml object created successfully."
} catch {
    Write-Error "Failed to generate values.yaml object: $_"
    exit 1
}

# Write generated files to disk
try {
    Write-Host "Writing generated files to disk..."

    # Create output directory structure
    $templatesDir = Join-Path $OutputDirectory "templates"

    if (-not (Test-Path $OutputDirectory)) {
        Write-Host "Creating output directory: $OutputDirectory"
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    if (-not (Test-Path $templatesDir)) {
        New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
        # Create a placeholder file in templates directory
        Set-Content -Path (Join-Path $templatesDir ".gitkeep") -Value "# Placeholder for generated templates"
    }

    # Write the generated Chart.yaml content to output directory
    $chartOutputPath = Join-Path $OutputDirectory "Chart.yaml"
    $chartYaml = ConvertTo-Yaml $chartObject
    Set-Content -Path $chartOutputPath -Value $chartYaml
    Write-Host "Generated Chart.yaml written to: $chartOutputPath"

    # Write values.yaml to output directory
    $valuesOutputPath = Join-Path $OutputDirectory "values.yaml"
    $valuesYaml = ConvertTo-Yaml $valuesObject
    Set-Content -Path $valuesOutputPath -Value $valuesYaml
    Write-Host "Generated values.yaml written to: $valuesOutputPath"

    Write-Host "All files written successfully."
} catch {
    Write-Error "Failed to write generated files to disk: $_"
    exit 1
}

Write-Host "Chart generation completed successfully!"
