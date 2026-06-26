import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';
import Stripe from 'npm:stripe';

type SupportType = 'dollar_support' | 'superswoop' | 'supporter_membership' | 'other';

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

function toTimestamp(value: number | null | undefined): string | null {
  if (!value) return null;
  return new Date(value * 1000).toISOString();
}

function getUserIdFromObject(object: Stripe.Checkout.Session | Stripe.Subscription): string | null {
  const metadataUserId = typeof object.metadata?.user_id === 'string' ? object.metadata.user_id : null;
  if (metadataUserId) return metadataUserId;
  if ('client_reference_id' in object && typeof object.client_reference_id === 'string') return object.client_reference_id;
  return null;
}

function inferSupportType(session: Stripe.Checkout.Session): SupportType {
  const metadataSupportType = session.metadata?.support_type as SupportType | undefined;
  if (metadataSupportType) return metadataSupportType;
  if (session.mode === 'subscription') return 'supporter_membership';

  // Safety fallback for the current sandbox Payment Links:
  // $1.00 one-time = HEHA Swipe Support, $2.00 one-time = SuperSwoop.
  // Future production links should send explicit metadata instead of relying on amount.
  if (session.mode === 'payment' && session.amount_total === 100) return 'dollar_support';
  if (session.mode === 'payment' && session.amount_total === 200) return 'superswoop';

  return 'other';
}

function buildSessionMetadata(session: Stripe.Checkout.Session, supportType: SupportType) {
  return {
    ...(session.metadata ?? {}),
    support_type: supportType,
    payment_link: typeof session.payment_link === 'string' ? session.payment_link : session.payment_link?.id ?? null,
    checkout_session_id: session.id,
    environment: session.livemode ? 'live' : 'test',
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');

  if (!stripeSecretKey || !webhookSecret) {
    console.error('Stripe webhook missing STRIPE_SECRET_KEY or STRIPE_WEBHOOK_SECRET');
    return new Response('Webhook not configured', { status: 500 });
  }

  const stripe = new Stripe(stripeSecretKey, { apiVersion: '2025-02-24.acacia' });
  const signature = req.headers.get('stripe-signature');
  const body = await req.text();

  if (!signature) {
    return new Response('Missing Stripe signature', { status: 400 });
  }

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
  } catch (error) {
    console.error('Stripe signature verification failed', error);
    return new Response('Bad signature', { status: 400 });
  }

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, getSupabaseServiceKey(), {
    auth: { persistSession: false },
  });

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const userId = getUserIdFromObject(session);
        const customerId = typeof session.customer === 'string' ? session.customer : session.customer?.id ?? null;
        const sessionAmount = session.amount_total ?? 0;
        const currency = session.currency ?? 'usd';
        const supportType = inferSupportType(session);

        if (session.mode === 'subscription' && typeof session.subscription === 'string') {
          const subscription = await stripe.subscriptions.retrieve(session.subscription);
          const priceId = subscription.items.data[0]?.price?.id ?? session.metadata?.price_id ?? null;
          const quantity = subscription.items.data[0]?.quantity ?? Number(session.metadata?.quantity ?? 1);
          const unitAmount = subscription.items.data[0]?.price?.unit_amount ?? 100;

          await supabase.from('supporter_subscriptions').upsert({
            user_id: userId,
            stripe_subscription_id: subscription.id,
            stripe_customer_id: customerId,
            stripe_price_id: priceId,
            quantity,
            amount_cents: (unitAmount ?? 100) * quantity,
            currency,
            status: subscription.status,
            current_period_start: toTimestamp(subscription.current_period_start),
            current_period_end: toTimestamp(subscription.current_period_end),
            cancel_at_period_end: subscription.cancel_at_period_end,
            canceled_at: toTimestamp(subscription.canceled_at),
            metadata: {
              ...(subscription.metadata ?? {}),
              support_type: 'supporter_membership',
              checkout_session_id: session.id,
              environment: session.livemode ? 'live' : 'test',
            },
          }, { onConflict: 'stripe_subscription_id' });

          if (userId) {
            await supabase.from('profiles').update({
              stripe_customer_id: customerId,
              stripe_subscription_id: subscription.id,
              subscription_type: 'supporter_membership',
              subscription_amount: ((unitAmount ?? 100) * quantity) / 100,
              subscription_active: ['active', 'trialing'].includes(subscription.status),
              subscription_status: subscription.status,
            }).eq('id', userId);
          }
        } else {
          await supabase.from('supporter_payments').upsert({
            user_id: userId,
            stripe_checkout_session_id: session.id,
            stripe_payment_intent_id: typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id ?? null,
            stripe_customer_id: customerId,
            amount_cents: sessionAmount,
            currency,
            support_type: supportType,
            status: session.payment_status === 'paid' ? 'paid' : 'pending',
            metadata: buildSessionMetadata(session, supportType),
          }, { onConflict: 'stripe_checkout_session_id' });

          await supabase.from('contributions').insert({
            user_id: userId,
            type: supportType,
            amount: sessionAmount / 100,
            freebird_portion: 0,
            heha_portion: sessionAmount / 100,
            stripe_payment_id: typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id ?? session.id,
            status: session.payment_status === 'paid' ? 'paid' : 'pending',
          });
        }
        break;
      }

      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const subscription = event.data.object as Stripe.Subscription;
        const userId = getUserIdFromObject(subscription);
        const customerId = typeof subscription.customer === 'string' ? subscription.customer : subscription.customer?.id ?? null;
        const priceId = subscription.items.data[0]?.price?.id ?? null;
        const quantity = subscription.items.data[0]?.quantity ?? Number(subscription.metadata?.quantity ?? 1);
        const unitAmount = subscription.items.data[0]?.price?.unit_amount ?? 100;

        await supabase.from('supporter_subscriptions').upsert({
          user_id: userId,
          stripe_subscription_id: subscription.id,
          stripe_customer_id: customerId,
          stripe_price_id: priceId,
          quantity,
          amount_cents: (unitAmount ?? 100) * quantity,
          currency: subscription.currency ?? 'usd',
          status: subscription.status,
          current_period_start: toTimestamp(subscription.current_period_start),
          current_period_end: toTimestamp(subscription.current_period_end),
          cancel_at_period_end: subscription.cancel_at_period_end,
          canceled_at: toTimestamp(subscription.canceled_at),
          metadata: {
            ...(subscription.metadata ?? {}),
            support_type: 'supporter_membership',
          },
        }, { onConflict: 'stripe_subscription_id' });

        if (userId) {
          await supabase.from('profiles').update({
            stripe_customer_id: customerId,
            stripe_subscription_id: subscription.id,
            subscription_type: 'supporter_membership',
            subscription_amount: ((unitAmount ?? 100) * quantity) / 100,
            subscription_active: ['active', 'trialing'].includes(subscription.status),
            subscription_status: subscription.status,
          }).eq('id', userId);
        }
        break;
      }

      default:
        console.log(`Unhandled Stripe event type: ${event.type}`);
    }

    return Response.json({ received: true });
  } catch (error) {
    console.error('stripe-webhook processing error', error);
    return new Response('Webhook processing failed', { status: 500 });
  }
});
