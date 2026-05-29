{{- define "tripplanning.initContainerResources" -}}
resources:
  requests:
    cpu: 10m
    memory: 16Mi
  limits:
    cpu: 50m
    memory: 32Mi
{{- end -}}

{{- define "tripplanning.waitForValkey" -}}
- name: wait-for-valkey
  image: busybox:1.36
  command:
    - sh
    - -c
    - until nc -z {{ .Values.backingServices.valkey.serviceName }} 6379; do echo "waiting for valkey..."; sleep 2; done
  {{- include "tripplanning.initContainerResources" . | nindent 2 }}
{{- end -}}

{{- define "tripplanning.waitForSearch" -}}
- name: wait-for-search
  image: busybox:1.36
  command:
    - sh
    - -c
    - until wget -qO- http://{{ .Values.backingServices.elasticsearch.serviceName }}:9200/_cluster/health?wait_for_status=yellow\&timeout=1s >/dev/null 2>&1; do echo "waiting for search..."; sleep 3; done
  {{- include "tripplanning.initContainerResources" . | nindent 2 }}
{{- end -}}
