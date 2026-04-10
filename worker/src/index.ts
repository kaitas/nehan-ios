import { Hono } from 'hono';
import { bearerAuth } from 'hono/bearer-auth';

type Bindings = {
  DB: D1Database;
  API_TOKEN: string;
};

const app = new Hono<{ Bindings: Bindings }>();

// Auth middleware
app.use('/api/*', async (c, next) => {
  const auth = bearerAuth({ token: c.env.API_TOKEN });
  return auth(c, next);
});

// --- 共通HTMLレイアウト ---
function pageLayout(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} — nehan.ai</title>
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" href="/favicon-32x32.png" type="image/png" sizes="32x32">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #333; line-height: 1.8; }
    .legal-header { background: #4B0082; padding: 1.5rem 2rem; }
    .legal-header a { color: #fff; text-decoration: none; font-weight: 600; font-size: 1.1rem; }
    .legal-content { max-width: 720px; margin: 2rem auto; padding: 0 1.5rem 4rem; }
    .legal-content h1 { font-size: 1.8rem; margin-bottom: 1.5rem; color: #4B0082; }
    .legal-content h2 { font-size: 1.2rem; margin-top: 2rem; margin-bottom: 0.5rem; color: #333; }
    .legal-content p, .legal-content li { font-size: 0.95rem; margin-bottom: 0.5rem; }
    .legal-content ul { padding-left: 1.5rem; }
    .legal-footer { border-top: 1px solid #eee; margin-top: 3rem; padding-top: 1.5rem; font-size: 0.85rem; color: #888; text-align: center; }
    .legal-footer a { color: #4B0082; text-decoration: none; margin: 0 0.5rem; }
  </style>
</head>
<body>
  <div class="legal-header"><a href="/">nehan.ai</a></div>
  <div class="legal-content">
    ${body}
    <div class="legal-footer">
      <a href="/">トップ</a> · <a href="/privacy">プライバシーポリシー</a> · <a href="/terms">利用規約</a>
      <br>&copy; 2026 AICU Inc.
    </div>
  </div>
</body>
</html>`;
}

// GET /privacy — プライバシーポリシー
app.get('/privacy', (c) => {
  const html = pageLayout('プライバシーポリシー', `
    <h1>プライバシーポリシー</h1>
    <p>最終更新日: 2026年4月11日</p>

    <h2>1. 運営者</h2>
    <p>AICU Inc.（代表: 白井博士）が本アプリ「nehan.ai」を運営しています。</p>

    <h2>2. 収集するデータ</h2>
    <p>本アプリは以下のデータを収集します。</p>
    <ul>
      <li><strong>位置情報</strong>: バックグラウンドでの現在位置および逆ジオコーディングによる地名</li>
      <li><strong>HealthKitデータ</strong>: 睡眠分析（deep / REM / core / awake）、歩数、心拍数（平均・最小・最大）</li>
      <li><strong>ユーザー入力</strong>: 手動メモ、ブックマーク</li>
    </ul>

    <h2>3. データの送信先・保存場所</h2>
    <p>収集したデータは <code>ios.nehan.ai</code>（Cloudflare Worker + D1データベース）に暗号化通信（HTTPS）で送信・保存されます。</p>

    <h2>4. 利用目的</h2>
    <ul>
      <li>ライフログの記録・可視化</li>
      <li>日報（GitHub Issue）の自動生成</li>
      <li>Discord への日報通知</li>
    </ul>

    <h2>5. 第三者提供</h2>
    <p>収集したデータを第三者に提供・販売することはありません。広告目的でHealthKitデータを使用することもありません。</p>

    <h2>6. 広告について</h2>
    <p>本アプリは将来的にAdMobによる広告を導入する予定です。広告配信においてHealthKitデータおよびライフログデータは一切使用しません。</p>

    <h2>7. データの削除</h2>
    <p>ユーザーは以下のメールアドレスに連絡することで、保存されたデータの削除を要求できます。</p>
    <p>📧 <a href="mailto:and@and-and.com">and@and-and.com</a></p>

    <h2>8. Cookieの使用</h2>
    <p>本サービスはCookieを使用しません。API認証にはBearerトークンを使用しています。</p>

    <h2>9. ポリシーの変更</h2>
    <p>本ポリシーを変更する場合は、本ページにて告知します。</p>
  `);
  return c.html(html);
});

// GET /terms — 利用規約
app.get('/terms', (c) => {
  const html = pageLayout('利用規約', `
    <h1>利用規約</h1>
    <p>最終更新日: 2026年4月11日</p>

    <h2>第1条（サービス内容）</h2>
    <p>「nehan.ai」（以下「本サービス」）は、AICU Inc.（以下「運営者」）が提供するライフログ記録・日報自動生成サービスです。iOSアプリを通じて位置情報・HealthKitデータ・メモを記録し、日報として整理・通知します。</p>

    <h2>第2条（利用条件）</h2>
    <ul>
      <li>本サービスの利用にはiOSデバイスおよびインターネット接続が必要です。</li>
      <li>HealthKitデータの取得にはユーザーの明示的な許可が必要です。</li>
      <li>位置情報の取得にはユーザーの明示的な許可が必要です。</li>
    </ul>

    <h2>第3条（禁止事項）</h2>
    <ul>
      <li>APIの不正利用・逆コンパイル・リバースエンジニアリング</li>
      <li>他者のアカウントやトークンの不正使用</li>
      <li>サーバーへの過度な負荷をかける行為</li>
      <li>法令または公序良俗に反する行為</li>
    </ul>

    <h2>第4条（免責事項）</h2>
    <ul>
      <li>位置情報の正確性を保証するものではありません。</li>
      <li>HealthKitデータの正確性はApple HealthKitに依存し、運営者は保証しません。</li>
      <li>サービスの中断・停止により生じた損害について、運営者は責任を負いません。</li>
      <li>日報生成の遅延・欠損について、運営者は責任を負いません。</li>
    </ul>

    <h2>第5条（データの取り扱い）</h2>
    <p>ユーザーデータの取り扱いについては<a href="/privacy">プライバシーポリシー</a>をご参照ください。</p>

    <h2>第6条（サービスの変更・終了）</h2>
    <p>運営者は、事前の告知なくサービス内容の変更・終了を行うことがあります。</p>

    <h2>第7条（準拠法・管轄）</h2>
    <p>本規約は日本法に準拠し、紛争が生じた場合は東京地方裁判所を第一審の専属的合意管轄裁判所とします。</p>
  `);
  return c.html(html);
});

// GET /dashboard — ダッシュボード（プレースホルダー）
app.get('/dashboard', (c) => {
  const html = pageLayout('ダッシュボード', `
    <h1>ダッシュボード</h1>
    <p style="margin-top: 2rem; text-align: center; color: #888; font-size: 1.1rem;">
      🚧 準備中です。ログイン機能とダッシュボードは今後のアップデートで実装予定です。
    </p>
  `);
  return c.html(html);
});

// POST /api/log — バッチログ受信
app.post('/api/log', async (c) => {
  const { entries } = await c.req.json<{
    entries: Array<{
      timestamp: string;
      type: 'location' | 'sleep' | 'memo';
      latitude?: number;
      longitude?: number;
      place_name?: string;
      payload?: string;
    }>;
  }>();

  if (!entries?.length) return c.json({ error: 'No entries' }, 400);

  const stmt = c.env.DB.prepare(
    'INSERT INTO logs (timestamp, type, latitude, longitude, place_name, payload) VALUES (?, ?, ?, ?, ?, ?)'
  );

  const batch = entries.map((e) =>
    stmt.bind(e.timestamp, e.type, e.latitude ?? null, e.longitude ?? null, e.place_name ?? null, e.payload ?? null)
  );

  await c.env.DB.batch(batch);
  return c.json({ ok: true, count: entries.length });
});

// GET /api/logs?date=YYYY-MM-DD
app.get('/api/logs', async (c) => {
  const date = c.req.query('date') ?? new Date().toISOString().slice(0, 10);
  const results = await c.env.DB.prepare(
    "SELECT * FROM logs WHERE date(timestamp, '+9 hours') = ? ORDER BY timestamp ASC"
  ).bind(date).all();
  return c.json(results);
});

// GET /api/summary?date=YYYY-MM-DD — 日報プレビュー
app.get('/api/summary', async (c) => {
  const date = c.req.query('date') ?? new Date().toISOString().slice(0, 10);
  const markdown = await generateDailyReport(c.env.DB, date);
  return c.text(markdown);
});

// --- Blog API ---

// Simple Markdown to HTML converter
function renderMarkdown(md: string): string {
  return md
    .split('\n')
    .map((line) => {
      // Headers
      if (line.startsWith('##### ')) return `<h5>${escapeHtml(line.slice(6))}</h5>`;
      if (line.startsWith('#### ')) return `<h4>${escapeHtml(line.slice(5))}</h4>`;
      if (line.startsWith('### ')) return `<h3>${escapeHtml(line.slice(4))}</h3>`;
      if (line.startsWith('## ')) return `<h2>${escapeHtml(line.slice(3))}</h2>`;
      if (line.startsWith('# ')) return `<h1>${escapeHtml(line.slice(2))}</h1>`;
      // Horizontal rule
      if (/^---+$/.test(line.trim())) return '<hr>';
      // List items
      if (line.startsWith('- ')) return `<li>${inlineMarkdown(line.slice(2))}</li>`;
      if (/^\d+\. /.test(line)) return `<li>${inlineMarkdown(line.replace(/^\d+\. /, ''))}</li>`;
      // Empty line → paragraph break
      if (line.trim() === '') return '';
      // Normal paragraph
      return `<p>${inlineMarkdown(line)}</p>`;
    })
    .join('\n');
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function inlineMarkdown(s: string): string {
  let out = escapeHtml(s);
  // Images: ![alt](url)
  out = out.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" style="max-width:100%;border-radius:8px;margin:0.5rem 0;">');
  // Links: [text](url)
  out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" style="color:#4B0082;">$1</a>');
  // Bold
  out = out.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  // Italic
  out = out.replace(/\*(.+?)\*/g, '<em>$1</em>');
  // Inline code
  out = out.replace(/`(.+?)`/g, '<code style="background:#f4f0ff;padding:0.1em 0.4em;border-radius:3px;font-size:0.9em;">$1</code>');
  return out;
}

// POST /api/blog — create or update a blog entry (authenticated)
app.post('/api/blog', async (c) => {
  const { username, date, title, body, cover_url, is_draft } = await c.req.json<{
    username: string;
    date: string;
    title?: string;
    body: string;
    cover_url?: string;
    is_draft?: boolean;
  }>();

  if (!username || !date || !body) {
    return c.json({ error: 'username, date, and body are required' }, 400);
  }

  await c.env.DB.prepare(
    'INSERT OR REPLACE INTO blogs (username, date, title, body, cover_url, is_draft) VALUES (?, ?, ?, ?, ?, ?)'
  ).bind(username, date, title ?? null, body, cover_url ?? null, is_draft ? 1 : 0).run();

  return c.json({ ok: true, username, date, is_draft: !!is_draft });
});

// GET /blog/:username — list all blogs for a user (public)
app.get('/blog/:username', async (c) => {
  const username = c.req.param('username');
  const { results } = await c.env.DB.prepare(
    'SELECT date, title FROM blogs WHERE username = ? AND (is_draft IS NULL OR is_draft = 0) ORDER BY date DESC'
  ).bind(username).all();

  if (!results?.length) {
    const html = pageLayout(`${username} のブログ`, `
      <h1>${escapeHtml(username)} のブログ</h1>
      <p style="margin-top:2rem;color:#888;">記事がまだありません。</p>
    `);
    return c.html(html);
  }

  const listItems = (results as any[]).map((r) => {
    const d = r.date as string;
    const shortDate = d.slice(2).replace(/-/g, ''); // YYYY-MM-DD → YYMMDD
    const displayTitle = r.title || d;
    return `<li style="margin-bottom:0.8rem;">
      <a href="/blog/${encodeURIComponent(username)}/${shortDate}" style="color:#4B0082;text-decoration:none;font-size:1.05rem;">
        <strong>${escapeHtml(displayTitle)}</strong>
      </a>
      <span style="color:#888;font-size:0.85rem;margin-left:0.5rem;">${escapeHtml(d)}</span>
    </li>`;
  }).join('\n');

  const html = pageLayout(`${username} のブログ`, `
    <h1>${escapeHtml(username)} のブログ</h1>
    <ul style="list-style:none;padding:0;margin-top:1.5rem;">
      ${listItems}
    </ul>
  `);
  return c.html(html);
});

// GET /blog/:username/:date — render a single blog post (public)
app.get('/blog/:username/:date', async (c) => {
  const username = c.req.param('username');
  const rawDate = c.req.param('date'); // YYMMDD format

  // Convert YYMMDD → YYYY-MM-DD
  if (!/^\d{6}$/.test(rawDate)) {
    const html = pageLayout('404', `<h1>404 Not Found</h1><p>日付の形式が正しくありません。YYMMDD 形式で指定してください。</p>`);
    return c.html(html, 404);
  }
  const yy = rawDate.slice(0, 2);
  const mm = rawDate.slice(2, 4);
  const dd = rawDate.slice(4, 6);
  const fullDate = `20${yy}-${mm}-${dd}`;

  const row = await c.env.DB.prepare(
    'SELECT * FROM blogs WHERE username = ? AND date = ? AND (is_draft IS NULL OR is_draft = 0)'
  ).bind(username, fullDate).first();

  if (!row) {
    const html = pageLayout('404', `
      <h1>404 Not Found</h1>
      <p>記事が見つかりませんでした。</p>
      <p><a href="/blog/${encodeURIComponent(username)}" style="color:#4B0082;">${escapeHtml(username)} の記事一覧へ</a></p>
    `);
    return c.html(html, 404);
  }

  const title = (row.title as string) || fullDate;
  const coverHtml = row.cover_url
    ? `<img src="${escapeHtml(row.cover_url as string)}" alt="cover" style="width:100%;max-height:360px;object-fit:cover;border-radius:12px;margin-bottom:1.5rem;">`
    : '';
  const bodyHtml = renderMarkdown(row.body as string);

  const html = pageLayout(title, `
    ${coverHtml}
    <h1>${escapeHtml(title)}</h1>
    <p style="color:#888;font-size:0.9rem;margin-bottom:2rem;">
      ${escapeHtml(fullDate)} · <a href="/blog/${encodeURIComponent(username)}" style="color:#4B0082;text-decoration:none;">${escapeHtml(username)}</a>
    </p>
    <article style="line-height:1.9;">
      ${bodyHtml}
    </article>
  `);
  return c.html(html);
});

export default app;

function toJST(ts: string): string {
  try {
    const d = new Date(ts);
    return d.toLocaleTimeString('ja-JP', { timeZone: 'Asia/Tokyo', hour: '2-digit', minute: '2-digit', hour12: false });
  } catch {
    return ts?.slice(11, 16) ?? '?';
  }
}

// 同じ場所（500m以内）の連続ログを開始〜終了に集約
function collapseLocations(locations: any[]): Array<{ place: string; coord: string; start: string; end: string }> {
  if (!locations.length) return [];

  const collapsed: Array<{ place: string; coord: string; start: string; end: string }> = [];

  let current = {
    place: (locations[0] as any).place_name || formatCoord(locations[0]),
    coord: formatCoord(locations[0]),
    lat: (locations[0] as any).latitude as number | null,
    lon: (locations[0] as any).longitude as number | null,
    start: (locations[0] as any).timestamp as string,
    end: (locations[0] as any).timestamp as string,
  };

  for (let i = 1; i < locations.length; i++) {
    const l = locations[i] as any;
    const dist = haversine(current.lat, current.lon, l.latitude, l.longitude);

    if (dist < 500) {
      // 同じ場所 → 終了時刻を更新
      current.end = l.timestamp;
    } else {
      // 新しい場所 → 前を確定して次へ
      collapsed.push({ place: current.place, coord: current.coord, start: current.start, end: current.end });
      current = {
        place: l.place_name || formatCoord(l),
        coord: formatCoord(l),
        lat: l.latitude,
        lon: l.longitude,
        start: l.timestamp,
        end: l.timestamp,
      };
    }
  }
  collapsed.push({ place: current.place, coord: current.coord, start: current.start, end: current.end });
  return collapsed;
}

function formatCoord(l: any): string {
  if (l.latitude == null || l.longitude == null) return '—';
  return `${(l.latitude as number).toFixed(4)}, ${(l.longitude as number).toFixed(4)}`;
}

function haversine(lat1: number | null, lon1: number | null, lat2: number | null, lon2: number | null): number {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return Infinity;
  const R = 6371000;
  const toRad = (d: number) => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function generateDailyReport(db: D1Database, date: string): Promise<string> {
  const { results } = await db.prepare(
    "SELECT * FROM logs WHERE date(timestamp, '+9 hours') = ? ORDER BY timestamp ASC"
  ).bind(date).all();

  if (!results?.length) return '';

  const locations = results.filter((r: any) => r.type === 'location');
  const sleeps = results.filter((r: any) => r.type === 'sleep');
  const healthMemos = results.filter((r: any) => r.type === 'memo' && (r as any).payload?.startsWith('health:'));
  const memos = results.filter((r: any) => r.type === 'memo' && !(r as any).payload?.startsWith('health:'));

  let md = `# 📍 nehan日報 ${date}\n\n`;

  // 睡眠（最新1件のみ）
  if (sleeps.length > 0) {
    const s = sleeps[sleeps.length - 1];
    md += `## 🛏️ 睡眠\n`;
    try {
      const p = JSON.parse((s as any).payload || '{}');
      const asleepTime = p.asleep ? toJST(p.asleep) : '?';
      const awakeTime = p.awake ? toJST(p.awake) : '?';
      const totalH = p.totalHours ? ` (${p.totalHours}h)` : '';
      md += `- 就寝: ${asleepTime} → 起床: ${awakeTime}${totalH}\n`;
      if (p.stages) {
        for (const st of p.stages) {
          md += `  - ${st.stage}: ${st.minutes}min\n`;
        }
      }
    } catch {
      md += `- (データ解析エラー)\n`;
    }
    md += '\n';
  }

  // ヘルスデータ（最新1件のみ）
  if (healthMemos.length > 0) {
    const h = healthMemos[healthMemos.length - 1];
    try {
      const json = (h as any).payload?.replace('health: ', '') ?? '{}';
      const p = JSON.parse(json);
      if (p.steps || p.heartRate) {
        md += `## 🏃 アクティビティ\n`;
        if (p.steps) md += `- 歩数: ${Number(p.steps).toLocaleString()} 歩\n`;
        if (p.heartRate) {
          md += `- 心拍: 平均 ${p.heartRate.avg} bpm (↓${p.heartRate.min} ↑${p.heartRate.max})\n`;
        }
        md += '\n';
      }
    } catch { /* skip */ }
  }

  // 訪問場所（同じ場所を開始〜終了に集約）
  if (locations.length > 0) {
    const collapsed = collapseLocations(locations);
    md += `## 📍 訪問場所\n`;
    md += `| 時刻 | 場所 | 座標 |\n|------|------|------|\n`;
    for (const loc of collapsed) {
      const startTime = toJST(loc.start);
      const endTime = toJST(loc.end);
      const time = loc.start === loc.end ? startTime : `${startTime}〜${endTime}`;
      md += `| ${time} | ${loc.place} | ${loc.coord} |\n`;
    }
    md += '\n';
  }

  // メモ
  if (memos.length > 0) {
    md += `## 📝 メモ\n`;
    for (const m of memos) {
      const time = toJST((m as any).timestamp);
      md += `- ${time} ${(m as any).payload || ''}\n`;
    }
    md += '\n';
  }

  md += `---\n*Generated by nehan.ai*\n`;
  return md;
}
