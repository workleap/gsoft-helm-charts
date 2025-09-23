{{- if .Values.autoscaling.enabled }}
    {{- if not .Values.autoscaling.minReplicas }}
    {{- fail "autoscaling.minReplicas is required" }}
    {{- else}}
        {{- if le (int .Values.autoscaling.minReplicas) (int .Values.podDisruptionBudget.minAvailable) }}
        {{- fail "autoscaling.minReplicas cannot be less than podDisruptionBudget.minAvailable" }}
        {{- end }}
    {{- end }}
{{- end }}
