#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

bash -n \
  "${script_dir}/remediate.sh" \
  "${script_dir}/validate.sh" \
  "${script_dir}/deploy.sh" \
  "${script_dir}/cleanup.sh"

kubectl kustomize "$script_dir" >/dev/null

echo "Local validation passed."
