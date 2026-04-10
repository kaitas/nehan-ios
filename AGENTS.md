# AGENTS.md — nehan.ai 実装ガイド

考えるのは英語、ユーザに表示する言語は日本語のケースが多いと思うので、ドキュメントは日本語で書いています。

## システム概要

nehan.ai は「あなたのiPhoneヘルスケアが、そのまま日記になる」ライフログ日報システム。
iOS アプリがバックグラウンドで位置情報・睡眠データ・HealthKitデータを自動記録し、Cloudflare Worker (D1) に同期。
毎日 23:00 JST に GitHub Actions が日報 Issue を作成し Discord に通知する(有料オプション)
日報はブログ（公開/非公開）として自動生成され、ゲーミフィケーション要素で継続を促進する。

### コンセプト
- **ヘルスケア→日記**: HealthKitデータが自動で日記・ブログになる
- **オンデバイスAI**: Foundation Models framework でローカルLLM推論（状態評価・要約）
- **画像生成**: Image Playground framework でカバーアート生成 + PhotosPicker でカメラロール選択
- **ゲーミフィケーション**: 継続記録・達成バッジ・ストリークでモチベーション維持
- **グローバル展開**: 日本語版を先行し、多言語対応（英語・中国語等）を初期設計から考慮
- **夢日記**: 起床時に夢の内容を記録（オンデバイスLLMで分析）
- **生理周期**: 女性ユーザー向けに周期記録 + 主観的な体調をemojiで記録

### オンデバイスAI機能
- **Foundation Models framework** (iOS 26+): テキスト要約・状態評価をローカルで実行
- **Image Playground framework** (iOS 18+): Apple標準の画像生成でカバーアート・状態イラストを生成
- HealthKitデータ・位置情報から1日のコンディションをスコアリング
- ブログ記事のタイトル・要約を自動生成

```
┌─────────────────────┐
│  iOS App (Swift)     │
│  - CoreLocation      │  POST /api/log
│  - HealthKit         │───────────────┐
│  - BackgroundTasks   │               │
└─────────────────────┘               ▼
                            ┌──────────────────┐
                            │ Cloudflare Worker │
                            │ Hono + D1         │
                            │                    │
                            │ POST /api/log      │
                            │ GET  /api/logs     │
                            │ GET  /api/summary  │
                            └────────┬─────────┘
                                     │
               ┌─────────────────────┼──────────────────────┐
               ▼                     ▼                      ▼
    GitHub Actions (23:00 JST)   外部 Actions          他サービス
    → /api/summary 取得          → /api/logs 取得
    → GitHub Issue 作成          → データ活用
    → Discord 通知
```

## Worker API リファレンス

### 認証
全 `/api/*` エンドポイントは Bearer Token 認証。
```
Authorization: Bearer <API_TOKEN>
```

### `POST /api/log` — ログ一括登録
```json
{
  "entries": [
    {
      "timestamp": "2026-04-10T14:30:00Z",
      "type": "location",
      "latitude": 35.6580,
      "longitude": 139.7016,
      "place_name": "渋谷ストリーム"
    },
    {
      "timestamp": "2026-04-09T21:00:00Z",
      "type": "sleep",
      "payload": "{\"asleep\":\"2026-04-09T14:30:00Z\",\"awake\":\"2026-04-09T21:00:00Z\",\"stages\":[{\"stage\":\"deep\",\"minutes\":90},{\"stage\":\"rem\",\"minutes\":60},{\"stage\":\"core\",\"minutes\":180},{\"stage\":\"awake\",\"minutes\":15}]}"
    },
    {
      "timestamp": "2026-04-10T01:00:00Z",
      "type": "memo",
      "payload": "Jerry Chiと打合せ@渋谷ストリーム"
    }
  ]
}
```

**レスポンス**: `{"ok": true, "count": 3}`

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `timestamp` | string (ISO8601) | Yes | UTC推奨。JST offset付きも可 |
| `type` | `"location"` \| `"sleep"` \| `"memo"` | Yes | ログ種別 |
| `latitude` | number | No | 緯度 (location用) |
| `longitude` | number | No | 経度 (location用) |
| `place_name` | string | No | 地名 (逆ジオコーディング結果) |
| `payload` | string | No | 任意データ (sleep: JSON, memo: テキスト) |

### `GET /api/logs?date=YYYY-MM-DD` — 日別ログ取得
日付は **JST** 基準。`date(timestamp, '+9 hours')` で比較。

