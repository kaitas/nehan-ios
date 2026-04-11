// Admin Dashboard — Basic Auth protected, server-rendered HTML
import { Hono } from 'hono';
import { basicAuth } from 'hono/basic-auth';

type Bindings = {
  DB: D1Database;
  COVERS: R2Bucket;
  API_TOKEN: string;
  RESEND_API_KEY: string;
  ADMIN_TOKEN: string;
};

const adminApp = new Hono<{ Bindings: Bindings }>();

// Basic Auth middleware
adminApp.use('*', async (c, next) => {
  const token = c.env.ADMIN_TOKEN;
  if (!token) {
    return c.text('ADMIN_TOKEN not configured', 503);
  }
  const auth = basicAuth({ username: 'admin', password: token });
  return auth(c, next);
});

// --- Stats JSON API ---
adminApp.get('/api/stats', async (c) => {
  const stats = await c.env.DB.batch([
    c.env.DB.prepare('SELECT COUNT(*) as total FROM users'),
    c.env.DB.prepare('SELECT tier, COUNT(*) as count FROM users GROUP BY tier'),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM users WHERE created_at >= date('now', '-1 day')"),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM users WHERE created_at >= date('now', '-7 days')"),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM users WHERE created_at >= date('now', '-30 days')"),
    c.env.DB.prepare('SELECT COUNT(*) as total FROM email_verifications'),
    c.env.DB.prepare('SELECT COUNT(*) as count FROM email_verifications WHERE used_at IS NOT NULL'),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM email_verifications WHERE used_at IS NULL AND expires_at > datetime('now')"),
    c.env.DB.prepare("SELECT COUNT(DISTINCT user_id) as count FROM logs WHERE timestamp >= date('now')"),
    c.env.DB.prepare('SELECT COUNT(*) as total FROM blogs WHERE (is_draft IS NULL OR is_draft = 0)'),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM blogs WHERE (is_draft IS NULL OR is_draft = 0) AND published_at >= date('now', '-30 days')"),
    c.env.DB.prepare("SELECT COUNT(DISTINCT user_id) as count FROM blogs WHERE (is_draft IS NULL OR is_draft = 0) AND published_at >= date('now', '-30 days')"),
    c.env.DB.prepare('SELECT COUNT(*) as total FROM logs'),
    c.env.DB.prepare('SELECT id, username, email, tier, created_at FROM users ORDER BY created_at DESC LIMIT 20'),
    c.env.DB.prepare("SELECT COALESCE(language, 'unknown') as language, COUNT(*) as count FROM users GROUP BY language ORDER BY count DESC"),
    c.env.DB.prepare("SELECT COALESCE(gender, 'unknown') as gender, COUNT(*) as count FROM users GROUP BY gender ORDER BY count DESC"),
    c.env.DB.prepare(`SELECT
      CASE
        WHEN birth_year IS NULL THEN 'unknown'
        WHEN (strftime('%Y','now') - birth_year) < 18 THEN 'under18'
        WHEN (strftime('%Y','now') - birth_year) < 25 THEN '18-24'
        WHEN (strftime('%Y','now') - birth_year) < 35 THEN '25-34'
        WHEN (strftime('%Y','now') - birth_year) < 45 THEN '35-44'
        WHEN (strftime('%Y','now') - birth_year) < 55 THEN '45-54'
        ELSE '55+'
      END as age_group, COUNT(*) as count FROM users GROUP BY age_group ORDER BY count DESC`),
  ]);

  const totalUsers = (stats[0].results[0] as any)?.total ?? 0;
  const tierBreakdown = stats[1].results as any[];
  const newToday = (stats[2].results[0] as any)?.count ?? 0;
  const new7d = (stats[3].results[0] as any)?.count ?? 0;
  const new30d = (stats[4].results[0] as any)?.count ?? 0;
  const emailTotal = (stats[5].results[0] as any)?.total ?? 0;
  const emailVerified = (stats[6].results[0] as any)?.count ?? 0;
  const emailPending = (stats[7].results[0] as any)?.count ?? 0;
  const activeToday = (stats[8].results[0] as any)?.count ?? 0;
  const blogTotal = (stats[9].results[0] as any)?.total ?? 0;
  const blogMonth = (stats[10].results[0] as any)?.count ?? 0;
  const activeBloggers = (stats[11].results[0] as any)?.count ?? 0;
  const logTotal = (stats[12].results[0] as any)?.total ?? 0;
  const recentUsers = stats[13].results;
  const languageDist = stats[14].results;
  const genderDist = stats[15].results;
  const ageDist = stats[16].results;

  return c.json({
    users: { total: totalUsers, tierBreakdown, newToday, new7d, new30d },
    email: { total: emailTotal, verified: emailVerified, pending: emailPending },
    activity: { activeToday, logTotal },
    blogs: { total: blogTotal, thisMonth: blogMonth, activeBloggers },
    demographics: { language: languageDist, gender: genderDist, age: ageDist },
    recentUsers,
  });
});

