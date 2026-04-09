# nehan.ai — ライフログ日報システム

## プロジェクト概要
個人用iOSライフログアプリ + Cloudflare Workerバックエンド。
バックグラウンドで位置情報と睡眠データを記録し、1日の終わりにGitHub Issue日報を自動生成する。

- **所有者**: はかせ（白井博士 / AICU Inc.）専用・非公開
- **ドメイン**: ios.nehan.ai（Cloudflare Worker）
- **Bundle ID**: ai.nehan.ios
- **リポジトリ**: aicuai/nehan-ai（private）

## アーキテクチャ

```
┌─────────────────────┐
│  iOS App (Swift)     │
│  Bundle: ai.nehan.ios│  POST /api/log
│  - CoreLocation      │──────────────────┐
│  - HealthKit         │                  │
│  - Background Tasks  │                  ▼
└─────────────────────┘       ┌──────────────────┐
                              │ Cloudflare Worker │
                              │ ios.nehan.ai      │
                              │ Hono + D1         │
                              │                    │
                              │ POST /api/log      │
                              │ GET  /api/logs     │
                              │ GET  /api/summary  │
                              │ CRON → GitHub Issue│
                              └──────────────────┘
```

## 技術スタック

### iOS App
- **言語**: Swift 5.9+, iOS 17.0+
- **フレームワーク**: CoreLocation, HealthKit, BackgroundTasks, SwiftUI
- **通信**: URLSession → ios.nehan.ai
- **ストレージ**: UserDefaults（設定）, インメモリバッファ（同期待ち）

### Backend (Cloudflare Worker)
- **フレームワーク**: Hono
- **DB**: D1
- **認証**: Bearer Token（環境変数 `API_TOKEN`）
- **日報出力**: GitHub Issue API

## APIキー管理
非公開・個人用のため:
- iOS側: `AppConfig.swift` にハードコード
- Worker側環境変数:
  - `API_TOKEN` — iOS→Worker認証用
  - `GITHUB_TOKEN` — GitHub Issue作成用PAT
  - `GITHUB_REPO` — aicuai/nehan-ai

## コーディング規約
- Swift: async/await優先, SwiftUI
- Worker: TypeScript strict, Hono
- コミット: conventional commits (feat/fix/docs)