**レスポンス例**:
```json
{
  "results": [
    {
      "id": 1,
      "timestamp": "2026-04-10T01:00:00Z",
      "type": "memo",
      "latitude": null,
      "longitude": null,
      "place_name": null,
      "payload": "テスト投稿",
      "synced_from": "ios",
      "created_at": "2026-04-10 00:12:00"
    }
  ],
  "success": true
}
```

### `GET /privacy` — プライバシーポリシー
認証不要。日本語HTMLでプライバシーポリシーを表示。App Store審査用URL。

### `GET /terms` — 利用規約
認証不要。日本語HTMLで利用規約を表示。App Store審査用URL。

### `GET /dashboard` — ダッシュボード（準備中）
認証不要。将来のダッシュボード用プレースホルダー。

### `POST /api/blog` — ブログ投稿/更新 (認証必須)
```json
{
  "username": "hakase",
  "date": "2026-04-11",
  "title": "連続投稿3日目",
  "body": "今日は横浜のAIDX Labを中心に活動しました。\n睡眠 6h30m...",
  "cover_url": "https://...",
  "is_draft": false
}
```
**レスポンス**: `{"ok": true, "username": "hakase", "date": "2026-04-11"}`

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `username` | string | Yes | ユーザー名 |
| `date` | string (YYYY-MM-DD) | Yes | JST日付 |
| `title` | string | No | タイトル（デフォルト: "連続投稿N日目"） |
| `body` | string | Yes | 本文 (Markdown) |
| `cover_url` | string | No | カバーアートURL |
| `is_draft` | boolean | No | true=下書き、false=公開（デフォルト: false） |

**1日1記事**: `UNIQUE(username, date)` + `INSERT OR REPLACE` で同一日は上書き更新。
ブログは重複せず、同じ日の記事を何度でも編集・更新できる。

### `GET /blog/:username` — ブログ一覧 (公開)
認証不要。公開済み（is_draft=0）のブログ記事のみリスト表示。

### `GET /blog/:username/:date` — ブログ記事表示 (公開)
認証不要。公開済みのみ。dateは `YYMMDD` 形式（例: `260411`）。Markdown→HTML変換して表示。
公開URL: `https://nehan.ai/{username}/YYMMDD` (例: `https://nehan.ai/hakase/260411`)

### `GET /api/summary?date=YYYY-MM-DD` — 日報 Markdown 取得
日付は **JST** 基準。日報の Markdown テキストを返す。データなしの場合は空文字。

**他の GitHub Actions からの利用例**:
```bash
# 特定日のログを JSON で取得
curl -H "Authorization: Bearer $NEHAN_API_TOKEN" \
  "$NEHAN_WORKER_URL/api/logs?date=2026-04-10"

# 日報 Markdown を取得
curl -H "Authorization: Bearer $NEHAN_API_TOKEN" \
  "$NEHAN_WORKER_URL/api/summary?date=2026-04-10"
```

GitHub Actions から使う場合、リポジトリの Secrets に以下を設定:
- `NEHAN_API_TOKEN` — Bearer Token
- `NEHAN_WORKER_URL` — `https://nehan-worker.aki-2c0.workers.dev`

### D1 スキーマ
```sql
-- logs テーブル (schema.sql)
CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('location', 'sleep', 'memo')),
  latitude REAL,
  longitude REAL,
  place_name TEXT,
  payload TEXT,
  synced_from TEXT DEFAULT 'ios',
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_type ON logs(type);
CREATE INDEX IF NOT EXISTS idx_logs_date ON logs(date(timestamp));

-- blogs テーブル (migrations/0001_blogs.sql)
CREATE TABLE IF NOT EXISTS blogs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  date TEXT NOT NULL,
  title TEXT,
  body TEXT NOT NULL,
  cover_url TEXT,
  is_draft INTEGER DEFAULT 0,
  published_at TEXT DEFAULT (datetime('now')),
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(username, date)
);
```

**注意**: 日付検索は `date(timestamp, '+9 hours')` で JST 変換して比較する。

### 日報出力例
タイトル: `📍 nehan日報 2026-04-10（木）`
```markdown
# 📍 nehan日報 2026-04-10

## 🛏️ 睡眠
- 就寝: 23:30 → 起床: 06:00
  - deep: 90min
  - rem: 60min
  - core: 180min
  - awake: 15min

## 📍 訪問場所
| 時刻 | 場所 | 座標 |
|------|------|------|
| 09:15 | 自宅付近 | 35.xxxx, 139.xxxx |
| 10:00 | 渋谷ストリーム, 渋谷区 | 35.6580, 139.7016 |
| 18:30 | 自宅付近 | 35.xxxx, 139.xxxx |

## 📝 メモ
- 10:00 Jerry Chiと打合せ@渋谷ストリーム

---
*Generated by nehan.ai*
```

