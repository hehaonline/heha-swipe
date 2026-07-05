import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';

const HUBSPOT_BASE_URL = 'https://api.hubapi.com';
const COMPANY_TO_CONTACT = 280;
const NOTE_TO_COMPANY = 190;
const NOTE_TO_CONTACT = 202;

type QueueRow = {
  id: string;
  partner_id: string;
  hubspot_contact_id: string | null;
  hubspot_company_id: string | null;
  hubspot_contact_ids: Record<string, string> | null;
  hubspot_note_id: string | null;
  lifecycle_stage: string | null;
  lead_category: string | null;
  last_note_fingerprint: string | null;
  last_payload_hash: string | null;
  sync_status: string;
};

type PartnerRow = {
  id: string;
  name: string | null;
  category: string | null;
  location: string | null;
  contact: string | null;
  instagram: string | null;
  website: string | null;
  bio: string | null;
  phone: string | null;
  business_type: string | null;
  partner_type: string | null;
  neighborhood: string | null;
  tagline: string | null;
  hours: string | null;
};

type ScoutLeadRow = {
  id: string;
  business_name: string | null;
  lead_type: string | null;
  heha_pillar: string | null;
  business_category: string | null;
  neighborhood: string | null;
  tagline: string | null;
  bio: string | null;
  hours: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  postal_code: string | null;
  phone: string | null;
  email: string | null;
  website: string | null;
  instagram: string | null;
  google_maps_url: string | null;
  primary_contact_name: string | null;
  primary_contact_role: string | null;
  visit_notes: string | null;
  first_impression: string | null;
  heha_fit_notes: string | null;
  fit_score: number | null;
  products_services: string | null;
  offerings_text: string | null;
  featured_items_text: string | null;
  potential_offer: string | null;
};

type ScoutContactRow = {
  id: string;
  contact_name: string | null;
  contact_role: string | null;
  phone: string | null;
  email: string | null;
  instagram: string | null;
  linkedin: string | null;
  is_primary: boolean;
  contact_status: string | null;
  notes: string | null;
};

type ContactCandidate = {
  key: string;
  name: string | null;
  role: string | null;
  phone: string | null;
  email: string | null;
  instagram: string | null;
  linkedin: string | null;
  notes: string | null;
};

class HubSpotApiError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'HubSpotApiError';
    this.status = status;
  }
}

function getSupabaseServiceKey(): string {
  const legacyServiceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacyServiceRole) return legacyServiceRole;

  const secretKeysJson = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (secretKeysJson) {
    const parsed = JSON.parse(secretKeysJson);
    if (parsed.default) return parsed.default;
  }

  throw new Error('Missing Supabase service/secret key for Edge Function admin operations.');
}

function compactProperties(values: Record<string, string | number | null | undefined>): Record<string, string> {
  return Object.entries(values).reduce<Record<string, string>>((next, [key, value]) => {
    if (value === null || value === undefined) return next;
    const stringValue = String(value).trim();
    if (stringValue) next[key] = stringValue;
    return next;
  }, {});
}

