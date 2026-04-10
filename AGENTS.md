# AGENTS.md — nehan.ai マルチエージェント実装ガイド

> エージェントは自分の担当セクション(§)を読み、必要に応じて他セクションを参照する。
> 全体概要は [CLAUDE.md](CLAUDE.md) を参照。

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

---

## §Worker — Cloudflare Worker (Hono + D1 + R2)

### ファイル構成
```
worker/
├── src/index.ts          -- 全ルート定義 (Hono)
├── public/index.html     -- LP (nehan.ai トップ)
├── wrangler.toml         -- 設定 (D1, R2, ルーティング)
├── migrations/
│   ├── 0001_blogs.sql    -- blogs テーブル
│   └── 0002_usernames.sql -- reserved_usernames テーブル (202件)
├── schema.sql            -- logs テーブル
└── package.json
```

### バインディング
```typescript
type Bindings = {
  DB: D1Database;       // nehan-db (APAC)
  COVERS: R2Bucket;     // nehan-covers
  API_TOKEN: string;    // wrangler secret
};
```

### ドメインルーティング
```toml
# wrangler.toml (トップレベルに配置必須)
routes = [
  { pattern = "nehan.ai/*", zone_name = "nehan.ai" },
  { pattern = "ios.nehan.ai/*", zone_name = "nehan.ai" }
]
```

### APIエンドポイント一覧

#### 認証必須 (`/api/*` — Bearer Token)
| メソッド | パス | 説明 |
|---------|------|------|
| `POST` | `/api/log` | ログ一括登録 (location/sleep/memo) |
| `GET` | `/api/logs?date=YYYY-MM-DD` | 日別ログ取得 (JST基準) |
| `GET` | `/api/summary?date=YYYY-MM-DD` | 日報Markdown取得 |
| `POST` | `/api/blog` | ブログ投稿/更新 (UPSERT by username+date) |
| `POST` | `/api/blog/cover` | カバーアートPNG → R2アップロード |
| `GET` | `/api/username/check?name=xxx` | ユーザー名利用可否チェック |

#### 公開ページ (認証不要)
| メソッド | パス | 説明 |
|---------|------|------|
| `GET` | `/` | LP (public/index.html) |
| `GET` | `/terms/privacy/:lang` | プライバシーポリシー (ja/en) |
| `GET` | `/terms/tos/:lang` | 利用規約 (ja/en) |
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
  created_at TEXT DEFAULT (datetime('now'))
);

-- blogs (migrations/0001_blogs.sql)
CREATE TABLE blogs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL, date TEXT NOT NULL,
  title TEXT, body TEXT NOT NULL, cover_url TEXT,
  is_draft INTEGER DEFAULT 0,
  published_at TEXT DEFAULT (datetime('now')),
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(username, date)
);

-- reserved_usernames (migrations/0002_usernames.sql)
CREATE TABLE reserved_usernames (username TEXT PRIMARY KEY);
-- 202件の禁止ユーザー名 (admin, root, api, blog, nehan, aicu等)
```

**日付クエリ**: `date(timestamp, '+9 hours')` で JST 変換。

### ユーザー名ルール
- 3-12文字、`/^[a-z0-9_-]{3,12}$/`
- `reserved_usernames` テーブルで禁止名チェック
- メール認証後、無償ユーザーは変更不可

### POST /api/log リクエスト例
```json
{
  "entries": [
    { "timestamp": "2026-04-10T14:30:00Z", "type": "location",
      "latitude": 35.6580, "longitude": 139.7016, "place_name": "渋谷ストリーム" },
    { "timestamp": "2026-04-10T21:00:00Z", "type": "sleep",
      "payload": "{\"asleep\":\"...\",\"awake\":\"...\",\"stages\":[...]}" },
    { "timestamp": "2026-04-10T01:00:00Z", "type": "memo",
      "payload": "打合せメモ" }
  ]
}
```

### POST /api/blog リクエスト例
```json
{
  "username": "o_ob", "date": "2026-04-11",
  "title": "連続投稿3日目", "body": "今日は...",
  "cover_url": "/o_ob/260411.png", "is_draft": false
}
```

### 開発コマンド
```bash
cd worker
npm install
npx wrangler dev                                    # ローカル開発
npx wrangler d1 execute nehan-db --remote --file=migrations/XXXX.sql  # マイグレーション
npx wrangler deploy                                 # デプロイ
echo "token" | npx wrangler secret put API_TOKEN    # シークレット設定
```

---

## §iOS — Swift/SwiftUI アプリ

### ファイル構成
```
NehanAI/NehanAI/
├── NehanAIApp.swift              -- @main, BGTaskScheduler, オンボーディング分岐
├── ContentView.swift             -- メイン画面 (タイムライン, ブログ, 同期, 座標メモ)
├── OnboardingView.swift          -- 初回: 言語→プロフィール→利用規約
├── BlogEditorView.swift          -- 6フィールド構造化エディタ + Image Playground
├── Config/AppConfig.swift        -- Bundle.main → WORKER_URL, API_TOKEN
├── Models/
│   ├── LogEntry.swift            -- Codable struct + API変換
│   ├── PlaceBookmark.swift       -- 座標メモ + Category enum
│   └── UserProfile.swift         -- プロフィール (年齢, 性別, 言語, ストリーク)
├── Services/
│   ├── LocationService.swift     -- CLLocationManager + 逆ジオコーディング
│   ├── HealthKitService.swift    -- 睡眠/歩数/心拍/生理周期
│   ├── SyncService.swift         -- バッファ管理 → POST /api/log
│   ├── BlogPublishService.swift  -- ブログ投稿 + R2カバーアップロード
│   ├── NotificationService.swift -- リマインダー通知
│   ├── FoundationModelService.swift -- オンデバイスLLM (iOS 26+)
│   └── ImagePlaygroundService.swift -- 画像生成 (iOS 18+)
├── NehanAI.entitlements
└── Info.plist
```

### 主要コンポーネント

**ContentView** — メイン画面
- ヘッダー: 天気 + 表情画像 + 日付 + ストリーク + `/{username}` Webリンク
- ステータス: 記録中/停止中 + バッファ + GPS精度 + 座標メモ名
- ライフログ: 288セルタイムライン (5分刻み) + アイコンサマリー
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
- **Secrets**: `NehanAI/Config/Secrets.xcconfig` → xcconfig example: `Secrets.xcconfig.example`
- **BGTask IDs**: `ai.aicu.nehan.healthfetch`, `ai.aicu.nehan.blogpublish`

---

## §DevOps — CI/CD・インフラ

### GitHub Actions
```yaml
# .github/workflows/daily-report.yml
# 毎日 23:00 JST (14:00 UTC) + workflow_dispatch
# Worker /api/summary → GitHub Issue (ラベル: nehan, daily-report) → Discord Webhook
```

### GitHub Secrets
| Secret | 用途 |
|--------|------|
| `NEHAN_API_TOKEN` | Worker API Bearer Token |
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
npx wrangler deploy                    # Worker デプロイ
npx wrangler d1 migrations apply nehan-db --remote  # D1マイグレーション
```

