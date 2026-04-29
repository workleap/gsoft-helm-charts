{{- if and .Values.httpRoute.create (not .Values.httpRoute.parentRefs) }}
    {{- fail "httpRoute.parentRefs is required when httpRoute.create is true" }}
{{- end }}
{{- if .Values.autoscaling.enabled }}
    {{- if not .Values.autoscaling.minReplicas }}
    {{- fail "autoscaling.minReplicas is required" }}
    {{- end }}
{{- end }}
{{- if include "aspnetcore.requiresPDB" . }}
    {{- $replicas := ternary (.Values.autoscaling.minReplicas | int) (.Values.replicaCount | int) .Values.autoscaling.enabled -}}
    {{- if le $replicas 1 }}
    {{- fail "Production and DR deployments require replicaCount > 1 (or autoscaling.minReplicas > 1)" }}
    {{- end }}
{{- end }}
