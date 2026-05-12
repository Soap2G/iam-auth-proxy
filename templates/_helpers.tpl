{{/*
Expand the name of the chart.
*/}}
{{- define "iam-auth-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "iam-auth-proxy.fullname" -}}
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
{{- define "iam-auth-proxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "iam-auth-proxy.labels" -}}
helm.sh/chart: {{ include "iam-auth-proxy.chart" . }}
{{ include "iam-auth-proxy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "iam-auth-proxy.chart" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "iam-auth-proxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "iam-auth-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Generate a proxy prefix with leading slash and without trailing slash,
prefixed by the route/ingress path when it's not "/".
*/}}
{{- define "iam-auth-proxy.proxyPrefix" -}}
{{- $pp := .Values.authOptions.proxyPrefix | default "/oauth2" }}
{{- $r := "" }}
{{- $path := "" }}
{{- if .Values.ingress.enabled }}
{{- $path = .Values.ingress.path | default "/" }}
{{- else if .Values.route.enabled }}
{{- $path = .Values.route.path | default "/" }}
{{- end }}
{{- if and $path (ne $path "/") }}
{{- $r = print "/" (trimAll "/" $path) }}
{{- end }}
{{- printf "%s/%s" $r (trimAll "/" $pp) -}}
{{- end }}

{{/*
Cookie path — the path at which the cookie is scoped, matching the ingress/route path.
*/}}
{{- define "iam-auth-proxy.cookiePath" -}}
{{- if .Values.ingress.enabled }}
{{- .Values.ingress.path | default "/" }}
{{- else if .Values.route.enabled }}
{{- .Values.route.path | default "/" }}
{{- else }}
{{- print "/" }}
{{- end }}
{{- end }}

{{/*
Generate Upstream URL: http://SERVICE:PORT/
*/}}
{{- define "iam-auth-proxy.upstreamUrl" -}}
{{- printf "http://%s:%v/" .Values.upstream.service.name .Values.upstream.service.port -}}
{{- end }}

{{/*
Redirect URI for the OAuth2 callback.
*/}}
{{- define "iam-auth-proxy.redirectUri" -}}
{{- $pp := (include "iam-auth-proxy.proxyPrefix" .) }}
{{- $host := "" }}
{{- if .Values.ingress.enabled }}
{{- $host = .Values.ingress.hostname }}
{{- else if .Values.route.enabled }}
{{- $host = .Values.route.hostname }}
{{- end }}
{{- printf "https://%s%s/callback" $host $pp -}}
{{- end }}

{{/*
Hostname used in NOTES.txt — derived from whichever entrypoint is active.
*/}}
{{- define "iam-auth-proxy.hostname" -}}
{{- if .Values.ingress.enabled }}
{{- .Values.ingress.hostname }}
{{- else if .Values.route.enabled }}
{{- .Values.route.hostname }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding OIDC credentials and cookie secret.
When oidc.existingSecret is set, use that; otherwise use the chart-managed one.
*/}}
{{- define "iam-auth-proxy.secretName" -}}
{{- if .Values.oidc.existingSecret }}
{{- .Values.oidc.existingSecret }}
{{- else }}
{{- include "iam-auth-proxy.fullname" . }}
{{- end }}
{{- end }}

{{/*
Cookie secret: use the provided value, or look up an already-existing chart-managed
secret so we don't rotate the cookie on every upgrade, or generate a new one.
*/}}
{{- define "iam-auth-proxy.cookieSecret" -}}
{{- if .Values.cookie.secret }}
{{- $len := len .Values.cookie.secret }}
{{- if not (or (eq $len 16) (eq $len 24) (eq $len 32)) }}
{{- fail "cookie.secret must be exactly 16, 24, or 32 characters for AES session encryption." }}
{{- end }}
{{- .Values.cookie.secret | b64enc }}
{{- else }}
{{- $secretName := include "iam-auth-proxy.fullname" . }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace $secretName }}
{{- if and $existing $existing.data (index $existing.data "cookie-secret") }}
{{- index $existing.data "cookie-secret" }}
{{- else }}
{{- randAlphaNum 32 | b64enc }}
{{- end }}
{{- end }}
{{- end }}

{{/*
OIDC scope — driven by iam.profile preset, overridden by authOptions.scope if non-empty.
When iam.profile=custom, authOptions.scope is required.
*/}}
{{- define "iam-auth-proxy.scope" -}}
{{- if .Values.authOptions.scope }}
{{- .Values.authOptions.scope }}
{{- else if eq .Values.iam.profile "wlcg" }}
{{- print "openid profile email offline_access wlcg.groups" }}
{{- else if eq .Values.iam.profile "aarc" }}
{{- print "openid profile email offline_access eduperson_entitlement" }}
{{- else if eq .Values.iam.profile "custom" }}
{{- fail "authOptions.scope is required when iam.profile=custom." }}
{{- else }}
{{- print "openid profile email offline_access groups" }}
{{- end }}
{{- end }}

{{/*
OIDC groups claim — driven by iam.profile preset, overridden by authOptions.oidcGroupsClaim if non-empty.
When iam.profile=custom, authOptions.oidcGroupsClaim is required.
*/}}
{{- define "iam-auth-proxy.oidcGroupsClaim" -}}
{{- if .Values.authOptions.oidcGroupsClaim }}
{{- .Values.authOptions.oidcGroupsClaim }}
{{- else if eq .Values.iam.profile "wlcg" }}
{{- print "wlcg.groups" }}
{{- else if eq .Values.iam.profile "aarc" }}
{{- print "eduperson_entitlement" }}
{{- else if eq .Values.iam.profile "custom" }}
{{- fail "authOptions.oidcGroupsClaim is required when iam.profile=custom." }}
{{- else }}
{{- print "groups" }}
{{- end }}
{{- end }}

{{/*
Entrypoint guard: exactly one of ingress or route must be enabled.
*/}}
{{- define "iam-auth-proxy.validateEntrypoint" -}}
{{- if and .Values.ingress.enabled .Values.route.enabled }}
{{- fail "ingress.enabled and route.enabled cannot both be true — choose one entrypoint." }}
{{- end }}
{{- if and (not .Values.ingress.enabled) (not .Values.route.enabled) }}
{{- fail "At least one entrypoint must be enabled: set ingress.enabled=true or route.enabled=true." }}
{{- end }}
{{- end }}

{{/*
Credentials guard: when not using existingSecret, all three OIDC fields must be provided.
*/}}
{{- define "iam-auth-proxy.validateCredentials" -}}
{{- if not .Values.oidc.existingSecret }}
{{- if not .Values.oidc.issuerURL }}
{{- fail "oidc.issuerURL is required when oidc.existingSecret is not set." }}
{{- end }}
{{- if not .Values.oidc.clientID }}
{{- fail "oidc.clientID is required when oidc.existingSecret is not set." }}
{{- end }}
{{- if not .Values.oidc.clientSecret }}
{{- fail "oidc.clientSecret is required when oidc.existingSecret is not set." }}
{{- end }}
{{- end }}
{{- end }}
