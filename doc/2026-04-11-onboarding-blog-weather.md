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

## セッション2: マルチエージェント最適化・Issue一括解決 (夜)

### AGENTS.md / CLAUDE.md マルチエージェント最適化
- **CLAUDE.md**: エージェント共通エントリポイントに簡素化（アーキテクチャ概要、担当領域テーブル、コーディング規約）
- **AGENTS.md**: ドメインセクション(§)構造に再編（§Worker, §iOS, §DevOps, §セキュリティ, §LP, §日報, §外部連携）
- **§運用ルール** 追加: 「依頼：」Issueプロトコル（マスター @kaitas が手動対応必要なタスクの依頼方法）

### Issue一括解決（マルチエージェント並列実行）
3エージェントを並列起動して同時実装:
- **#17 GA4トラッキング**: `public/index.html` と `pageLayout()` にGA4タグ挿入 → 測定ID `G-NHJNT7G479` 反映・デプロイ完了
- **#10 オンボーディング修正**: 生年月日を1カードに統合、座標メモ説明削除
- **#11 Apple Intelligenceフォールバック**: `FoundationModelService.isAvailable` チェック、非対応アラート、テンプレートフォールバック

### 既存Issue整理
クローズ: #10, #11, #12, #14, #16, #17 (6件)

### 「依頼：」Issue作成
- **#19** GA4測定ID取得 → ✅ 即日解決（`G-NHJNT7G479`）
- **#20** Apple Developer Program登録（手順付き）
- **#21** Worker API_TOKEN本番値設定（手順付き）

### 新規Issue
- **#18** 初期ユーザ向けナビゲーション＆チュートリアル
- **#22** GA4分析ダッシュボード (/admin/) + Claude Codeスキル

### GA4 設定完了
| 項目 | 値 |
|------|-----|
| 測定ID | `G-NHJNT7G479` |
| ストリームID | `14348007420` |
| ストリーム名 | nehan.ai Web |
| 対象 | LP + 全公開ページ（pageLayout共通） |

## コミット履歴
| ハッシュ | 内容 |
|---------|------|
| `e0a0521` | LP刷新、多言語Terms、ブログURL変更、座標メモカテゴリ、R2アップロード |
| `3c48ad6` | AGENTS.md / CLAUDE.md マルチエージェント最適化 |
| `03753a8` | GA4トラッキング、オンボーディングUI改善、Apple Intelligenceフォールバック |
| `e436598` | GA4測定ID反映、「依頼：」運用ルール追加 |
| `f985653` | AGENTS.md にGA4設定情報追記 |

## 未解決Issue
- [ ] #18 初期ユーザ向けナビゲーション＆チュートリアル
- [ ] #20 依頼：Apple Developer Program登録
- [ ] #21 依頼：API_TOKEN本番値設定
- [ ] #22 GA4分析ダッシュボード + スキル
- [ ] #13 マネタイズ - Stripe
- [ ] #1 WeatherKit（Apple Developer Program待ち）
- [ ] セキュリティ: per-user認証 (Phase 1-3)
- [ ] Resend メール認証連携
- [ ] 静的サイト生成（MkDocs Material + Cloudflare Pages）
- [ ] 多言語ローカライズファイル（en, zh-Hans, zh-Hant）

## 技術メモ
- Hono ルート順序: 正規表現付きルートを catch-all パラメータルートより前に配置必須
- `wrangler.toml`: `routes` はトップレベルに配置（`[[r2_buckets]]`等のセクション内に入れない）
- `wrangler delete` は非対話モードでCWD名のworkerを削除するため要注意
- Cloudflare DNS API: `POST /zones/:zone_id/dns_records` でCNAMEレコード追加可能
- Image Playground は1:1出力 → `CGImage.cropping(to:)` でセンタークロップ
- マルチエージェント並列実行: 独立したファイルを扱うタスクは `run_in_background` で同時実行可能
