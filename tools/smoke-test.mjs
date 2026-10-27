// End-to-End-Test des API-Vertrags. Läuft gegen den Mock-Server ODER das echte Backend.
//   Mock:    BASE_URL=http://localhost:8080 ADMIN_KEY=dev-admin node smoke-test.mjs
//   Backend: BASE_URL=http://localhost:8080 ADMIN_KEY=<aus .env> node smoke-test.mjs
// ACHTUNG beim echten Backend: der Test löst 2 KI-Aufrufe aus (Plan + Folgeplan), das kostet ein paar Cent.
// Mit SKIP_AI=1 werden die KI-Schritte übersprungen.
import { checkPlan, addDays } from './lib/plan-checks.mjs';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';
const ADMIN_KEY = process.env.ADMIN_KEY ?? 'dev-admin';
const SKIP_AI = process.env.SKIP_AI === '1';

let failures = 0;
const ok = (cond, msg) => {
  console.log(`${cond ? 'OK  ' : 'FAIL'} ${msg}`);
  if (!cond) failures++;
};

async function call(method, path, { body, token, admin } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (admin) headers['X-Admin-Key'] = ADMIN_KEY;
  const res = await fetch(BASE + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* leer */ }
  return { status: res.status, json };
}

const today = new Date().toISOString().slice(0, 10);
const start = addDays(today, 1);
const name = `smoke-${Date.now() % 100000}`;

const health = await call('GET', '/health');
ok(health.status === 200, 'GET /health');

const noAuth = await call('GET', '/api/anamnese');
ok(noAuth.status === 401, 'API ohne Token wird abgelehnt (401)');

const created = await call('POST', '/admin/users', { body: { name }, admin: true });
ok(created.status === 200 && created.json?.code, 'Admin legt Nutzer an und erhält Einladungscode');
const code = created.json?.code;

const dup = await call('POST', '/admin/users', { body: { name }, admin: true });
ok(dup.status === 409, 'Doppelter Name wird abgelehnt (409)');

const badAdmin = await call('POST', '/admin/users', { body: { name: 'x-y' } });
ok(badAdmin.status === 401, 'Anlegen ohne Admin-Key wird abgelehnt (401)');

const badLogin = await call('POST', '/auth/login', { body: { name, code: 'falsch' } });
ok(badLogin.status === 401, 'Login mit falschem Code scheitert (401)');

const login = await call('POST', '/auth/login', { body: { name, code } });
ok(login.status === 200 && login.json?.hasAnamnese === false, 'Login klappt, noch keine Anamnese');

const anamnese = {
  profile: { age: 34, heightCm: 175, weightKg: 68 },
  goal: { raceDate: addDays(today, 90), category: 'single', division: 'Open', priority: 'improve', targetTime: '1:25:00' },
  selfAssessment: {
    runWeeklyKm: 25, strengthExperience: 'some', runnerType: 'strong_runner',
    ratings: { running: 4, strength: 2, skierg: 2, sled_push: 1, wall_balls: 3 },
    limiter: 'Nach Sled Pull brennen die Arme',
  },
  schedule: { daysPerWeek: 4, days: [
    { weekday: 1, mode: 'ask', maxDurationMin: 60 },
    { weekday: 3, mode: 'gym', maxDurationMin: 75 },
    { weekday: 5, mode: 'home', maxDurationMin: 45 },
    { weekday: 6, mode: 'ask', maxDurationMin: 90 },
  ] },
  equipment: { home: ['kettlebell', 'pullup_bar'], gym: ['barbell', 'sled', 'skierg', 'rower'] },
  restrictions: '',
  focusChosen: [],
  focusConfirmed: false,
};
const put = await call('PUT', '/api/anamnese', { body: anamnese, token: code });
ok(put.status === 200, 'PUT /api/anamnese');

const result = await call('POST', '/api/results', { token: code, body: {
  eventName: 'Testlauf', date: addDays(today, -60), category: 'Open',
  totalTimeSec: 0, roxzoneSec: 240,
  runsSec: [290, 295, 300, 310, 330, 345, 360, 375],
  stationsSec: [270, 190, 230, 300, 280, 140, 260, 300],
} });
ok(result.status === 200 && result.json?.totalTimeSec > 0, 'POST /api/results (Gesamtzeit wird berechnet)');

