# AGENTS.md — nehan.ai マルチエージェント実装ガイド

> エージェントは自分の担当セクション(§)を読み、必要に応じて他セクションを参照する。
> 全体概要は [CLAUDE.md](CLAUDE.md) を参照。
> **優先順位**: CLAUDE.md > AGENTS.md（矛盾がある場合はCLAUDE.mdを優先）

---

## §運用ルール — エージェントの行動規範

### 「依頼：」Issue
マスター（@kaitas）が手動で操作しなければ進まないタスク（外部サービスの設定、課金、アカウント登録等）は、エージェントが自力で解決しようとせず **Issue タイトルに「依頼：」プレフィックス** を付けて作成する。

- タイトル: `依頼：〇〇の設定`
- 本文に必ず含めること:
  1. **設定URL**: ブラウザで開くべきダッシュボード/コンソールの直リンク
  2. **手順**: スクリーンショットがなくても迷わないレベルの丁寧な手順説明
  3. **完了条件**: 何が得られたら完了か（例: 測定IDをコードに反映、シークレットを設定）
  4. **コード側の対応**: エージェントがコードに反映する箇所（ファイルパス + 該当行）
- ラベル: `nehan` + 適切なラベル
- アサイン: `@kaitas`

**例**: GA4の測定ID取得、Apple Developer Program登録、Stripe本番キー設定、wrangler secret設定 等

### 2段階ユーザーモデル
- **Guest (Tier 0)**: アプリ初回起動時に自動登録。データ同期可能、ブログ公開不可。
- **Registered (Tier 1)**: メール認証 + ユーザー名確定 + nehan.ai利用規約承認。ブログ公開可能。
- **Pro (Tier 2)**: サブスクリプション（将来）。API連携・外部配信。

### FTUE (First Time User Experience)
- `needsFTUE`: `!profileStore.profile.onboardingCompleted || !AuthService.shared.isRegistered`
- Keychainに API Key がない場合 → 必ずオンボーディングを表示
- ローカルデータがあっても認証未確立なら FTUE に戻す
- オンボーディング完了フロー（非同期）:
  1. `AuthService.shared.register()` — device_id生成 → POST /api/register → API key取得 → Keychain保存
  2. `AuthService.shared.syncDemographics()` — ユーザー属性同期
  3. `profileStore.completeOnboarding()` — onboardingCompleted = true → ContentView遷移
- 13歳未満は利用規約に基づき利用不可（年齢ゲート）
- スプラッシュ画面: ContentView起動時にプログレスバー + ステータステキスト表示

---

## §FlavorText — AIウェルカムメッセージ仕様

### 概要
ContentView トップに表示される1行のAI生成ウェルカムメッセージ。
Foundation Models (オンデバイスAI) で生成。最大40文字。

### 実装場所
- `ContentView.swift` → `generateFlavorText()` / `flavorTextPrompt(hour:lang:context:event:)`
- `FoundationModelService.swift` → `generate(prompt:)`

### 時間帯別システムプロンプト

| 時間帯 | ペルソナ | 例 (ja) |
|--------|---------|---------|
| 06:00–11:59 | おはよう。睡眠・夢について評価 | 「7時間眠れましたね、いい朝です」 |
| 12:00–17:59 | アクティブな活動を支援 | 「1,200歩達成！午後も頑張って」 |
| 18:00–23:59 | 今日の頑張りを認め、就寝を促す | 「お疲れさま、そろそろ休みましょう」 |
| 00:00–05:59 | おやすみ。チル・リラックスを促す | 「深夜ですね、ゆっくり休んで」 |

### `flavorTextPrompt()` API
```swift
static func flavorTextPrompt(
    hour: Int,         // 0-23
    lang: String,      // "ja", "en", etc.
    context: String,   // HealthKit/位置情報の要約
    event: String?     // イベント・プロモーション上書き (nil = 通常)
) -> String
```

### イベント・プロモーション拡張
`event` パラメータに文字列を渡すと、時間帯ペルソナを上書きする。

用途例:
- 季節イベント: `"It's New Year's Day! Wish the user a happy new year."`
- プロモーション: `"nehan.ai Pro is now available! Mention the new features."`
- 記念日: `"Today is the user's birthday! Celebrate warmly."`
- 天気連動: `"It's raining outside. Suggest indoor activities."`

