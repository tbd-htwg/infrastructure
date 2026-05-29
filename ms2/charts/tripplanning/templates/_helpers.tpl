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

{{- define "tripplanning.tripReplicas" -}}
{{- if .Values.autoscaling.enabled -}}
{{ include "tripplanning.tripAutoscalingMinReplicas" . }}
{{- else -}}
{{ .Values.services.trip.replicas }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.socialReplicas" -}}
{{- if .Values.autoscaling.enabled -}}
{{ include "tripplanning.socialAutoscalingMinReplicas" . }}
{{- else -}}
{{ .Values.services.social.replicas }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.externalInfoReplicas" -}}
{{- if .Values.autoscaling.enabled -}}
{{ include "tripplanning.externalInfoAutoscalingMinReplicas" . }}
{{- else -}}
{{ .Values.services.externalInfo.replicas }}
{{- end -}}
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
{{- if hasKey .Values.autoscaling.trip "targetMemoryUtilizationPercentage" -}}
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

{{- define "tripplanning.socialAutoscalingMaxReplicas" -}}
{{- if .Values.autoscaling.social.maxReplicas -}}
{{ .Values.autoscaling.social.maxReplicas }}
{{- else -}}
{{ .Values.autoscaling.maxReplicas }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.externalInfoAutoscalingMinReplicas" -}}
{{- if .Values.autoscaling.externalInfo.minReplicas -}}
{{ .Values.autoscaling.externalInfo.minReplicas }}
{{- else -}}
{{ .Values.autoscaling.minReplicas }}
{{- end -}}
{{- end -}}

{{- define "tripplanning.externalInfoAutoscalingMaxReplicas" -}}
{{- if .Values.autoscaling.externalInfo.maxReplicas -}}
{{ .Values.autoscaling.externalInfo.maxReplicas }}
{{- else -}}
{{ .Values.autoscaling.maxReplicas }}
{{- end -}}
{{- end -}}
