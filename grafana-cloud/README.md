# Grafana Cloud セットアップガイド

EC2 セルフホスト構成の代替として、**Grafana Cloud** を使った監視スタックのセットアップ手順です。
インフラ管理が一切不要で、Free Tier で十分な規模をカバーできます。

## EC2 vs Grafana Cloud

| 項目 | EC2 セルフホスト | Grafana Cloud |
|---|---|---|
| インフラ管理 | EC2 / nginx / certbot / Route53 | **不要** |
| 可用性 | 手動 start/stop | **常時稼働** |
| SSH 鍵管理 | 必要 | **不要** |
| コスト | ~$3/月（起動時間による） | **Free Tier あり** |
| OTel 送信 | Collector 経由 | **CLI から直接送信** |

## Grafana Cloud Free Tier の上限

- メトリクス: 10,000 series
- ログ: 50 GB/月
- データ保持: 14日

チーム人数 〜20人程度であれば Free Tier で十分です。

---

## セットアップ手順

### 1. Grafana Cloud アカウント作成

1. [grafana.com](https://grafana.com) でサインアップ（Free Tier を選択）
2. スタック名・リージョンを選択（`ap-southeast-1` など近いリージョン推奨）

### 2. OTLP エンドポイントと認証情報を取得

1. Grafana Cloud ポータルにログイン
2. 左メニュー → **My Account** → スタックを選択
3. **OpenTelemetry** タイルをクリック
4. 以下の情報をメモする：

   | 項目 | 例 |
   |---|---|
   | OTLP エンドポイント | `https://otlp-gateway-prod-ap-southeast-1.grafana.net/otlp` |
   | Instance ID | `123456` |
   | API Key | `glc_xxxxxxxxxxxx` |

5. Authorization ヘッダー値を生成：
   ```bash
   echo -n "123456:glc_xxxxxxxxxxxx" | base64 | tr -d ' \n'
   # → MTIzNDU2OmdsY194eHh4eHh4eHh4eHh4
   ```
   > **注意:** `base64` の出力にスペースや改行が混入すると 401 Unauthorized になります。`tr -d ' \n'` で除去してください。

### 3. Managed Settings に設定を登録

[claude.ai Admin Console](https://claude.ai) → Settings → Claude Code → Managed Settings に以下を登録：

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://otlp-gateway-prod-ap-southeast-1.grafana.net/otlp",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic MTIzNDU2OmdsY194eHh4eHh4eHh4eHh4",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",
    "OTEL_METRIC_EXPORT_INTERVAL": "10000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000",
    "OTEL_LOG_TOOL_DETAILS": "1"
  }
}
```

> EC2構成と違い、`otel.htpasswd` や nginx の設定は不要です。

### 4. ダッシュボードをインポート

#### 方法A: deploy.sh を使う（推奨）

```bash
export GRAFANA_CLOUD_URL=https://your-org.grafana.net
export GRAFANA_CLOUD_API_KEY=glsa_xxxxxxxxxxxx  # Grafana Cloud の Service Account Token
./grafana-cloud/deploy.sh
```

Service Account Token の作成: Grafana Cloud → Administration → Service accounts → Add service account token

スクリプトは自動で Prometheus データソースの UID を検索しますが、Grafana Cloud の組み込みデータソース (`grafanacloud-<org>-prom`) は `/api/datasources` に返ってこない場合があります。その場合は UID を直接指定してください：

```bash
# Connections → Data sources → grafanacloud-<org>-prom の編集画面 URL末尾が UID
# 例: https://your-org.grafana.net/connections/datasources/edit/grafanacloud-prom
export GRAFANA_METRICS_DS_UID=grafanacloud-prom
./grafana-cloud/deploy.sh
```

#### 方法B: Grafana UI から手動インポート

1. Grafana Cloud の Grafana にログイン
2. 左メニュー → Dashboards → **Import**
3. `grafana-cloud/dashboards/claude-code.json` の内容を貼り付け
4. データソースの選択画面で **Grafana Cloud Metrics** (Mimir) を選択
5. **Import** をクリック

---

## 動作確認

1. Claude Code で何かタスクを実行する
2. 30秒〜1分待つ
3. Grafana Cloud のダッシュボードを開いてデータが表示されるか確認

データが表示されない場合:
- Managed Settings が反映されているか確認（CLI を再起動）
- Grafana Cloud の **Explore** で `{__name__=~"claude_code.*"}` を実行してメトリクスが届いているか確認

---

## 参考

- [Grafana Cloud OTLP ドキュメント](https://grafana.com/docs/grafana-cloud/send-data/otlp/)
- [サーバー管理設定ガイド](../docs/server-managed-settings.md)
- [EC2 セルフホスト構成](../README.md)