### 多言語対応
- `lang` パラメータで出力言語を制御
- プロンプトは英語で記述し、出力のみ指定言語
- 対応言語: ja, en, zh-Hans, zh-Hant

### 制約
- 最大40文字（UIで `.prefix(40)` で切り詰め）
- 改行・引用符・Markdownは自動除去
- Foundation Models 非対応端末ではフォールバック（テンプレートメッセージ）

---

## §Worker — Cloudflare Worker (Hono + D1 + R2)

### ファイル構成
```
worker/
├── src/
│   ├── index.ts              -- ルート定義 + auth middleware (Hono)
│   ├── admin.ts              -- Admin Dashboard (Basic Auth + D1 stats)
│   └── legal.ts              -- iOS ToS / Service ToS コンテンツ
├── public/index.html         -- LP (nehan.ai トップ)
├── wrangler.toml             -- 設定 (D1, R2, ルーティング)
├── migrations/
│   ├── 0001_blogs.sql        -- blogs テーブル
│   ├── 0002_usernames.sql    -- reserved_usernames テーブル
│   ├── 0003_users.sql        -- users テーブル (per-user auth)
│   ├── 0004_logs_user_id.sql -- logs.user_id カラム追加
│   ├── 0005_blogs_user_id.sql -- blogs.user_id カラム追加
│   ├── 0006_email_verification.sql -- email_verifications テーブル
│   └── 0007_user_demographics.sql -- users.language/gender/birth_year
├── schema.sql                -- logs テーブル
└── package.json
```

### バインディング
```typescript
type Bindings = {
  DB: D1Database;       // nehan-db (APAC)
  COVERS: R2Bucket;     // nehan-covers
  API_TOKEN: string;    // wrangler secret (legacy, GitHub Actions互換)
  RESEND_API_KEY: string; // wrangler secret (メール認証)
  ADMIN_TOKEN: string;  // wrangler secret (Admin Dashboard Basic Auth)
};
```

### Auth Middleware
```typescript
// 1. POST /api/register → 認証不要
// 2. Bearer token === API_TOKEN → owner user (GitHub Actions互換)
// 3. Bearer token → SHA-256 hash → users.api_key_hash lookup
```

### ドメインルーティング
```toml
routes = [
  { pattern = "nehan.ai/*", zone_name = "nehan.ai" },
  { pattern = "ios.nehan.ai/*", zone_name = "nehan.ai" }
]
```
**重要**: APIリクエストは必ず `ios.nehan.ai` を使用すること。`workers.dev` URL (`nehan-worker.*.workers.dev`) ではカスタムルートが正しく動作せず404を返す。`Secrets.xcconfig` の `WORKER_URL` は `https://ios.nehan.ai` を設定すること。

### APIエンドポイント一覧

#### 認証不要
| メソッド | パス | 説明 |
|---------|------|------|
| `POST` | `/api/register` | ゲスト登録 (device_id → API key発行) |

#### 認証必須 (`/api/*` — Bearer Token)
| メソッド | パス | 説明 |
|---------|------|------|
| `GET` | `/api/me` | 認証ユーザープロフィール取得 |
| `POST` | `/api/log` | ログ一括登録 (user_id付与) |
| `GET` | `/api/logs?date=YYYY-MM-DD` | 日別ログ取得 (user_idフィルタ) |
| `GET` | `/api/summary?date=YYYY-MM-DD` | 日報Markdown取得 |
| `POST` | `/api/blog` | ブログ投稿/更新 (Tier 1必須, usernameはauth contextから) |
| `POST` | `/api/blog/cover` | カバーアートPNG → R2 (Tier 1必須) |
| `DELETE` | `/api/blog` | ブログ削除 + R2カバー削除 |
| `DELETE` | `/api/account` | 全データ削除 (blogs, logs, R2, user) |
| `GET` | `/api/username/check?name=xxx` | ユーザー名利用可否チェック |
| `POST` | `/api/verify-email/send` | メール認証コード送信 (Resend) |
| `POST` | `/api/verify-email/confirm` | メール認証コード検証 |
| `PUT` | `/api/me/demographics` | ユーザー属性更新 (language, gender, birth_year) |
| `POST` | `/api/upgrade` | Tier 0 → Tier 1 昇格 (email認証+username+ToS) |

