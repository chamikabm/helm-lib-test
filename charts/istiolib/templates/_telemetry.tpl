{{- define "istiolib.telemetry" -}}
{{- with .Values.istio }}
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: mesh-telemetry-default
  namespace: istio-system
spec:
  {{- if .selector }}
  selector:
    matchLabels:
      {{- range $k, $v := .selector }}
      {{ $k }}: {{ $v }}
      {{- end }}
  {{- end }}
  tracing:
  - randomSamplingPercentage: {{ .randomSamplingPercentage | default 10.0 }}
{{- end }}
{{- end }}