---

## §セキュリティ — 現状と対策

### 現状の問題 (2026-04-11)
1. 単一共有 `API_TOKEN` — 全ユーザー同一トークン
2. ユーザー所有権検証なし — 任意ユーザー名でブログ投稿可能
3. レート制限なし
4. メール認証未実装
5. `/api/username/check` が認証不要

### 対策ロードマップ
- **Phase 1**: D1 `users` テーブル + per-user API key (SHA-256) + 所有権検証 + レート制限
- **Phase 2**: Resend メール認証 + アカウント登録フロー
- **Phase 3**: リフレッシュトークン + デバイス管理 + 不正検知

---

## §LP・Web — ランディングページ

### LP構成 (`worker/public/index.html`)
- ヒーロー: ロゴ「N」+ キャッチコピー + App Storeバッジ(準備中)
- 6特徴カード: 日報自動作成 / 健康管理 / 家族安否確認 / Apple Intelligence / API連携(有料) / ゲーミフィケーション
- 使い方3ステップ
- フッター: プライバシーポリシー / 利用規約 / AICU Inc.

### デザイン
- 紫ベース `#4B0082`, ダークテーマ (`#0a0014`)
- 法務ページ: 白背景, `pageLayout()` 共通レイアウト
- 言語切替: `langSwitcher()` ヘルパー (ja/en)

---

## §日報出力フォーマット
```markdown
# 📍 nehan日報 2026-04-11

## 🛏️ 睡眠
- 就寝: 23:30 → 起床: 06:00 (6.5h)
  - deep: 90min / rem: 60min / core: 180min / awake: 15min

## 🏃 アクティビティ
- 歩数: 8,234 歩
- 心拍: 平均 72 bpm (↓55 ↑120)

## 📍 訪問場所
| 時刻 | 場所 | 座標 |
|------|------|------|
| 09:15〜10:00 | 自宅付近 | 35.xxxx, 139.xxxx |

## 📝 メモ
- 10:00 打合せ

---
*Generated by nehan.ai*
```

---

## §外部連携

### GitHub Actions からの利用
```bash
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
| Per-user認証 | 🔴 未着手 | §セキュリティ Phase 1 |
| GA4トラッキング | ✅ 完了 | `G-NHJNT7G479` — §DevOps GA4セクション参照 |
| Resendメール認証 | 🔴 未着手 | §セキュリティ Phase 2 |
| 静的サイト生成 | 🟡 設計中 | MkDocs Material + Cloudflare Pages |
| WeatherKit | ⏸️ ブロック | Apple Developer Program登録待ち |
| 多言語ローカライズ | 🟡 計画中 | en, zh-Hans, zh-Hant |
| 設定画面 | 🟡 計画中 | パブリッシュ時刻、言語、displayName等 |
| AdMob | 🟡 計画中 | 広告配信（HealthKitデータ非使用） |