#### Admin Dashboard (Basic Auth: `admin` / `ADMIN_TOKEN`)
| メソッド | パス | 説明 |
|---------|------|------|
| `GET` | `/admin` | ダッシュボードHTML (ユーザー数, ブログ数, メール認証率等) |
| `GET` | `/admin/api/stats` | 全統計JSON |
| `GET` | `/admin/api/retention` | 7日間コホートリテンションJSON |
| `GET` | `/admin/api/features` | ログ種別分布JSON |

#### 公開ページ (認証不要)
| メソッド | パス | 説明 |
|---------|------|------|
| `GET` | `/` | LP (public/index.html) |
| `GET` | `/terms/privacy/:lang` | プライバシーポリシー (ja/en) |
| `GET` | `/terms/tos/:lang` | nehan.aiサービス利用規約 (ja/en) |
| `GET` | `/terms/ios-tos/:lang` | iOSアプリ利用規約 (ja/en) |
| `GET` | `/dashboard` | ダッシュボード (準備中) |
| `GET` | `/:username` | ブログ一覧 |
| `GET` | `/:username/YYMMDD` | ブログ記事表示 (HTML) |
| `GET` | `/:username/YYMMDD.md` | ブログ記事 (raw Markdown) |
| `GET` | `/:username/YYMMDD.png` | カバーアート (R2) |

**ルート順序が重要**: `.md`/`.png` 正規表現ルート → catch-all `/:username/:date` の順。

### D1スキーマ
```sql
-- logs (schema.sql)
CREATE TABLE logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('location', 'sleep', 'memo')),
  latitude REAL, longitude REAL, place_name TEXT,
  payload TEXT, synced_from TEXT DEFAULT 'ios',
  user_id INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

-- blogs (migrations/0001_blogs.sql + 0005)
CREATE TABLE blogs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL, date TEXT NOT NULL,
  title TEXT, body TEXT NOT NULL, cover_url TEXT,
  is_draft INTEGER DEFAULT 0,
  user_id INTEGER,
  published_at TEXT DEFAULT (datetime('now')),
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(username, date)
);

-- users (migrations/0003_users.sql)
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE,
  email TEXT, email_verified_at TEXT,
  api_key_hash TEXT NOT NULL,
  device_id TEXT UNIQUE NOT NULL,
  tier INTEGER DEFAULT 0,
  tos_accepted_at TEXT, tos_version TEXT,
  language TEXT, gender TEXT, birth_year INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

-- email_verifications (migrations/0006)
CREATE TABLE email_verifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  email TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  used_at TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- reserved_usernames (migrations/0002_usernames.sql)
CREATE TABLE reserved_usernames (username TEXT PRIMARY KEY);
```

**日付クエリ**: `date(timestamp, '+9 hours')` で JST 変換。

### ユーザー名ルール
- 3-12文字、`/^[a-z0-9_-]{3,12}$/`
- `reserved_usernames` テーブルで禁止名チェック
- `users` テーブルで重複チェック
- メール認証後、無償ユーザーは変更不可

### 既存データ移行 (手動実行)
```sql
INSERT INTO users (username, api_key_hash, device_id, tier, tos_accepted_at)
VALUES ('o_ob', '<sha256-of-API_TOKEN>', 'owner-device', 1, datetime('now'));
UPDATE logs SET user_id = 1 WHERE user_id IS NULL;
UPDATE blogs SET user_id = 1 WHERE username = 'o_ob';
```

### 開発コマンド
```bash
cd worker
npm install
npx wrangler dev                                    # ローカル開発
npx wrangler d1 migrations apply nehan-db --remote  # マイグレーション
npx wrangler deploy                                 # デプロイ
echo "token" | npx wrangler secret put API_TOKEN    # シークレット設定
echo "key" | npx wrangler secret put RESEND_API_KEY # Resendキー設定
echo "pw" | npx wrangler secret put ADMIN_TOKEN     # 管理画面パスワード
```

---

## §iOS — Swift/SwiftUI アプリ