const badResult = await call('POST', '/api/results', { token: code, body: { date: today, runsSec: [1], stationsSec: [] } });
ok(badResult.status === 400, 'Ergebnis mit falscher Anzahl Splits wird abgelehnt (400)');

const sugg = await call('GET', '/api/anamnese/suggestions', { token: code });
ok(sugg.status === 200 && Array.isArray(sugg.json) && sugg.json.length > 0, 'Fokus-Vorschläge ohne KI');
console.log('     Vorschläge:', sugg.json?.map((s) => s.label).join(' | '));
ok(sugg.json?.some((s) => s.key === 'pacing'), 'Pacing-Einbruch aus den Splits erkannt');

if (SKIP_AI) {
  console.log('SKIP_AI=1: KI-Schritte übersprungen');
} else {
  const gen = await call('POST', '/api/plans/generate', { token: code, body: { startDate: start, weeks: 2 } });
  ok(gen.status === 200, `POST /api/plans/generate (Status ${gen.status}${gen.json?.error ? ': ' + gen.json.error : ''})`);
  if (gen.status === 200) {
    const errs = checkPlan(gen.json.plan, start, 2);
    ok(errs.length === 0, `Plan erfüllt Schema und Strukturregeln ${errs.length ? '→ ' + errs.join(' ') : ''}`);

    // Home/Gym-Logik: Tage laut Zeitplan haben genau die erwarteten Varianten
    const mondays = gen.json.plan.weeks[0].days.filter((d) => new Date(`${d.date}T00:00:00Z`).getUTCDay() === 1);
    ok(mondays.every((d) => d.variants.length === 2), 'Tag mit mode "ask" hat Gym- UND Home-Variante');
    const wed = gen.json.plan.weeks[0].days.find((d) => new Date(`${d.date}T00:00:00Z`).getUTCDay() === 3);
    ok(wed && wed.variants.length === 1 && wed.variants[0].location === 'gym', 'Tag mit mode "gym" hat nur Gym-Variante');
  }

  const cur = await call('GET', '/api/plans/current', { token: code });
  ok(cur.status === 200 && cur.json?.plan, 'GET /api/plans/current');

  // Training protokollieren
  const firstTraining = cur.json?.plan?.weeks?.[0]?.days?.find((d) => d.variants?.length);
  if (firstTraining) {
    const v = firstTraining.variants[0];
    const exs = v.blocks.flatMap((b) => b.exercises).slice(0, 3).map((e) => ({
      name: e.name, station: e.station, skipped: false,
      sets: [{ reps: e.reps ?? 8, loadKg: e.loadKg ?? 20, distanceM: e.distanceM, durationSec: e.durationSec }],
    }));
    const wo = await call('POST', '/api/workouts', { token: code, body: {
      date: firstTraining.date, dayTitle: firstTraining.title, planId: cur.json.id, location: v.location, rpe: 7, durationMin: 50, exercises: exs,
    } });
    ok(wo.status === 200, 'POST /api/workouts');
    const prog = await call('GET', '/api/progress', { token: code });
    ok(prog.status === 200 && prog.json?.totalSessions === 1, 'GET /api/progress zählt die Einheit');
  }

  const adapt = await call('POST', '/api/plans/adapt', { token: code, body: { startDate: addDays(start, 14), weeks: 2, notes: 'Sled war zu schwer' } });
  ok(adapt.status === 200, `POST /api/plans/adapt (Status ${adapt.status}${adapt.json?.error ? ': ' + adapt.json.error : ''})`);
  if (adapt.status === 200) {
    const errs = checkPlan(adapt.json.plan, addDays(start, 14), 2);
    ok(errs.length === 0, `Folgeplan erfüllt Schema und Strukturregeln ${errs.length ? '→ ' + errs.join(' ') : ''}`);
    ok(adapt.json.kind === 'adapted', 'Folgeplan ist als "adapted" markiert');
  }

  const usage = await call('GET', '/api/usage', { token: code });
  ok(usage.status === 200, 'GET /api/usage');
  console.log('     Nutzung:', JSON.stringify(usage.json));
}

console.log(failures === 0 ? '\nAlles bestanden.' : `\n${failures} Test(s) fehlgeschlagen.`);
process.exit(failures === 0 ? 0 : 1);
