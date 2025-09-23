{{- if .Values.autoscaling.enabled }}
    {{- if not .Values.autoscaling.minReplicas }}
    {{- fail "autoscaling.minReplicas is required" }}
    {{- else}}
        {{- if le (int .Values.autoscaling.minReplicas) (int .Values.podDisruptionBudget.minAvailable) }}
        {{- fail "autoscaling.minReplicas cannot be less than podDisruptionBudget.minAvailable" }}
        {{- end }}
    {{- end }}
{{- else}}
    {{- if gt (int .Values.replicaCount) 1 }}
        {{- if le (int .Values.replicaCount) (int .Values.podDisruptionBudget.minAvailable) }}
        {{- fail "replicaCount cannot be less or equal to podDisruptionBudget.minAvailable" }}
        {{- end }}
    {{- end }}
{{- end }}
