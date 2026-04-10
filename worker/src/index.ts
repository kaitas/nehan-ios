import { Hono } from 'hono';
import { bearerAuth } from 'hono/bearer-auth';

type Bindings = {
  DB: D1Database;
  COVERS: R2Bucket;
  API_TOKEN: string;
};

const app = new Hono<{ Bindings: Bindings }>();

// --- Username validation ---
const USERNAME_REGEX = /^[a-z0-9_-]{3,12}$/;

async function validateUsername(
  db: D1Database,
  name: string
): Promise<{ available: boolean; reason?: string }> {
  // Format check
  if (!name || name.length < 3) {
    return { available: false, reason: 'Username must be at least 3 characters' };
  }
  if (name.length > 12) {
    return { available: false, reason: 'Username must be at most 12 characters' };
  }
  if (!USERNAME_REGEX.test(name)) {
    return { available: false, reason: 'Username may only contain lowercase letters, digits, underscores, and hyphens' };
  }

  // Reserved name check
  const reserved = await db.prepare(
    'SELECT 1 FROM reserved_usernames WHERE username = ?'
  ).bind(name).first();
  if (reserved) {
    return { available: false, reason: 'This username is reserved' };
  }

  return { available: true };
}

// Auth middleware
app.use('/api/*', async (c, next) => {
  const auth = bearerAuth({ token: c.env.API_TOKEN });
  return auth(c, next);
});

// --- 共通HTMLレイアウト ---
function pageLayout(title: string, body: string, lang: string = 'ja'): string {
  const footerLabels = lang === 'en'
    ? { top: 'Home', privacy: 'Privacy Policy', terms: 'Terms of Service' }
    : { top: 'トップ', privacy: 'プライバシーポリシー', terms: '利用規約' };
  return `<!DOCTYPE html>
<html lang="${lang}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} — nehan.ai</title>
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" href="/favicon-32x32.png" type="image/png" sizes="32x32">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <!-- Google Analytics (GA4) -->
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXXXXXX"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-XXXXXXXXXX');
  </script>
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
    .legal-content ol { padding-left: 1.5rem; }
    .legal-footer { border-top: 1px solid #eee; margin-top: 3rem; padding-top: 1.5rem; font-size: 0.85rem; color: #888; text-align: center; }
    .legal-footer a { color: #4B0082; text-decoration: none; margin: 0 0.5rem; }
    .lang-switcher { text-align: right; margin-bottom: 1rem; font-size: 0.85rem; }
    .lang-switcher a { color: #4B0082; text-decoration: none; margin: 0 0.3rem; }
    .lang-switcher a.active { font-weight: 700; text-decoration: underline; }
  </style>
</head>
<body>
  <div class="legal-header"><a href="/">nehan.ai</a></div>
  <div class="legal-content">
    ${body}
    <div class="legal-footer">
      <a href="/">${footerLabels.top}</a> · <a href="/terms/privacy/${lang}">${footerLabels.privacy}</a> · <a href="/terms/tos/${lang}">${footerLabels.terms}</a>
      <br>&copy; 2026 AICU Inc.
    </div>
  </div>
</body>
</html>`;
}

// GET /privacy — redirect to /terms/privacy/ja
app.get('/privacy', (c) => c.redirect('/terms/privacy/ja', 301));

// GET /terms — redirect to /terms/tos/ja
app.get('/terms', (c) => c.redirect('/terms/tos/ja', 301));

// --- Language switcher helper ---
function langSwitcher(section: 'privacy' | 'tos', currentLang: string): string {
  const langs = [
    { code: 'ja', label: '日本語' },
    { code: 'en', label: 'English' },
  ];
  const links = langs.map((l) =>
    `<a href="/terms/${section}/${l.code}" class="${l.code === currentLang ? 'active' : ''}">${l.label}</a>`
  ).join(' | ');
  return `<div class="lang-switcher">${links}</div>`;
}

