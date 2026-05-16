#!/usr/bin/env bash
# Smoke-test checklist for trip + social services on GKE.
# Keep in sync with docs/gettingstarted/README.md §7.
set -euo pipefail

NS=tripplanning
API_HOST="${API_HOST:-api.k8s.tbd-htwg.de}"
API_SCHEME="${API_SCHEME:-http}"
VERIFY_STRICT="${VERIFY_STRICT:-false}"
FAILED=0

note_fail() {
  echo "FAIL: $*"
  FAILED=1
}

echo "== Pods =="
kubectl get pods -n "$NS" -o wide

TRIP_READY="$(kubectl get pods -n "$NS" -l app=trip-service \
  -o jsonpath='{.items[?(@.status.containerStatuses[?(@.name=="trip-service")].ready==true)].metadata.name}' 2>/dev/null || true)"
SOCIAL_READY="$(kubectl get pods -n "$NS" -l app=social-service \
  -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | head -1 || true)"

if [[ -z "${TRIP_READY}" ]]; then
  note_fail "no Ready trip-service pod (often ES/Lucene or DB — check logs)"
else
  echo "trip-service ready pod: ${TRIP_READY}"
fi
if [[ -z "${SOCIAL_READY}" ]]; then
  note_fail "no Running social-service pod"
else
  echo "social-service pod: ${SOCIAL_READY}"
fi

echo "== Services =="
kubectl get svc -n "$NS"

echo "== HTTPRoute / Gateway =="
kubectl get gateway,httproute -n "$NS"
GW_IP="$(kubectl get gateway tripplanning-api -n "$NS" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
if [[ -z "${GW_IP}" ]]; then
  echo "NOTE: Gateway has no ADDRESS yet (can take several minutes after first apply)."
else
  echo "Gateway IP: ${GW_IP}"
fi

echo "== ExternalSecrets =="
if kubectl api-resources 2>/dev/null | grep -q '^externalsecrets '; then
  kubectl get externalsecret -n "$NS" 2>/dev/null || true
else
  echo "Not installed (expected for minimal dev — secrets via bootstrap-k8s-secrets.sh)"
fi

if [[ -n "${TRIP_READY}" ]]; then
  echo "== Trip health (port-forward) =="
  kubectl port-forward -n "$NS" "pod/${TRIP_READY}" 18080:8080 &
  PF=$!
  sleep 2
  curl -sf "http://127.0.0.1:18080/actuator/health" | head -c 200 || note_fail "trip health curl failed"
  kill "$PF" 2>/dev/null || true
  wait "$PF" 2>/dev/null || true
else
  echo "Skipping trip port-forward (no ready pod)"
fi

if [[ -n "${SOCIAL_READY}" ]]; then
  echo "== Social health (port-forward) =="
  kubectl port-forward -n "$NS" "svc/social-service" 18081:8080 &
  PF=$!
  sleep 2
  curl -sf "http://127.0.0.1:18081/actuator/health" | head -c 200 || note_fail "social health curl failed"
  kill "$PF" 2>/dev/null || true
  wait "$PF" 2>/dev/null || true
else
  echo "Skipping social port-forward (no running pod)"
fi

echo "== Public API (if DNS ready) =="
curl -sf "${API_SCHEME}://${API_HOST}/actuator/health" || echo "public API not reachable yet (${API_SCHEME}://${API_HOST})"

if [[ "${FAILED}" -ne 0 ]]; then
  echo ""
  echo "Verify reported failures. Logs:"
  echo "  kubectl logs -n ${NS} deployment/trip-service -c trip-service --tail=40"
  echo "  kubectl logs -n ${NS} deployment/social-service --tail=40"
  if [[ "${VERIFY_STRICT}" == "true" ]]; then
    exit 1
  fi
  echo "VERIFY_STRICT=false — continuing (warnings only)."
fi

echo "Done. Test API manually: ${API_SCHEME}://${API_HOST}/api/v2"
