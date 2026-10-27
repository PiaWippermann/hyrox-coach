// Spiegelbild von backend/HyroxCoach.Api/Services/PlanValidator.cs.
// Wird im Smoke-Test genutzt, damit Mock und echtes Backend dieselben Regeln erfüllen müssen.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import Ajv from 'ajv';

const here = path.dirname(fileURLToPath(import.meta.url));
export const schemaPath = path.join(here, '..', '..', 'contracts', 'plan.schema.json');

const ajv = new Ajv({ allErrors: true });
const validateSchema = ajv.compile(JSON.parse(readFileSync(schemaPath, 'utf8')));

export function addDays(dateStr, n) {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Gibt eine Liste von Fehlern zurück (leer = gültig). */
export function checkPlan(plan, startDate, weeks) {
  const errors = [];

  if (!validateSchema(plan)) {
    for (const e of validateSchema.errors.slice(0, 8)) errors.push(`Schema: ${e.instancePath} ${e.message}`);
    return errors;
  }

  if (plan.startDate !== startDate) errors.push(`startDate im Plan muss ${startDate} sein.`);
  if (plan.weeks.length !== weeks) errors.push(`Es müssen genau ${weeks} Wochen sein, geliefert: ${plan.weeks.length}.`);

  let dayIndex = 0;
  plan.weeks.forEach((week, wi) => {
    if (week.days.length !== 7) {
      errors.push(`Woche ${wi + 1} muss genau 7 Tage haben.`);
      dayIndex += 7;
      return;
    }
    for (const day of week.days) {
      const expected = addDays(startDate, dayIndex++);
      if (day.date !== expected) errors.push(`Tag ${dayIndex}: Datum muss ${expected} sein (war ${day.date}).`);
      if (day.dayType === 'rest') continue;
      if (!day.variants || day.variants.length === 0) {
        errors.push(`Tag ${expected}: Trainingstag ohne Variante.`);
        continue;
      }
      for (const v of day.variants) {
        if (!['gym', 'home'].includes(v.location)) errors.push(`Tag ${expected}: ungültiger Ort ${v.location}.`);
        if (!v.blocks || v.blocks.length === 0) errors.push(`Tag ${expected}: Variante ${v.location} ohne Blöcke.`);
      }
    }
  });

  return errors;
}
