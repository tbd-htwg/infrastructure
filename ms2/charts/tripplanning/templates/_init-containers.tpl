{{- define "tripplanning.waitForValkey" -}}
- name: wait-for-valkey
  image: busybox:1.36
  command:
    - sh
    - -c
    - until nc -z {{ .Values.backingServices.valkey.serviceName }} 6379; do echo "waiting for valkey..."; sleep 2; done
{{- end -}}

{{- define "tripplanning.waitForSearch" -}}
- name: wait-for-search
  image: busybox:1.36
  command:
    - sh
    - -c
    - until wget -qO- http://{{ .Values.backingServices.elasticsearch.serviceName }}:9200/_cluster/health?wait_for_status=yellow\&timeout=1s >/dev/null 2>&1; do echo "waiting for search..."; sleep 3; done
{{- end -}}