## GitHub Actions — 日報自動生成

### `.github/workflows/daily-report.yml`
- **スケジュール**: 毎日 23:00 JST (14:00 UTC)
- **手動実行**: `workflow_dispatch` 対応
- **処理フロー**:
  1. Worker `/api/summary?date=<JST今日>` から Markdown 取得
  2. 空でなければ GitHub Issue 作成 (ラベル: `nehan`, `daily-report`)
  3. Discord Webhook で通知 (embed形式)

### 必要な GitHub Secrets
| Secret | 用途 |
|---|---|
| `NEHAN_API_TOKEN` | Worker API 認証用 Bearer Token |
| `NEHAN_WORKER_URL` | Worker の URL |
| `DISCORD_WEBHOOK_URL` | Discord 通知用 Webhook |

## iOS App

### プロジェクト構成
```
NehanAI/
├── NehanAI.xcodeproj/
├── Config/
│   ├── Secrets.xcconfig           -- API_TOKEN, WORKER_URL (gitignored)
│   └── Secrets.xcconfig.example   -- テンプレート (committed)
├── NehanAI/
│   ├── NehanAIApp.swift           -- @main, BGTaskScheduler登録, オンボーディング分岐
│   ├── ContentView.swift          -- メイン画面 (ライフログタイムライン, ブログ, 同期)
│   ├── OnboardingView.swift       -- 初回起動: 言語選択→年齢性別→利用規約同意
│   ├── NehanAI.entitlements       -- HealthKit entitlement
│   ├── Info.plist                 -- 権限説明文, BGTask ID, xcconfig変数展開
│   ├── Config/
│   │   └── AppConfig.swift        -- Bundle.main から WORKER_URL, API_TOKEN 読み取り
│   ├── Models/
│   │   ├── LogEntry.swift         -- Codable struct + API変換
│   │   ├── PlaceBookmark.swift    -- 座標メモ (旧ブックマーク)
│   │   └── UserProfile.swift      -- ユーザープロフィール (年齢, 誕生日, 性別, 言語, 座標メモ設定, ストリーク)
│   ├── BlogEditorView.swift          -- 構造化ブログエディタ (6フィールド + カバーアート + Image Playground)
│   ├── Services/
│   │   ├── LocationService.swift       -- CLLocationManager + MKReverseGeocodingRequest
│   │   ├── HealthKitService.swift      -- HKHealthStore 睡眠・歩数・心拍・生理周期
│   │   ├── SyncService.swift           -- バッファ管理 → Worker POST
│   │   ├── BlogPublishService.swift    -- ブログ自動投稿 (POST /api/blog)
│   │   ├── NotificationService.swift   -- ブログリマインダー通知
│   │   ├── FoundationModelService.swift -- オンデバイスLLMブログ生成 (iOS 26+)
│   │   └── ImagePlaygroundService.swift -- Image Playground表情生成 (iOS 18+)
│   └── Assets.xcassets/
├── NehanAITests/
└── NehanAIUITests/
```

### オンボーディングフロー (Glass UI)
初回起動時に4ステップのオンボーディングを表示:
1. **ウェルカム**: ロゴ + キャッチコピー「あなたのiPhoneヘルスケアが、そのまま日記になる」
2. **言語選択**: 日本語 / English / 简体中文 / 繁體中文
3. **プロフィール**: 生まれた年 + 誕生日(月/日) + 性別 + 座標メモ説明 + 地名記録設定
4. **利用規約**: SFSafariViewControllerで表示、閉じると自動チェックON。両方確認で同意ボタン有効化

`UserProfileStore` (`@Observable`, UserDefaults永続化) でオンボーディング完了状態を管理。

### メイン画面 (ContentView)
- **ヘッダー**: 天気 + 表情プレースホルダー(1:1) + 日付 + ストリーク
- **ステータス**: 記録中/停止中 + バッファ件数 + 最終同期HH:mm / GPS精度アイコン + 座標メモ名
- **ライフログ**: 288セルタイムライン (5分刻み、睡眠=紫、活動=青、静止=黄) + アイコンサマリー
- **ブログ**: 6フィールド構造化エディタ (天気/睡眠/夢日記/場所/やり残し/感想) + カバーアート(16:9) + 下書き/公開 + ストリーク
- **操作**: 同期 + ヘルスデータ取得 + 開始/停止ボタン + 座標メモ一覧

