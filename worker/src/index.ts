import { Hono } from 'hono';
import { iosToSContent, serviceToSContent } from './legal';
import adminApp from './admin';

type Bindings = {
  DB: D1Database;
  COVERS: R2Bucket;
  API_TOKEN: string;
  RESEND_API_KEY: string;
  ADMIN_TOKEN: string;
};

type UserContext = {
  id: number;
  username: string | null;
  tier: number;
} | null;

type Variables = {
  user: UserContext;
};

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// --- Username validation ---
const USERNAME_REGEX = /^[a-z0-9_-]{3,12}$/;

async function validateUsername(
  db: D1Database,
  name: string
): Promise<{ available: boolean; reason?: string }> {
  if (!name || name.length < 3) {
    return { available: false, reason: 'Username must be at least 3 characters' };
  }
  if (name.length > 12) {
    return { available: false, reason: 'Username must be at most 12 characters' };
  }
  if (!USERNAME_REGEX.test(name)) {
    return { available: false, reason: 'Username may only contain lowercase letters, digits, underscores, and hyphens' };
  }

  const reserved = await db.prepare(
    'SELECT 1 FROM reserved_usernames WHERE username = ?'
  ).bind(name).first();
  if (reserved) {
    return { available: false, reason: 'This username is reserved' };
  }

  // Check if already taken by another user
  const existing = await db.prepare(
    'SELECT 1 FROM users WHERE username = ?'
  ).bind(name).first();
  if (existing) {
    return { available: false, reason: 'This username is already taken' };
  }

  return { available: true };
}

// --- SHA-256 helper ---
async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
}

// --- Waitlist (unauthenticated) ---
app.post('/api/waitlist', async (c) => {
  const { email } = await c.req.json<{ email: string }>();
  if (!email || !email.includes('@') || !email.includes('.')) {
    return c.json({ error: 'Valid email is required' }, 400);
  }

  try {
    await c.env.DB.prepare(
      'INSERT INTO waitlist (email) VALUES (?)'
    ).bind(email.toLowerCase().trim()).run();
  } catch (e: any) {
    if (e.message?.includes('UNIQUE')) {
      return c.json({ ok: true, message: 'already_registered' });
    }
    throw e;
  }

  // Send welcome email via Resend
  if (c.env.RESEND_API_KEY) {
    try {
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${c.env.RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'nehan.ai <noreply@nehan.ai>',
          to: [email],
          subject: 'nehan.ai ウェイトリストへようこそ',
          html: `<p>nehan.ai ウェイトリストにご登録いただきありがとうございます。</p>
<p>App Storeでのリリース時にお知らせいたします。</p>
<p>— nehan.ai team</p>`,
        }),
      });
    } catch (e) {
      console.error('Resend waitlist email error:', e);
    }
  }

  return c.json({ ok: true });
});

