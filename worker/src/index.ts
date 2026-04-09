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
