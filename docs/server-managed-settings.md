# サーバー管理設定（Managed Settings）による自動配布ガイド

Claude Team / Enterprise プランの **Managed Settings** 機能を使うと、管理者が一度設定するだけで、チーム全メンバーの `~/.claude/settings.json` に設定が自動配布されます。メンバー側の作業は一切不要です。

---

## 概要

```
管理者が claude.ai Admin Console に JSON を登録
            ↓
   各メンバーの Claude Code CLI が 1 時間ごとにポーリング
            ↓
  ~/.claude/settings.json に自動マージ（ユーザー設定を上書き）
```

- **配布間隔**: 約 1 時間（次回 CLI 起動時または自動ポーリング）
- **対象**: Teamプラン・Enterpriseプランのメンバー全員
- **上書き挙動**: Managed Settings の値はユーザーのローカル設定より優先されます

---

## 管理者の操作手順

### 1. Admin Console を開く

1. [claude.ai](https://claude.ai) にアクセス
2. 右上のアカウントメニュー → **Admin Console**
3. 左メニューから **Settings** → **Claude Code** を選択

### 2. Managed Settings に JSON を登録

以下の JSON を入力フィールドに貼り付けます。`<...>` の部分を実際の値に置き換えてください。

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.<your-domain>",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic <base64-encoded-credentials>",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "delta",
    "OTEL_METRIC_EXPORT_INTERVAL": "240000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000",
    "OTEL_LOG_TOOL_DETAILS": "0"
  }
}
```

### 3. Authorization ヘッダー値の生成

`OTEL_EXPORTER_OTLP_HEADERS` に設定する Base64 値は以下のコマンドで生成します。

`<password>` には OTel Collector の Basic 認証パスワード（`otel.htpasswd` に登録したもの）を入力してください。

**Mac / Linux:**
```bash
echo -n "claude:<password>" | base64
```

**Windows (PowerShell):**
```powershell
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("claude:<password>"))
```

出力例: `Y2xhdWRlOnBhc3N3b3Jk`

設定値の例：
```
Authorization=Basic Y2xhdWRlOnBhc3N3b3Jk
```

### 4. 保存して確認

**Save** をクリックして設定を保存します。メンバーの CLI は次のポーリングサイクル（最大 1 時間）で設定を取得します。

---

## 設定項目の説明

| キー | 値 | 説明 |
|---|---|---|
| `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` | テレメトリを有効化 |
| `OTEL_METRICS_EXPORTER` | `otlp` | メトリクスを OTLP で送信 |
| `OTEL_LOGS_EXPORTER` | `otlp` | ログを OTLP で送信 |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` | HTTP/protobuf 形式で送信 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otel.<domain>` | OTel Collector のエンドポイント URL |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Basic <base64>` | Basic 認証ヘッダー |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | `delta` | 差分形式で送信（再起動時のグラフ断絶を防ぐ） |
| `OTEL_METRIC_EXPORT_INTERVAL` | `240000` | メトリクス送信間隔（ミリ秒）。Grafana Cloud Free Tier の 1 DPM 枠に収めるため 240 秒（= 0.25 DPM）に設定 |
| `OTEL_LOGS_EXPORT_INTERVAL` | `5000` | ログ送信間隔（ミリ秒） |
| `OTEL_LOG_TOOL_DETAILS` | `0` | ツール呼び出しの詳細ログ（`1` で有効、`0` で無効。無効化するとLogs容量を大幅削減） |

---

## 収集されるユーザー識別情報

Managed Settings で配布した設定でテレメトリを有効化すると、各メトリクスに以下のラベルが自動付与されます：

| ラベル | 内容 |
|---|---|
| `user_email` | アカウントのメールアドレス |
| `user_account_uuid` | Anthropicアカウントの UUID |
| `organization_id` | 組織の ID |
| `session_id` | CLI セッションの ID |
| `model` | 使用したモデル名 |

これらのラベルを使い、Grafana ダッシュボードでユーザー別の集計・絞り込みが可能です。

> **⚠️ `session_id` ラベルは除外してはいけません**: `OTEL_METRICS_INCLUDE_SESSION_ID=false` を設定すると、同一ユーザーの複数プロセスが同じ時系列に書き込み、独立した cumulative カウンタが衝突します。結果として Mimir/Prometheus が無効なカウンタリセットを検出し、`rate()`/`increase()` が桁違いに膨らみます（過去の実例: 24 時間で 18B トークン、$10K といった異常値）。データ量削減は `OTEL_METRIC_EXPORT_INTERVAL` を延長（例: `240000` = 240 秒 = 0.25 DPM）し、`OTEL_LOG_TOOL_DETAILS=0` でログ側を絞ることで行ってください。

---

## トラブルシューティング

### 設定が反映されない

- CLI を完全に終了して再起動してください
- ポーリング間隔は最大 1 時間です。しばらく待ってから再確認してください
- `~/.claude/settings.json` を直接確認して `env` セクションが追加されているか確認してください

### データが Grafana に表示されない

1. Claude Code で何かタスクを実行する（テレメトリはアクティブ時に送信）
2. 30 秒〜1 分待つ
3. Grafana のダッシュボードを更新する
4. 時間範囲が「Last 24 hours」などに設定されているか確認する

OTel Collector のログを確認するには：
```bash
docker compose logs otel-collector -f
```

Prometheus にデータが届いているか確認するには、Grafana の Explore で以下を実行：
```promql
{__name__=~"claude_code.*"}
```

### `user_email` ラベルが空

Claude Code がバージョン古い場合、`user_email` を送信しない可能性があります。最新バージョンに更新してください：

```bash
npm update -g @anthropic-ai/claude-code
```

---

---

## Grafana Cloud を使う場合の設定

EC2 セルフホスト構成の代わりに Grafana Cloud を使う場合、設定が大きく簡略化されます。

### 違い

| 項目 | EC2 セルフホスト | Grafana Cloud |
|---|---|---|
| エンドポイント | `https://otel.<your-domain>` | `https://otlp-gateway-<region>.grafana.net/otlp` |
| 認証 | `Basic <base64(claude:password)>` | `Basic <base64(instanceId:apiKey)>` |
| OTel Collector | 必要（EC2 上で運用） | **不要**（直接送信） |
| htpasswd ファイル | 必要 | **不要** |

### Grafana Cloud 用 Managed Settings JSON

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://otlp-gateway-prod-ap-southeast-1.grafana.net/otlp",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic <base64(instanceId:apiKey)>",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",
    "OTEL_METRIC_EXPORT_INTERVAL": "240000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000",
    "OTEL_LOG_TOOL_DETAILS": "0"
  }
}
```

`instanceId` と `apiKey` は Grafana Cloud ポータルの **OpenTelemetry** タイルから取得します。
Authorization ヘッダー値の生成:

```bash
echo -n "<instanceId>:<apiKey>" | base64 | tr -d ' \n'
```

> **注意:** `base64` の出力にスペースや改行が混入すると 401 Unauthorized になります。`tr -d ' \n'` で除去してください。

詳細: [Grafana Cloud セットアップガイド](../grafana-cloud/README.md)

---

## 参考リンク

- [Claude Code Managed Settings 公式ドキュメント](https://docs.anthropic.com/ja/claude-code/settings#managed-settings)
- [Claude Code テレメトリ設定ガイド](../claude-code-telemetry-setup.md)
- [監視スタック セットアップ README](../README.md)
- [Grafana Cloud セットアップガイド](../grafana-cloud/README.md)