// GET /terms/privacy/:lang — プライバシーポリシー (multi-language)
app.get('/terms/privacy/:lang', (c) => {
  const lang = c.req.param('lang');

  if (lang === 'en') {
    const html = pageLayout('Privacy Policy', `
    ${langSwitcher('privacy', 'en')}
    <h1>Privacy Policy</h1>
    <p>Last updated: April 11, 2026</p>

    <h2>1. Operator</h2>
    <p>AICU Inc. operates the "nehan.ai" service.</p>
    <p>Privacy inquiries: <a href="mailto:privacy@aicu.ai">privacy@aicu.ai</a></p>
    <p>See also: <a href="https://corp.aicu.ai/ja/privacy" target="_blank">AICU Inc. Privacy Policy</a></p>

    <h2>2. Data We Collect</h2>
    <ul>
      <li><strong>Location data</strong>: Background location and reverse-geocoded place names</li>
      <li><strong>HealthKit data</strong>: Sleep analysis (deep/REM/core/awake), steps, heart rate (avg/min/max)</li>
      <li><strong>User input</strong>: Memos, dream diary, blog posts, cover art images</li>
      <li><strong>Account information</strong>: Username, email address (for verification)</li>
    </ul>

    <h2>3. Where Data Is Stored</h2>
    <p>Data is transmitted via HTTPS to <code>ios.nehan.ai</code> (Cloudflare Worker + D1 database + R2 storage).</p>

    <h2>4. Purpose of Use</h2>
    <ul>
      <li>Lifelog recording, visualization, and automated blog generation</li>
      <li>On-device AI (Apple Intelligence) text and image generation</li>
      <li>External service integration (GitHub Issues, Discord — paid plans, with user consent)</li>
    </ul>

    <h2>5. On-Device Processing</h2>
    <p>Text generation via Apple Intelligence (Foundation Models) and image generation via Image Playground are performed entirely on-device. No data is sent to external servers for AI processing.</p>

    <h2>6. Third-Party Sharing</h2>
    <p>We do not sell or share your data with third parties. HealthKit data is never used for advertising purposes.</p>

    <h2>7. Data Retention and Deletion</h2>
    <p>You may request deletion of all your data by contacting <a href="mailto:privacy@aicu.ai">privacy@aicu.ai</a>. We will delete all data within 30 days of the request.</p>

    <h2>8. Cookies</h2>
    <p>This service does not use cookies. API authentication uses Bearer tokens.</p>

    <h2>9. Children's Privacy</h2>
    <p>This service is not intended for children under 13. We do not knowingly collect data from children under 13.</p>

    <h2>10. Changes to This Policy</h2>
    <p>Changes will be posted on this page.</p>
    `, 'en');
    return c.html(html);
  }

  // Default: Japanese
  const html = pageLayout('プライバシーポリシー', `
    ${langSwitcher('privacy', 'ja')}
    <h1>プライバシーポリシー</h1>
    <p>最終更新日: 2026年4月11日</p>

    <h2>1. 運営者</h2>
    <p>AICU Inc. が本サービス「nehan.ai」を運営しています。</p>
    <p>プライバシーに関するお問い合わせ: <a href="mailto:privacy@aicu.ai">privacy@aicu.ai</a></p>
    <p>AICU Inc. のプライバシーポリシー: <a href="https://corp.aicu.ai/ja/privacy" target="_blank">corp.aicu.ai/ja/privacy</a></p>

    <h2>2. 収集するデータ</h2>
    <ul>
      <li><strong>位置情報</strong>: バックグラウンドでの現在位置および逆ジオコーディングによる地名</li>
      <li><strong>HealthKitデータ</strong>: 睡眠分析（deep / REM / core / awake）、歩数、心拍数（平均・最小・最大）</li>
      <li><strong>ユーザー入力</strong>: 手動メモ、夢日記、ブログ記事、カバーアート画像</li>
      <li><strong>アカウント情報</strong>: ユーザー名、メールアドレス（認証用）</li>
    </ul>

    <h2>3. データの送信先・保存場所</h2>
    <p>収集したデータは <code>ios.nehan.ai</code>（Cloudflare Worker + D1データベース + R2ストレージ）に暗号化通信（HTTPS）で送信・保存されます。</p>

    <h2>4. 利用目的</h2>
    <ul>
      <li>ライフログの記録・可視化・ブログ自動生成</li>
      <li>オンデバイスAI（Apple Intelligence）によるテキスト・画像生成</li>
      <li>外部サービス連携（GitHub Issues、Discord等 — 有料プラン、ユーザー同意のうえ）</li>
    </ul>

    <h2>5. オンデバイス処理</h2>
    <p>Apple Intelligence (Foundation Models) によるテキスト生成・Image Playgroundによる画像生成はすべてデバイス上で実行され、AI処理のためにデータが外部サーバーに送信されることはありません。</p>

    <h2>6. 第三者提供</h2>
    <p>収集したデータを第三者に提供・販売することはありません。広告目的でHealthKitデータを使用することもありません。</p>

    <h2>7. データの保持と削除</h2>
    <p>ユーザーは <a href="mailto:privacy@aicu.ai">privacy@aicu.ai</a> に連絡することで、保存されたすべてのデータの削除を要求できます。要求から30日以内にデータを削除します。</p>

    <h2>8. Cookieの使用</h2>
    <p>本サービスはCookieを使用しません。API認証にはBearerトークンを使用しています。</p>

    <h2>9. 児童のプライバシー</h2>
    <p>本サービスは13歳未満の児童を対象としていません。13歳未満の児童のデータを意図的に収集することはありません。</p>

    <h2>10. ポリシーの変更</h2>
    <p>本ポリシーを変更する場合は、本ページにて告知します。</p>
  `, 'ja');
  return c.html(html);
});

