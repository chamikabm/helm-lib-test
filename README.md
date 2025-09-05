# istiolib (Helm Library Chart)

Helm library chart exporting a single reusable Istio Telemetry named template: `istiolib.telemetry`.

Structure:
- `charts/istiolib` – library (type: library)
- `charts/istiolib-test` – test harness chart consuming the library for unit tests

Why a harness? Library charts don’t render manifests themselves; the harness includes the template so `helm unittest` can assert the output.

## Template

Library template file: `charts/istiolib/templates/_telemetry.tpl`

```
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
```

Consumers include it in their own chart manifests like:

```
{{ include "istiolib.telemetry" . }}
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `istio.randomSamplingPercentage` | float | `10.0` | Trace sampling percentage. |
| `istio.selector` | map | (nil) | Optional selector labels for the Telemetry resource. |

## Unit Testing

We test via the harness chart `charts/istiolib-test` which declares a dependency on the library and renders the template.

### Install Helm (if needed)
macOS (Homebrew):
```
brew install helm
```

### Install helm-unittest plugin
```
helm plugin install https://github.com/helm-unittest/helm-unittest
```
(If already installed, upgrade with `helm plugin update unittest`.)

### Quick start (script)
From repo root (make script executable once):
```
chmod +x scripts/run-tests.sh
./scripts/run-tests.sh
```

### Manual steps (equivalent)
```
helm dependency build charts/istiolib-test
helm lint charts/istiolib charts/istiolib-test  # optional but recommended
helm unittest charts/istiolib-test
```

### Script options
`scripts/run-tests.sh` accepts:

| Option | Description |
|--------|-------------|
| `--skip-plugin-install` | Assume `helm-unittest` already installed (CI/container) |
| `--no-lint` | Skip Helm lint phase inside the script |
| `-q/--quiet` | Minimal output (only summary / errors) |
| `-h/--help` | Show usage |

Examples:
```
./scripts/run-tests.sh --skip-plugin-install
./scripts/run-tests.sh --no-lint -q
```

### Makefile targets
Common tasks are wrapped in a `Makefile`:
```
make help          # list targets
make deps          # build test chart dependencies
make lint          # helm lint both charts
make test          # run unit tests (script)
make docker-build  # build test image
make docker-test   # run tests inside container
make all           # deps + lint + test

Podman instead of Docker:
```
make docker-test CONTAINER=podman
make docker-build CONTAINER=podman
```
```

## Container Usage (Docker / Podman)

Reproducible toolchain (pinned Helm + plugin):
```
docker build -t istiolib-tests .
docker run --rm -v $(pwd):/workspace istiolib-tests --skip-plugin-install
```
Podman:
```
podman build -t istiolib-tests .
podman run --rm -v $(pwd):/workspace istiolib-tests --skip-plugin-install
```
Add script flags after image name:
```
docker run --rm -v $(pwd):/workspace istiolib-tests --no-lint -q
```

## Continuous Integration (GitHub Actions)

Included workflow: `.github/workflows/helm-tests.yml`

It runs two jobs:
- Native install (faster, caches plugin)
- Docker build (ensures containerized reproducibility)

Trigger: pushes / PRs touching `charts/**`, test script, Dockerfile, or workflow.

Local dry-run equivalent:
```
./scripts/run-tests.sh
```

### Expected output
Successful run ends with:
```
Charts:      1 passed, 1 total
Tests:       3 passed, 3 total
```

## Using in Another Chart
Add this repo as a submodule or publish the packaged library chart to a Helm repository.

1. Package the library chart (from repo root):
```
helm package charts/istiolib
```
2. (Optional) Add to a repo index:
```
helm repo index .
```
3. In the parent (application) chart's `Chart.yaml` add a dependency referencing this packaged repo or a `file://` path.

Inside a consuming chart template:
```
{{ include "istiolib.telemetry" . }}
```

### Local file path dependency example
In parent chart `Chart.yaml` (assuming parent is repo root or sibling referencing `charts/`):
```
dependencies:
  - name: istiolib
    version: 0.1.0
    repository: "file://charts/istiolib"
```

Template usage (idempotent include):
```
{{ include "istiolib.telemetry" . }}
```

## Git Setup
```
git init
git add .
git commit -m "refactor: restructure into charts/ with istiolib and istiolib-test"

## Pre-commit Hook (optional)
Add `.git/hooks/pre-commit`:
```
#!/usr/bin/env bash
set -e
./scripts/run-tests.sh -q
```
Then make it executable:
```
chmod +x .git/hooks/pre-commit
```
```

## Notes
- Library chart only defines templates; nothing renders unless explicitly included.
- Adjust `metadata.namespace` if your Istio control plane namespace differs.
- For CI speed, prefer native job + container job (defense in depth).
- Podman support via `CONTAINER` make var (defaults to docker).
- You can remove deprecated top-level legacy chart artifacts (if any) once adoption complete.

## License
Choose and add a license (e.g., Apache-2.0) if you plan to distribute publicly.
