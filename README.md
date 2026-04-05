# claude-opentelemetry

Claude Code の利用状況（コスト・トークン・セッション数）を OpenTelemetry で収集し、Grafana で可視化する自前の監視スタック。

```text
Claude Code (local)
    │ OTLP over HTTPS
    ▼
otel.<domain>  ──┐
                  ├── EC2 t3.micro (動的IP + Route53 自動更新)
grafana.<domain>──┘
                      nginx (Let's Encrypt)
                      ├── OTel Collector :4318 (Basic Auth)
                      └── Grafana :3000
                              │
                          Prometheus :9090 (メトリクス)
                          Loki :3100 (ログ)
```

**収集データ**: メトリクス（コスト・トークン・セッション数）→ Prometheus、ログ（ツール呼び出し履歴）→ Loki

**コスト**: 使用時のみ起動（~$3/月）

![Grafana ダッシュボード](docs/images/grafana_dashboard.png)

---

## 前提条件

- AWS アカウント・CLI 設定済み（`aws login` で SSO 可）
- Route53 で管理しているドメイン
- Terraform >= 1.5
- EC2 キーペア作成済み

```powershell
# キーペア作成（未作成の場合）
aws ec2 create-key-pair --key-name claude-monitoring `
  --query 'KeyMaterial' --output text `
  | Out-File -Encoding ascii "$HOME\.ssh\claude-monitoring.pem"
```

---

## 初回セットアップ

### 1. S3 バックエンド用バケットを作成

```powershell
aws s3 mb s3://claude-monitoring-tfstate --region ap-northeast-1
```

### 2. 設定ファイルを用意

```powershell
cp infra\terraform.tfvars.example infra\terraform.tfvars
cp infra\backend.tfbackend.example infra\backend.tfbackend
cp .env.example .env
```

`infra\terraform.tfvars` を編集：

```hcl
hosted_zone_id = "Z0000000000000000000"  # Route53 ホストゾーン ID
ssh_key_name   = "claude-monitoring"     # EC2 キーペア名
```

`infra\backend.tfbackend` を確認（デフォルトのまま変更不要）：

```hcl
bucket = "claude-monitoring-tfstate"
key    = "terraform.tfstate"
region = "ap-northeast-1"
```

### 3. AWS リソースを作成

```powershell
cd infra
.\manage.ps1 apply -Profile default
cd ..
```

### 4. EC2 を起動して Route53 を更新

```powershell
.\manage.ps1 start -Profile default
```

### 5. EC2 初期設定（docker / nginx / certbot / TLS 証明書）

```powershell
.\manage.ps1 setup -KeyFile $HOME\.ssh\claude-monitoring.pem -Profile default
```

### 6. OTel 用 `otel.htpasswd` と `.env`

bcrypt の `$` は Docker Compose の `.env` 展開で壊れやすいため、**Basic 認証は `otel.htpasswd` ファイル**で渡す（`.gitignore` 済み）。

```powershell
docker run --rm httpd htpasswd -nbB claude "<任意のパスワード>" > otel.htpasswd
```

`.env` には Grafana 用など（`GF_SECURITY_ADMIN_PASSWORD` 等）だけを設定する。

### 7. 設定ファイルをデプロイしてコンテナ起動

```powershell
.\manage.ps1 deploy -KeyFile $HOME\.ssh\claude-monitoring.pem -Profile default
```

> **注意**: 初回デプロイ時は `grafana_data` ボリュームが存在しない状態で起動する必要がある。既存ボリュームがある場合は削除してから再デプロイ。
>
> ```bash
> docker compose down && docker volume rm claude-monitoring_grafana_data
> ```

---

## 日常の使い方

### 作業開始時

```powershell
.\manage.ps1 start -Profile default
# DNS 反映まで最大 60 秒
```

### 作業終了時

```powershell
.\manage.ps1 stop -Profile default
```

### 設定変更後の再デプロイ

