# 2026-04-11: LP刷新・利用規約多言語化・ブログURL変更・座標メモカテゴリ・セキュリティ監査

## 概要
App Store審査に向けたLP（ランディングページ）の大幅刷新、プライバシーポリシー・利用規約の多言語対応、ブログURLのルートレベル化、予約ユーザー名テーブル、カバーアートR2アップロード、座標メモカテゴリ追加、カスタムドメイン設定、セキュリティ監査を実施。

## 実施内容

### LP刷新 (`worker/public/index.html`)
- **6つの特徴カード**: 日報自動作成 / 健康管理 / 家族安否確認 / Apple Intelligence / API連携(有料) / ゲーミフィケーション
- **「使い方」3ステップセクション**: インストール → 日常生活 → 日報自動完成
- **フッター**: プライバシーポリシー・利用規約リンク、AICU Inc.クレジット
- デザイン: 紫ベース(`#4B0082`)グラデーション維持

### 利用規約・プライバシーポリシー多言語化
- **URL構造変更**: `/privacy` → `/terms/privacy/:lang`, `/terms` → `/terms/tos/:lang`
- **301リダイレクト**: 旧URL → 新URL（日本語デフォルト）
- **言語切替UI**: `langSwitcher()` ヘルパーで ja/en トグル
- **プライバシーポリシー**: corp.aicu.ai 参照、privacy@aicu.ai 連絡先、HealthKit・位置情報・R2ストレージ説明
- **利用規約**: ユーザー名ルール（第2条/第3条）、メール認証、無償ユーザー制限

### ブログURL変更
- `/blog/:username` → `/:username` （ルートレベル）
- `/blog/:username/:date` → `/:username/:date`
- `.md`/`.png` ファイル配信: `/:username/YYMMDD.md`, `/:username/YYMMDD.png`
- **ルート順序**: 正規表現ファイルルート → catch-all（順序重要）

### 予約ユーザー名テーブル (`migrations/0002_usernames.sql`)
- 202件の禁止ユーザー名（admin, root, api, blog, nehan, aicu, hakase等）
- `reserved_usernames` テーブル（D1）
- `GET /api/username/check?name=xxx` — ユーザー名利用可否チェックAPI
- ルール: 3-12文字、小文字英数字+アンダースコア+ハイフン、メール認証後変更不可（無償）

### カバーアートR2アップロード
- `POST /api/blog/cover` — multipart/base64 PNG → R2 (`nehan-covers`バケット)
- `BlogPublishService.uploadCover()` — iOS側マルチパートフォームアップロード
- Image Playground 1:1出力 → `UIImage.croppedTo16x9()` センタークロップ

### ブログリスト改善
- 日付重複なし（UNIQUE制約）
- タイトル + 最終更新 YYMMDD hh:mm の2行表示
- 右側に16:9サムネイル（96x54px）

### 座標メモカテゴリ追加 (`PlaceBookmark.swift`)
- `Category` enum: 自宅(house.fill) / 職場(building.2.fill) / 自席(desktopcomputer) / 寝室(bed.double.fill) / その他(mappin)
- ContentView: カテゴリ選択Picker、リスト表示にアイコン+ラベルカプセル
- `saveCoordMemo()` にカテゴリ引数追加

### カスタムドメイン設定
- `nehan.ai/*` → LP・ブログ・利用規約
- `ios.nehan.ai/*` → API エンドポイント
- Cloudflare DNS API でCNAMEレコード追加
- `wrangler.toml` にルート設定
- CLAUDE.md / AGENTS.md のWorker URL更新

### iOS ヘッダーリンク
- 「nehan.ai」タイトル右に `/{username}` リンク追加
- タップでブラウザで `https://nehan.ai/{username}` を開く

### セキュリティ監査
**発見された問題**:
1. 単一共有API_TOKEN — 全ユーザーが同じトークン
2. ユーザー所有権検証なし — 任意ユーザー名でブログ投稿可能
3. レート制限なし
4. メール認証未実装
5. `/api/username/check` が認証不要（ユーザー名列挙可能）

**対策方針** (Phase 1-3):
- Phase 1: D1 users テーブル + per-user API key + 所有権検証
- Phase 2: Resend メール認証
- Phase 3: リフレッシュトークン、デバイス管理、不正検知

## 変更ファイル一覧
| ファイル | 変更内容 |
|---------|---------|
| `worker/src/index.ts` | URL構造変更、利用規約多言語化、ブログルート変更、R2アップロード、ユーザー名検証 |
| `worker/public/index.html` | LP刷新（6特徴、3ステップ、フッター） |
| `worker/wrangler.toml` | カスタムドメインルート、R2バケット設定 |
| `worker/migrations/0002_usernames.sql` | 予約ユーザー名テーブル（202件） |
| `NehanAI/NehanAI/BlogEditorView.swift` | 16:9クロップ、ストリークベースタイトル |
| `NehanAI/NehanAI/ContentView.swift` | ヘッダーリンク、座標メモカテゴリUI |
| `NehanAI/NehanAI/Models/PlaceBookmark.swift` | Category enum追加 |
| `NehanAI/NehanAI/Services/BlogPublishService.swift` | R2カバーアップロード |
| `AGENTS.md` | Worker URL更新 |
| `CLAUDE.md` | Worker URL更新 |

## 未解決Issue
- [ ] セキュリティ: per-user認証の実装
- [ ] GA4設定とトラッキング
- [ ] API_TOKEN の再設定（現在 "test"）
- [ ] Resend メール認証連携
- [ ] 静的サイト生成（MkDocs Material + Cloudflare Pages）の評価
- [ ] Apple Developer Program 登録再試行
- [ ] 多言語ローカライズファイル（en, zh-Hans, zh-Hant）

## 技術メモ
- Hono ルート順序: 正規表現付きルートを catch-all パラメータルートより前に配置必須
- `wrangler.toml`: `routes` はトップレベルに配置（`[[r2_buckets]]`等のセクション内に入れない）
- `wrangler delete` は非対話モードでCWD名のworkerを削除するため要注意
- Cloudflare DNS API: `POST /zones/:zone_id/dns_records` でCNAMEレコード追加可能
- Image Playground は1:1出力 → `CGImage.cropping(to:)` でセンタークロップ
