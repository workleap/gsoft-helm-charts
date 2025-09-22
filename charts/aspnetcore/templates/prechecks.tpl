{{- if .Values.autoscaling.enabled }}
    {{- if not .Values.autoscaling.minReplicas }}
    {{- fail "autoscaling.minReplicas is required" }}
    {{- else}}
        {{- if le (int .Values.autoscaling.minReplicas) (int .Values.podDisruptionBudget.minAvailable) }}
        {{- fail "autoscaling.minReplicas cannot be less than podDisruptionBudget.minAvailable" }}
        {{- end }}
    {{- end }}
{{- end }}

{{/* Pod Disruption Budget validation to prevent deadlock scenarios */}}
{{- $minAvailable := .Values.podDisruptionBudget.minAvailable }}
{{- $minAvailableStr := ($minAvailable | toString) }}
{{- $replicaCount := (.Values.replicaCount | int) }}
{{- $isPercentage := hasSuffix "%" $minAvailableStr }}

{{/* Check for potential PDB deadlock scenarios */}}
{{/* Skip validation when replicaCount=1 for backward compatibility (PDB won't be created anyway) */}}
{{- if and $minAvailable (gt $replicaCount 1) }}
    {{- if and (not $isPercentage) (ge ($minAvailable | int) $replicaCount) }}
        {{- fail "Pod Disruption Budget minAvailable cannot be greater than or equal to replicaCount as it will cause node drain deadlocks" }}
    {{- end }}
{{- end }}

