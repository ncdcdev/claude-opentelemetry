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
    "OTEL_METRIC_EXPORT_INTERVAL": "10000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000",
    "OTEL_LOG_TOOL_DETAILS": "1"
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
| `OTEL_METRIC_EXPORT_INTERVAL` | `10000` | メトリクス送信間隔（ミリ秒） |
| `OTEL_LOGS_EXPORT_INTERVAL` | `5000` | ログ送信間隔（ミリ秒） |
| `OTEL_LOG_TOOL_DETAILS` | `1` | ツール呼び出しの詳細もログに記録 |

---

## 収集されるユーザー識別情報

Managed Settings で配布した設定でテレメトリを有効化すると、各メトリクスに以下のラベルが自動付与されます：

| ラベル | 内容 |
|---|---|
| `account_uuid` | Anthropicアカウントの UUID |
| `organization_id` | 組織の ID |
| `user_email` | アカウントのメールアドレス |
| `session_id` | CLI セッションの ID |
| `model` | 使用したモデル名 |

これらのラベルを使い、Grafana ダッシュボードでユーザー別の集計・絞り込みが可能です。

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

### `account_uuid` ラベルが空

Claude Code がバージョン古い場合、`account_uuid` を送信しない可能性があります。最新バージョンに更新してください：

```bash
npm update -g @anthropic-ai/claude-code
```

---

## 参考リンク

- [Claude Code Managed Settings 公式ドキュメント](https://docs.anthropic.com/ja/claude-code/settings#managed-settings)
- [Claude Code テレメトリ設定ガイド](../claude-code-telemetry-setup.md)
- [監視スタック セットアップ README](../README.md)