// GET /terms/tos/:lang — 利用規約 (multi-language)
app.get('/terms/tos/:lang', (c) => {
  const lang = c.req.param('lang');

  if (lang === 'en') {
    const html = pageLayout('Terms of Service', `
    ${langSwitcher('tos', 'en')}
    <h1>Terms of Service</h1>
    <p>Last updated: April 11, 2026</p>

    <h2>Article 1 (Service Description)</h2>
    <p>"nehan.ai" (hereinafter "the Service") is a life log recording and automatic daily report generation service provided by AICU Inc. (hereinafter "the Operator"). Through the iOS application, the Service records location data, HealthKit data, and memos, organizing and delivering them as daily reports.</p>

    <h2>Article 2 (Terms of Use)</h2>
    <ul>
      <li>Use of this Service requires an iOS device and an internet connection.</li>
      <li>Explicit user permission is required to access HealthKit data.</li>
      <li>Explicit user permission is required to access location data.</li>
    </ul>

    <h2>Article 3 (Username Rules)</h2>
    <p>Users who register an account must choose a username subject to the following rules:</p>
    <ol>
      <li>Usernames must be unique across the service.</li>
      <li>Usernames must be between 3 and 12 characters long.</li>
      <li>Only lowercase alphanumeric characters, underscores (_), and hyphens (-) are permitted.</li>
      <li>Email verification is required to complete registration.</li>
      <li>Free-tier users cannot change their username once it has been set.</li>
      <li>The Operator maintains a list of reserved usernames that are not available for registration.</li>
    </ol>

    <h2>Article 4 (Prohibited Activities)</h2>
    <ul>
      <li>Unauthorized use of the API, decompilation, or reverse engineering</li>
      <li>Unauthorized use of another person's account or tokens</li>
      <li>Placing excessive load on the servers</li>
      <li>Any activity that violates laws or public order and morals</li>
    </ul>

    <h2>Article 5 (Disclaimer)</h2>
    <ul>
      <li>The accuracy of location data is not guaranteed.</li>
      <li>The accuracy of HealthKit data depends on Apple HealthKit; the Operator does not guarantee it.</li>
      <li>The Operator is not liable for damages caused by service interruptions or outages.</li>
      <li>The Operator is not liable for delays or missing daily reports.</li>
    </ul>

    <h2>Article 6 (Data Handling)</h2>
    <p>Please refer to our <a href="/terms/privacy/en">Privacy Policy</a> for information on how user data is handled.</p>

    <h2>Article 7 (Changes and Termination of Service)</h2>
    <p>The Operator may change or terminate the Service without prior notice.</p>

    <h2>Article 8 (Governing Law and Jurisdiction)</h2>
    <p>These terms are governed by the laws of Japan. In the event of a dispute, the Tokyo District Court shall be the court of exclusive jurisdiction in the first instance.</p>
    `, 'en');
    return c.html(html);
  }

  // Default: Japanese
  const html = pageLayout('利用規約', `
    ${langSwitcher('tos', 'ja')}
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

    <h2>第3条（ユーザー名に関する規則）</h2>
    <p>アカウントを登録するユーザーは、以下の規則に従ってユーザー名を選択する必要があります。</p>
    <ol>
      <li>ユーザー名はサービス全体で一意である必要があります。</li>
      <li>ユーザー名は3文字以上12文字以下とします。</li>
      <li>使用できる文字は半角英小文字、数字、アンダースコア（_）、ハイフン（-）のみです。</li>
      <li>登録の完了にはメールアドレスの認証が必要です。</li>
      <li>無料ユーザーは、一度設定したユーザー名を変更することはできません。</li>
      <li>運営者が定める予約済みユーザー名は登録できません。</li>
    </ol>

    <h2>第4条（禁止事項）</h2>
    <ul>
      <li>APIの不正利用・逆コンパイル・リバースエンジニアリング</li>
      <li>他者のアカウントやトークンの不正使用</li>
      <li>サーバーへの過度な負荷をかける行為</li>
      <li>法令または公序良俗に反する行為</li>
    </ul>

    <h2>第5条（免責事項）</h2>
    <ul>
      <li>位置情報の正確性を保証するものではありません。</li>
      <li>HealthKitデータの正確性はApple HealthKitに依存し、運営者は保証しません。</li>
      <li>サービスの中断・停止により生じた損害について、運営者は責任を負いません。</li>
      <li>日報生成の遅延・欠損について、運営者は責任を負いません。</li>
    </ul>

    <h2>第6条（データの取り扱い）</h2>
    <p>ユーザーデータの取り扱いについては<a href="/terms/privacy/ja">プライバシーポリシー</a>をご参照ください。</p>

    <h2>第7条（サービスの変更・終了）</h2>
    <p>運営者は、事前の告知なくサービス内容の変更・終了を行うことがあります。</p>

    <h2>第8条（準拠法・管轄）</h2>
    <p>本規約は日本法に準拠し、紛争が生じた場合は東京地方裁判所を第一審の専属的合意管轄裁判所とします。</p>
  `, 'ja');
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

// GET /api/username/check?name=xxx — ユーザー名の利用可否チェック
app.get('/api/username/check', async (c) => {
  const name = c.req.query('name');
  if (!name) {
    return c.json({ available: false, reason: 'name query parameter is required' }, 400);
  }
  const result = await validateUsername(c.env.DB, name);
  return c.json(result);
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

// --- File serving & cover upload (must be before catch-all /:username routes) ---

// POST /api/blog/cover — upload cover art PNG (authenticated)
app.post('/api/blog/cover', async (c) => {
  const contentType = c.req.header('Content-Type') || '';

  let username: string;
  let date: string;
  let imageData: ArrayBuffer;

  if (contentType.includes('multipart/form-data')) {
    const form = await c.req.formData();
    username = form.get('username') as string;
    date = form.get('date') as string;
    const file = form.get('image') as File;
    if (!file) return c.json({ error: 'image is required' }, 400);
    imageData = await file.arrayBuffer();
  } else {
    const body = await c.req.json<{ username: string; date: string; image_base64: string }>();
    username = body.username;
    date = body.date;
    if (!body.image_base64) return c.json({ error: 'image_base64 is required' }, 400);
    const binary = atob(body.image_base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    imageData = bytes.buffer;
  }

  if (!username || !date) {
    return c.json({ error: 'username and date are required' }, 400);
  }

  const yymmdd = date.slice(2).replace(/-/g, '');
  const key = `${username}/${yymmdd}.png`;

  await c.env.COVERS.put(key, imageData, {
    httpMetadata: { contentType: 'image/png' },
  });

  const coverUrl = `/${username}/${yymmdd}.png`;

  await c.env.DB.prepare(
    'UPDATE blogs SET cover_url = ? WHERE username = ? AND date = ?'
  ).bind(coverUrl, username, date).run();

  return c.json({ ok: true, cover_url: coverUrl, size: imageData.byteLength });
});

// GET /:username/YYMMDD.md — raw Markdown text
app.get('/:username/:file{[0-9]{6}\\.md}', async (c) => {
  const username = c.req.param('username');
  const file = c.req.param('file');
  const yymmdd = file.replace('.md', '');
  const fullDate = `20${yymmdd.slice(0, 2)}-${yymmdd.slice(2, 4)}-${yymmdd.slice(4, 6)}`;

  const row = await c.env.DB.prepare(
    'SELECT title, body, cover_url FROM blogs WHERE username = ? AND date = ? AND (is_draft IS NULL OR is_draft = 0)'
  ).bind(username, fullDate).first();

  if (!row) {
    return c.text('404 Not Found', 404);
  }

  let md = `# ${(row.title as string) || fullDate}\n\n`;
  if (row.cover_url) {
    md += `![cover](${row.cover_url as string})\n\n`;
  }
  md += (row.body as string);
  md += `\n\n---\n*Generated by [nehan.ai](https://nehan.ai)*\n`;

  return new Response(md, {
    headers: {
      'Content-Type': 'text/markdown; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
    },
  });
});

// GET /:username/YYMMDD.png — cover art from R2
app.get('/:username/:file{[0-9]{6}\\.png}', async (c) => {
  const username = c.req.param('username');
  const file = c.req.param('file');
  const key = `${username}/${file}`;

  const object = await c.env.COVERS.get(key);
  if (!object) {
    return c.text('404 Not Found', 404);
  }

  return new Response(object.body, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'public, max-age=86400',
      'ETag': object.httpEtag,
    },
  });
});

// --- Blog public pages (catch-all, must be last) ---

// GET /:username — blog list
app.get('/:username', async (c) => {
  const username = c.req.param('username');
  const { results } = await c.env.DB.prepare(
    'SELECT date, title, cover_url, published_at FROM blogs WHERE username = ? AND (is_draft IS NULL OR is_draft = 0) ORDER BY date DESC'
  ).bind(username).all();

  if (!results?.length) {
    const html = pageLayout(`${username} のブログ`, `
      <h1>${escapeHtml(username)} のブログ</h1>
      <p style="margin-top:2rem;color:#888;">記事がまだありません。</p>
    `);
    return c.html(html);
  }

  const seen = new Set<string>();
  const unique = (results as any[]).filter((r) => {
    if (seen.has(r.date)) return false;
    seen.add(r.date);
    return true;
  });

  const listItems = unique.map((r) => {
    const d = r.date as string;
    const shortDate = d.slice(2).replace(/-/g, '');
    const displayTitle = r.title || d;
    const coverUrl = r.cover_url as string | null;
    const thumbnailSrc = coverUrl || `/${encodeURIComponent(username)}/${shortDate}.png`;

    let updatedStr = shortDate;
    if (r.published_at) {
      try {
        const pub = new Date(r.published_at + 'Z');
        const jst = new Date(pub.getTime() + 9 * 60 * 60 * 1000);
        const yy = String(jst.getFullYear()).slice(2);
        const mo = String(jst.getMonth() + 1).padStart(2, '0');
        const da = String(jst.getDate()).padStart(2, '0');
        const hh = String(jst.getHours()).padStart(2, '0');
        const mi = String(jst.getMinutes()).padStart(2, '0');
        updatedStr = `${yy}${mo}${da} ${hh}:${mi}`;
      } catch { /* fallback */ }
    }

    return `<li style="margin-bottom:1rem;">
      <a href="/${encodeURIComponent(username)}/${shortDate}" style="text-decoration:none;display:flex;align-items:stretch;gap:12px;padding:8px;border-radius:8px;transition:background 0.2s;" onmouseover="this.style.background='#f8f4ff'" onmouseout="this.style.background='transparent'">
        <div style="flex:1;min-width:0;">
          <div style="font-size:1.05rem;font-weight:600;color:#4B0082;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${escapeHtml(displayTitle)}</div>
          <div style="font-size:0.8rem;color:#888;margin-top:2px;">更新 ${escapeHtml(updatedStr)}</div>
        </div>
        <img src="${escapeHtml(thumbnailSrc)}" alt="" style="width:96px;height:54px;object-fit:cover;border-radius:6px;background:#f0ecf5;flex-shrink:0;" onerror="this.style.display='none'">
      </a>
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

// GET /:username/:date — single blog post (YYMMDD)
app.get('/:username/:date', async (c) => {
  const username = c.req.param('username');
  const rawDate = c.req.param('date');

  if (!/^\d{6}$/.test(rawDate)) {
    return c.html(pageLayout('404', `<h1>404</h1><p>YYMMDD形式で指定してください。</p>`), 404);
  }
  const fullDate = `20${rawDate.slice(0, 2)}-${rawDate.slice(2, 4)}-${rawDate.slice(4, 6)}`;

  const row = await c.env.DB.prepare(
    'SELECT * FROM blogs WHERE username = ? AND date = ? AND (is_draft IS NULL OR is_draft = 0)'
  ).bind(username, fullDate).first();

  if (!row) {
    return c.html(pageLayout('404', `
      <h1>404 Not Found</h1>
      <p>記事が見つかりませんでした。</p>
      <p><a href="/${encodeURIComponent(username)}" style="color:#4B0082;">${escapeHtml(username)} の記事一覧へ</a></p>
    `), 404);
  }

  const title = (row.title as string) || fullDate;
  const coverHtml = row.cover_url
    ? `<img src="${escapeHtml(row.cover_url as string)}" alt="cover" style="width:100%;max-height:360px;object-fit:cover;border-radius:12px;margin-bottom:1.5rem;">`
    : '';
  const bodyHtml = renderMarkdown(row.body as string);

  return c.html(pageLayout(title, `
    ${coverHtml}
    <h1>${escapeHtml(title)}</h1>
    <p style="color:#888;font-size:0.9rem;margin-bottom:2rem;">
      ${escapeHtml(fullDate)} · <a href="/${encodeURIComponent(username)}" style="color:#4B0082;text-decoration:none;">${escapeHtml(username)}</a>
    </p>
    <article style="line-height:1.9;">
      ${bodyHtml}
    </article>
  `));
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
