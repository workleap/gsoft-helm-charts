{{/* Selector labels */}}
{{- define "aspnetcore.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Standard Helm and Kubernetes labels */}}
{{- define "aspnetcore.standardLabels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "aspnetcore.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Dynamic service account name */}}
{{- define "aspnetcore.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
  {{- default (printf "%s-serviceaccount" .Release.Name) .Values.serviceAccount.name }}
{{- else }}
  {{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Standard Workleap annotations */}}
{{- define "workleap.standardAnnotations" -}}
workleap.com/git: {{ .Values.gitRepoUrl }}
{{- end }}
