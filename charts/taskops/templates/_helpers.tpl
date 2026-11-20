{{- define "taskops.labels" -}}
app.kubernetes.io/part-of: taskops
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "taskops.image" -}}
{{ .Values.api.image.repository }}:{{ .Values.api.image.tag | default .Chart.AppVersion }}
{{- end -}}


{{/* Paramètres de connexion à la base selon le mode (CloudNativePG ou StatefulSet simple) */}}
{{- define "taskops.db" -}}
{{- if .Values.cnpg.enabled -}}
host: {{ .Values.cnpg.name }}-rw
user: {{ .Values.cnpg.owner }}
name: {{ .Values.cnpg.database }}
image: {{ .Values.cnpg.imageName }}
{{- else -}}
host: {{ .Values.postgres.name }}
user: {{ .Values.postgres.user }}
name: {{ .Values.postgres.database }}
image: {{ .Values.postgres.image }}
{{- end -}}
{{- end -}}
