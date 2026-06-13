alter table public.partners
  add column if not exists partner_type text,
  add column if not exists product_price_policy text,
  add column if not exists service_fee_type text,
  add column if not exists service_fee_amount numeric default 0,
  add column if not exists delivery_days text[] default '{}',
  add column if not exists pricing_notes text;

create index if not exists partners_partner_type_idx
  on public.partners (partner_type);

create index if not exists partners_product_price_policy_idx
  on public.partners (product_price_policy);
