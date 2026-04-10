# 2026-04-11: オンボーディング・ライフログUI・ブログ・座標メモ・全Issue実装

## 概要
App Store審査に向けたオンボーディングフロー構築、Glass UIへの全面移行、ライフログタイムライン、ブログ自動生成・ストリーク機能、座標メモ機能、夢日記を実装。さらに全GitHub Issue（#2〜#9）を実装完了。

## 実施内容

### オンボーディング (OnboardingView) — Glass UI
- **Glass UI**: 紫ベタ塗りから `ultraThinMaterial` ベースに全面移行
- **4ステップフロー**: ウェルカム → 言語選択 → プロフィール → 利用規約
- **プロフィール画面**:
  - 生まれた年 + 誕生日（月/日ピッカー）
  - 説明: 「年齢認証、ヘルスケアデータの分析と誕生日サプライズに使用します」
  - 性別選択（女性→生理周期記録有効化の案内）
  - **座標メモ説明**: GPSの値や住所を表示せずに座標メモで記録可能、プライバシー保護にも活用
  - **地名記録チェックボックス**: `recordPlaceNames` 設定
- **利用規約画面**: SFSafariViewControllerで表示→閉じたら自動チェックON。両方確認で同意ボタン有効化

### ContentView 全面リニューアル
**ヘッダーセクション**:
- Image Playground表情画像 (iOS 18+) / プレースホルダー(1:1)
- コンテキストメッセージ（時刻・場所・睡眠・歩数に応じた挨拶）
- 天気表示（WeatherKit有効化後）
- 日付 + ストリーク(flame.fill) + タップでヘルプポップオーバー

**ステータス（2行構成）**:
- Row 1: 記録中/停止中 + バッファ件数(小さくカプセル) + 最終同期HH:mm
- Row 2: GPS精度アイコン(色分け±Xm) + 座標メモ名(ブックマーク時は座標非表示)

**ライフログセクション（旧ヘルスデータ）**:
- **288セルタイムライン**: 00:00〜23:55を5分刻みで可視化
  - 🟣 睡眠 / 🟦 活動 / 🟡 静止 / グレー=未記録
  - 時刻ラベル(0, 6, 12, 18, 24)
  - 凡例表示
- モノクロアイコンでサマリー（睡眠、歩数、心拍、生理周期）
- 睡眠詳細（就寝→起床、deep/rem/core）

**ブログセクション（大幅リニューアル）**:
- **構造化エディタ**: BlogEditorView with 6フィールド
  1. 日付・天気・ヘルスサマリー (sun.max)
  2. 睡眠情報 (moon.zzz)
  3. 夢日記 (moon.stars)
  4. 訪問場所 (mappin.and.ellipse)
  5. 今日の感想 (face.smiling)
  6. やり残し (checklist)
- ヘッダーに「N時に自動投稿」表示
- プレビュータップでエディタsheet起動
- リロード🔁はエディタ内に配置
- Foundation Models (iOS 26+) で感想欄をLLM自動生成
- **自動パブリッシュ**: BGTaskでblogPublishHour時に `POST /api/blog` → Worker
- ストリーク表示（ヘッダー）
- footer: 「24時間に1回ブログを書くとストリーク獲得」

**操作セクション**:
- 同期 + 最終同期HH:mm
- ヘルスデータ取得 + 開始/停止ボタン(play/pause) + 最終更新HH:mm
- 座標メモ一覧

### 名称変更
- 「ブックマーク」→「座標メモ」（全UI・ダイアログ・リスト画面）
- 「ヘルスデータ」→「ライフログ」
- `BookmarkListView` → `CoordMemoListView`

### UserProfile拡張
- `recordPlaceNames: Bool` — 地名の自動記録設定
- `birthMonth`, `birthDay` — 誕生日（サプライズ用）
- `blogPublishHour` — 自動パブリッシュ時刻（デフォルト20時）
- `currentStreak`, `lastBlogDate` — ストリーク管理
- `displayName: String` — ユーザー表示名（ブログのusernameに使用）

### Worker
- `/privacy`, `/terms`, `/dashboard` ルート
- LP刷新
- **NEW: `POST /api/blog`** — ブログ投稿API（認証必須）
- **NEW: `GET /blog/:username`** — ユーザーのブログ一覧
- **NEW: `GET /blog/:username/:date`** — 個別ブログ表示（Markdown→HTML）
- D1 `blogs` テーブル（migrations/0001_blogs.sql）
- シンプルMarkdown→HTMLレンダラー（見出し、リスト、リンク、画像、太字、斜体、コード）

### iOS新ファイル
- `BlogEditorView.swift` — 構造化ブログエディタ（6フィールド）
- `BlogPublishService.swift` — Worker API連携、BGTask自動パブリッシュ
- `FoundationModelService.swift` — Foundation Models (iOS 26+) LLM日記生成
- `ImagePlaygroundService.swift` — Image Playground表情画像生成
- `NotificationService.swift` — ブログリマインダー通知

## GitHub Issues (全完了)
| # | タイトル | 状態 |
|---|---------|------|
| #1 | WeatherKit integration | ⏸️ BLOCKED (Apple Developer Portal) |
| #2 | Image Playground cover art | ✅ ExpressionPlaygroundView実装 |
| #3 | Foundation Models blog generation | ✅ FoundationModelService実装 |
| #4 | Blog auto-publish to nehan.ai | ✅ Worker API + BlogPublishService + BGTask |
| #5 | Menstrual cycle tracking | ✅ HealthKit menstrualFlow + UI表示 |
| #6 | Blog reminder notification | ✅ NotificationService実装 |
| #7 | Pull-to-refresh | ✅ `.refreshable` 実装 |
| #8 | Coord memo list improvements | ✅ tips, rename, delete, lastVisitedAt |
| #9 | Context-aware status message | ✅ contextMessage + streak help |

## 技術メモ
- Swift 6 `default-isolation MainActor` では `@Observable` + `@State`/`@Bindable` を使用（`ObservableObject`は制約あり）
- Glass UI: `.ultraThinMaterial` + `.presentationBackground(.ultraThinMaterial)` が基本パターン
- タイムラインは `GeometryReader` + 288個の `Rectangle` で実装
- ブログ生成: テンプレートベース → Foundation Models (iOS 26+) で感想欄をLLM強化
- Image Playground: `imagePlaygroundSheet` で表情画像生成（iOS 18+）
- 生理周期: `HKCategoryValueVaginalBleeding` (旧 `HKCategoryValueMenstrualFlow` は deprecated)
- ブログ自動投稿: `BGProcessingTask` + `BlogPublishService.scheduledPublish()`
- Worker Markdown→HTML: 独自軽量レンダラー（escapeHtml + inline変換）
- Apple Developer Program 登録が現在ブロック中（WeatherKit, App Store提出に影響）

## 残タスク
- [ ] Apple Developer Program 登録再試行
- [ ] 多言語ローカライズファイル（en, zh-Hans, zh-Hant）
- [ ] 設定画面（パブリッシュ時刻、地名記録、言語変更、displayName設定等をまとめる）
- [ ] 5分ごとの実データをタイムラインに反映
- [ ] Worker migrations をデプロイ時に実行（`wrangler d1 migrations apply`）
- [ ] displayName のiPhoneからの自動取得検討
