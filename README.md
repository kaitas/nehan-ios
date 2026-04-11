# nehan.ai

iPhoneのヘルスケアデータから日報を自動生成するライフログアプリ。

## データフロー — 端末 vs クラウド

```mermaid
flowchart TB
    subgraph iPhone["iPhone (端末)"]
        HK[HealthKit<br/>睡眠・歩数・心拍・HRV]
        CL[CoreLocation<br/>位置情報]
        FM[Foundation Models<br/>オンデバイスAI]
        IP[Image Playground<br/>カバーアート生成]
        KC[Keychain<br/>API Key / Device ID]
        UD[UserDefaults<br/>プロフィール・設定<br/>ブログ下書き・ストリーク]
        FS[FileSystem<br/>カバー画像キャッシュ]
    end

    subgraph Cloud["Cloudflare (クラウド)"]
        D1[(D1 Database<br/>users / logs / blogs<br/>email_verifications<br/>waitlist)]
        R2[(R2 Storage<br/>カバー画像)]
        RE[Resend API<br/>メール認証]
    end

    HK -->|読み取り専用| iPhone
    CL -->|バックグラウンド| iPhone

    iPhone -->|POST /api/log<br/>Bearer Token| D1
    iPhone -->|POST /api/blog<br/>本文+タイトル| D1
    iPhone -->|POST /api/blog/cover<br/>PNG upload| R2
    iPhone -->|POST /api/register<br/>device_id| D1
    iPhone -->|POST /api/verify-email/send| RE

    D1 -->|GET /api/logs<br/>今日のデータ復元| iPhone
    D1 -->|GET /api/me<br/>ユーザー情報| iPhone
```

## 認証・起動フロー

```mermaid
flowchart TD
    Start([アプリ起動]) --> CheckAuth{Keychain に<br/>API Key あり?}
    CheckAuth -->|No| CheckOnboard{オンボーディング<br/>完了済み?}
    CheckOnboard -->|No| Onboard[OnboardingView<br/>利用規約・プロフィール]
    CheckOnboard -->|Yes| Register[POST /api/register<br/>API Key 取得]
    Onboard --> Register
    Register --> SaveKey[Keychain に保存]
    SaveKey --> Content

    CheckAuth -->|Yes| Content[ContentView<br/>メイン画面]
    Content --> FetchMe[GET /api/me<br/>ティア確認]
    Content --> FetchLogs[GET /api/logs?date=today<br/>今日のデータ復元]
    Content --> StartTracking[位置情報・HealthKit<br/>記録開始]
```

## ティアモデル

```mermaid
flowchart LR
    W[Waitlist<br/>メールのみ] -.->|アプリDL| G
    G[Tier 0: Guest<br/>ログ記録・閲覧] -->|メール認証<br/>ユーザー名<br/>ToS承認| R[Tier 1: Registered<br/>ブログ公開]
    R -.->|将来| P[Tier 2: Pro<br/>API連携・外部配信]
```

| Tier | 名称 | 条件 | できること |
|------|------|------|-----------|
| — | Waitlist | LP でメール登録 | リリース通知 |
| 0 | Guest | アプリ起動 + device 登録 | ログ記録・同期・閲覧・下書き |
| 1 | Registered | メール認証 + ユーザー名 + ToS | ブログ公開・カバーアート |
| 2 | Pro (将来) | サブスクリプション | API連携・外部配信 |

## データ所在一覧

| データ | 端末 | クラウド | 備考 |
|--------|------|---------|------|
| API Key | Keychain | users.api_key_hash (SHA-256) | 端末: 平文 / クラウド: ハッシュのみ |
| Device ID | Keychain | users.device_id | UUID, アプリ再インストールでも維持 |
| プロフィール (生年月日・性別・言語) | UserDefaults | users (demographics) | 双方に保存、端末が正 |
| HealthKit データ | HealthKit (OS管理) | logs テーブル (数値のみ) | 端末: 生データ / クラウド: 集計値 |
| 位置情報 | CoreLocation (OS管理) | logs テーブル (緯度経度) | シークレット場所は座標なし |
| ブログ本文 | UserDefaults (下書き) | blogs テーブル | 公開後は端末の下書きを削除 |
| カバー画像 | Documents/ (PNG) | R2 Storage | 端末: キャッシュ / クラウド: 正本 |
| AI生成テキスト | — (メモリのみ) | blogs.body に含まれる | Foundation Models でオンデバイス生成 |
| メール認証コード | — | email_verifications | 10分TTL、使い捨て |
| ブログストリーク | UserDefaults | — | 端末のみ (将来クラウド化検討) |
| 座標メモ (PlaceBookmark) | UserDefaults | — | 端末のみ、プライバシー保護 |

## セキュリティ方針

- HealthKit データは広告目的に使用禁止 (Apple ガイドライン)
- 全 API 通信は HTTPS + Bearer Token
- AI処理は Foundation Models (オンデバイス)、外部 AI サービス不使用
- パスワードなし認証 (Device ID + メール認証コード)
- カバー画像は R2 に保存、公開ブログからのみアクセス可能

## 開発

```bash
# Worker
cd worker && npm install && npx wrangler dev

# iOS
open NehanAI/NehanAI.xcodeproj
# Xcode: iOS 26+ / iPhone 実機 (HealthKit はシミュレータ非対応)
```

詳細は [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md) を参照。
