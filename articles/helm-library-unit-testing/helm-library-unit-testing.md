---
title: "Unit Testing Helm Library Charts: From Invisible Templates to Verified Manifests"
subtitle: "Practical patterns, tooling, and CI/CD integration using an Istio Telemetry example (istiolib)"
author: Your Name
tags: [Helm, Kubernetes, DevOps, Testing, CI/CD, Istio]
publish_status: draft
---

# Unit Testing Helm Library Charts: From Invisible Templates to Verified Manifests

> Library charts export helpers—not Kubernetes objects. That makes them powerful, but also easy to break silently. Here's a battle‑tested pattern to give them the same safety net as application charts.

## 1. Why Test a Helm *Library* Chart?
Helm library charts (`type: library`) provide *named templates* (functions) consumed by other charts. They produce **no resources on their own**. A refactor or value handling tweak can silently alter downstream manifests (e.g., tracing, security policies, sidecars). Unit tests:

- Catch regressions before downstream consumers are surprised.
- Enforce contract for required / optional values.
- Provide fast feedback (milliseconds vs spinning full clusters).
- Enable refactors with confidence.

## 2. Core Challenge
`helm template` or `helm unittest` needs a chart that renders manifests. A pure library **renders nothing**—so you must *wrap* it. Enter the **Harness Chart Pattern**.

## 3. Approaches Compared

| Approach | Description | Pros | Cons | Recommendation |
|----------|-------------|------|------|----------------|
| Harness Chart | Separate “consumer” chart depends on library and includes its templates | Realistic, extensible, reusable | Slight duplication (test chart) | ✅ Primary pattern |
| Inline Test Templates | Add temporary template that `include`s the library, gated by a value like `_unitTest` | Single chart repo | Pollutes library with test-only logic; easy to ship accidentally | ⚠️ Avoid for published libs |
| Snapshot Tests Only | Assert entire rendered YAML diff | Simple initial setup | Brittle; minor formatting changes break | Use sparingly with structural asserts |
| Structural Assertions | Use `helm-unittest` to assert specific paths | Stable, focused, readable | Requires deliberate coverage | ✅ Core technique |
| Integration via Kind/Cluster | Install consumer chart into a temporary cluster | High confidence | Slow & heavier infra | Use for selective deep tests |

## 4. The Example: `istiolib`
Exports a single named template producing an Istio `Telemetry` resource.

`charts/istiolib/templates/_telemetry.tpl`:
```yaml
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

Key behaviors under test:
- Default sampling to `10.0` when unset
- Omit `spec.selector` unless provided
- Render all supplied label keys/values

## 5. Harness Chart Layout
```
charts/
  istiolib/            # library
    Chart.yaml (type: library)
    templates/_telemetry.tpl
  istiolib-test/       # harness
    Chart.yaml (depends on istiolib)
    templates/telemetry.yaml  # includes library template
    tests/telemetry_test.yaml # helm-unittest suite
```

Harness `templates/telemetry.yaml`:
```yaml
{{ include "istiolib.telemetry" . }}
```

Dependency (excerpt from `charts/istiolib-test/Chart.yaml`):
```yaml
dependencies:
  - name: istiolib
    version: 0.1.0
    repository: "file://../istiolib"
```

## 6. Writing Unit Tests with `helm-unittest`

`charts/istiolib-test/tests/telemetry_test.yaml`:
```yaml
suite: "istiolib test harness"
templates:
  - telemetry.yaml

tests:
  - it: "renders with provided sampling and selector"
    set:
      istio:
        randomSamplingPercentage: 22.2
        selector:
          app: demo
    asserts:
      - hasDocuments: { count: 1 }
      - isKind: { of: Telemetry }
      - equal: { path: spec.tracing[0].randomSamplingPercentage, value: 22.2 }
      - equal: { path: spec.selector.matchLabels.app, value: demo }

  - it: "defaults sampling to 10 when sampling not set"
    set:
      istio:
        selector:
          app: demo
    asserts:
      - equal: { path: spec.tracing[0].randomSamplingPercentage, value: 10 }

  - it: "omits selector when not provided"
    set:
      istio:
        randomSamplingPercentage: 55.5
    asserts:
      - notExists: { path: spec.selector }
      - equal: { path: spec.tracing[0].randomSamplingPercentage, value: 55.5 }
