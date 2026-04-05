#!/usr/bin/env bash
# Grafana Cloud にダッシュボードをデプロイするスクリプト
# 使い方:
#   export GRAFANA_CLOUD_URL=https://your-org.grafana.net
#   export GRAFANA_CLOUD_API_KEY=glsa_xxxxxxxxxxxx
#   ./grafana-cloud/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_FILE="$SCRIPT_DIR/dashboards/claude-code.json"

: "${GRAFANA_CLOUD_URL:?GRAFANA_CLOUD_URL が未設定です。例: https://your-org.grafana.net}"
: "${GRAFANA_CLOUD_API_KEY:?GRAFANA_CLOUD_API_KEY が未設定です}"

GRAFANA_CLOUD_URL="${GRAFANA_CLOUD_URL%/}"

echo "==> Grafana Cloud にダッシュボードをデプロイします..."
echo "    URL: $GRAFANA_CLOUD_URL"

# Prometheus (Mimir) データソースの UID を取得
# 環境変数 GRAFANA_METRICS_DS_UID で直接指定も可能
if [[ -n "${GRAFANA_METRICS_DS_UID:-}" ]]; then
  MIMIR_UID="$GRAFANA_METRICS_DS_UID"
  echo "    データソース UID: $MIMIR_UID (環境変数から指定)"
else
  echo "==> Prometheus データソースを検索中..."
  DS_RESPONSE=$(curl -s \
    "$GRAFANA_CLOUD_URL/api/datasources" \
    -H "Authorization: Bearer $GRAFANA_CLOUD_API_KEY")

  # prometheus または grafana-mimir-datasource 型を検索
  MIMIR_UID=$(echo "$DS_RESPONSE" | jq -r '[.[] | select(.type == "prometheus" or .type == "grafana-mimir-datasource")] | first | .uid // empty')

  if [[ -z "$MIMIR_UID" ]]; then
    echo "エラー: Prometheus / Mimir 型のデータソースが見つかりません。"
    echo ""
    echo "対処方法:"
    echo "  1. Grafana Cloud → Connections → Data sources → Add new data source → Prometheus"
    echo "     URL: Grafana Cloud ポータルの Prometheus タイルで確認してください"
    echo "  または"
    echo "  2. 既存データソースの UID を確認して環境変数で指定:"
    echo "     export GRAFANA_METRICS_DS_UID=<uid>"
    echo ""
    echo "現在のデータソース一覧:"
    echo "$DS_RESPONSE" | jq '[.[] | {name, type, uid}]'
    exit 1
  fi

  MIMIR_NAME=$(echo "$DS_RESPONSE" | jq -r '[.[] | select(.type == "prometheus" or .type == "grafana-mimir-datasource")] | first | .name')
  echo "    データソース: $MIMIR_NAME (uid: $MIMIR_UID)"
fi

# __inputs を解決して /api/dashboards/import でインポート
PAYLOAD=$(jq -n \
  --argjson dashboard "$(cat "$DASHBOARD_FILE")" \
  --arg uid "$MIMIR_UID" \
  '{
    dashboard: $dashboard,
    overwrite: true,
    folderId: 0,
    inputs: [{ name: "DS_METRICS", type: "datasource", pluginId: "prometheus", value: $uid }]
  }')

HTTP_STATUS=$(curl -s -o /tmp/grafana-deploy-response.json -w "%{http_code}" \
  -X POST "$GRAFANA_CLOUD_URL/api/dashboards/import" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GRAFANA_CLOUD_API_KEY" \
  -d "$PAYLOAD")

if [[ "$HTTP_STATUS" == "200" ]]; then
  DASHBOARD_URL=$(jq -r '.importedUrl' /tmp/grafana-deploy-response.json)
  echo "==> デプロイ完了！"
  echo "    ダッシュボード: ${GRAFANA_CLOUD_URL}${DASHBOARD_URL}"
else
  echo "==> デプロイ失敗 (HTTP $HTTP_STATUS)"
  cat /tmp/grafana-deploy-response.json
  exit 1
fi
