#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
context="$(kubectl config current-context)"

if [[ "${1:-}" != "--yes" ]]; then
  echo "WARNING: this deploys a privileged DaemonSet that modifies AKS node hosts."
  printf 'Current Kubernetes context: %s\n' "$context"
  read -r -p "Type the current context name to continue: " confirmation
  if [[ "$confirmation" != "$context" ]]; then
    echo "Context confirmation did not match; deployment cancelled." >&2
    exit 1
  fi
fi

kubectl apply --kustomize "$script_dir"
"${script_dir}/validate.sh"
