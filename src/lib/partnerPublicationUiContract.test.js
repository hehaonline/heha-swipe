import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const profileTabSource = readFileSync(
  new URL("../components/ProfileTab.jsx", import.meta.url),
  "utf8"
);

test("ProfileTab wires destination-scoped owner withdrawal to the repository", () => {
  assert.match(
    profileTabSource,
    /import\s*\{[^}]*withdrawPartnerProfilePublication[^}]*\}\s*from\s*["']\.\.\/services\/partnerPublicationConsentRepository["']/s
  );
  assert.match(
    profileTabSource,
    /validatePartnerPublicationWithdrawal\(\{[\s\S]*?activeDestinations:\s*publicationStatus\?\.publication_destinations\s*\|\|\s*\[\][\s\S]*?\}\)/
  );
  assert.match(
    profileTabSource,
    /withdrawPartnerProfilePublication\(\{[\s\S]*?destinations:\s*validation\.destinations[\s\S]*?requestKey:\s*publicationWithdrawalRequestKey[\s\S]*?\}\)/
  );
  assert.doesNotMatch(
    profileTabSource,
    /withdrawPartnerProfilePublication\(\{[\s\S]*?destinations:\s*publicationStatus\?\.publication_destinations/
  );
  assert.doesNotMatch(
    profileTabSource,
    /\{publicationStatusError\}\s*HEHA has not changed this listing’s public visibility/
  );
});
