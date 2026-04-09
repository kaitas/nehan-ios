# nehan.ai — ライフログ日報システム

## プロジェクト概要
個人用iOSライフログアプリ + Cloudflare Workerバックエンド。
バックグラウンドで位置情報（地名付き）と睡眠データを記録し、毎日23:00 JSTにGitHub Issue日報を自動生成してDiscordに通知する。

- **所有者**: はかせ（白井博士 / AICU Inc.）
- **リポジトリ**: kaitas/nehan-ios
- **Worker URL**: `https://nehan-worker.aki-2c0.workers.dev`
- **Bundle ID**: AI.AICU.NehanAI

## アーキテクチャ

```
iOS App (Swift/SwiftUI)
  CoreLocation → 位置 + MKReverseGeocodingRequest → 地名
  HealthKit → 睡眠データ (前夜〜当日朝)
  手動メモ入力
       │
       │ POST /api/log (Bearer Token)
       ▼
Cloudflare Worker (Hono + D1)
  POST /api/log      ← ログ一括登録
  GET  /api/logs     ← 日別JSON取得 (JST基準)
  GET  /api/summary  ← 日報Markdown取得 (JST基準)
       │
       │ GitHub Actions (23:00 JST cron)
       ▼
GitHub Issue (日報) → Discord Webhook 通知
```

## 技術スタック

### iOS App
- **言語**: Swift, iOS 26+, Xcode 26.3
- **フレームワーク**: SwiftUI, CoreLocation, MapKit, HealthKit, BackgroundTasks
- **シークレット管理**: Secrets.xcconfig → Info.plist → Bundle.main (gitignored)

### Backend (Cloudflare Worker)
- **フレームワーク**: Hono (TypeScript)
- **DB**: D1 (nehan-db, APAC region)
- **認証**: Bearer Token (`API_TOKEN` via wrangler secret)
- **タイムゾーン**: timestamp は UTC 保存、クエリ時 `date(timestamp, '+9 hours')` で JST 変換

### 日報生成 (GitHub Actions)
- **スケジュール**: 毎日 23:00 JST (cron: `0 14 * * *`)
- **フロー**: Worker /api/summary → GitHub Issue → Discord Webhook
- **Secrets**: `NEHAN_API_TOKEN`, `NEHAN_WORKER_URL`, `DISCORD_WEBHOOK_URL`

## APIキー管理
- iOS側: `Secrets.xcconfig` (gitignored) → Info.plist展開 → AppConfig.swift
- Worker側: `wrangler secret put API_TOKEN`
- GitHub Actions: Repository Secrets (`NEHAN_API_TOKEN`, `NEHAN_WORKER_URL`, `DISCORD_WEBHOOK_URL`)

## 外部連携
Worker API は Bearer Token 認証で他の GitHub Actions やサービスからも利用可能。
詳細は [AGENTS.md](AGENTS.md) の API リファレンスを参照。

## コーディング規約
- Swift: async/await優先, SwiftUI, Swift 6 concurrency (MainActor default)
- Worker: TypeScript, Hono
- コミット: conventional commits (feat/fix/docs)