### ファイル構成
```
NehanAI/NehanAI/
├── NehanAIApp.swift              -- @main, BGTaskScheduler, auto-registration
├── ContentView.swift             -- メイン画面 (タイムライン, ブログ, 同期, 座標メモ)
├── OnboardingView.swift          -- 初回: 言語→プロフィール→iOS ToS
├── BlogEditorView.swift          -- 6フィールド構造化エディタ + Image Playground
├── RegistrationView.swift        -- Tier 1登録フロー (ToS→メール→コード→ユーザー名)
├── SettingsView.swift            -- アカウント管理 (プロフィール, 法的情報, 削除)
├── Config/AppConfig.swift        -- Bundle.main → WORKER_URL, API_TOKEN (legacy)
├── Models/
│   ├── LogEntry.swift            -- Codable struct + API変換
│   ├── PlaceBookmark.swift       -- 座標メモ + Category enum
│   └── UserProfile.swift         -- プロフィール (年齢, 性別, 言語, ストリーク)
├── Services/
│   ├── AuthService.swift         -- デバイス登録, API key管理, ユーザープロフィール同期
│   ├── KeychainService.swift     -- Security framework wrapper (API key, device_id)
│   ├── LocationService.swift     -- CLLocationManager + 逆ジオコーディング
│   ├── HealthKitService.swift    -- 睡眠/歩数/心拍/生理周期
│   ├── SyncService.swift         -- バッファ管理 → POST /api/log (AuthService.apiKey使用)
│   ├── BlogPublishService.swift  -- ブログ投稿 + R2カバー (AuthService.apiKey使用)
│   ├── NotificationService.swift -- リマインダー通知
│   ├── FoundationModelService.swift -- オンデバイスLLM (iOS 26+)
│   └── ImagePlaygroundService.swift -- 画像生成 (iOS 18+)
├── NehanAI.entitlements
└── Info.plist
```

### 認証フロー
1. 初回起動: FTUE判定 → OnboardingView (言語→プロフィール→iOS ToS)
2. 「同意してはじめる」→ `register()` → `syncDemographics()` → `completeOnboarding()`
3. ContentView遷移 → `.task` で `fetchMe()` + `syncDemographics()` 再実行
4. 以降全APIコールは `AuthService.shared.apiKey` で認証
5. レガシー移行: Keychain にAPI keyなし + AppConfig.apiToken あり → レガシーで一時利用

### AppConfig URL解決
- `Secrets.xcconfig` → Info.plist `$(WORKER_URL)` → `AppConfig.workerURL`
- **フォールバック**: xcconfig未設定時 (`""` or `"$(WORKER_URL)"`) → `https://ios.nehan.ai`
- `!url.isEmpty && !url.hasPrefix("$(")` で未展開マクロを検出

### ブログ公開ゲート
- BlogEditorViewの「公開」ボタン → Tier 0なら `RegistrationView` をsheet表示
- RegistrationView: Service ToS → メール入力 → 6桁コード → ユーザー名 → POST /api/upgrade → 即公開

### アカウント削除
- SettingsView → 「アカウントを削除」→ DELETE /api/account
- Keychain + UserDefaults クリア → OnboardingViewに戻る

### 主要コンポーネント

**ContentView** — メイン画面
- ヘッダー: 天気 + 表情画像 + 日付 + ストリーク + `/{username}` Webリンク
- ステータス: 記録中/停止中 + バッファ + GPS精度 + 座標メモ名
- ライフログ: 288セルタイムライン (5分刻み) + アイコンサマリー
- クイック記録: カフェイン・飲水・歯磨き・頭痛・手洗い
- ブログ: プレビュー → エディタsheet
- 操作: 同期 + ヘルスデータ取得 + 座標メモ一覧

**BlogEditorView** — 6フィールド
1. 日付・天気・ヘルス (sun.max)
2. 睡眠情報 (moon.zzz)
3. 夢日記 (moon.stars)
4. 訪問場所 (mappin.and.ellipse)
5. 今日の感想 (face.smiling) — Foundation Models自動生成
6. やり残し (checklist)
- カバーアート: Image Playground (1:1) → `croppedTo16x9()` センタークロップ