```powershell
.\manage.ps1 start -Profile default
.\manage.ps1 deploy -KeyFile $HOME\.ssh\claude-monitoring.pem -Profile default
```

---

## Claude Code の設定

### 方法 A: サーバー管理設定（Team / Enterprise プラン推奨）

Team または Enterprise プランでは、管理者が **Admin Console** で一度設定するだけでチーム全員に自動配布できます。メンバー側の作業は不要です。

詳細: [サーバー管理設定による自動配布ガイド](docs/server-managed-settings.md)

**Admin Console に登録する JSON:**

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.<your-domain>",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic <base64(claude:<password>)>",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "delta",
    "OTEL_METRIC_EXPORT_INTERVAL": "10000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000",
    "OTEL_LOG_TOOL_DETAILS": "1"
  }
}
```

### 方法 B: 手動設定（個人・検証用）

`~/.claude/settings.json` に直接追加します。詳細: [テレメトリ設定ガイド](claude-code-telemetry-setup.md)

`Authorization` ヘッダーの値は次のコマンドで生成：

```powershell
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("claude:<password>"))
```

Claudeへ頼むと楽

設定方法：Claudeへ以下のプロンプトを入力する

```text
以下のドキュメントを参照し、テレメトリの設定をしてください
https://github.com/karuru6225/claude-opentelemetry/blob/main/claude-code-telemetry-setup.md
エンドポイントは xxxxx
パスワードは xxxx
```

---

## SSH アクセス

SSH ポートはデフォルト `2222`。開閉は Terraform で管理：

```hcl
# infra/terraform.tfvars
ssh_open = true   # 開く
ssh_open = false  # 閉じる（デフォルト）
```

変更後に `infra\manage.ps1 apply` で反映。

```powershell
ssh -i $HOME\.ssh\claude-monitoring.pem -p 2222 ec2-user@<IP>
```

---

## manage.ps1 コマンド一覧

| コマンド | 説明 |
| --- | --- |
| `.\manage.ps1 start` | EC2 起動 + Route53 A レコード更新 |
| `.\manage.ps1 stop` | EC2 停止 |
| `.\manage.ps1 setup -KeyFile <pem>` | 初回のみ: docker/nginx/certbot インストール |
| `.\manage.ps1 deploy -KeyFile <pem>` | 設定ファイル転送 + nginx 設定 + コンテナ起動 |

すべてのコマンドに `-Profile <name>` を付けると AWS プロファイルを指定できる。

---

## 監視スタックの選択

| | EC2 セルフホスト（本ドキュメント） | Grafana Cloud |
|---|---|---|
| インフラ管理 | 必要（EC2/nginx/certbot） | **不要** |
| コスト | ~$3/月 | **Free Tier あり** |
| OTel Collector | 必要 | **不要** |
| データ保持 | 90日（設定変更可） | 14日（Free）|

**Grafana Cloud を使う場合**: [grafana-cloud/README.md](grafana-cloud/README.md) を参照してください。

---

## ユーザー別ダッシュボード

Grafana ダッシュボードにはチーム全体のサマリーに加え、**ユーザー別分析**セクションが含まれています。

- **ユーザー選択ドロップダウン**: 特定のメンバーに絞り込んで全パネルを確認
- **ユーザー別コスト / トークン / セッション数**: 横棒グラフで一覧比較
- **ユーザー別コスト・トークン推移**: 時系列グラフ
- **ユーザー別コード変更行数・アクティブ時間**: 作業量の可視化

各ユーザーは `user_email` ラベルで識別されます。

---

## 会社展開時の拡張

`.env` の以下を有効化するだけで Google Workspace SSO が使える：

```ini
GF_AUTH_GOOGLE_ENABLED=true
GF_AUTH_GOOGLE_CLIENT_ID=<GCP OAuth クライアント ID>
GF_AUTH_GOOGLE_CLIENT_SECRET=<シークレット>
GF_AUTH_GOOGLE_ALLOWED_DOMAINS=yourcompany.com
```

その後 `.\manage.ps1 deploy` で反映。
