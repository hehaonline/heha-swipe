#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?Use a disposable database only; DATABASE_URL is required}"

# Two real PostgreSQL sessions contend for the same invitation. Exactly one can
# consume it because redeem_partner_claim locks invitation then partner consistently.
token=${CLAIM_TOKEN:?CLAIM_TOKEN is required}
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select public.redeem_partner_claim(:'token')" -v token="$token" > /tmp/claim-a.out 2>&1 & a=$!
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select public.redeem_partner_claim(:'token')" -v token="$token" > /tmp/claim-b.out 2>&1 & b=$!
ok=0
wait "$a" && ok=$((ok+1)) || true
wait "$b" && ok=$((ok+1)) || true
test "$ok" -eq 1 || { cat /tmp/claim-a.out /tmp/claim-b.out; exit 1; }
