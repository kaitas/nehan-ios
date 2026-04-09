# 2026-04-10: nehan.ai 初期構築

## 概要
iOSライフログアプリ + Cloudflare Workerバックエンドの初期構築を完了。
バックグラウンド位置情報・HealthKit・メモ記録 → D1保存 → GitHub Issue日報の一連のパイプラインが稼働。

## 実施内容

### iOS App (NehanAI)
- Xcode プロジェクト統合（2つのディレクトリをマージ、PBXFileSystemSynchronizedRootGroup活用）
- **CoreLocation**: `startMonitoringSignificantLocationChanges()` によるバックグラウンド位置記録
- **MapKit**: `MKReverseGeocodingRequest` で逆ジオコーディング（iOS 26対応、CLGeocoder非推奨対応）
- **HealthKit**: 睡眠（ステージ別）・歩数・心拍データの取得と同期
- **BGTaskScheduler**: 定期同期（30分間隔）+ 睡眠データ取得（毎朝7時）
- **場所ブックマーク機能**: 長押しコンテキストメニューで名前付け、秘密フラグ（座標非送信）、UserDefaults永続化、200m半径マッチング
- **シークレット管理**: `Secrets.xcconfig` → Info.plist → Bundle.main パターンで外部化
- **アプリアイコン**: Indigo背景 + 白「N」ロゴ（1024x1024、Pillow生成）

### Cloudflare Worker (nehan-worker)
- **Hono + D1** でAPI構築
  - `POST /api/log` — バッチログ受信（Bearer Token認証）
  - `GET /api/logs?date=` — 日付別ログ取得
  - `GET /api/summary?date=` — Markdown日報プレビュー
- **日報生成ロジック**:
  - 位置情報: Haversine距離計算で500m以内の連続ログを開始〜終了に集約
  - 睡眠・ヘルスデータ: 最新1件のみ使用（重複排除）
  - JST変換: `date(timestamp, '+9 hours')` でSQLiteタイムゾーン処理
- **静的アセット配信**: favicon, OGP画像, ランディングページ（Indigo「N」デザイン）
- デプロイ先: `https://nehan-worker.aki-2c0.workers.dev`

### GitHub Actions
- `.github/workflows/daily-report.yml` — 毎日23:00 JST (cron `0 14 * * *`)
- Worker `/api/summary` → GitHub Issue作成 → Discord Webhook通知（embed形式）

## 解決した問題
| 問題 | 原因 | 対応 |
|------|------|------|
| CLGeocoder非推奨 | iOS 26で廃止 | MKReverseGeocodingRequest に移行 |
| Discord通知が来ない | SQLiteのdate()がUTCで比較 | `date(timestamp, '+9 hours')` でJST変換 |
| アクティビティ重複 | 複数health memoが各セクション生成 | 最新1件のみ使用 |
| Cron制限 | Cloudflare Free = 5トリガー上限 | GitHub Actions cronで代替 |
| xcconfig内の `//` | コメントとして扱われる | `https:/$()/domain` ワークアラウンド |
| GitHub Issueラベル | リポジトリに未作成 | `gh label create` で事前作成 |

## 技術メモ
- Xcode 26.3 の `PBXFileSystemSynchronizedRootGroup` はSwiftファイルを自動検出するため、pbxproj編集不要
- `MKReverseGeocodingRequest` のアドレス取得は `item.address?.shortAddress`（`placemark.locality` は非推奨）
- D1のタイムスタンプはISO8601(UTC)で保存、クエリ時にJSTオフセット適用がシンプル

## 残タスク
- カスタムドメイン `ios.nehan.ai` → Worker ルーティング設定
- ブックマーク送信の実機検証（次回位置イベント発火時）
- ランディングページの拡充（必要に応じて）
