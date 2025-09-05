#!/usr/bin/env bash
set -euo pipefail

ORIG_CALC_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HARNESS_CHART="charts/istiolib-test"
LIB_CHART="charts/istiolib"

# Determine repo root robustly (handles case where script is installed into /usr/local/bin inside container)
detect_root() {
  local candidates=("$PWD" "/workspace" "$ORIG_CALC_ROOT" "$(pwd)")
  for c in "${candidates[@]}"; do
    if [ -d "$c/$HARNESS_CHART" ] && [ -f "$c/$LIB_CHART/Chart.yaml" ]; then
      echo "$c"; return 0; fi
  done
  # Fallback to original even if it may be wrong; error will be raised later if dirs missing
  echo "$ORIG_CALC_ROOT"
}

ROOT_DIR="$(detect_root)"
SKIP_PLUGIN_INSTALL=false
RUN_LINT=true
QUIET=false

usage() {
  cat <<EOF
run-tests.sh - Run Helm lint + unit tests for istiolib.

Usage: $0 [options]
Options:
  --skip-plugin-install   Assume helm-unittest already installed
  --no-lint               Skip helm lint
  -q, --quiet             Reduced output
  -h, --help              Show this help

Environment:
  HELM_BIN (optional)     Path to helm binary (default: helm in PATH)
EOF
}

log() { $QUIET && return 0; echo "[run-tests] $*"; }
err() { echo "[run-tests][ERROR] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-plugin-install) SKIP_PLUGIN_INSTALL=true; shift;;
    --no-lint) RUN_LINT=false; shift;;
    -q|--quiet) QUIET=true; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

HELM_BIN=${HELM_BIN:-helm}

if ! command -v "$HELM_BIN" >/dev/null 2>&1; then
  err "Helm not found in PATH. Install Helm first (e.g. brew install helm)."; exit 2
fi

log "Helm version: $($HELM_BIN version --short 2>/dev/null || true)"

if ! $SKIP_PLUGIN_INSTALL; then
  if ! $HELM_BIN plugin list 2>/dev/null | grep -q '\bunittest\b'; then
    log "Installing helm-unittest plugin..."
    $HELM_BIN plugin install https://github.com/helm-unittest/helm-unittest >/dev/null
  else
    log "helm-unittest plugin already present."
  fi
else
  log "Skipping plugin installation as requested."
fi

if [[ ! -d "$ROOT_DIR/$HARNESS_CHART" ]]; then
  err "Harness chart directory '$HARNESS_CHART' not found (resolved ROOT_DIR=$ROOT_DIR)."; exit 3
fi

log "Building dependencies for harness chart..."
pushd "$ROOT_DIR/$HARNESS_CHART" >/dev/null
$HELM_BIN dependency build >/dev/null
popd >/dev/null

if $RUN_LINT; then
  if [[ -d "$ROOT_DIR/$LIB_CHART" ]]; then
    log "Linting library chart..."
    $HELM_BIN lint "$ROOT_DIR/$LIB_CHART"
  fi
  log "Linting harness chart..."
  $HELM_BIN lint "$ROOT_DIR/$HARNESS_CHART"
fi

log "Running unit tests..."
$HELM_BIN unittest "$ROOT_DIR/$HARNESS_CHART"
log "All tests completed successfully."
