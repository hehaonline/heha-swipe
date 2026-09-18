// Real overlapping psql sessions against the disposable CI Supabase only.
import assert from "node:assert/strict";
import { createDisposableMediaPsql } from "./disposable_media_target.mjs";

const database = createDisposableMediaPsql(process.env.DATABASE_URL);
const sql = (input) => database.sql(input).trim();
const owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const staff = "12121212-1212-4212-8212-121212121212";
const partner = "78787878-7878-4787-8787-787878787878";
const snapshot = sql(`SELECT to_jsonb(p) FROM public.partners p WHERE id='${partner}';`);
const auth = (actor) => `SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claims','{"sub":"${actor}","role":"authenticated"}',true),set_config('request.jwt.claim.sub','${actor}',true);`;
const pause = () => new Promise((resolve) => setTimeout(resolve, 100));
const sessions = new Set();

function session(name, isolation = "READ COMMITTED") {
  const child = database.session();
  sessions.add(child);
  let output = "";
  child.stdout.on("data", (data) => { output += data; });
  child.stderr.on("data", (data) => { output += data; });
  const done = new Promise((resolve) => child.on("close", (code) => { sessions.delete(child); resolve({ code, output }); }));
  child.stdin.write(`SET application_name='${name}'; BEGIN ISOLATION LEVEL ${isolation}; SET LOCAL statement_timeout='15s';\n`);
  return { child, done, write: (value) => child.stdin.write(value + "\n") };
}
async function waitState(name, predicate) {
  for (let tries = 0; tries < 100; tries += 1) {
    if (sql(`SELECT count(*) FROM pg_stat_activity WHERE application_name='${name}' AND ${predicate};`) === "1") return;
    await pause();
  }
  throw new Error(`No observed ${predicate} for ${name}`);
}

function request(actor, kind, path) {
  if (actor === staff) return `SELECT public.submit_assisted_partner_media(gen_random_uuid(),'${partner}','${path}','${kind}','media-boundary-race.jpg','image/jpeg',64,'synthetic:race-source','synthetic:race-rights');`;
  return `INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path,original_filename) VALUES('${partner}','${owner}','${kind}','${path}','media-boundary-race.jpg');`;
}
function clear() {
  sql(`DELETE FROM public.partner_media_requests WHERE partner_id='${partner}' AND original_filename='media-boundary-race.jpg';`);
}

async function race(label, kind, firstActor, secondActor, { samePath = false, repeatable = false } = {}) {
  clear();
  const firstPath = `${firstActor}/${partner}/media-boundary-race-${label}-first.jpg`;
  const secondPath = samePath ? firstPath : `${secondActor}/${partner}/media-boundary-race-${label}-second.jpg`;
  if (kind === "gallery" && !samePath) {
    sql(`INSERT INTO public.partner_media_requests(partner_id,owner_id,media_type,storage_path,original_filename)
      SELECT '${partner}','${owner}','gallery','${owner}/${partner}/media-boundary-race-${label}-seed-'||n||'.jpg','media-boundary-race.jpg' FROM generate_series(1,5) n;`);
  }
  // Prepare only synthetic private objects for actual assisted RPC validation.
  for (const [actor, path] of [[firstActor, firstPath], [secondActor, secondPath]]) {
    if (actor === staff) sql(`INSERT INTO storage.objects(bucket_id,name) VALUES('partner-media-pending','${path}') ON CONFLICT DO NOTHING;`);
  }
  const firstName = `media_boundary_${label}_winner`;
  const secondName = `media_boundary_${label}_waiter`;
  const second = repeatable ? session(secondName, "REPEATABLE READ") : null;
  if (second) {
    second.write(`SELECT count(*) FROM public.partner_media_requests WHERE partner_id='${partner}'; SELECT 'media_snapshot_ready';`);
    await waitState(secondName, "state='idle in transaction' AND query LIKE '%media_snapshot_ready%'");
  }
  const first = session(firstName);
  first.write(auth(firstActor) + request(firstActor, kind, firstPath) + "SELECT 'media_winner_ready';");
  await waitState(firstName, "state='idle in transaction' AND query LIKE '%media_winner_ready%'");
  const waiter = second || session(secondName);
  waiter.write(auth(secondActor) + request(secondActor, kind, secondPath) + "COMMIT;");
  waiter.child.stdin.end();
  // Proves overlap on the real database lock, not Promise ordering or a sleep.
  await waitState(secondName, "wait_event_type='Lock'");
  first.write("COMMIT;"); first.child.stdin.end();
  const winner = await first.done;
  assert.equal(winner.code, 0, winner.output);
  const loser = await waiter.done;
  assert.notEqual(loser.code, 0, "both writes unexpectedly committed");
  assert.match(loser.output, repeatable ? /40001/ : kind === "gallery" && !samePath ? /23514/ : /23505/);
  assert.doesNotMatch(loser.output, /40P01|deadlock detected/);
  const expected = kind === "gallery" && !samePath ? "6" : "1";
  assert.equal(sql(`SELECT count(*) FROM public.partner_media_requests WHERE partner_id='${partner}' AND original_filename='media-boundary-race.jpg' AND media_type='${kind}' AND status IN('submitted','needs_info','approved');`), expected);
  assert.equal(sql(`SELECT to_jsonb(p) FROM public.partners p WHERE id='${partner}';`), snapshot);
  assert.equal(sql(`SELECT count(*) FROM public.partner_media_intake_evidence e JOIN public.partner_media_requests r ON r.id=e.request_id WHERE r.storage_path='${secondPath}' AND r.owner_id='${secondActor}';`), "0");
  if (firstActor === staff) assert.equal(sql(`SELECT count(*) FROM public.partner_media_intake_evidence e JOIN public.partner_media_requests r ON r.id=e.request_id WHERE r.storage_path='${firstPath}' AND e.source_reference='synthetic:race-source' AND e.rights_reference='synthetic:race-rights';`), "1");
  console.log(`${label}: PASS (observed lock overlap; one winner; ${repeatable ? "40001 retry" : "constraint rejection"}; partner unchanged)`);
}

try {
  await race("owner_owner_path", "gallery", owner, owner, { samePath: true });
  for (const kind of ["logo", "cover", "gallery"]) {
    await race(`owner_owner_${kind}`, kind, owner, owner);
    await race(`owner_staff_${kind}`, kind, owner, staff);
    await race(`staff_owner_${kind}`, kind, staff, owner);
  }
  await race("repeatable_read_gallery", "gallery", owner, owner, { repeatable: true });
  console.log("11 genuine two-session media races passed; synthetic private storage objects remain disposable only.");
} finally {
  for (const child of sessions) child.kill("SIGTERM");
  clear();
}
