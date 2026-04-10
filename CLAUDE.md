# nehan.ai — ライフログ日報システム

> **すべてのエージェントはこのファイルを最初に読む。詳細は [AGENTS.md](AGENTS.md) を参照。**

## プロジェクト概要
iOSライフログアプリ + Cloudflare Workerバックエンド。
HealthKit・位置情報・メモを自動記録し、オンデバイスAIでブログ日報を生成。

- **所有者**: はかせ（白井博士 / AICU Inc.）
- **リポジトリ**: kaitas/nehan-ios
- **ドメイン**: `nehan.ai`（LP・ブログ）/ `ios.nehan.ai`（API）
- **Bundle ID**: AI.AICU.NehanAI

## アーキテクチャ概要

```
iOS App (Swift/SwiftUI, iOS 26+)
  CoreLocation + HealthKit + Foundation Models + Image Playground
       │ POST /api/log (Bearer Token, HTTPS)
       ▼
Cloudflare Worker (Hono + D1 + R2)
  nehan.ai     → LP, ブログ (/:username), 利用規約
  ios.nehan.ai → API (/api/*)
       │
       ▼
GitHub Actions (23:00 JST) → Issue + Discord通知
```

## エージェント担当領域

| 領域 | ディレクトリ | 言語 | 参照セクション |
|------|------------|------|--------------|
| iOS App | `NehanAI/` | Swift 6 / SwiftUI | AGENTS.md §iOS |
| Worker API | `worker/` | TypeScript / Hono | AGENTS.md §Worker |
| CI/CD | `.github/workflows/` | YAML | AGENTS.md §DevOps |
| LP/Web | `worker/public/` | HTML/CSS | AGENTS.md §Worker |
| ドキュメント | `doc/`, `AGENTS.md` | Markdown | — |

## コーディング規約（全エージェント共通）
- **コミット**: conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`)
- **Swift**: async/await, SwiftUI, Swift 6 concurrency (`@MainActor` default)
- **TypeScript**: Hono framework, D1/R2バインディング
- **セキュリティ**: HealthKitデータは広告目的に使用禁止。HTTPS必須。シークレットはgitignored xcconfig / wrangler secret
- **言語**: コード・コメントは英語、UIテキスト・ドキュメントは日本語

## シークレット管理
| 場所 | 方法 |
|------|------|
| iOS | `Secrets.xcconfig` (gitignored) → Info.plist → AppConfig.swift |
| Worker | `wrangler secret put API_TOKEN` |
| GitHub Actions | Repository Secrets: `NEHAN_API_TOKEN`, `NEHAN_WORKER_URL`, `DISCORD_WEBHOOK_URL` |

## 現在の課題 (2026-04-11)
1. **セキュリティ**: 単一共有トークン → per-user認証が必要
2. **GA4**: Google Analytics 4 の設定とトラッキング未実装
3. **メール認証**: Resend連携未実装
4. **静的サイト生成**: MkDocs Material + Cloudflare Pages の評価待ち
5. **Apple Developer Program**: 登録再試行が必要（WeatherKit, App Store提出に影響）
