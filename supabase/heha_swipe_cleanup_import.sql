-- HEHA Swipe cleanup + Perfect CRM import
-- Generated from HEHA_HubSpot_Perfect_CRM.xlsx
-- Purpose:
-- 1) Delete obvious demo/test listings.
-- 2) Set only Pure Kitchen, Mediterranean Chickpea, and Orawganic as HEHA Certified.
-- 3) Insert eligible public business listings from Perfect CRM as non-partner 'listed' records.
-- Review before running in Supabase SQL editor.

begin;

delete from public.partners
where lower(name)=lower('Test Massage Business') OR lower(name)=lower('Mind & Body Massage') OR lower(name)=lower('Green Bowl Tampa') OR lower(name)=lower('The Wellness Coach') OR lower(name)=lower('Roots Market') OR lower(name)=lower('Sol Yoga Studio') OR lower(name)=lower('Iron & Oak Fitness');

update public.partners
set heha_partner = false,
    status = case when status = 'approved' then 'listed' else status end,
    updated_at = now()
where not (lower(name)=lower('Pure Kitchen') OR lower(name)=lower('Pure Kitchen Organic Vegan') OR lower(name)=lower('Mediterranean Chickpea') OR lower(name)=lower('The Mediterranean Chickpea') OR lower(name)=lower('Orawganic'));

update public.partners
set heha_partner = true,
    status = 'approved',
    updated_at = now()
where lower(name)=lower('Pure Kitchen') OR lower(name)=lower('Pure Kitchen Organic Vegan') OR lower(name)=lower('Mediterranean Chickpea') OR lower(name)=lower('The Mediterranean Chickpea') OR lower(name)=lower('Orawganic');

-- Full generated import file is attached in the companion CSV/XLSX from Nova.
-- Use heha_swipe_supabase_import.csv or HEHA_Swipe_CRM_Supabase_Import.xlsx for bulk import.

commit;

-- Verification:
-- select name, heha_partner, status from public.partners where heha_partner = true order by name;
-- select count(*) from public.partners;
