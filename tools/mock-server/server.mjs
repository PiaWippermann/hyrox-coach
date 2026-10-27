// Mock des Backends: gleiche Endpunkte wie docs/api.md, alles im Speicher, KEINE KI, KEIN MongoDB.
// Zweck: die Flutter-App ohne Docker und ohne API-Key entwickeln und den API-Vertrag testen.
//   node mock-server/server.mjs     (Port 8080, oder PORT=9090)
import http from 'node:http';
import crypto from 'node:crypto';
import { addDays } from '../lib/plan-checks.mjs';

const PORT = Number(process.env.PORT ?? 8080);
const ADMIN_KEY = process.env.ADMIN_KEY ?? 'dev-admin';

const users = new Map();      // userId -> {id, name, nameKey, hash}
const anamneses = new Map();  // userId -> anamnese
const results = new Map();    // userId -> []
const plans = new Map();      // userId -> []
const workouts = new Map();   // userId -> []
const usage = new Map();      // userId -> count

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const send = (res, status, body) => {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(body === undefined ? '' : JSON.stringify(body));
};
const readBody = (req) =>
  new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => (data += c));
    req.on('end', () => resolve(data ? JSON.parse(data) : {}));
  });

// ---------- Planbau (nur Fixture, keine Intelligenz) ----------
const TYPES = ['strength', 'run', 'hyrox_sim', 'mixed'];
const isoWeekday = (dateStr) => new Date(`${dateStr}T00:00:00Z`).getUTCDay() || 7;

function variant(location, type) {
  const gym = location === 'gym';
  const warmup = { name: 'Aufwärmen', type: 'warmup', format: 'circuit', rounds: 2, exercises: [
    { name: 'Lockeres Einlaufen oder Rudern', durationSec: 300, rpeTarget: 3 },
    { name: 'Mobilisation Hüfte/Schulter', durationSec: 180 },
  ]};
  let main;
  if (type === 'run') {
    main = { name: 'Intervalle', type: 'main', format: 'intervals', exercises: [
      { name: '1-km-Intervall', station: 'run', sets: 5, distanceM: 1000, targetPace: '5:15/km', restSec: 90, rpeTarget: 7 },
    ]};
  } else if (type === 'hyrox_sim') {
    main = { name: 'Hyrox-Simulation (verkürzt)', type: 'main', format: 'for_time', rounds: 1, exercises: gym ? [
      { name: 'Lauf', station: 'run', distanceM: 1000 },
      { name: 'SkiErg', station: 'skierg', distanceM: 1000 },
      { name: 'Lauf', station: 'run', distanceM: 1000 },
      { name: 'Sled Push', station: 'sled_push', distanceM: 50, loadNote: 'Wettkampfgewicht -20 %' },
    ] : [
      { name: 'Lauf', station: 'run', distanceM: 1000 },
      { name: 'Kettlebell Swings', reps: 40, loadKg: 24, equipment: ['kettlebell'] },
      { name: 'Lauf', station: 'run', distanceM: 1000 },
      { name: 'Burpee Broad Jumps', station: 'burpee_broad_jump', distanceM: 80 },
    ]};
  } else {
    main = { name: 'Kraft', type: 'main', format: 'straight_sets', exercises: gym ? [
      { name: 'Kniebeuge', sets: 4, reps: 6, loadKg: 70, restSec: 120, equipment: ['barbell'] },
      { name: 'Rumänisches Kreuzheben', sets: 3, reps: 8, loadKg: 60, restSec: 120 },
    ] : [
      { name: 'Goblet Squat', sets: 4, reps: 10, loadKg: 20, restSec: 90, equipment: ['kettlebell'] },
      { name: 'Ausfallschritte', sets: 3, reps: 12, loadKg: 12, restSec: 60 },
    ]};
  }
  const cooldown = { name: 'Cooldown', type: 'cooldown', exercises: [{ name: 'Dehnen', durationSec: 300 }] };
  return { location, equipment: gym ? ['barbell', 'sled', 'skierg'] : ['kettlebell'], blocks: [warmup, main, cooldown] };
}

