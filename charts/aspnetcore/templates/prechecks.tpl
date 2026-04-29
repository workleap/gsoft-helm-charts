{{- if and .Values.httpRoute.create (not .Values.httpRoute.parentRefs) }}
    {{- fail "httpRoute.parentRefs is required when httpRoute.create is true" }}
{{- end }}
{{- if .Values.autoscaling.enabled }}
    {{- if not .Values.autoscaling.minReplicas }}
    {{- fail "autoscaling.minReplicas is required" }}
    {{- end }}
{{- end }}
{{- if include "aspnetcore.isProduction" . }}
    {{- $replicas := ternary (.Values.autoscaling.minReplicas | int) (.Values.replicaCount | int) .Values.autoscaling.enabled -}}
    {{- if le $replicas 1 }}
    {{- fail "production deployments require replicaCount > 1 (or autoscaling.minReplicas > 1)" }}
    {{- end }}
{{- end }}