**PlaceBookmark** — 座標メモ
```swift
enum Category: String, Codable, CaseIterable {
    case home = "自宅"       // house.fill
    case work = "職場"       // building.2.fill
    case desk = "自席"       // desktopcomputer
    case bedroom = "寝室"    // bed.double.fill
    case other = "その他"    // mappin
}
```
- 200m以内マッチング + lastVisitedAt自動更新
- UserDefaults永続化

**UserProfile** — `@Observable`, UserDefaults
- `displayName`, `language`, `birthYear`, `birthMonth`, `birthDay`, `gender`
- `recordPlaceNames`, `blogPublishHour` (デフォルト20時)
- `currentStreak`, `lastBlogDate`

### Xcode設定
- **Capabilities**: Background Modes (Location, Fetch, Processing), HealthKit, WeatherKit
- **Secrets**: `NehanAI/Config/Secrets.xcconfig` (gitignored)
  ```ini
  API_TOKEN = <legacy-shared-token>
  WORKER_URL = https:/$()/ios.nehan.ai
  ```
  **注意**: `WORKER_URL` は必ず `ios.nehan.ai` を指定。`workers.dev` URLは404になる。
- **BGTask IDs**: `ai.aicu.nehan.sync`, `ai.aicu.nehan.sleep`, `ai.aicu.nehan.blogpublish`

---

## §DevOps — CI/CD・インフラ

### GitHub Actions
```yaml
# .github/workflows/daily-report.yml
# 毎日 23:00 JST (14:00 UTC) + workflow_dispatch
# Worker /api/summary → GitHub Issue (ラベル: nehan, daily-report) → Discord Webhook
# 認証: legacy API_TOKEN (owner user として動作)
```

### GitHub Secrets
| Secret | 用途 |
|--------|------|
| `NEHAN_API_TOKEN` | Worker API Bearer Token (legacy, owner互換) |
| `NEHAN_WORKER_URL` | `https://ios.nehan.ai` |
| `DISCORD_WEBHOOK_URL` | Discord通知 |

### Cloudflare リソース
| リソース | 名前 | リージョン |
|---------|------|----------|
| Worker | `nehan-worker` | — |
| D1 | `nehan-db` | APAC |
| R2 | `nehan-covers` | — |
| DNS | `nehan.ai` CNAME → Worker | — |
| DNS | `ios.nehan.ai` CNAME → Worker | — |

### Worker Secrets
| Secret | 用途 |
|--------|------|
| `API_TOKEN` | Legacy shared token (GitHub Actions互換) |
| `RESEND_API_KEY` | Resend メール認証API |
| `ADMIN_TOKEN` | Admin Dashboard Basic Auth パスワード |

### Google Analytics 4 (GA4)
| 項目 | 値 |
|------|-----|
| 測定ID | `G-NHJNT7G479` |
| ストリーム名 | nehan.ai Web |
| ストリームURL | https://nehan.ai |
| ストリームID | 14348007420 |
| ダッシュボード | https://analytics.google.com/ |

タグ挿入箇所:
- `worker/public/index.html` — LP `<head>` 内
- `worker/src/index.ts` — `pageLayout()` `<head>` 内（全公開ページ共通）

### デプロイフロー
```bash
cd worker
npx wrangler d1 migrations apply nehan-db --remote  # D1マイグレーション (先に実行)
npx wrangler deploy                                 # Worker デプロイ
```

---

## §セキュリティ — 認証・データ分離

### 2段階ユーザーモデル
| Tier | 名称 | 条件 | 機能 |
|------|------|------|------|
| 0 | Guest | アプリ起動 → 自動登録 | データ同期, ログ閲覧 |
| 1 | Registered | メール認証 + ユーザー名 + ToS同意 | ブログ公開, カバーアート |

### Auth Middleware フロー
```
Bearer Token
  ├─ === API_TOKEN → owner user (id=1, legacy互換)
  └─ SHA-256 hash → users.api_key_hash → user context
```

