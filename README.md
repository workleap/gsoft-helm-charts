# Workleap generic Helm charts

This repository contains generic Helm charts available through GitHub Pages.


## Generic Helm chart for ASP.NET Core

By default, this chart bootstraps the [official ASP.NET Core sample application](https://hub.docker.com/_/microsoft-dotnet-samples).

Please read the documented [`charts/aspnetcore/values.yaml`](charts/aspnetcore/values.yaml) file to understand how to override default values in order to deploy your own ASP.NET Core application.


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
    version: 3.1.0
    repository: https://workleap.github.io/gsoft-helm-charts
```

Then, in your `values.yaml` file, override the default values:

```yaml
aspnetcore:
  image:
    registry: your-registry.com
    repository: your-repository

# [...]
```
Finally, deploy your chart using the `--dependency-update` flag:

```bash
helm upgrade --install --atomic --cleanup-on-fail --debug --dependency-update [...more options] ./your-chart/
```


## Release and versioning process

* Commit your changes on a new branch.
* In the same branch, manually bump the version property in `charts/<affected-chartname>/Chart.yaml` by following [SemVer](https://semver.org/) guidelines.
* Create a pull request and go through the review process.
* When the pull request is merged back in the main branch, the following workflows are automatically triggered:
  1. [Release charts](.github/workflows/release-charts.yml): packages the updated chart, creates a GitHub release and updates the public Helm [index.yaml](pages/index.yaml) repository file. This has no effect if no chart version was changed.
  2. [Deploy pages](.github/workflows/deploy-pages.yml): deploy the latest [index.yaml](https://workleap.github.io/gsoft-helm-charts/index.yaml) file to GitHub Pages.


## License

Copyright © 2025, Workleap Technologies. This code is licensed under the Apache License, Version 2.0.
