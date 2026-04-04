#!/usr/bin/env bash
# Grafana Cloud にダッシュボードをデプロイするスクリプト
# 使い方:
#   export GRAFANA_CLOUD_URL=https://your-org.grafana.net
#   export GRAFANA_CLOUD_API_KEY=glsa_xxxxxxxxxxxx
#   ./grafana-cloud/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_FILE="$SCRIPT_DIR/dashboards/claude-code.json"

: "${GRAFANA_CLOUD_URL:?GRAFANA_CLOUD_URL が未設定アル。例: https://your-org.grafana.net}"
: "${GRAFANA_CLOUD_API_KEY:?GRAFANA_CLOUD_API_KEY が未設定アル}"

GRAFANA_CLOUD_URL="${GRAFANA_CLOUD_URL%/}"

echo "==> Grafana Cloud にダッシュボードをデプロイするアル..."
echo "    URL: $GRAFANA_CLOUD_URL"

PAYLOAD=$(jq -n \
  --argjson dashboard "$(cat "$DASHBOARD_FILE")" \
  '{dashboard: $dashboard, overwrite: true, folderId: 0}')

HTTP_STATUS=$(curl -s -o /tmp/grafana-deploy-response.json -w "%{http_code}" \
  -X POST "$GRAFANA_CLOUD_URL/api/dashboards/db" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GRAFANA_CLOUD_API_KEY" \
  -d "$PAYLOAD")

if [[ "$HTTP_STATUS" == "200" ]]; then
  DASHBOARD_URL=$(jq -r '.url' /tmp/grafana-deploy-response.json)
  echo "==> デプロイ完了アル！"
  echo "    ダッシュボード: ${GRAFANA_CLOUD_URL}${DASHBOARD_URL}"
else
  echo "==> デプロイ失敗アル (HTTP $HTTP_STATUS)"
  cat /tmp/grafana-deploy-response.json
  exit 1
fi