// --- Retention JSON API ---
adminApp.get('/api/retention', async (c) => {
  // 7-day cohort retention: users who registered in the last 4 weeks
  const cohorts = [];
  for (let week = 0; week < 4; week++) {
    const startDay = week * 7 + 7;
    const endDay = week * 7;
    const cohortQuery = await c.env.DB.prepare(`
      SELECT
        COUNT(DISTINCT u.id) as cohort_size,
        ${[1, 2, 3, 4, 5, 6, 7].map(d =>
          `COUNT(DISTINCT CASE WHEN EXISTS (
            SELECT 1 FROM logs l WHERE l.user_id = u.id
            AND date(l.timestamp, '+9 hours') = date(u.created_at, '+${d} days')
          ) THEN u.id END) as d${d}`
        ).join(',\n        ')}
      FROM users u
      WHERE u.created_at >= date('now', '-${startDay} days')
        AND u.created_at < date('now', '-${endDay} days')
    `).first();
    cohorts.push({
      week: `W-${week + 1}`,
      startDay,
      endDay,
      ...(cohortQuery as any),
    });
  }
  return c.json({ cohorts });
});

// --- Feature usage JSON API ---
adminApp.get('/api/features', async (c) => {
  const features = await c.env.DB.batch([
    c.env.DB.prepare("SELECT type, COUNT(*) as count FROM logs GROUP BY type ORDER BY count DESC"),
    c.env.DB.prepare("SELECT type, COUNT(*) as count FROM logs WHERE timestamp >= date('now', '-7 days') GROUP BY type ORDER BY count DESC"),
  ]);
  return c.json({
    allTime: features[0].results,
    last7d: features[1].results,
  });
});

