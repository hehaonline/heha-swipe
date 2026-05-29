import { createClient } from '@supabase/supabase-js'
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
export async function signUp({email,password,fullName,role}){const{data,error}=await supabase.auth.signUp({email,password,options:{data:{full_name:fullName,role}}});if(error)throw error;return data}
export async function signIn({email,password}){const{data,error}=await supabase.auth.signInWithPassword({email,password});if(error)throw error;return data}
export async function signOut(){await supabase.auth.signOut()}
export async function getSession(){const{data:{session}}=await supabase.auth.getSession();return session}
export async function getCurrentUser(){const{data:{user}}=await supabase.auth.getUser();return user}
export function onAuthChange(cb){return supabase.auth.onAuthStateChange((_,s)=>cb(s?.user??null))}
export async function getPartners({category=null}={}){let q=supabase.from('partners').select('*,partner_photos(url,position),featured_items(id,name,description,price,emoji,position),partner_services(id,name,price)').eq('status','live');if(category&&category!=='All')q=q.eq('category',category);const{data,error}=await q;if(error)throw error;return data}
export async function savePartner(partnerId){const u=await getCurrentUser();if(!u)return;await supabase.from('saves').upsert({user_id:u.id,partner_id:partnerId});}
export async function getSavedPartners(){const u=await getCurrentUser();if(!u)return[];const{data}=await supabase.from('saves').select('partners(*)').eq('user_id',u.id);return data?.map(s=>s.partners)||[]}
export async function trackSwipe({partnerId,direction}){const u=await getCurrentUser();await supabase.from('swipe_events').insert({user_id:u?.id||null,partner_id:partnerId,direction})}
export async function createPartner(d){const u=await getCurrentUser();if(!u)throw new Error('Sign in required');const{data,error}=await supabase.from('partners').insert({owner_id:u.id,...d,status:'pending'}).select().single();if(error)throw error;return data}
export async function submitReview({partnerId,stars,body}){const u=await getCurrentUser();if(!u)throw new Error('Sign in required');const{data,error}=await supabase.from('reviews').upsert({user_id:u.id,partner_id:partnerId,stars,body,discount_pct:5}).select().single();if(error)throw error;return data}
