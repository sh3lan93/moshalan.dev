# {{ .Title }}

{{ with .Description }}> {{ . }}

{{ end -}}
- Author: {{ .Params.author | default site.Params.author }} ({{ site.Home.Permalink }})
- Published: {{ .Date.Format "2006-01-02" }}
- Canonical URL: {{ .Permalink }}
{{- with .Params.tags }}
- Topics: {{ delimit . ", " }}
{{- end }}

{{ .RawContent }}
