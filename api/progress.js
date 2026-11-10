import { neon } from "@neondatabase/serverless";
import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

const COOKIE_NAME = "thesis_roadmap_session";
const SESSION_SECONDS = 60 * 60 * 24 * 30;
const VALID_IDS = new Set([
  "s0a", "s0b", "s0e", "r1", "r2", "r3", "r5", "r4", "c1", "s1e",
  "r6", "s2a", "r7", "r8", "c2", "s2e", "r9", "r10", "r21", "r12",
  "c3", "c4", "r11", "r13", "r14", "r15", "r16", "r17", "r18", "r19",
  "r20", "c5", "c7", "s4e", "s5a", "s5b", "r22", "r23", "r24", "r25",
  "r26", "r27", "s5e", "s6a", "r33", "s6b", "r28", "r29", "r30", "r31",
  "c6", "c8", "s6e", "g0", "g1", "g2", "g3", "g4", "g5", "g6",
]);

function json(data, status = 200, extraHeaders = {}) {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store, max-age=0",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    ...extraHeaders,
  });
  return new Response(JSON.stringify(data), { status, headers });
}

function fail(status, message) {
  return json({ error: message }, status);
}

function constantTimeTextEqual(left, right) {
  const leftHash = createHash("sha256").update(String(left)).digest();
  const rightHash = createHash("sha256").update(String(right)).digest();
  return timingSafeEqual(leftHash, rightHash);
}

function sign(value) {
  return createHmac("sha256", process.env.SESSION_SECRET).update(value).digest("base64url");
}

function makeSession() {
  const payload = `${Math.floor(Date.now() / 1000) + SESSION_SECONDS}.${randomBytes(18).toString("base64url")}`;
  return `${payload}.${sign(payload)}`;
}

function cookieValue(request) {
  const raw = request.headers.get("cookie") || "";
  const entry = raw.split(";").map((part) => part.trim()).find((part) => part.startsWith(`${COOKIE_NAME}=`));
  if (!entry) return "";
  try { return decodeURIComponent(entry.slice(COOKIE_NAME.length + 1)); }
  catch { return ""; }
}

function isAuthenticated(request) {
  const token = cookieValue(request);
  const parts = token.split(".");
  if (parts.length !== 3 || !process.env.SESSION_SECRET) return false;
  const [expires, nonce, signature] = parts;
  if (!/^\d+$/.test(expires) || Number(expires) <= Math.floor(Date.now() / 1000) || !nonce || !signature) return false;
  const expected = Buffer.from(sign(`${expires}.${nonce}`));
  const actual = Buffer.from(signature);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

function sessionCookie(token, maxAge, request) {
  const secure = new URL(request.url).protocol === "https:";
  return `${COOKIE_NAME}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure ? "; Secure" : ""}`;
}

function sameOrigin(request) {
  const origin = request.headers.get("origin");
  if (!origin) return false;
  try { return new URL(origin).origin === new URL(request.url).origin; }
  catch { return false; }
}

function database() {
  if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL is missing");
  return neon(process.env.DATABASE_URL);
}

async function ensureTable(sql) {
  await sql`CREATE TABLE IF NOT EXISTS thesis_roadmap_progress (
    id SMALLINT PRIMARY KEY CHECK (id = 1),
    items JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )`;
}

async function readProgress(sql) {
  const rows = await sql`SELECT items, updated_at FROM thesis_roadmap_progress WHERE id = 1`;
  return { items: rows[0]?.items || {}, updatedAt: rows[0]?.updated_at || null };
}

function cleanChanges(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Progress changes must be an object");
  const keys = Object.keys(input);
  if (keys.length > VALID_IDS.size) throw new Error("Too many progress items");
  const now = new Date().toISOString();
  const safe = {};
  for (const id of keys) {
    const entry = input[id];
    if (!VALID_IDS.has(id) || !entry || typeof entry !== "object" || Array.isArray(entry)) throw new Error("Unknown roadmap item");
    if (!["todo", "doing", "done"].includes(entry.status)) throw new Error("Invalid status");
    if (typeof entry.note !== "string" || entry.note.length > 2000) throw new Error("A note is too long");
    safe[id] = { status: entry.status, note: entry.note, updatedAt: now };
  }
  return safe;
}

export async function GET(request) {
  if (!isAuthenticated(request)) return fail(401, "Please sign in again.");
  try {
    const sql = database();
    await ensureTable(sql);
    return json(await readProgress(sql));
  } catch (error) {
    console.error("Progress read failed:", error);
    return fail(503, "The database is unavailable. Check DATABASE_URL in your Vercel project settings.");
  }
}

export async function POST(request) {
  if (!sameOrigin(request)) return fail(403, "This request was not accepted.");

  let body;
  try { body = await request.json(); }
  catch { return fail(400, "Invalid request body."); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return fail(400, "Invalid request body.");

  if (body.action === "login") {
    if (!process.env.APP_PASSWORD || process.env.APP_PASSWORD.length < 12 || !process.env.SESSION_SECRET || process.env.SESSION_SECRET.length < 32) {
      return fail(503, "Set APP_PASSWORD to at least 12 characters and SESSION_SECRET to at least 32 characters in Vercel.");
    }
    const password = typeof body.password === "string" ? body.password.slice(0, 512) : "";
    if (!constantTimeTextEqual(password, process.env.APP_PASSWORD)) return fail(401, "That password did not match.");
    try {
      const sql = database();
      await ensureTable(sql);
      const progress = await readProgress(sql);
      return json(progress, 200, { "Set-Cookie": sessionCookie(makeSession(), SESSION_SECONDS, request) });
    } catch (error) {
      console.error("Sign-in database check failed:", error);
      return fail(503, "The database is unavailable. Connect Neon Postgres and set DATABASE_URL.");
    }
  }

  if (body.action === "logout") {
    return json({ ok: true }, 200, { "Set-Cookie": sessionCookie("", 0, request) });
  }

  if (body.action === "save") {
    if (!isAuthenticated(request)) return fail(401, "Your session expired. Please sign in again.");
    let changes;
    try { changes = cleanChanges(body.items); }
    catch (error) { return fail(400, error.message); }
    if (Object.keys(changes).length === 0) return json({ ok: true });
    try {
      const sql = database();
      await ensureTable(sql);
      const rows = await sql`
        INSERT INTO thesis_roadmap_progress (id, items)
        VALUES (1, ${JSON.stringify(changes)}::jsonb)
        ON CONFLICT (id) DO UPDATE SET
          items = thesis_roadmap_progress.items || COALESCE((
            SELECT jsonb_object_agg(incoming.key, incoming.value)
            FROM jsonb_each(EXCLUDED.items) AS incoming(key, value)
            WHERE COALESCE(thesis_roadmap_progress.items -> incoming.key ->> 'updatedAt', '')
              <= COALESCE(incoming.value ->> 'updatedAt', '')
          ), '{}'::jsonb),
          updated_at = NOW()
        RETURNING items, updated_at
      `;
      return json({ ok: true, items: rows[0]?.items || {}, updatedAt: rows[0]?.updated_at || null });
    } catch (error) {
      console.error("Progress save failed:", error);
      return fail(503, "Cloud save failed. Your browser backup is safe; retrying shortly.");
    }
  }

  return fail(400, "Unknown action.");
}

export async function OPTIONS() {
  return new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });
}