// --- Dashboard HTML ---
adminApp.get('/', async (c) => {
  // Fetch stats inline for server-rendered page
  const stats = await c.env.DB.batch([
    c.env.DB.prepare('SELECT COUNT(*) as total FROM users'),
    c.env.DB.prepare('SELECT tier, COUNT(*) as count FROM users GROUP BY tier'),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM users WHERE created_at >= date('now', '-1 day')"),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM users WHERE created_at >= date('now', '-7 days')"),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM users WHERE created_at >= date('now', '-30 days')"),
    c.env.DB.prepare('SELECT COUNT(*) as total FROM email_verifications'),
    c.env.DB.prepare('SELECT COUNT(*) as count FROM email_verifications WHERE used_at IS NOT NULL'),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM email_verifications WHERE used_at IS NULL AND expires_at > datetime('now')"),
    c.env.DB.prepare("SELECT COUNT(DISTINCT user_id) as count FROM logs WHERE timestamp >= date('now')"),
    c.env.DB.prepare('SELECT COUNT(*) as total FROM blogs WHERE (is_draft IS NULL OR is_draft = 0)'),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM blogs WHERE (is_draft IS NULL OR is_draft = 0) AND published_at >= date('now', '-30 days')"),
    c.env.DB.prepare("SELECT COUNT(DISTINCT user_id) as count FROM blogs WHERE (is_draft IS NULL OR is_draft = 0) AND published_at >= date('now', '-30 days')"),
    c.env.DB.prepare('SELECT COUNT(*) as total FROM logs'),
    c.env.DB.prepare('SELECT id, username, email, tier, created_at FROM users ORDER BY created_at DESC LIMIT 20'),
    c.env.DB.prepare("SELECT type, COUNT(*) as count FROM logs GROUP BY type ORDER BY count DESC"),
    c.env.DB.prepare("SELECT COALESCE(language, 'unknown') as language, COUNT(*) as count FROM users GROUP BY language ORDER BY count DESC"),
    c.env.DB.prepare("SELECT COALESCE(gender, 'unknown') as gender, COUNT(*) as count FROM users GROUP BY gender ORDER BY count DESC"),
    c.env.DB.prepare(`SELECT
      CASE
        WHEN birth_year IS NULL THEN 'unknown'
        WHEN (strftime('%Y','now') - birth_year) < 18 THEN 'under18'
        WHEN (strftime('%Y','now') - birth_year) < 25 THEN '18-24'
        WHEN (strftime('%Y','now') - birth_year) < 35 THEN '25-34'
        WHEN (strftime('%Y','now') - birth_year) < 45 THEN '35-44'
        WHEN (strftime('%Y','now') - birth_year) < 55 THEN '45-54'
        ELSE '55+'
      END as age_group, COUNT(*) as count FROM users GROUP BY age_group ORDER BY count DESC`),
    c.env.DB.prepare('SELECT COUNT(*) as total FROM waitlist'),
    c.env.DB.prepare("SELECT COUNT(*) as count FROM waitlist WHERE created_at >= date('now', '-7 days')"),
  ]);

  const totalUsers = (stats[0].results[0] as any)?.total ?? 0;
  const tierBreakdown = stats[1].results as any[];
  const newToday = (stats[2].results[0] as any)?.count ?? 0;
  const new7d = (stats[3].results[0] as any)?.count ?? 0;
  const new30d = (stats[4].results[0] as any)?.count ?? 0;
  const emailTotal = (stats[5].results[0] as any)?.total ?? 0;
  const emailVerified = (stats[6].results[0] as any)?.count ?? 0;
  const emailPending = (stats[7].results[0] as any)?.count ?? 0;
  const activeToday = (stats[8].results[0] as any)?.count ?? 0;
  const blogTotal = (stats[9].results[0] as any)?.total ?? 0;
  const blogMonth = (stats[10].results[0] as any)?.count ?? 0;
  const activeBloggers = (stats[11].results[0] as any)?.count ?? 0;
  const logTotal = (stats[12].results[0] as any)?.total ?? 0;
  const recentUsers = stats[13].results as any[];
  const logTypes = stats[14].results as any[];
  const languageDist = stats[15].results as any[];
  const genderDist = stats[16].results as any[];
  const ageDist = stats[17].results as any[];
  const waitlistTotal = (stats[18].results[0] as any)?.total ?? 0;
  const waitlistWeek = (stats[19].results[0] as any)?.count ?? 0;

  const guestCount = tierBreakdown.find((t: any) => t.tier === 0)?.count ?? 0;
  const registeredCount = tierBreakdown.find((t: any) => t.tier === 1)?.count ?? 0;

  const emailRate = emailTotal > 0 ? Math.round((emailVerified / emailTotal) * 100) : 0;

  const recentUsersRows = recentUsers.map((u: any) => `
    <tr>
      <td>${esc(String(u.id))}</td>
      <td>${u.username ? esc(u.username) : '<span style="color:#666;">—</span>'}</td>
      <td>${u.email ? esc(u.email) : '<span style="color:#666;">—</span>'}</td>
      <td><span class="tier-badge tier-${u.tier}">Tier ${u.tier}</span></td>
      <td>${esc(u.created_at ?? '')}</td>
    </tr>
  `).join('');

  const logTypeRows = logTypes.map((t: any) => `
    <tr>
      <td>${esc(t.type)}</td>
      <td>${Number(t.count).toLocaleString()}</td>
    </tr>
  `).join('');

  const langLabels: Record<string, string> = {
    ja: '日本語', en: 'English', 'zh-Hans': '简体中文', 'zh-Hant': '繁體中文', unknown: '未設定',
  };
  const genderLabels: Record<string, string> = {
    male: '男性', female: '女性', other: 'その他', preferNotToSay: '回答しない', unknown: '未設定',
  };

  const langRows = languageDist.map((r: any) => `
    <tr><td>${esc(langLabels[r.language] ?? r.language)}</td><td>${r.count}</td></tr>
  `).join('');
  const genderRows = genderDist.map((r: any) => `
    <tr><td>${esc(genderLabels[r.gender] ?? r.gender)}</td><td>${r.count}</td></tr>
  `).join('');
  const ageRows = ageDist.map((r: any) => `
    <tr><td>${esc(r.age_group === 'unknown' ? '未設定' : r.age_group)}</td><td>${r.count}</td></tr>
  `).join('');

  const html = `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Admin Dashboard — nehan.ai</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #0a0014;
      color: #e0d8f0;
      line-height: 1.6;
    }
    .header {
      background: linear-gradient(135deg, #1a0030, #2d1050);
      padding: 1.5rem 2rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid #3d2060;
    }
    .header h1 {
      font-size: 1.3rem;
      color: #c8b0ff;
    }
    .header a { color: #9070cc; text-decoration: none; font-size: 0.9rem; }
    .header a:hover { color: #c8b0ff; }
    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 1.5rem;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 1rem;
      margin-bottom: 1.5rem;
    }
    .card {
      background: #1a0f2e;
      border: 1px solid #2d1850;
      border-radius: 12px;
      padding: 1.2rem;
    }
    .card h3 {
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #8060b0;
      margin-bottom: 0.5rem;
    }
    .card .value {
      font-size: 2.2rem;
      font-weight: 700;
      color: #c8b0ff;
    }
    .card .sub {
      font-size: 0.85rem;
      color: #7060a0;
      margin-top: 0.3rem;
    }
    .section {
      background: #1a0f2e;
      border: 1px solid #2d1850;
      border-radius: 12px;
      padding: 1.5rem;
      margin-bottom: 1.5rem;
    }
    .section h2 {
      font-size: 1.1rem;
      color: #c8b0ff;
      margin-bottom: 1rem;
      padding-bottom: 0.5rem;
      border-bottom: 1px solid #2d1850;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.9rem;
    }
    th {
      text-align: left;
      padding: 0.6rem 0.8rem;
      color: #8060b0;
      font-weight: 600;
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.03em;
      border-bottom: 1px solid #2d1850;
    }
    td {
      padding: 0.5rem 0.8rem;
      border-bottom: 1px solid #1d1040;
    }
    tr:hover { background: #1f1440; }
    .tier-badge {
      display: inline-block;
      padding: 0.15rem 0.5rem;
      border-radius: 4px;
      font-size: 0.75rem;
      font-weight: 600;
    }
    .tier-0 { background: #2d1850; color: #9080b0; }
    .tier-1 { background: #1a3050; color: #70b0e0; }
    .bar {
      display: flex;
      height: 8px;
      border-radius: 4px;
      overflow: hidden;
      background: #1d1040;
      margin-top: 0.5rem;
    }
    .bar-fill {
      background: linear-gradient(90deg, #6040a0, #9070e0);
      border-radius: 4px;
      transition: width 0.3s;
    }
    .links {
      display: flex;
      gap: 1rem;
      flex-wrap: wrap;
    }
    .links a {
      display: inline-block;
      padding: 0.6rem 1rem;
      background: #2d1850;
      color: #c8b0ff;
      border-radius: 8px;
      text-decoration: none;
      font-size: 0.85rem;
    }
    .links a:hover { background: #3d2070; }
    @media (max-width: 600px) {
      .grid { grid-template-columns: 1fr 1fr; }
      .card .value { font-size: 1.6rem; }
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>nehan.ai Admin</h1>
    <div>
      <a href="/">LP</a> &middot;
      <a href="/admin/api/stats">JSON API</a> &middot;
      <a href="https://analytics.google.com/" target="_blank">GA4</a>
    </div>
  </div>
  <div class="container">
    <!-- Overview Cards -->
    <div class="grid">
      <div class="card">
        <h3>Total Users</h3>
        <div class="value">${totalUsers}</div>
        <div class="sub">Guest: ${guestCount} / Registered: ${registeredCount}</div>
      </div>
      <div class="card">
        <h3>New Users (Today)</h3>
        <div class="value">${newToday}</div>
        <div class="sub">7d: ${new7d} / 30d: ${new30d}</div>
      </div>
      <div class="card">
        <h3>Active Today</h3>
        <div class="value">${activeToday}</div>
        <div class="sub">Users with logs today</div>
      </div>
      <div class="card">
        <h3>Total Logs</h3>
        <div class="value">${Number(logTotal).toLocaleString()}</div>
      </div>
    </div>

    <div class="grid">
      <div class="card">
        <h3>Published Blogs</h3>
        <div class="value">${blogTotal}</div>
        <div class="sub">This month: ${blogMonth} / Bloggers: ${activeBloggers}</div>
      </div>
      <div class="card">
        <h3>Email Verification</h3>
        <div class="value">${emailRate}%</div>
        <div class="sub">Sent: ${emailTotal} / Verified: ${emailVerified} / Pending: ${emailPending}</div>
        <div class="bar"><div class="bar-fill" style="width:${emailRate}%"></div></div>
      </div>
      <div class="card">
        <h3>Waitlist</h3>
        <div class="value">${waitlistTotal}</div>
        <div class="sub">This week: +${waitlistWeek}</div>
      </div>
    </div>

    <!-- User Demographics -->
    <div class="section">
      <h2>User Demographics</h2>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;">
        <div>
          <h3 style="font-size:0.85rem;color:#8060b0;margin-bottom:0.5rem;">Language</h3>
          <table>
            <thead><tr><th>Language</th><th>Count</th></tr></thead>
            <tbody>${langRows || '<tr><td colspan="2" style="color:#666;">No data</td></tr>'}</tbody>
          </table>
        </div>
        <div>
          <h3 style="font-size:0.85rem;color:#8060b0;margin-bottom:0.5rem;">Gender</h3>
          <table>
            <thead><tr><th>Gender</th><th>Count</th></tr></thead>
            <tbody>${genderRows || '<tr><td colspan="2" style="color:#666;">No data</td></tr>'}</tbody>
          </table>
        </div>
        <div>
          <h3 style="font-size:0.85rem;color:#8060b0;margin-bottom:0.5rem;">Age Group</h3>
          <table>
            <thead><tr><th>Age</th><th>Count</th></tr></thead>
            <tbody>${ageRows || '<tr><td colspan="2" style="color:#666;">No data</td></tr>'}</tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Feature Usage -->
    <div class="section">
      <h2>Log Type Distribution</h2>
      <table>
        <thead><tr><th>Type</th><th>Count</th></tr></thead>
        <tbody>${logTypeRows || '<tr><td colspan="2" style="color:#666;">No data</td></tr>'}</tbody>
      </table>
    </div>

    <!-- Recent Users -->
    <div class="section">
      <h2>Recent Users (Latest 20)</h2>
      <table>
        <thead>
          <tr><th>ID</th><th>Username</th><th>Email</th><th>Tier</th><th>Created</th></tr>
        </thead>
        <tbody>${recentUsersRows || '<tr><td colspan="5" style="color:#666;">No users</td></tr>'}</tbody>
      </table>
    </div>

    <!-- External Links -->
    <div class="section">
      <h2>External</h2>
      <div class="links">
        <a href="https://analytics.google.com/" target="_blank">Google Analytics 4</a>
        <a href="https://dash.cloudflare.com/" target="_blank">Cloudflare Dashboard</a>
        <a href="https://github.com/kaitas/nehan-ios" target="_blank">GitHub Repository</a>
      </div>
      <div style="margin-top:1rem;padding:0.8rem;background:#1d1040;border-radius:8px;color:#7060a0;font-size:0.85rem;">
        Ad Revenue — Coming Soon
      </div>
    </div>
  </div>
</body>
</html>`;
  return c.html(html);
});

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

export default adminApp;