// --- Auth middleware ---
// Looks up Bearer token via SHA-256 hash in users table.
// Falls back to legacy API_TOKEN for GitHub Actions compatibility.
// POST /api/register is unauthenticated.
app.use('/api/*', async (c, next) => {
  // Skip auth for registration and waitlist
  if (c.req.path === '/api/waitlist' && c.req.method === 'POST') {
    return next();
  }
  if (c.req.path === '/api/register' && c.req.method === 'POST') {
    c.set('user', null);
    return next();
  }

  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const token = authHeader.slice(7);

  // 1. Check legacy API_TOKEN (GitHub Actions / owner compatibility)
  if (token === c.env.API_TOKEN) {
    // Look up owner user (id=1) or create a synthetic context
    const owner = await c.env.DB.prepare(
      'SELECT id, username, tier FROM users WHERE id = 1'
    ).first();
    if (owner) {
      c.set('user', { id: owner.id as number, username: owner.username as string | null, tier: owner.tier as number });
    } else {
      // Legacy mode: no users table populated yet
      c.set('user', { id: 0, username: 'o_ob', tier: 1 });
    }
    return next();
  }

  // 2. Look up per-user API key via SHA-256 hash
  const hash = await sha256(token);
  const user = await c.env.DB.prepare(
    'SELECT id, username, tier FROM users WHERE api_key_hash = ?'
  ).bind(hash).first();

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  c.set('user', { id: user.id as number, username: user.username as string | null, tier: user.tier as number });
  return next();
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
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-NHJNT7G479"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-NHJNT7G479');
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
    .legal-content table { font-size: 0.95rem; }
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
function langSwitcher(section: string, currentLang: string): string {
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
    <p>Privacy inquiries: <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a></p>
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
    <p>You may delete your account and all associated data through the app settings. You may also request deletion by contacting <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a>. We will delete all data within 30 days.</p>

    <h2>8. Cookies</h2>
    <p>This service does not use cookies. API authentication uses Bearer tokens.</p>

    <h2>9. Children's Privacy</h2>
    <p>This service is not intended for children under 13. We do not knowingly collect data from children under 13.</p>

    <h2>10. Changes to This Policy</h2>
    <p>Changes will be posted on this page. Registered users will be notified via email.</p>
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
    <p>プライバシーに関するお問い合わせ: <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a></p>
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
    <p>ユーザーはアプリの設定からアカウントおよび関連データをすべて削除できます。また、<a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a> に連絡することでも削除を要求できます。要求から30日以内にデータを削除します。</p>

    <h2>8. Cookieの使用</h2>
    <p>本サービスはCookieを使用しません。API認証にはBearerトークンを使用しています。</p>

    <h2>9. 児童のプライバシー</h2>
    <p>本サービスは13歳未満の児童を対象としていません。13歳未満の児童のデータを意図的に収集することはありません。</p>

    <h2>10. ポリシーの変更</h2>
    <p>本ポリシーを変更する場合は、本ページにて告知します。登録ユーザーにはメールで通知します。</p>
  `, 'ja');
  return c.html(html);
});

// GET /terms/tos/:lang — 利用規約 (existing simple ToS, kept for backward compatibility)
app.get('/terms/tos/:lang', (c) => {
  const lang = c.req.param('lang');
  const content = serviceToSContent(lang);
  return c.html(pageLayout(
    lang === 'en' ? 'Terms of Service' : '利用規約',
    `${langSwitcher('tos', lang)}${content}`,
    lang
  ));
});

// GET /terms/ios-tos/:lang — iOS App specific ToS (lightweight, for Guest users)
app.get('/terms/ios-tos/:lang', (c) => {
  const lang = c.req.param('lang');
  const content = iosToSContent(lang);
  return c.html(pageLayout(
    lang === 'en' ? 'iOS App Terms of Service' : 'iOSアプリ利用規約',
    `${langSwitcher('ios-tos', lang)}${content}`,
    lang
  ));
});

// GET /dashboard — ダッシュボード（プレースホルダー）
app.get('/dashboard', (c) => {
  const html = pageLayout('ダッシュボード', `
    <h1>ダッシュボード</h1>
    <p style="margin-top: 2rem; text-align: center; color: #888; font-size: 1.1rem;">
      準備中です。ログイン機能とダッシュボードは今後のアップデートで実装予定です。
    </p>
  `);
  return c.html(html);
});

// Admin Dashboard (Basic Auth protected, no GA4 tag)
app.route('/admin', adminApp);

// ==================== API Endpoints ====================

// POST /api/register — Guest registration (unauthenticated)
app.post('/api/register', async (c) => {
  const { device_id } = await c.req.json<{ device_id: string }>();
  if (!device_id) {
    return c.json({ error: 'device_id is required' }, 400);
  }

  // Generate new API key
  const apiKey = crypto.randomUUID() + '-' + crypto.randomUUID();
  const apiKeyHash = await sha256(apiKey);

  // Check if device already registered (e.g. app reinstall)
  const existing = await c.env.DB.prepare(
    'SELECT id, tier FROM users WHERE device_id = ?'
  ).bind(device_id).first();

  if (existing) {
    // Re-issue API key for existing device (preserves tier, username, etc.)
    await c.env.DB.prepare(
      'UPDATE users SET api_key_hash = ? WHERE id = ?'
    ).bind(apiKeyHash, existing.id).run();
    return c.json({ ok: true, api_key: apiKey, user_id: existing.id as number, tier: existing.tier as number });
  }

  // New device registration (Tier 0 = Guest)
  await c.env.DB.prepare(
    'INSERT INTO users (api_key_hash, device_id, tier) VALUES (?, ?, 0)'
  ).bind(apiKeyHash, device_id).run();

  const user = await c.env.DB.prepare(
    'SELECT id FROM users WHERE device_id = ?'
  ).bind(device_id).first();

  return c.json({ ok: true, api_key: apiKey, user_id: user?.id ?? 0, tier: 0 });
});

// GET /api/me — Current user profile
app.get('/api/me', async (c) => {
  const user = c.get('user');
  if (!user || user.id === 0) {
    return c.json({ error: 'Not authenticated' }, 401);
  }

  const row = await c.env.DB.prepare(
    'SELECT id, username, email, email_verified_at, tier, tos_accepted_at, device_id, created_at FROM users WHERE id = ?'
  ).bind(user.id).first();

  if (!row) {
    return c.json({ error: 'User not found' }, 404);
  }

  return c.json(row);
});

// PUT /api/me/demographics — update user demographics (language, gender, birth_year)
app.put('/api/me/demographics', async (c) => {
  const user = c.get('user');
  if (!user || user.id === 0) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { language, gender, birth_year } = await c.req.json<{
    language?: string;
    gender?: string;
    birth_year?: number;
  }>();

  // Validate inputs
  const validLanguages = ['ja', 'en', 'zh-Hans', 'zh-Hant'];
  const validGenders = ['male', 'female', 'other', 'preferNotToSay'];

  if (language && !validLanguages.includes(language)) {
    return c.json({ error: 'Invalid language' }, 400);
  }
  if (gender && !validGenders.includes(gender)) {
    return c.json({ error: 'Invalid gender' }, 400);
  }
  if (birth_year && (birth_year < 1900 || birth_year > new Date().getFullYear())) {
    return c.json({ error: 'Invalid birth_year' }, 400);
  }

  await c.env.DB.prepare(
    'UPDATE users SET language = COALESCE(?, language), gender = COALESCE(?, gender), birth_year = COALESCE(?, birth_year) WHERE id = ?'
  ).bind(language ?? null, gender ?? null, birth_year ?? null, user.id).run();

  return c.json({ ok: true });
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
  const user = c.get('user');
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

  const userId = user?.id ?? null;
  const stmt = c.env.DB.prepare(
    'INSERT INTO logs (timestamp, type, latitude, longitude, place_name, payload, user_id) VALUES (?, ?, ?, ?, ?, ?, ?)'
  );

  const batch = entries.map((e) =>
    stmt.bind(e.timestamp, e.type, e.latitude ?? null, e.longitude ?? null, e.place_name ?? null, e.payload ?? null, userId)
  );

  await c.env.DB.batch(batch);
  return c.json({ ok: true, count: entries.length });
});

// GET /api/logs?date=YYYY-MM-DD
app.get('/api/logs', async (c) => {
  const user = c.get('user');
  const date = c.req.query('date') ?? new Date().toISOString().slice(0, 10);

  // Filter by user_id if available
  if (user && user.id > 0) {
    const results = await c.env.DB.prepare(
      "SELECT * FROM logs WHERE date(timestamp, '+9 hours') = ? AND (user_id = ? OR user_id IS NULL) ORDER BY timestamp ASC"
    ).bind(date, user.id).all();
    return c.json(results);
  }

  const results = await c.env.DB.prepare(
    "SELECT * FROM logs WHERE date(timestamp, '+9 hours') = ? ORDER BY timestamp ASC"
  ).bind(date).all();
  return c.json(results);
});

// GET /api/summary?date=YYYY-MM-DD — 日報プレビュー
app.get('/api/summary', async (c) => {
  const user = c.get('user');
  const date = c.req.query('date') ?? new Date().toISOString().slice(0, 10);
  const userId = user?.id ?? null;
  const markdown = await generateDailyReport(c.env.DB, date, userId);
  return c.text(markdown);
});

// --- Blog API ---

// Simple Markdown to HTML converter
function renderMarkdown(md: string): string {
  return md
    .split('\n')
    .map((line) => {
      if (line.startsWith('##### ')) return `<h5>${escapeHtml(line.slice(6))}</h5>`;
      if (line.startsWith('#### ')) return `<h4>${escapeHtml(line.slice(5))}</h4>`;
      if (line.startsWith('### ')) return `<h3>${escapeHtml(line.slice(4))}</h3>`;
      if (line.startsWith('## ')) return `<h2>${escapeHtml(line.slice(3))}</h2>`;
      if (line.startsWith('# ')) return `<h1>${escapeHtml(line.slice(2))}</h1>`;
      if (/^---+$/.test(line.trim())) return '<hr>';
      if (line.startsWith('- ')) return `<li>${inlineMarkdown(line.slice(2))}</li>`;
      if (/^\d+\. /.test(line)) return `<li>${inlineMarkdown(line.replace(/^\d+\. /, ''))}</li>`;
      if (line.trim() === '') return '';
      return `<p>${inlineMarkdown(line)}</p>`;
    })
    .join('\n');
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function inlineMarkdown(s: string): string {
  let out = escapeHtml(s);
  out = out.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" style="max-width:100%;border-radius:8px;margin:0.5rem 0;">');
  out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" style="color:#4B0082;">$1</a>');
  out = out.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  out = out.replace(/\*(.+?)\*/g, '<em>$1</em>');
  out = out.replace(/`(.+?)`/g, '<code style="background:#f4f0ff;padding:0.1em 0.4em;border-radius:3px;font-size:0.9em;">$1</code>');
  return out;
}

// POST /api/blog — create or update a blog entry (authenticated)
app.post('/api/blog', async (c) => {
  const user = c.get('user');

  // Blog publishing requires tier >= 1 (registered user)
  if (!user || user.tier < 1) {
    return c.json({ error: 'Blog publishing requires registration (Tier 1)' }, 403);
  }

  const { date, title, body, cover_url, is_draft } = await c.req.json<{
    date: string;
    title?: string;
    body: string;
    cover_url?: string;
    is_draft?: boolean;
  }>();

  // Use username from auth context, not request body
  const username = user.username;
  if (!username || !date || !body) {
    return c.json({ error: 'date and body are required; username must be set via registration' }, 400);
  }

  await c.env.DB.prepare(
    'INSERT OR REPLACE INTO blogs (username, date, title, body, cover_url, is_draft, user_id) VALUES (?, ?, ?, ?, ?, ?, ?)'
  ).bind(username, date, title ?? null, body, cover_url ?? null, is_draft ? 1 : 0, user.id).run();

  return c.json({ ok: true, username, date, is_draft: !!is_draft });
});

// POST /api/blog/cover — upload cover art PNG (authenticated)
app.post('/api/blog/cover', async (c) => {
  const user = c.get('user');
  if (!user || user.tier < 1) {
    return c.json({ error: 'Cover upload requires registration (Tier 1)' }, 403);
  }

  const username = user.username;
  if (!username) {
    return c.json({ error: 'Username must be set via registration' }, 400);
  }

  const contentType = c.req.header('Content-Type') || '';
  let date: string;
  let imageData: ArrayBuffer;

  if (contentType.includes('multipart/form-data')) {
    const form = await c.req.formData();
    date = form.get('date') as string;
    const file = form.get('image') as File;
    if (!file) return c.json({ error: 'image is required' }, 400);
    imageData = await file.arrayBuffer();
  } else {
    const body = await c.req.json<{ date: string; image_base64: string }>();
    date = body.date;
    if (!body.image_base64) return c.json({ error: 'image_base64 is required' }, 400);
    const binary = atob(body.image_base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    imageData = bytes.buffer;
  }

  if (!date) {
    return c.json({ error: 'date is required' }, 400);
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

// DELETE /api/blog — delete a blog entry
app.delete('/api/blog', async (c) => {
  const user = c.get('user');
  if (!user || !user.username) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { date } = await c.req.json<{ date: string }>();
  if (!date) return c.json({ error: 'date is required' }, 400);

  // Delete blog record
  await c.env.DB.prepare(
    'DELETE FROM blogs WHERE username = ? AND date = ? AND user_id = ?'
  ).bind(user.username, date, user.id).run();

  // Delete R2 cover
  const yymmdd = date.slice(2).replace(/-/g, '');
  const key = `${user.username}/${yymmdd}.png`;
  await c.env.COVERS.delete(key);

  return c.json({ ok: true });
});

// DELETE /api/account — delete all user data
app.delete('/api/account', async (c) => {
  const user = c.get('user');
  if (!user || user.id === 0) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  // Delete all blogs
  const blogs = await c.env.DB.prepare(
    'SELECT username, date FROM blogs WHERE user_id = ?'
  ).bind(user.id).all();

  // Delete R2 covers
  for (const blog of blogs.results ?? []) {
    const yymmdd = (blog.date as string).slice(2).replace(/-/g, '');
    const key = `${blog.username}/${yymmdd}.png`;
    await c.env.COVERS.delete(key);
  }

  // Delete all data in batch
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM blogs WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM logs WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM email_verifications WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
  ]);

  return c.json({ ok: true });
});

// POST /api/verify-email/send — send verification email via Resend
app.post('/api/verify-email/send', async (c) => {
  const user = c.get('user');
  if (!user || user.id === 0) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { email } = await c.req.json<{ email: string }>();
  if (!email || !email.includes('@')) {
    return c.json({ error: 'Valid email is required' }, 400);
  }

  // Generate 6-digit code
  const code = String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

  // Store verification record
  await c.env.DB.prepare(
    'INSERT INTO email_verifications (user_id, email, code, expires_at) VALUES (?, ?, ?, ?)'
  ).bind(user.id, email, code, expiresAt).run();

  // Update user email
  await c.env.DB.prepare(
    'UPDATE users SET email = ? WHERE id = ?'
  ).bind(email, user.id).run();

  // Send email via Resend
  if (c.env.RESEND_API_KEY) {
    try {
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${c.env.RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'nehan.ai <noreply@nehan.ai>',
          to: [email],
          subject: 'nehan.ai - Email Verification Code',
          html: `<p>Your verification code is: <strong>${code}</strong></p><p>This code expires in 10 minutes.</p><p>If you did not request this, please ignore this email.</p>`,
        }),
      });
    } catch (e) {
      console.error('Resend API error:', e);
    }
  } else {
    // Dev mode: log code to console
    console.log(`[dev] Verification code for ${email}: ${code}`);
  }

  return c.json({ ok: true });
});

// POST /api/verify-email/confirm — verify email code
app.post('/api/verify-email/confirm', async (c) => {
  const user = c.get('user');
  if (!user || user.id === 0) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { code } = await c.req.json<{ code: string }>();
  if (!code) {
    return c.json({ error: 'code is required' }, 400);
  }

  const record = await c.env.DB.prepare(
    'SELECT id, email, expires_at FROM email_verifications WHERE user_id = ? AND code = ? AND used_at IS NULL ORDER BY created_at DESC LIMIT 1'
  ).bind(user.id, code).first();

  if (!record) {
    return c.json({ error: 'Invalid or expired code' }, 400);
  }

  const expiresAt = new Date(record.expires_at as string);
  if (expiresAt < new Date()) {
    return c.json({ error: 'Code has expired' }, 400);
  }

  const now = new Date().toISOString();

  // Mark code as used and verify email
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE email_verifications SET used_at = ? WHERE id = ?').bind(now, record.id),
    c.env.DB.prepare('UPDATE users SET email_verified_at = ? WHERE id = ?').bind(now, user.id),
  ]);

  return c.json({ ok: true });
});

// POST /api/upgrade — upgrade from guest to registered (Tier 1)
app.post('/api/upgrade', async (c) => {
  const user = c.get('user');
  if (!user || user.id === 0) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { username, tos_version } = await c.req.json<{ username: string; tos_version: string }>();

  // Check email verification
  const userRow = await c.env.DB.prepare(
    'SELECT email_verified_at FROM users WHERE id = ?'
  ).bind(user.id).first();

  if (!userRow?.email_verified_at) {
    return c.json({ error: 'Email verification required before upgrading' }, 400);
  }

  // Validate username
  const usernameResult = await validateUsername(c.env.DB, username);
  if (!usernameResult.available) {
    return c.json({ error: usernameResult.reason }, 400);
  }

  const now = new Date().toISOString();

  await c.env.DB.prepare(
    'UPDATE users SET username = ?, tier = 1, tos_accepted_at = ?, tos_version = ? WHERE id = ?'
  ).bind(username, now, tos_version || '2026-04-11', user.id).run();

  return c.json({ ok: true, username, tier: 1 });
});

// --- File serving & blog pages ---

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
      current.end = l.timestamp;
    } else {
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

async function generateDailyReport(db: D1Database, date: string, userId: number | null): Promise<string> {
  let results;
  if (userId && userId > 0) {
    const res = await db.prepare(
      "SELECT * FROM logs WHERE date(timestamp, '+9 hours') = ? AND (user_id = ? OR user_id IS NULL) ORDER BY timestamp ASC"
    ).bind(date, userId).all();
    results = res.results;
  } else {
    const res = await db.prepare(
      "SELECT * FROM logs WHERE date(timestamp, '+9 hours') = ? ORDER BY timestamp ASC"
    ).bind(date).all();
    results = res.results;
  }

  if (!results?.length) return '';

  const locations = results.filter((r: any) => r.type === 'location');
  const sleeps = results.filter((r: any) => r.type === 'sleep');
  const healthMemos = results.filter((r: any) => r.type === 'memo' && (r as any).payload?.startsWith('health:'));
  const memos = results.filter((r: any) => r.type === 'memo' && !(r as any).payload?.startsWith('health:'));

  let md = `# nehan日報 ${date}\n\n`;

  if (sleeps.length > 0) {
    const s = sleeps[sleeps.length - 1];
    md += `## 睡眠\n`;
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
      // Naps
      if (p.naps && Array.isArray(p.naps) && p.naps.length > 0) {
        md += `\n### 昼寝 (Naps)\n`;
        for (const nap of p.naps) {
          const napStart = nap.start ? toJST(nap.start) : '?';
          const napEnd = nap.end ? toJST(nap.end) : '?';
          md += `- ${napStart}〜${napEnd} ${nap.minutes}分 — ${nap.evaluation || ''}\n`;
        }
      }
    } catch {
      md += `- (データ解析エラー)\n`;
    }
    md += '\n';
  }

  if (healthMemos.length > 0) {
    const h = healthMemos[healthMemos.length - 1];
    try {
      const json = (h as any).payload?.replace('health: ', '') ?? '{}';
      const p = JSON.parse(json);
      if (p.steps || p.heartRate) {
        md += `## アクティビティ\n`;
        if (p.steps) md += `- 歩数: ${Number(p.steps).toLocaleString()} 歩\n`;
        if (p.heartRate) {
          md += `- 心拍: 平均 ${p.heartRate.avg} bpm (↓${p.heartRate.min} ↑${p.heartRate.max})\n`;
        }
        md += '\n';
      }
    } catch { /* skip */ }
  }

  if (locations.length > 0) {
    const collapsed = collapseLocations(locations);
    md += `## 訪問場所\n`;
    md += `| 時刻 | 場所 | 座標 |\n|------|------|------|\n`;
    for (const loc of collapsed) {
      const startTime = toJST(loc.start);
      const endTime = toJST(loc.end);
      const time = loc.start === loc.end ? startTime : `${startTime}〜${endTime}`;
      md += `| ${time} | ${loc.place} | ${loc.coord} |\n`;
    }
    md += '\n';
  }

  if (memos.length > 0) {
    md += `## メモ\n`;
    for (const m of memos) {
      const time = toJST((m as any).timestamp);
      md += `- ${time} ${(m as any).payload || ''}\n`;
    }
    md += '\n';
  }

  md += `---\n*Generated by nehan.ai*\n`;
  return md;
}
