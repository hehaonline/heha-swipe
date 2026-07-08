import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';
import Stripe from 'npm:stripe';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
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

function getBearerToken(req: Request): string | null {
  const header = req.headers.get('Authorization') ?? '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match?.[1] ?? null;
}

function getHehaSwipeBaseUrl(): string {
  const configured = Deno.env.get('HEHA_SWIPE_URL') ?? 'https://www.hehaswipe.app';
  return configured.replace(/\/+$/, '');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  try {
    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
    const membershipPriceId = Deno.env.get('STRIPE_SUPPORTER_MEMBERSHIP_PRICE_ID');
    const hehaSwipeUrl = getHehaSwipeBaseUrl();

    if (!stripeSecretKey) {
      return json({ error: 'STRIPE_SECRET_KEY is not configured.' }, 500);
    }

    if (!membershipPriceId) {
      return json({ error: 'STRIPE_SUPPORTER_MEMBERSHIP_PRICE_ID is not configured.' }, 500);
    }

    const bearerToken = getBearerToken(req);
    if (!bearerToken) {
      return json({ error: 'Missing user authorization token.' }, 401);
    }

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, getSupabaseServiceKey(), {
      auth: { persistSession: false },
    });

    const { data: userResult, error: userError } = await supabase.auth.getUser(bearerToken);
    if (userError || !userResult.user) {
      return json({ error: 'Invalid or expired user session.' }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const requestedQuantity = Number(body?.quantity ?? 1);
    const quantity = Number.isFinite(requestedQuantity)
      ? Math.max(1, Math.min(100, Math.floor(requestedQuantity)))
      : 1;

    const successUrl = `${hehaSwipeUrl}/support/success`;
    const cancelUrl = `${hehaSwipeUrl}/support/cancel`;

    const stripe = new Stripe(stripeSecretKey, { apiVersion: '2025-02-24.acacia' });

    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      line_items: [{ price: membershipPriceId, quantity }],
      success_url: successUrl,
      cancel_url: cancelUrl,
      customer_email: userResult.user.email ?? undefined,
      client_reference_id: userResult.user.id,
      allow_promotion_codes: false,
      subscription_data: {
        metadata: {
          user_id: userResult.user.id,
          support_type: 'supporter_membership',
          quantity: String(quantity),
          source: 'heha_swipe',
          environment: stripeSecretKey.startsWith('sk_test_') ? 'test' : 'live',
        },
      },
      metadata: {
        user_id: userResult.user.id,
        support_type: 'supporter_membership',
        quantity: String(quantity),
        source: 'heha_swipe',
        environment: stripeSecretKey.startsWith('sk_test_') ? 'test' : 'live',
      },
    });

    return json({ checkoutUrl: session.url, sessionId: session.id, quantity });
  } catch (error) {
    console.error('create-supporter-checkout error', error);
    return json({ error: 'Unable to create supporter checkout session.' }, 500);
  }
});
