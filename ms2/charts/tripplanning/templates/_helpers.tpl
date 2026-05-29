{{- define "tripplanning.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tripplanning.fullname" -}}
{{- if .Values.global.fullnameOverride -}}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" (include "tripplanning.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "tripplanning.labels" -}}
app.kubernetes.io/name: {{ include "tripplanning.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: Helm
{{- end -}}

{{- define "tripplanning.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "tripplanning.tripAutoscalingMinReplicas" -}}
{{- if .Values.autoscaling.trip.minReplicas -}}
{{ .Values.autoscaling.trip.minReplicas }}
{{- else -}}
{{ .Values.autoscaling.minReplicas }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.tripAutoscalingMaxReplicas" -}}
{{- if .Values.autoscaling.trip.maxReplicas -}}
{{ .Values.autoscaling.trip.maxReplicas }}
{{- else -}}
{{ .Values.autoscaling.maxReplicas }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.tripAutoscalingTargetCPU" -}}
{{- if .Values.autoscaling.trip.targetCPUUtilizationPercentage -}}
{{ .Values.autoscaling.trip.targetCPUUtilizationPercentage }}
{{- else -}}
{{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.tripAutoscalingTargetMemory" -}}
{{- if .Values.autoscaling.trip.targetMemoryUtilizationPercentage -}}
{{ .Values.autoscaling.trip.targetMemoryUtilizationPercentage }}
{{- else -}}
{{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.socialAutoscalingMinReplicas" -}}
{{- if .Values.autoscaling.social.minReplicas -}}
{{ .Values.autoscaling.social.minReplicas }}
{{- else -}}
{{ .Values.autoscaling.minReplicas }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.externalInfoAutoscalingMinReplicas" -}}
{{- if .Values.autoscaling.externalInfo.minReplicas -}}
{{ .Values.autoscaling.externalInfo.minReplicas }}
{{- else -}}
{{ .Values.autoscaling.minReplicas }}
{{- end -}}
{{- end -}}