function normalizeWebsite(value: string | null | undefined): { website: string | null; domain: string | null } {
  const raw = value?.trim();
  if (!raw) return { website: null, domain: null };

  try {
    const url = new URL(/^https?:\/\//i.test(raw) ? raw : `https://${raw}`);
    return {
      website: url.toString(),
      domain: url.hostname.replace(/^www\./i, '').toLowerCase(),
    };
  } catch {
    return { website: raw, domain: null };
  }
}

function splitName(value: string | null): { firstname?: string; lastname?: string } {
  const parts = value?.trim().split(/\s+/).filter(Boolean) ?? [];
  if (!parts.length) return {};
  if (parts.length === 1) return { firstname: parts[0] };
  return { firstname: parts.slice(0, -1).join(' '), lastname: parts.at(-1) };
}

function mapFitScore(score: number | null): string | null {
  if (!score) return null;
  if (score >= 4) return 'High';
  if (score === 3) return 'Medium';
  return 'Low';
}

function htmlEscape(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

async function sha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function hubspotRequest<T>(accessToken: string, path: string, init: RequestInit = {}): Promise<T> {
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= 4; attempt += 1) {
    const response = await fetch(`${HUBSPOT_BASE_URL}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        ...(init.headers ?? {}),
      },
    });

    if (response.ok) {
      if (response.status === 204) return undefined as T;
      return await response.json() as T;
    }

    const errorText = (await response.text()).slice(0, 1500);
    lastError = new HubSpotApiError(response.status, `HubSpot ${response.status}: ${errorText}`);

    if (response.status === 429 || response.status >= 500) {
      const retryAfter = Number(response.headers.get('retry-after') ?? 0);
      const delay = retryAfter > 0 ? Math.min(retryAfter * 1000, 10_000) : Math.min(500 * 2 ** (attempt - 1), 5_000);
      await sleep(delay);
      continue;
    }

    throw lastError;
  }

  throw lastError ?? new Error('HubSpot request failed after retries.');
}

async function searchHubSpotObject(
  accessToken: string,
  objectType: 'companies' | 'contacts',
  propertyName: string,
  value: string,
): Promise<string | null> {
  const result = await hubspotRequest<{ results?: Array<{ id: string }> }>(
    accessToken,
    `/crm/v3/objects/${objectType}/search`,
    {
      method: 'POST',
      body: JSON.stringify({
        filterGroups: [{ filters: [{ propertyName, operator: 'EQ', value }] }],
        properties: ['hs_object_id'],
        limit: 1,
      }),
    },
  );

  return result.results?.[0]?.id ?? null;
}

async function createHubSpotObject(
  accessToken: string,
  objectType: 'companies' | 'contacts',
  properties: Record<string, string>,
): Promise<string> {
  const result = await hubspotRequest<{ id: string }>(accessToken, `/crm/v3/objects/${objectType}`, {
    method: 'POST',
    body: JSON.stringify({ properties }),
  });
  return result.id;
}

async function updateHubSpotObject(
  accessToken: string,
  objectType: 'companies' | 'contacts',
  objectId: string,
  properties: Record<string, string>,
): Promise<void> {
  await hubspotRequest(accessToken, `/crm/v3/objects/${objectType}/${objectId}`, {
    method: 'PATCH',
    body: JSON.stringify({ properties }),
  });
}

async function upsertCompany(
  accessToken: string,
  existingId: string | null,
  properties: Record<string, string>,
): Promise<string> {
  let companyId = existingId;

  if (companyId) {
    try {
      await updateHubSpotObject(accessToken, 'companies', companyId, properties);
      return companyId;
    } catch (error) {
      if (!(error instanceof HubSpotApiError) || error.status !== 404) throw error;
      companyId = null;
    }
  }

  if (properties.domain) companyId = await searchHubSpotObject(accessToken, 'companies', 'domain', properties.domain);
  if (!companyId && properties.name) companyId = await searchHubSpotObject(accessToken, 'companies', 'name', properties.name);

  if (companyId) {
    await updateHubSpotObject(accessToken, 'companies', companyId, properties);
    return companyId;
  }

  return await createHubSpotObject(accessToken, 'companies', properties);
}

async function bestEffortCompanyProperty(
  accessToken: string,
  companyId: string,
  propertyName: string,
  value: string | null,
): Promise<void> {
  if (!value) return;
  try {
    await updateHubSpotObject(accessToken, 'companies', companyId, { [propertyName]: value });
  } catch (error) {
    console.warn(`Optional HubSpot company property ${propertyName} was skipped`, error instanceof Error ? error.message : error);
  }
}

async function upsertContact(
  accessToken: string,
  existingId: string | null,
  candidate: ContactCandidate,
  companyName: string,
): Promise<string> {
  const name = splitName(candidate.name);
  const properties = compactProperties({
    ...name,
    email: candidate.email,
    phone: candidate.phone,
    company: companyName,
    jobtitle: candidate.role,
    source: 'HEHA Scout Pipeline',
  });

  let contactId = existingId;

  if (contactId) {
    try {
      await updateHubSpotObject(accessToken, 'contacts', contactId, properties);
      return contactId;
    } catch (error) {
      if (!(error instanceof HubSpotApiError) || error.status !== 404) throw error;
      contactId = null;
    }
  }

  if (candidate.email) contactId = await searchHubSpotObject(accessToken, 'contacts', 'email', candidate.email);
  if (!contactId && candidate.phone) contactId = await searchHubSpotObject(accessToken, 'contacts', 'phone', candidate.phone);

  if (contactId) {
    await updateHubSpotObject(accessToken, 'contacts', contactId, properties);
    return contactId;
  }

  return await createHubSpotObject(accessToken, 'contacts', properties);
}

async function associateCompanyAndContact(accessToken: string, companyId: string, contactId: string): Promise<void> {
  await hubspotRequest(accessToken, `/crm/v4/objects/companies/${companyId}/associations/contacts/${contactId}`, {
    method: 'PUT',
    body: JSON.stringify([{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: COMPANY_TO_CONTACT }]),
  });
}

async function createHubSpotNote(
  accessToken: string,
  companyId: string,
  contactIds: string[],
  noteBody: string,
): Promise<string> {
  const associations = [
    {
      to: { id: companyId },
      types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: NOTE_TO_COMPANY }],
    },
    ...contactIds.map((contactId) => ({
      to: { id: contactId },
      types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: NOTE_TO_CONTACT }],
    })),
  ];

  const result = await hubspotRequest<{ id: string }>(accessToken, '/crm/v3/objects/notes', {
    method: 'POST',
    body: JSON.stringify({
      properties: {
        hs_timestamp: new Date().toISOString(),
        hs_note_body: noteBody,
      },
      associations,
    }),
  });

  return result.id;
}

function buildContactCandidates(lead: ScoutLeadRow | null, contacts: ScoutContactRow[]): ContactCandidate[] {
  const candidates: ContactCandidate[] = [];

  if (lead?.primary_contact_name?.trim()) {
    candidates.push({
      key: `lead:${lead.id}:primary`,
      name: lead.primary_contact_name,
      role: lead.primary_contact_role,
      phone: null,
      email: null,
      instagram: null,
      linkedin: null,
      notes: 'Person met during HEHA field visit.',
    });
  }

  for (const contact of contacts) {
    if (!contact.contact_name?.trim() && !contact.email?.trim() && !contact.phone?.trim()) continue;
    candidates.push({
      key: `scout_contact:${contact.id}`,
      name: contact.contact_name,
      role: contact.contact_role,
      phone: contact.phone,
      email: contact.email,
      instagram: contact.instagram,
      linkedin: contact.linkedin,
      notes: contact.notes,
    });
  }

  return candidates.slice(0, 10);
}

function buildNoteBody(
  queue: QueueRow,
  partner: PartnerRow,
  lead: ScoutLeadRow | null,
  contacts: ContactCandidate[],
): string {
  const lines: Array<[string, string | number | null | undefined]> = [
    ['Business', lead?.business_name ?? partner.name],
    ['HEHA lead category', queue.lead_category],
    ['Lead type', lead?.lead_type ?? partner.partner_type],
    ['HEHA pillar', lead?.heha_pillar],
    ['Business category', lead?.business_category ?? partner.category],
    ['HEHA fit score', lead?.fit_score],
    ['Neighborhood', lead?.neighborhood ?? partner.neighborhood],
    ['Business email', lead?.email ?? partner.contact],
    ['Business phone', lead?.phone ?? partner.phone],
    ['Instagram', lead?.instagram ?? partner.instagram],
    ['Google Maps', lead?.google_maps_url],
    ['Hours', lead?.hours ?? partner.hours],
    ['Offerings', lead?.offerings_text ?? lead?.products_services],
    ['Featured items / products', lead?.featured_items_text],
    ['First impression', lead?.first_impression],
    ['Why this may fit HEHA', lead?.heha_fit_notes],
    ['Potential deal / contribution', lead?.potential_offer],
    ['Visit notes', lead?.visit_notes],
  ];

  const contactLines = contacts.map((contact, index) => {
    const details = [contact.name, contact.role, contact.email, contact.phone, contact.instagram, contact.linkedin]
      .filter(Boolean)
      .join(' · ');
    return details ? `<strong>Contact ${index + 1}:</strong> ${htmlEscape(details)}` : '';
  }).filter(Boolean);

  const detailLines = lines
    .filter(([, value]) => value !== null && value !== undefined && String(value).trim())
    .map(([label, value]) => `<strong>${htmlEscape(label)}:</strong> ${htmlEscape(String(value))}`);

  return [
    '<strong>HEHA Scout field visit / partner intake</strong>',
    ...detailLines,
    ...contactLines,
    '<em>Created from the HEHA Scout & Partner Pipeline. Supabase remains the operational source of truth. Outreach and partnership commitments require HEHA approval.</em>',
  ].join('<br>');
}

async function processQueueRow(
  supabase: ReturnType<typeof createClient>,
  accessToken: string,
  queue: QueueRow,
): Promise<{ companyId: string; contactCount: number; noteCreated: boolean; skipped: boolean }> {
  const { data: partner, error: partnerError } = await supabase
    .from('partners')
    .select('id,name,category,location,contact,instagram,website,bio,phone,business_type,partner_type,neighborhood,tagline,hours')
    .eq('id', queue.partner_id)
    .maybeSingle();

  if (partnerError) throw partnerError;
  if (!partner) throw new Error(`Partner ${queue.partner_id} was not found.`);

  const { data: lead, error: leadError } = await supabase
    .from('scout_leads')
    .select('id,business_name,lead_type,heha_pillar,business_category,neighborhood,tagline,bio,hours,address,city,state,postal_code,phone,email,website,instagram,google_maps_url,primary_contact_name,primary_contact_role,visit_notes,first_impression,heha_fit_notes,fit_score,products_services,offerings_text,featured_items_text,potential_offer')
    .eq('partner_id', queue.partner_id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (leadError) throw leadError;

  let scoutContacts: ScoutContactRow[] = [];
  if (lead?.id) {
    const { data, error } = await supabase
      .from('scout_contacts')
      .select('id,contact_name,contact_role,phone,email,instagram,linkedin,is_primary,contact_status,notes')
      .eq('lead_id', lead.id)
      .order('is_primary', { ascending: false })
      .order('created_at', { ascending: true });
    if (error) throw error;
    scoutContacts = data ?? [];
  }

  const companyName = lead?.business_name?.trim() || (partner as PartnerRow).name?.trim();
  if (!companyName) throw new Error('Scout lead has no business name to sync to HubSpot.');

  const websiteInfo = normalizeWebsite(lead?.website ?? (partner as PartnerRow).website);
  const companyProperties = compactProperties({
    name: companyName,
    domain: websiteInfo.domain,
    website: websiteInfo.website,
    phone: lead?.phone ?? (partner as PartnerRow).phone,
    address: lead?.address,
    city: lead?.city,
    state: lead?.state,
    zip: lead?.postal_code,
    description: lead?.bio ?? (partner as PartnerRow).bio ?? lead?.heha_fit_notes,
    lifecyclestage: queue.lifecycle_stage ?? 'lead',
  });

  const contactCandidates = buildContactCandidates(lead as ScoutLeadRow | null, scoutContacts);
  const noteBody = buildNoteBody(queue, partner as PartnerRow, lead as ScoutLeadRow | null, contactCandidates);
  const noteFingerprint = await sha256(noteBody);
  const payloadHash = await sha256({ companyProperties, contactCandidates, noteFingerprint });

  if (queue.last_payload_hash === payloadHash && queue.hubspot_company_id) {
    await supabase
      .from('admin_hubspot_links')
      .update({
        sync_status: 'success',
        sync_error_notes: null,
        last_synced_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', queue.id)
      .eq('sync_status', 'syncing');

    return { companyId: queue.hubspot_company_id, contactCount: Object.keys(queue.hubspot_contact_ids ?? {}).length, noteCreated: false, skipped: true };
  }

  const companyId = await upsertCompany(accessToken, queue.hubspot_company_id, companyProperties);
  await bestEffortCompanyProperty(accessToken, companyId, 'google_maps_link', lead?.google_maps_url ?? null);
  await bestEffortCompanyProperty(accessToken, companyId, 'heha_fit_score', mapFitScore(lead?.fit_score ?? null));

  const contactIdMap: Record<string, string> = { ...(queue.hubspot_contact_ids ?? {}) };
  const syncedContactIds: string[] = [];

  for (const candidate of contactCandidates) {
    const contactId = await upsertContact(accessToken, contactIdMap[candidate.key] ?? null, candidate, companyName);
    await associateCompanyAndContact(accessToken, companyId, contactId);
    contactIdMap[candidate.key] = contactId;
    syncedContactIds.push(contactId);
  }

  let noteId = queue.hubspot_note_id;
  let noteCreated = false;
  if (queue.last_note_fingerprint !== noteFingerprint || !noteId) {
    noteId = await createHubSpotNote(accessToken, companyId, syncedContactIds, noteBody);
    noteCreated = true;
  }

  const firstContactId = syncedContactIds[0] ?? queue.hubspot_contact_id ?? null;
  await supabase
    .from('admin_hubspot_links')
    .update({
      hubspot_company_id: companyId,
      hubspot_contact_id: firstContactId,
      hubspot_contact_ids: contactIdMap,
      hubspot_note_id: noteId,
      last_note_fingerprint: noteFingerprint,
      last_payload_hash: payloadHash,
      sync_status: 'success',
      sync_error_notes: null,
      last_synced_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq('id', queue.id)
    .eq('sync_status', 'syncing');

  return { companyId, contactCount: syncedContactIds.length, noteCreated, skipped: false };
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const hubspotAccessToken = Deno.env.get('HUBSPOT_ACCESS_TOKEN');
  if (!hubspotAccessToken) {
    console.error('hubspot-sync missing HUBSPOT_ACCESS_TOKEN');
    return Response.json({ ok: false, configured: false, error: 'HubSpot sync secret is not configured.' }, { status: 503 });
  }

  let requestedLimit = 10;
  try {
    const body = await req.json().catch(() => ({}));
    requestedLimit = Number.isFinite(Number(body?.limit)) ? Number(body.limit) : 10;
  } catch {
    requestedLimit = 10;
  }
  const limit = Math.max(1, Math.min(Math.trunc(requestedLimit), 25));

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, getSupabaseServiceKey(), {
    auth: { persistSession: false },
  });

  const { data: queueRows, error: claimError } = await supabase.rpc('claim_hubspot_sync_queue', { p_limit: limit });
  if (claimError) {
    console.error('hubspot-sync queue claim failed', claimError);
    return Response.json({ ok: false, error: claimError.message }, { status: 500 });
  }

  const summary = { claimed: queueRows?.length ?? 0, success: 0, failed: 0, skipped: 0, notesCreated: 0, contactsSynced: 0 };

  for (const queue of (queueRows ?? []) as QueueRow[]) {
    try {
      const result = await processQueueRow(supabase, hubspotAccessToken, queue);
      summary.success += 1;
      if (result.skipped) summary.skipped += 1;
      if (result.noteCreated) summary.notesCreated += 1;
      summary.contactsSynced += result.contactCount;
    } catch (error) {
      summary.failed += 1;
      const message = error instanceof Error ? error.message : String(error);
      console.error(`hubspot-sync failed for queue ${queue.id}`, message);
      await supabase
        .from('admin_hubspot_links')
        .update({
          sync_status: 'failed',
          sync_error_notes: message.slice(0, 4000),
          updated_at: new Date().toISOString(),
        })
        .eq('id', queue.id)
        .eq('sync_status', 'syncing');
    }
  }

  return Response.json({ ok: summary.failed === 0, configured: true, ...summary });
});