function buildPlan(anamnese, startDate, weeks, kind) {
  const prefs = anamnese?.schedule?.days?.length
    ? anamnese.schedule.days
    : [1, 3, 5, 6].map((weekday) => ({ weekday, mode: 'ask', maxDurationMin: 60 }));
  const outWeeks = [];
  let trainingIdx = 0;
  for (let w = 0; w < weeks; w++) {
    const days = [];
    for (let d = 0; d < 7; d++) {
      const date = addDays(startDate, w * 7 + d);
      const pref = prefs.find((p) => p.weekday === isoWeekday(date));
      if (!pref) {
        days.push({ date, dayType: 'rest', title: 'Ruhetag', durationMin: 0, variants: [] });
        continue;
      }
      const type = TYPES[trainingIdx++ % TYPES.length];
      const locations = pref.mode === 'gym' ? ['gym'] : pref.mode === 'home' ? ['home'] : ['gym', 'home'];
      days.push({
        date, dayType: type,
        title: { strength: 'Kraft Unterkörper', run: 'Laufintervalle', hyrox_sim: 'Hyrox-Simulation', mixed: 'Mixed' }[type],
        intent: 'Mock-Plan (keine KI)',
        durationMin: Math.min(pref.maxDurationMin ?? 60, 60),
        variants: locations.map((l) => variant(l, type)),
      });
    }
    outWeeks.push({ weekNumber: w + 1, theme: `Woche ${w + 1} (Mock)`, days });
  }
  return {
    title: kind === 'adapted' ? 'Mock-Folgeplan' : 'Mock-Plan',
    summary: 'Beispielplan aus dem Mock-Server. Das echte Backend erzeugt den Plan per KI.',
    focus: { primary: anamnese?.focusChosen?.[0] ?? 'Allround', secondary: [], rationale: 'Mock' },
    startDate,
    weeks: outWeeks,
  };
}

function suggestions(a, latest) {
  const out = [];
  for (const [k, v] of Object.entries(a.selfAssessment?.ratings ?? {})) {
    if (v <= 2) out.push({ key: k, label: k, reason: `Selbsteinschätzung ${v} von 5`, weight: (3 - v) * 10 + 10 });
  }
  if (latest?.runsSec?.length >= 6) {
    const avg = (xs) => xs.reduce((s, x) => s + x, 0) / xs.length;
    const drift = avg(latest.runsSec.slice(-3)) / avg(latest.runsSec.slice(0, 3)) - 1;
    if (drift > 0.07) out.push({ key: 'pacing', label: 'Pacing und Laufen unter Ermüdung', reason: `Letzte drei Läufe ${(drift * 100).toFixed(0)} % langsamer`, weight: 25 });
  }
  if (!out.length) out.push({ key: 'allround', label: 'Allround-Vorbereitung', reason: 'Keine klare Schwäche erkennbar', weight: 5 });
  return out.sort((x, y) => y.weight - x.weight).slice(0, 4);
}

function progress(logs) {
  const byEx = new Map();
  for (const l of logs) for (const e of l.exercises ?? []) {
    if (e.skipped) continue;
    const arr = byEx.get(e.name) ?? [];
    arr.push({ date: l.date, topLoadKg: Math.max(0, ...(e.sets ?? []).map((s) => s.loadKg ?? 0)),
      totalReps: (e.sets ?? []).reduce((s, x) => s + (x.reps ?? 0), 0), totalDistanceM: (e.sets ?? []).reduce((s, x) => s + (x.distanceM ?? 0), 0) });
    byEx.set(e.name, arr);
  }
  return {
    totalSessions: logs.length,
    weekly: [],
    exercises: [...byEx].map(([name, points]) => ({ name, sessions: points.length, bestLoadKg: Math.max(...points.map((p) => p.topLoadKg)), points })),
  };
}

