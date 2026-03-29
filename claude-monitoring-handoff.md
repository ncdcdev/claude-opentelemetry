# Claude Code 監視スタック 引き継ぎ資料

## このプロジェクトの目的

Claude Code（AI コーディングアシスタント）の利用状況を OpenTelemetry で収集し、自前の Grafana で可視化する。
コスト、トークン消費、ツール使用状況、セッション情報などをモニタリングする。

---

## 背景・前セッションで判明したこと

### Claude Code の OTel 対応

Claude Code は標準で OTel テレメトリをサポートしている。以下の環境変数で有効化できる。

```json
// ~/.claude/settings.json の env セクションに追加
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://<collector-host>:<port>",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic <base64(user:pass)>",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",
    "OTEL_METRIC_EXPORT_INTERVAL": "10000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000"
  }
}
```

### 重要: Temporality の問題

Claude Code はデフォルトで Delta 形式でメトリクスを送る。Prometheus は Cumulative しか受け付けない。
**`OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative` が必須。** これがないと Prometheus が全メトリクスを 500 エラーで拒否する。

### 取得できるメトリクス（Prometheus 上のメトリック名）

| メトリック名 | 内容 |
|---|---|
| `claude_code_cost_usage_USD_total` | コスト（USD） |
| `claude_code_token_usage_tokens_total` | トークン消費量 |
| `claude_code_session_count_total` | セッション数 |
| `claude_code_lines_of_code_count_total` | 変更コード行数 |
| `claude_code_code_edit_tool_decision_total` | コード編集ツール決定 |

ラベルには `model`, `session_id`, `user_email`, `organization_id` などが含まれる。

ログイベント（OTLP Logs）:
- `claude_code.user_prompt` — プロンプト
- `claude_code.tool_result` — ツール実行結果
- `claude_code.api_request` / `claude_code.api_error`

### OTel Demo スタックで検証済み

localhost:8080 で OTel デモスタックを使って動作確認済み。データは正常に流れた。
ただしデモスタックは認証なし・設定カスタマイズ不可のため、専用スタックを構築する。

---

## 構築するスタック構成

```
Claude Code
    │ OTLP HTTP（Basic 認証付き）
    ▼
OTel Collector（otel/opentelemetry-collector-contrib）
    │ Prometheus Remote Write
    ▼
Prometheus（メトリクス保存）
    │
    ▼
Grafana（可視化）
    ※ Loki（ログ保存）は任意で追加
```

---

## 実装すること

### 1. docker-compose.yml

以下のサービスを含める：
- `otel-collector` — `otel/opentelemetry-collector-contrib` イメージ
- `prometheus` — `prom/prometheus` イメージ
- `grafana` — `grafana/grafana` イメージ

ポート構成（例）:
- Grafana: `3000:3000`
- Prometheus: `9090:9090`（外部公開は任意）
- OTel Collector OTLP HTTP: `4318:4318`（Claude Code からのデータ受け口）

### 2. OTel Collector 設定（otelcol-config.yaml）

**必須: basicauth extension を使って OTLP 受信に認証をかける**

```yaml
extensions:
  basicauth/otlp:
    htpasswd:
      inline: |
        <user>:<htpasswd形式のハッシュ>

receivers:
  otlp:
    protocols:
      http:
        auth:
          authenticator: basicauth/otlp
        endpoint: 0.0.0.0:4318

processors:
  batch:
  # Delta→Cumulative 変換（念のため）
  # cumulativetodelta は不要、送り側で cumulative 設定済み

exporters:
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
  debug:
    verbosity: basic

service:
  extensions: [basicauth/otlp]
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheusremotewrite, debug]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
```

### 3. Prometheus 設定（prometheus.yml）

Remote Write 受け入れを有効化するため、起動フラグに `--web.enable-remote-write-receiver` が必要。

```yaml
global:
  scrape_interval: 15s
```

docker-compose の command で `--web.enable-remote-write-receiver` を渡す。

### 4. Grafana 設定

- Prometheus データソースを追加（`http://prometheus:9090`）
- ダッシュボードを作成：コスト推移、トークン消費、セッション数など

### 5. htpasswd ハッシュの生成

```bash
htpasswd -nbB claude <任意のパスワード>
```

または Docker で:
```bash
docker run --rm httpd htpasswd -nbB claude <パスワード>
```

---

## 完成後の Claude Code 側設定

`~/.claude/settings.json` に追加:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic <base64(user:pass)>",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",
    "OTEL_METRIC_EXPORT_INTERVAL": "10000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000"
  }
}
```

`Authorization` ヘッダーの値:
```bash
echo -n "claude:<パスワード>" | base64
```

設定後は Claude Code を再起動して反映させる。

---

## 動作確認方法

```bash
# Prometheus にメトリクスが入っているか確認
curl -s "http://localhost:9090/api/v1/label/__name__/values" | \
  grep claude

# コスト確認
curl -s "http://localhost:9090/api/v1/query?query=claude_code_cost_usage_USD_total"
```

Grafana: http://localhost:3000