### 座標メモ (旧ブックマーク)
GPSの座標・住所を表示せずに、登録した名前で記録する機能。
プライバシー保護 + ブログ向けの地名管理に活用。最大精度で「自席」レベルも記録可能。

### Xcode Capabilities
- **Background Modes**: Location updates, Background fetch, Background processing
- **HealthKit**: 睡眠データ読み取り
- **WeatherKit**: 天気データ取得 (Apple Developer Portal での有効化が必要)

### シークレット管理
`Secrets.xcconfig` → Info.plist `$(変数)` 展開 → `Bundle.main` 読み取り。
xcconfig はプロジェクトの Debug/Release 両方の `baseConfigurationReference` に設定済み。

```
Secrets.xcconfig (gitignored)     →  Info.plist $(API_TOKEN)  →  AppConfig.swift Bundle.main
API_TOKEN = xxxx                      <key>API_TOKEN</key>        static let apiToken = Bundle...
WORKER_URL = https://...              <string>$(API_TOKEN)</string>
```

### 主要コンポーネント

**LocationService** (`@MainActor`, `ObservableObject`)
- `startMonitoringSignificantLocationChanges()` — 省電力、数百m移動で発火
- `MKReverseGeocodingRequest` → `MKMapItem.address.shortAddress` で地名取得
- `allowsBackgroundLocationUpdates = true`, `showsBackgroundLocationIndicator = true`

**HealthKitService**
- `HKCategoryType.sleepAnalysis` 読み取り（前日 20:00〜当日 12:00）
- stages: asleepDeep, asleepREM, asleepCore, awake の分数を集計
- `HKQuantityType.stepCount` — 当日の歩数
- `HKQuantityType.heartRate` — 平均・最小・最大心拍
- `HKCategoryType.menstrualFlow` — 生理周期（女性ユーザーのみ）
- BGTaskScheduler 毎朝 7:00 に自動取得

**BlogPublishService**
- `saveLocal()` でUserDefaultsにブログ自動保存（エディタ閉じる時）
- `saveDraft()` でクラウドに下書き保存（is_draft=true）
- `publish()` でクラウドに公開投稿（is_draft=false）+ ローカル削除
- `scheduledPublish()` — BGTaskからの自動投稿（UserDefaultsの保留記事を投稿）
- BGTask ID: `ai.aicu.nehan.blogpublish`

**NotificationService**
- `scheduleBlogReminder(hour:)` — 指定時刻にブログリマインダー通知
- `scheduleWakeUpReminder(wakeTime:)` — 起床検知5分後に夢日記リマインダー
  - 通知テキスト: 「起きた？夢を見たら夢日記を書こう」
  - タップ → `AppState.shouldOpenBlogEditor = true` → ブログエディタを開く
- カテゴリ: `DREAM_DIARY`（アクション: 「夢日記を書く」）

**FoundationModelService** (iOS 26+)
- `LanguageModelSession` でオンデバイスLLM推論
- 睡眠・歩数・心拍・場所・夢日記からコンテキストを構築
- 自然な日本語の感想文を生成

**SyncService**
- インメモリバッファに LogEntry を蓄積
- 50件到達 or 手動 or BGTask で `POST /api/log` にバッチ送信
- 失敗時はバッファ先頭に戻してリトライ

## Worker セットアップ手順
```bash
cd worker
npm install
npx wrangler d1 create nehan-db
# wrangler.toml の database_id を更新
npx wrangler d1 execute nehan-db --remote --file=schema.sql
echo "<your-token>" | npx wrangler secret put API_TOKEN
npx wrangler deploy
```

## デプロイチェックリスト

### Worker
- [x] D1 データベース作成 (nehan-db, APAC)
- [x] schema.sql 実行
- [x] `wrangler secret put API_TOKEN`
- [x] `wrangler deploy`
- [ ] カスタムドメイン: `ios.nehan.ai` → Worker ルーティング

### iOS
- [x] Xcode Capabilities: Background Modes + HealthKit
- [x] Info.plist 権限説明文 + BGTask ID
- [x] Secrets.xcconfig で API_TOKEN / WORKER_URL 管理
- [x] 実機ビルド成功
- [ ] 位置情報「常に許可」確認
- [ ] HealthKit 許可確認
- [ ] バックグラウンド位置記録確認
- [ ] Worker へのログ到達確認

### GitHub Actions
- [x] `NEHAN_API_TOKEN` Secret 設定
- [x] `NEHAN_WORKER_URL` Secret 設定
- [x] `DISCORD_WEBHOOK_URL` Secret 設定
- [x] daily-report.yml デプロイ
- [x] Discord 通知テスト成功
