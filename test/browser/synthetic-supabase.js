// Test-only transport, resolved by the isolated browser-proof Vite config. This
// module is not imported by production entry points and cannot contact a backend.
const owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const older = { id: "11111111-1111-4111-8111-111111111111", owner_id: owner,
  name: "Canonical A", category: "Restaurant", categories: ["Restaurant", "Vendor"],
  created_at: "2020-01-01T00:00:00Z", updated_at: "2020-01-01T00:00:00Z",
  status: "pending", complete_pct: 60, heha_partner: false, gallery_urls: [],
  bio: "Synthetic older canonical business", tagline: "Original A headline" };
const newer = { ...older, id: "22222222-2222-4222-8222-222222222222",
  name: "Newer B", categories: ["Wellness"], created_at: "2026-01-01T00:00:00Z" };
const key = "heha-synthetic-rendered-proof";
const initial = () => ({ partners: [newer, older], profileRequests: [], mediaRequests: [], uploads: [], calls: [], failNextUpload: true });
let state = JSON.parse(sessionStorage.getItem(key) || "null") || initial();
const save = () => sessionStorage.setItem(key, JSON.stringify(state));
let profileReadPlans = [];
let profileInsertPlans = [];
let nextProfileRead = 0;
const pendingProfileReads = new Map();
const pendingProfileInserts = new Map();
window.__syntheticProof = {
  snapshot: () => ({ ...structuredClone(state), pendingProfileReads: [...pendingProfileReads.keys()], pendingProfileInserts: [...pendingProfileInserts.keys()] }),
  resetProfileProof() {
    if (pendingProfileReads.size || pendingProfileInserts.size) throw new Error("Settle pending synthetic operations before resetting");
    state = initial(); profileReadPlans = []; profileInsertPlans = []; save();
  },
  queueProfileRead(plan) { profileReadPlans.push(structuredClone(plan)); },
  queueProfileInsert(plan) { profileInsertPlans.push(structuredClone(plan)); },
  settleProfileInsert(id) {
    const settle = pendingProfileInserts.get(id);
    if (!settle) throw new Error("Unknown deferred synthetic insert");
    pendingProfileInserts.delete(id); settle();
  },
  settleProfileRead(id) {
    const settle = pendingProfileReads.get(id);
    if (!settle) throw new Error("Unknown deferred synthetic read");
    pendingProfileReads.delete(id); settle();
  },
  seedProfileRequest(partnerId = older.id) {
    state.profileRequests.push({ id: "existing-submitted", partner_id: partnerId, owner_id: owner,
      status: "submitted", submitted_at: "2026-09-20T12:00:00Z", proposed_changes: { name: "Earlier request" } });
    save();
  },
};
const record = (call) => { state.calls.push(call); save(); };
const project = (row, projection) => !row ? null : Object.fromEntries(
  projection.split(",").map((column) => column.trim()).map((column) => [column, row[column] ?? null])
);

function query(table) {
  const call = { table, method: "select", filters: [], projection: "*" };
  let payload;
  let single = false;
  let maximum = Infinity;
  const builder = {
    select(projection) { call.projection = projection; return this; },
    eq(column, value) { call.filters.push([column, value]); return this; },
    order(column, options) { call.order = [column, options]; return this; },
    limit(count) { maximum = count; return this; },
    insert(value) { call.method = "insert"; payload = structuredClone(value); return this; },
    maybeSingle() { single = true; return this; },
    single() { single = true; return this; },
    then(resolve, reject) {
      return Promise.resolve().then(() => {
        record({ ...call, payload });
        if (call.method === "insert") {
          if (!["partner_profile_change_requests", "partner_media_requests"].includes(table)) throw new Error(`Unexpected write: ${table}`);
          if (payload.owner_id !== owner || !state.partners.some((row) => row.id === payload.partner_id && row.owner_id === owner)) throw new Error("Wrong synthetic owner");
          const row = { ...payload, id: `synthetic-${state.calls.length}`, status: "submitted", submitted_at: "2026-09-17T12:00:00Z" };
          const commit = () => {
            (table === "partner_profile_change_requests" ? state.profileRequests : state.mediaRequests).push(row);
            save();
            return { data: single ? project(row, call.projection) : null, error: null };
          };
          const plan = table === "partner_profile_change_requests" ? profileInsertPlans.shift() : null;
          if (plan?.defer) return new Promise(resolveInsert => pendingProfileInserts.set(row.id, () => resolveInsert(commit())));
          return commit();
        }
        const rows = table === "partners" ? state.partners
          : table === "partner_profile_change_requests" ? state.profileRequests
          : table === "partner_media_requests" ? state.mediaRequests
          : table === "in_app_messages" ? [] : null;
        if (!rows) throw new Error(`Unexpected read: ${table}`);
        let found = rows.filter((row) => call.filters.every(([column, value]) => row[column] === value));
        if (call.order) {
          const [column, options] = call.order;
          found = [...found].sort((a, b) => String(a[column]).localeCompare(String(b[column])) * (options?.ascending === false ? -1 : 1));
        }
        found = found.slice(0, maximum);
        if (single && found.length > 1) throw new Error("Ambiguous synthetic single-row selection");
        const result = { data: single ? project(found[0], call.projection) : found.map((row) => project(row, call.projection)), error: null };
        if (table === "partner_profile_change_requests" && profileReadPlans.length) {
          const plan = profileReadPlans.shift();
          const complete = () => {
            if (plan.reject) throw new Error("Synthetic pending-request connection failure");
            return plan.fail ? { data: null, error: { message: "Synthetic pending-request lookup failed" } } : result;
          };
          if (plan.defer) return new Promise((resolveRead, rejectRead) => {
            pendingProfileReads.set(++nextProfileRead, () => {
              try { resolveRead(complete()); } catch (error) { rejectRead(error); }
            });
          });
          return complete();
        }
        return result;
      }).then(resolve, reject);
    },
  };
  return builder;
}

export const supabase = {
  from: query,
  async rpc(name, args) {
    record({ rpc: name, args });
    if (name !== "get_my_partner_publication_status") throw new Error(`Unexpected RPC: ${name}`);
    return { data: { prepare_destinations: [], publication_destinations: [] }, error: null };
  },
  storage: { from(bucket) {
    if (bucket !== "partner-media-pending") throw new Error("Unexpected bucket");
    return {
      async upload(path, file, options) {
        record({ storage: "upload", bucket, path, size: file.size, type: file.type, options });
        if (state.failNextUpload) {
          state.failNextUpload = false;
          save();
          return { error: { message: "Synthetic upload failed; retry is safe." } };
        }
        state.uploads.push({ path, size: file.size, type: file.type });
        save();
        return { data: { path }, error: null };
      },
      async createSignedUrl(path) {
        record({ storage: "signed-url", path });
        // No image/network source is fabricated for a signed URL in this proof.
        return { data: null, error: { message: "Synthetic preview not provided" } };
      },
      async remove(paths) { record({ storage: "remove", paths }); return { data: [], error: null }; },
    };
  } },
};