const envelope = (p) => ({ id: p.id, createdAt: p.createdAt, startDate: p.startDate, weeks: p.weeks, kind: p.kind, status: p.status, plan: p.plan });

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    const route = `${req.method} ${url.pathname}`;
    if (route === 'GET /health') return send(res, 200, { status: 'ok' });

    if (route === 'POST /admin/users') {
      if (req.headers['x-admin-key'] !== ADMIN_KEY) return send(res, 401, { error: 'Nicht erlaubt.' });
      const { name } = await readBody(req);
      const nm = (name ?? '').trim();
      if (nm.length < 2 || nm.length > 40) return send(res, 400, { error: 'Name muss 2 bis 40 Zeichen lang sein.' });
      if ([...users.values()].some((u) => u.nameKey === nm.toLowerCase())) return send(res, 409, { error: 'Dieser Name ist schon vergeben.' });
      const code = crypto.randomBytes(16).toString('hex');
      const user = { id: crypto.randomUUID().replaceAll('-', ''), name: nm, nameKey: nm.toLowerCase(), hash: sha(code) };
      users.set(user.id, user);
      return send(res, 200, { userId: user.id, name: user.name, code });
    }

    if (route === 'POST /auth/login') {
      const { name, code } = await readBody(req);
      const u = [...users.values()].find((x) => x.nameKey === (name ?? '').trim().toLowerCase());
      if (!u || u.hash !== sha(code ?? '')) return send(res, 401, { error: 'Name oder Code stimmt nicht.' });
      return send(res, 200, { userId: u.id, name: u.name, hasAnamnese: anamneses.has(u.id), hasPlan: (plans.get(u.id) ?? []).some((p) => p.status === 'active') });
    }

    if (url.pathname.startsWith('/api/')) {
      const auth = req.headers.authorization ?? '';
      const user = auth.startsWith('Bearer ') ? [...users.values()].find((u) => u.hash === sha(auth.slice(7).trim())) : null;
      if (!user) return send(res, 401, { error: 'Nicht angemeldet.' });
      const uid = user.id;

      switch (route) {
        case 'GET /api/anamnese':
          return anamneses.has(uid) ? send(res, 200, anamneses.get(uid)) : send(res, 404, { error: 'Noch keine Anamnese.' });
        case 'PUT /api/anamnese': {
          const a = { ...(await readBody(req)), userId: uid, updatedAt: new Date().toISOString() };
          anamneses.set(uid, a);
          return send(res, 200, a);
        }
        case 'GET /api/anamnese/suggestions': {
          if (!anamneses.has(uid)) return send(res, 400, { error: 'Bitte zuerst die Anamnese speichern.' });
          const latest = [...(results.get(uid) ?? [])].sort((a, b) => b.date.localeCompare(a.date))[0];
          return send(res, 200, suggestions(anamneses.get(uid), latest));
        }
        case 'GET /api/results':
          return send(res, 200, [...(results.get(uid) ?? [])].sort((a, b) => b.date.localeCompare(a.date)));
        case 'POST /api/results': {
          const r = await readBody(req);
          if (r.runsSec?.length !== 8 || r.stationsSec?.length !== 8) return send(res, 400, { error: 'Es werden genau 8 Lauf- und 8 Stationszeiten erwartet (in Sekunden).' });
          r.id = crypto.randomUUID().replaceAll('-', ''); r.userId = uid; r.source = 'manual';
          if (!(r.totalTimeSec > 0)) r.totalTimeSec = r.runsSec.reduce((s, x) => s + x, 0) + r.stationsSec.reduce((s, x) => s + x, 0) + (r.roxzoneSec ?? 0);
          results.set(uid, [...(results.get(uid) ?? []), r]);
          return send(res, 200, r);
        }
        case 'GET /api/plans/current': {
          const p = (plans.get(uid) ?? []).find((x) => x.status === 'active');
          return p ? send(res, 200, envelope(p)) : send(res, 404, { error: 'Noch kein Plan.' });
        }
        case 'POST /api/plans/generate':
        case 'POST /api/plans/adapt': {
          const body = await readBody(req);
          const kind = route.endsWith('adapt') ? 'adapted' : 'initial';
          if (!anamneses.has(uid)) return send(res, 400, { error: 'Bitte zuerst die Anamnese ausfüllen.' });
          if (!(body.weeks >= 2 && body.weeks <= 4)) return send(res, 400, { error: 'weeks muss zwischen 2 und 4 liegen.' });
          if (kind === 'adapted' && !(plans.get(uid) ?? []).some((p) => p.status === 'active')) return send(res, 400, { error: 'Es gibt noch keinen Plan, der angepasst werden könnte.' });
          const calls = (usage.get(uid) ?? 0) + 1;
          if (calls > 8) return send(res, 429, { error: 'Monatslimit für KI-Aufrufe erreicht (8).' });
          usage.set(uid, calls);
          for (const p of plans.get(uid) ?? []) p.status = 'archived';
          const doc = { id: crypto.randomUUID().replaceAll('-', ''), createdAt: new Date().toISOString(), startDate: body.startDate, weeks: body.weeks, kind, status: 'active', plan: buildPlan(anamneses.get(uid), body.startDate, body.weeks, kind) };
          plans.set(uid, [...(plans.get(uid) ?? []), doc]);
          return send(res, 200, envelope(doc));
        }
        case 'POST /api/workouts': {
          const w = await readBody(req);
          w.id = crypto.randomUUID().replaceAll('-', ''); w.userId = uid;
          workouts.set(uid, [...(workouts.get(uid) ?? []), w]);
          return send(res, 200, w);
        }
        case 'GET /api/workouts':
          return send(res, 200, [...(workouts.get(uid) ?? [])].sort((a, b) => b.date.localeCompare(a.date)));
        case 'GET /api/progress':
          return send(res, 200, progress(workouts.get(uid) ?? []));
        case 'GET /api/usage':
          return send(res, 200, { callsThisMonth: usage.get(uid) ?? 0, monthlyLimit: 8, dailyLimit: 4, inputTokens: 0, outputTokens: 0, model: 'mock' });
      }
      if (req.method === 'DELETE' && url.pathname.startsWith('/api/results/')) {
        const id = url.pathname.split('/').pop();
        results.set(uid, (results.get(uid) ?? []).filter((r) => r.id !== id));
        res.writeHead(204); return res.end();
      }
    }
    send(res, 404, { error: 'Nicht gefunden.' });
  } catch (err) {
    send(res, 500, { error: String(err?.message ?? err) });
  }
});

server.listen(PORT, () => console.log(`Mock-Server läuft auf http://localhost:${PORT} (ADMIN_KEY=${ADMIN_KEY})`));
