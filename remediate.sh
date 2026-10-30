#!/usr/bin/env bash
set -Eeuo pipefail

node_name="${1:-unknown}"

report_failure() {
  local exit_code=$?
  printf 'RESULT node=%s status=FAILED reason=command-error exit_code=%s\n' \
    "$node_name" "$exit_code" >&2
}
trap report_failure ERR

fail() {
  local reason="$1"
  shift
  printf '%s\n' "$*" >&2
  printf 'RESULT node=%s status=FAILED reason=%s\n' \
    "$node_name" "$reason" >&2
  exit 1
}

if [[ ! -r /etc/os-release ]]; then
  fail "unknown-host-os" "Unable to identify the host operating system."
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
  printf 'RESULT node=%s status=SKIPPED reason=non-ubuntu os=%s version=%s\n' \
    "$node_name" "${ID:-unknown}" "${VERSION_ID:-unknown}"
  exit 0
fi

case "${VERSION_ID:-}" in
  22.04)
    minimum_version="1.0.9-2ubuntu0.1"
    ;;
  24.04)
    minimum_version="1.1.0-2ubuntu0.1"
    ;;
  *)
    printf 'RESULT node=%s status=SKIPPED reason=unsupported-ubuntu version=%s\n' \
      "$node_name" "${VERSION_ID:-unknown}"
    exit 0
    ;;
esac

installed_version="$(dpkg-query -W -f='${Version}' libbrotli1 2>/dev/null)" || {
  fail "package-not-installed" "libbrotli1 is not installed on ${node_name}."
}

if dpkg --compare-versions "$installed_version" ge "$minimum_version"; then
  printf 'RESULT node=%s status=COMPLIANT os=ubuntu-%s version=%s minimum=%s\n' \
    "$node_name" "$VERSION_ID" "$installed_version" "$minimum_version"
  exit 0
fi

exec 9>/var/lock/aks-brotli-remediation.lock
if ! flock --exclusive --wait 600 9; then
  fail "remediation-lock-timeout" \
    "Timed out waiting for the remediation lock on ${node_name}."
fi

# Another process might have remediated the node while this process waited.
installed_version="$(dpkg-query -W -f='${Version}' libbrotli1)"
if dpkg --compare-versions "$installed_version" ge "$minimum_version"; then
  printf 'RESULT node=%s status=COMPLIANT os=ubuntu-%s version=%s minimum=%s\n' \
    "$node_name" "$VERSION_ID" "$installed_version" "$minimum_version"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 install --only-upgrade --yes libbrotli1

updated_version="$(dpkg-query -W -f='${Version}' libbrotli1)"
if ! dpkg --compare-versions "$updated_version" ge "$minimum_version"; then
  fail "version-below-minimum" \
    "libbrotli1 validation failed on ${node_name}: installed=${updated_version} minimum=${minimum_version}"
fi

printf 'RESULT node=%s status=UPDATED os=ubuntu-%s before=%s version=%s minimum=%s\n' \
  "$node_name" "$VERSION_ID" "$installed_version" "$updated_version" "$minimum_version"
