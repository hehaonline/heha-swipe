import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

async function source(relativePath) {
  return readFile(path.join(repoRoot, relativePath), "utf8");
}

test("the owner withdrawal repository call remains destination scoped", async () => {
  const repository = await source("src/services/partnerPublicationConsentRepository.js");
  const wrapperStart = repository.indexOf("export async function withdrawPartnerProfilePublication({");
  const wrapperEnd = repository.indexOf("export async function getMyPartnerPublicationStatus", wrapperStart);
  const wrapper = repository.slice(wrapperStart, wrapperEnd);

  assert.ok(wrapperStart >= 0, "the owner withdrawal wrapper must remain exported");
  assert.match(wrapper, /supabase\.rpc\("withdraw_partner_publication_authorization"/);
  assert.match(wrapper, /p_destinations:\s*destinations/);
  assert.match(wrapper, /p_authorized_representative_name:\s*representativeName\.trim\(\)/);
  assert.match(wrapper, /p_authorized_representative_title:\s*representativeTitle\.trim\(\)/);
  assert.match(wrapper, /p_request_key:\s*requestKey/);
});

test("ProfileTab exposes withdrawal for every current publication authorization", async () => {
  const profile = await source("src/components/ProfileTab.jsx");
  const renderStart = profile.indexOf("{!publicationStatusLoading");
  const heading = profile.indexOf("Withdraw profile permission", renderStart);
  const renderGate = profile.slice(renderStart, heading);

  assert.match(profile, /withdrawPartnerProfilePublication,/);
  assert.ok(renderStart >= 0 && heading > renderStart, "the withdrawal form must render in ProfileTab");
  assert.match(renderGate, /currentPublicationDestinations\.length > 0/);
  assert.doesNotMatch(
    renderGate,
    /needs_publication_approval/,
    "withdrawal must not disappear for partial or fully approved authorization state"
  );
  assert.match(profile, /currentPublicationDestinations\.map\(\(destination\) =>/);
  assert.match(profile, /togglePublicationWithdrawalDestination\(destination\)/);
  assert.match(profile, /publicationWithdrawal\.representativeName/);
  assert.match(profile, /publicationWithdrawal\.representativeTitle/);
  assert.match(profile, /I withdraw publication permission for the selected destinations\./);
});

test("ProfileTab withdrawal is idempotent, single-flight, and refreshes server status", async () => {
  const profile = await source("src/components/ProfileTab.jsx");
  const handlerStart = profile.indexOf("const withdrawCurrentPartnerPublication = async () => {");
  const handlerEnd = profile.indexOf("const resetAppProfile = async () => {", handlerStart);
  const handler = profile.slice(handlerStart, handlerEnd);
  const rpcCall = handler.indexOf("await withdrawPartnerProfilePublication({");
  const statusRefresh = handler.indexOf("await getMyPartnerPublicationStatus(activeListing.id);", rpcCall);
  const resetAfterRefresh = handler.indexOf("resetPublicationWithdrawalForm();", statusRefresh);

  assert.ok(handlerStart >= 0 && handlerEnd > handlerStart, "the withdrawal handler must remain present");
  assert.match(handler, /publicationWithdrawalInFlight\.current/);
  assert.match(handler, /publicationWithdrawalWriteRecorded/);
  assert.match(handler, /currentPublicationDestinations\.includes\(destination\)/);
  assert.match(handler, /!publicationWithdrawal\.confirmed/);
  assert.ok(rpcCall >= 0, "the handler must call the owner withdrawal RPC wrapper");
  assert.match(handler, /requestKey:\s*publicationWithdrawalRequestKey/);
  assert.ok(statusRefresh > rpcCall, "authoritative status must refresh after the withdrawal write");
  assert.ok(resetAfterRefresh > statusRefresh, "the request key and form may reset only after status refresh succeeds");
  assert.doesNotMatch(
    handler.slice(rpcCall, statusRefresh),
    /setPublicationWithdrawalRequestKey/,
    "the idempotency key must stay stable while write status is uncertain"
  );
  assert.match(handler, /publicationWithdrawalAwaitingStatusRefresh\.current = true/);
  assert.match(handler, /setPublicationStatusError\(WITHDRAWAL_STATUS_REFRESH_ERROR\)/);
  assert.match(handler, /Use Retry status; do not submit it again\./);
});
