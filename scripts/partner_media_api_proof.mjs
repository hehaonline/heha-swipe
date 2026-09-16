// Disposable localhost Supabase only. Verified Auth fixtures, not email delivery proof.
import { readFileSync } from 'node:fs';
import { randomBytes, randomUUID } from 'node:crypto';
import { createDisposableMediaPsql, requireDisposableMediaApiTarget, verifyDisposableMediaApi } from './disposable_media_target.mjs';
import assert from 'node:assert/strict';
const cfg=JSON.parse(readFileSync(0,'utf8'));
const url=cfg.API_URL, key=cfg.ANON_KEY, service=cfg.SERVICE_ROLE_KEY, db=cfg.DB_URL;
requireDisposableMediaApiTarget(url);
const database=createDisposableMediaPsql(db,process.env,url);
assert.ok(key && service);
database.verify();
await verifyDisposableMediaApi(url,key,service,database.nonce);
const checks=[];
function ok(label,value){assert.ok(value,label); checks.push(label);}
function sql(statement){return database.sql(statement);}
async function api(path,token=key,method='GET',body,raw=false){
 const response=await fetch(url+path,{method,redirect:'error',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':raw?'image/png':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:raw?body:JSON.stringify(body)});
 const text=await response.text(); let data;
 try{data=JSON.parse(text)}catch{data=null}
 return {ok:response.ok,status:response.status,data};
}
async function must(path,token,method,body,raw=false){
 const result=await api(path,token,method,body,raw);
 assert.ok(result.ok,'request failed: '+method+' '+path.split('?')[0]+' status '+result.status);
 return result.data;
}
async function account(label){
 const email='media-'+label+'-'+randomUUID()+'@example.invalid',password=randomBytes(24).toString('hex');
 const user=await must('/auth/v1/admin/users',service,'POST',{email,password,email_confirm:true});
 const session=await must('/auth/v1/token?grant_type=password',key,'POST',{email,password});
 assert.equal(session.user.id,user.id);
 return {email,password,id:user.id,token:session.access_token};
}
const owner=await account('owner'),peer=await account('peer'),staff=await account('staff');
sql("INSERT INTO public.user_roles(user_id,role,active) VALUES('"+staff.id+"','pm_admin',true)");
const partner=randomUUID();
sql("INSERT INTO public.partners(id,name,status,category,categories,owner_id) VALUES('"+partner+"','Synthetic Media API Restaurant','pending','Restaurant',ARRAY['Restaurant'],NULL)");
sql("NOTIFY pgrst, 'reload schema'");
await new Promise(r=>setTimeout(r,1500));
const invitation=await must('/rest/v1/rpc/create_partner_claim_invite',staff.token,'POST',{p_partner_id:partner,p_intended_email:owner.email});
assert.equal(invitation[0].partner_id,partner);
const rawToken=invitation[0].raw_token;
const wrong=await api('/rest/v1/rpc/claim_partner_profile',peer.token,'POST',{p_raw_token:rawToken});
ok('wrong recipient denied',!wrong.ok);
await must('/rest/v1/rpc/preview_partner_claim',owner.token,'POST',{p_raw_token:rawToken});
await must('/rest/v1/rpc/claim_partner_profile',owner.token,'POST',{p_raw_token:rawToken});
const rows=await must('/rest/v1/partners?id=eq.'+partner+'&select=id,owner_id,image_url,gallery_urls',owner.token);
ok('claim binds same card',rows.length===1 && rows[0].id===partner && rows[0].owner_id===owner.id);
const duplicate=await api('/rest/v1/rpc/claim_partner_profile',owner.token,'POST',{p_raw_token:rawToken});
ok('consumed claim denied',!duplicate.ok);
await must('/rest/v1/partner_profile_change_requests',owner.token,'POST',{partner_id:partner,owner_id:owner.id,proposed_changes:{hours:'Synthetic hours for review',categories:['Restaurant'],category:'Restaurant'}});
ok('profile edit submitted through review queue',true);
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF1cAAAAASUVORK5CYII=','base64');
const path=owner.id+'/'+partner+'/fixture.png',bucket='partner-media-pending';
await must('/storage/v1/object/'+bucket+'/'+path,owner.token,'POST',png,true);
ok('Storage API byte upload',true);
const rejected=await api('/storage/v1/object/'+bucket+'/'+peer.id+'/'+partner+'/foreign.png',peer.token,'POST',png,true);
ok('Storage API cross-business upload denied',!rejected.ok);
const retry=await api('/storage/v1/object/'+bucket+'/'+path,owner.token,'POST',png,true);
ok('duplicate object overwrite denied',!retry.ok);
await must('/rest/v1/partner_media_requests',owner.token,'POST',{partner_id:partner,owner_id:owner.id,media_type:'gallery',storage_path:path,mime_type:'image/png',file_size_bytes:png.length,original_filename:'fixture.png'});
async function readBytes(token){
 const signed=await must('/storage/v1/object/sign/'+bucket+'/'+path,token,'POST',{expiresIn:60});
 assert.ok(typeof signed.signedURL==='string' && signed.signedURL.startsWith('/object/sign/') && !signed.signedURL.includes('\\'));
 const response=await fetch(url+'/storage/v1'+signed.signedURL,{redirect:'error'});
 assert.ok(response.ok);
 return Buffer.from(await response.arrayBuffer());
}
ok('private signed read returns exact bytes',(await readBytes(owner.token)).equals(png));
const peerRead=await api('/storage/v1/object/sign/'+bucket+'/'+path,peer.token,'POST',{expiresIn:60});
ok('peer signed read denied',!peerRead.ok);
await api('/storage/v1/object/'+bucket,peer.token,'DELETE',{prefixes:[path]});
ok('peer delete leaves file intact',(await readBytes(owner.token)).equals(png));
await must('/auth/v1/logout',owner.token,'POST');
const renewed=await must('/auth/v1/token?grant_type=password',key,'POST',{email:owner.email,password:owner.password});
owner.token=renewed.access_token;
const saved=await must('/rest/v1/partner_profile_change_requests?partner_id=eq.'+partner+'&select=status,proposed_changes',owner.token);
ok('edit persists after logout/login',saved.length===1 && saved[0].status==='submitted' && saved[0].proposed_changes.hours==='Synthetic hours for review');
ok('photo persists after logout/login',(await readBytes(owner.token)).equals(png));
await must('/storage/v1/object/'+bucket,owner.token,'DELETE',{prefixes:[path]});
const gone=await api('/storage/v1/object/sign/'+bucket+'/'+path,owner.token,'POST',{expiresIn:60});
ok('owner Storage API delete succeeds',!gone.ok);
const after=await must('/rest/v1/partners?id=eq.'+partner+'&select=id,owner_id,image_url,gallery_urls',owner.token);
ok('no public image activation',after[0].image_url===rows[0].image_url && JSON.stringify(after[0].gallery_urls)===JSON.stringify(rows[0].gallery_urls));
console.log(JSON.stringify({scope:'isolated actual Auth, PostgREST and Storage API; verified synthetic accounts, no SMTP/browser claim',passed:checks.length,checks},null,2));
