#!/usr/bin/env bash
set -Eeuo pipefail

namespace="aks-brotli-remediation"
daemonset="aks-brotli-remediation"
timeout="${1:-15m}"

kubectl rollout status "daemonset/${daemonset}" \
  --namespace "$namespace" \
  --timeout "$timeout"

desired="$(kubectl get daemonset "$daemonset" \
  --namespace "$namespace" \
  --output jsonpath='{.status.desiredNumberScheduled}')"
ready="$(kubectl get daemonset "$daemonset" \
  --namespace "$namespace" \
  --output jsonpath='{.status.numberReady}')"

if [[ "$desired" -eq 0 ]]; then
  echo "The DaemonSet did not select any Linux nodes." >&2
  exit 1
fi

if [[ "$ready" -ne "$desired" ]]; then
  printf 'Only %s of %s DaemonSet pods are ready.\n' "$ready" "$desired" >&2
  exit 1
fi

mapfile -t pods < <(
  kubectl get pods \
    --namespace "$namespace" \
    --selector app.kubernetes.io/name=aks-brotli-remediation \
    --output name
)

failed=0
validated=0

printf '%-48s %s\n' "NODE" "RESULT"
printf '%-48s %s\n' "----" "------"

for pod in "${pods[@]}"; do
  node="$(kubectl get "$pod" \
    --namespace "$namespace" \
    --output jsonpath='{.spec.nodeName}')"
  result="$(
    kubectl logs "$pod" \
      --namespace "$namespace" \
      --container remediate |
      grep '^RESULT ' |
      tail -n 1 || true
  )"

  printf '%-48s %s\n' "$node" "${result:-NO_RESULT}"

  case "$result" in
    *" status=COMPLIANT "*|*" status=UPDATED "*)
      ((validated += 1))
      ;;
    *" status=SKIPPED reason=non-ubuntu "*|*" status=SKIPPED reason=unsupported-ubuntu "*)
      ;;
    *)
      failed=1
      ;;
  esac
done

if [[ "$validated" -eq 0 ]]; then
  echo "No supported Ubuntu 22.04 or 24.04 nodes were validated." >&2
  exit 1
fi

exit "$failed"