```

Design choices:
- Explicit `set:` values isolate each behavior.
- Avoid snapshots for core logic; use structural assertions for resilience.

## 7. Running Tests Locally

### Option A: Script (recommended)
```bash
./scripts/run-tests.sh
```

Flags:
```bash
./scripts/run-tests.sh --skip-plugin-install  # assume plugin present
./scripts/run-tests.sh --no-lint
./scripts/run-tests.sh -q                     # quiet
```

### Option B: Makefile
```bash
make test      # run script
make all       # deps + lint + test
make docker-test          # containerized
make docker-test CONTAINER=podman
```

### Option C: Raw Helm
```bash
helm dependency build charts/istiolib-test
helm unittest charts/istiolib-test
```

### Option D: Container (reproducible toolchain)
```bash
docker build -t istiolib-tests .
docker run --rm -v $(pwd):/workspace istiolib-tests --skip-plugin-install
```
Podman:
```bash
make docker-test CONTAINER=podman
```

## 8. CI/CD Integration (GitHub Actions Example)

`.github/workflows/helm-tests.yml` (excerpt):
```yaml
jobs:
  native:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/setup-helm@v4
        with: { version: v3.14.2 }
      - run: helm plugin install https://github.com/helm-unittest/helm-unittest || true
      - run: ./scripts/run-tests.sh

  docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t istiolib-tests .
      - run: docker run --rm -v $PWD:/workspace istiolib-tests --skip-plugin-install
```

Pipeline benefits:
- Dual-mode (native + container) catches environment drift.
- Independent caching of Helm plugins vs container layers.
- Fast feedback (< 1s test runtime measured locally).

## 9. Scaling the Pattern

| Concern | Pattern |
|---------|---------|
| Many library templates | Group related helpers; split when ownership diverges |
| Versioning | Semantic version & lock harness dependency version in consumers |
| Performance | Keep tests narrow; avoid huge value matrices in unit phase |
| Multiple libs | One harness per lib OR a unified “aggregate” harness if cross-interaction needed |
| Security | Scan Docker image; pin plugin repo commit (optional fork) |

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `template ... not exists or not selected` | Wrong path in test `templates:` list | Use filename relative to harness `templates/` |
| Default not applied | Value present but empty map blocked `default` | Set `null` / remove key; or adjust template logic |
| Selector always present | Provided empty map triggers block | Add `if .selector` guard (already present) |
| Tests pass locally, fail in CI | Plugin not installed | Ensure install step or script handles it |
| Container run can’t find chart dirs | Script path vs mounted repo mismatch | Root auto-detection added in script; ensure `-v $(pwd):/workspace` |

## 11. Extension Ideas
- Add snapshot test for *one* golden rendering (change detector).
- Add JSON Schema validation using `yq` + schema (for CRDs with stable schema docs).
- Generate coverage matrix (e.g., sampling extremes: `0, 10, 100`).
- Introduce `make diff` target comparing rendered output vs main branch.
- Publish packaged chart via GitHub Pages or ChartMuseum.

## 12. Minimal Checklist (Copy/Paste)
```
[ ] Create library chart (type: library)
[ ] Create harness chart with dependency (file:// reference initially)
[ ] Add include template in harness
[ ] Install helm-unittest plugin
[ ] Write structural tests (defaults, overrides, omission cases)
[ ] Add run-tests.sh script (lint + unit tests)
[ ] Add Makefile targets (deps, lint, test, docker-test)
[ ] Add Dockerfile (pinned Helm + plugin)
[ ] Add CI workflow (native + container jobs)
[ ] Document usage (README / article)
[ ] Enforce tests in pre-commit (optional)
```

## 13. Conclusion
Unit testing Helm library charts is straightforward once you adopt the harness pattern. You turn *hidden* template logic into *observable* artifacts, enabling safe iteration, cleaner contracts, and CI confidence. Your future self—and every downstream chart—will thank you.

---
*Have improvements? Open a PR or adapt this scaffold to your own internal libraries.*