### セキュリティ対策状況
| 対策 | 状態 |
|------|------|
| Per-user API key (SHA-256) | ✅ 実装済み |
| users テーブル + データ分離 | ✅ 実装済み |
| ブログ公開 Tier ゲート | ✅ 実装済み |
| メール認証 (Resend) | ✅ 実装済み (要RESEND_API_KEY設定) |
| アカウント削除 | ✅ 実装済み |
| ブログ削除 | ✅ 実装済み |
| iOS ToS / Service ToS | ✅ 実装済み |
| Admin Dashboard | ✅ 実装済み (要ADMIN_TOKEN設定) |
| レート制限 | 🔴 未着手 |
| リフレッシュトークン | 🔴 未着手 |
| 不正検知 | 🔴 未着手 |

---

## §LP・Web — ランディングページ

### LP構成 (`worker/public/index.html`)
- ヒーロー: ロゴ「N」+ キャッチコピー + App Storeバッジ(準備中)
- 6特徴カード: 日報自動作成 / 健康管理 / 家族安否確認 / Apple Intelligence / API連携(有料) / ゲーミフィケーション
- 使い方3ステップ
- フッター: プライバシーポリシー / 利用規約 / AICU Inc.

### 法務ページ
| パス | 内容 | 対象 |
|------|------|------|
| `/terms/ios-tos/:lang` | iOSアプリ利用規約 (軽量) | Guest (Tier 0) |
| `/terms/tos/:lang` | nehan.aiサービス利用規約 (Medium構造) | Registered (Tier 1) |
| `/terms/privacy/:lang` | プライバシーポリシー | 全ユーザー |

### デザイン
- 紫ベース `#4B0082`, ダークテーマ (`#0a0014`)
- 法務ページ: 白背景, `pageLayout()` 共通レイアウト
- 言語切替: `langSwitcher()` ヘルパー (ja/en)

---

## §日報出力フォーマット
```markdown
# nehan日報 2026-04-11

## 睡眠
- 就寝: 23:30 → 起床: 06:00 (6.5h)
  - deep: 90min / rem: 60min / core: 180min / awake: 15min

## アクティビティ
- 歩数: 8,234 歩
- 心拍: 平均 72 bpm (↓55 ↑120)

## 訪問場所
| 時刻 | 場所 | 座標 |
|------|------|------|
| 09:15〜10:00 | 自宅付近 | 35.xxxx, 139.xxxx |

## メモ
- 10:00 打合せ

---
*Generated by nehan.ai*
```

---

## §外部連携

### GitHub Actions からの利用
```bash
# Legacy API_TOKEN はowner user (id=1) として認証される
curl -H "Authorization: Bearer $NEHAN_API_TOKEN" \
  "$NEHAN_WORKER_URL/api/logs?date=2026-04-11"

curl -H "Authorization: Bearer $NEHAN_API_TOKEN" \
  "$NEHAN_WORKER_URL/api/summary?date=2026-04-11"
```

### Discord Webhook
GitHub Actions daily-report.yml から embed 形式で通知。
Secret: `DISCORD_WEBHOOK_URL`

---

## §未実装・計画中

| 項目 | 状態 | 詳細 |
|------|------|------|
| Per-user認証 | ✅ 完了 | users テーブル + SHA-256 API key |
| GA4トラッキング | ✅ 完了 | `G-NHJNT7G479` — §DevOps GA4セクション参照 |
| Resendメール認証 | ✅ 完了 | 要 `RESEND_API_KEY` wrangler secret設定 |
| iOS ToS / Service ToS | ✅ 完了 | `/terms/ios-tos/:lang`, `/terms/tos/:lang` |
| アカウント管理 (SettingsView) | ✅ 完了 | 削除, 法的情報リンク |
| Admin Dashboard | ✅ 完了 | `/admin` — Basic Auth, 要 `ADMIN_TOKEN` wrangler secret |
| レート制限 | 🔴 未着手 | Cloudflare Rate Limiting検討 |
| 静的サイト生成 | 🟡 設計中 | MkDocs Material + Cloudflare Pages |
| WeatherKit | ⏸️ ブロック | Apple Developer Program登録待ち |
| 多言語ローカライズ | 🟡 計画中 | en, zh-Hans, zh-Hant |
| AdMob | 🟡 計画中 | 広告配信（HealthKitデータ非使用） |
| リフレッシュトークン | 🔴 未着手 | §セキュリティ Phase 3 |
