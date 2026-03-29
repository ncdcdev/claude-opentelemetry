# Route53 ホストゾーンは data source として参照するのみ
# A レコードは manage.ps1 start で動的に更新する（EC2 起動のたびに IP が変わるため）
#
# ドメイン情報は outputs.tf から参照できる:
#   terraform output domain          → ベースドメイン
#   terraform output otel_endpoint   → OTel Collector エンドポイント
#   terraform output grafana_url     → Grafana URL
