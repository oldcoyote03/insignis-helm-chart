{{/*
Expand the name of the chart.
*/}}
{{- define "insignis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "insignis.fullname" -}}
{{- if .Values.fullnameOverride }}
    {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
    {{- $name := default .Chart.Name .Values.nameOverride }}
    {{- if contains $name .Release.Name }}
        {{- .Release.Name | trunc 63 | trimSuffix "-" }}
    {{- else }}
        {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "insignis.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "insignis.labels" -}}
helm.sh/chart: {{ include "insignis.chart" . }}
{{ include "insignis.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "insignis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "insignis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "insignis.tls.serviceAccount.name" -}}
{{- if .Values.tls.serviceAccount.create }}
    {{- default (include "insignis.fullname" .) .Values.tls.serviceAccount.name }}
{{- else }}
    {{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Define the default values for the certificate selfSigner inputs
*/}}
{{- define "selfcerts.fullname" -}}
  {{- printf "%s-%s" (include "insignis.fullname" .) "cockroachdb-self-signer" | trunc 56 | trimSuffix "-" -}}
{{- end -}}

{{- define "rotatecerts.fullname" -}}
  {{- printf "%s-%s" (include "insignis.fullname" .) "rotate-self-signer" | trunc 56 | trimSuffix "-" -}}
{{- end -}}

{{- define "selfcerts.minimumCertDuration" -}}
  {{- if .Values.tls.certs.selfSigner.minimumCertDuration -}}
    {{- print (.Values.tls.certs.selfSigner.minimumCertDuration | trimSuffix "h") -}}
  {{- else }}
    {{- $minCertDuration := min (sub (.Values.tls.certs.selfSigner.clientCertDuration | trimSuffix "h" ) (.Values.tls.certs.selfSigner.clientCertExpiryWindow | trimSuffix "h")) (sub (.Values.tls.certs.selfSigner.nodeCertDuration | trimSuffix "h") (.Values.tls.certs.selfSigner.nodeCertExpiryWindow | trimSuffix "h")) -}}
    {{- print $minCertDuration -}}
  {{- end }}
{{- end -}}

{{/*
Define the cron schedules for certificate rotate jobs and converting from hours to valid cron string.
We assume that each month has 31 days, hence the cron job may run few days earlier in a year. In a cron schedule,
we can not set a cron of more than a year, hence we try to run the cron in such a way that the cron run comes to
as close possible to the expiry window. However, it is possible that cron may run earlier than the expiry window.
*/}}
{{- define "selfcerts.clientRotateSchedule" -}}
{{- $tempHours := int64 (include "selfcerts.minimumCertDuration" .) -}}
{{- $days := "*" -}}
{{- $months := "*" -}}
{{- $hours := mod $tempHours 24 -}}
{{- if not (eq $hours $tempHours) -}}
{{- $tempDays := div $tempHours 24 -}}
{{- $days = mod $tempDays 31 -}}
{{- if not (eq $days $tempDays) -}}
{{- $days = add $days 1 -}}
{{- $tempMonths := div $tempDays 31 -}}
{{- $months = mod $tempMonths 12 -}}
{{- if not (eq $months $tempMonths) -}}
{{- $months = add $months 1 -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if ne (toString $months) "*" -}}
{{- $months = printf "*/%s" (toString $months) -}}
{{- else -}}
{{- if ne (toString $days) "*" -}}
{{- $days = printf "*/%s" (toString $days) -}}
{{- else -}}
{{- if ne $hours 0 -}}
{{- $hours = printf "*/%s" (toString $hours) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- printf "0 %s %s %s *" (toString $hours) (toString $days) (toString $months) -}}
{{- end -}}


{{/*
Validate that if caProvided is true, then the caSecret must not be empty and secret must be present in the namespace.
*/}}
{{- define "cockroachdb.tls.certs.selfSigner.caProvidedValidation" -}}
{{- if eq "" .Values.tls.certs.selfSigner.caSecret -}}
    {{ fail "CA secret can't be empty if caProvided is set to true" }}
{{- else -}}
    {{- if not (lookup "v1" "Secret" .Release.Namespace .Values.tls.certs.selfSigner.caSecret) }}
        {{ fail "CA secret is not present in the release namespace" }}
    {{- end }}
{{- end -}}
{{- end -}}

{{/*
Validate that if clientCertDuration must not be empty and it must be greater than minimumCertDuration.
*/}}
{{- define "cockroachdb.tls.certs.selfSigner.clientCertValidation" -}}
{{- if or (not .Values.tls.certs.selfSigner.clientCertDuration) (not .Values.tls.certs.selfSigner.clientCertExpiryWindow) }}
  {{ fail "Client cert duration can not be empty" }}
{{- else }}
{{- if lt (sub (.Values.tls.certs.selfSigner.clientCertDuration | trimSuffix "h") (.Values.tls.certs.selfSigner.clientCertExpiryWindow | trimSuffix "h")) (int64 (include "selfcerts.minimumCertDuration" .)) }}
   {{ fail "Client cert duration minus client cert expiry window should not be less than minimum Cert duration" }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Validate that if user enabled tls, then either self-signed certificates or certificate manager is enabled
*/}}
{{- define "insignis.tlsValidation" -}}
{{- if .Values.tls.enabled -}}
{{- if and (not .Values.tls.certs.selfSigner.enabled) (not .Values.tls.certs.provided) -}}
    {{ fail "You have to enable either self signed certificates or provide certificates, if you have enabled tls" }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate configurations if user will leverage cockroachdb CA cert
*/}}
{{- define "cockroachdb.tls.certs.selfSigner.validation" -}}
{{ include "cockroachdb.tls.certs.selfSigner.caProvidedValidation" . }}
{{ include "cockroachdb.tls.certs.selfSigner.clientCertValidation" . }}
{{- end -}}