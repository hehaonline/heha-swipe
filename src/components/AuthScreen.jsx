import { useState, useEffect } from "react";
import { supabase } from "../lib/supabase";
export default function AuthScreen() {
  const [mode, setMode] = useState("email");
  const [value, setValue] = useState("");
  const [sent, setSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);
  const [socialLoading, setSocialLoading] = useState(null);
  const [error, setError] = useState("");
  const [authError, setAuthError] = useState("");
  const [cooldown, setCooldown] = useState(0);
  useEffect(() => {
    const hash = window.location.hash;
    if (hash.includes("error=")) {
      const params = new URLSearchParams(hash.substring(1));
      const code = params.get("error_code");
      const desc = params.get("error_description")?.replace(/\+/g," ");
      setAuthError(code==="otp_expired"?"Your sign-in link has expired. Request a new one.":desc||"Sign-in failed.");
      window.history.replaceState(null,"",window.location.pathname);
    }
  }, []);
  useEffect(() => { if(cooldown>0){const t=setTimeout(()=>setCooldown(c=>c-1),1000);return()=>clearTimeout(t);} },[cooldown]);
  const social = async (provider) => {
    setSocialLoading(provider); setError("");
    try {
      const {error:e} = await supabase.auth.signInWithOAuth({ provider, options:{ redirectTo:`${window.location.origin}/` } });
      if(e) throw e;
    } catch(e) { setError(e.message||`${provider} sign-in failed.`); setSocialLoading(null); }
  };
  const send = async () => {
    setError(""); if(!value.trim()){setError(`Enter your ${mode==="email"?"email":"phone number"}.`);return;} setLoading(true);
    try {
      if(mode==="email"){const{error:e}=await supabase.auth.signInWithOtp({email:value.trim(),options:{shouldCreateUser:true}});if(e)throw e;}
      else{const phone=value.trim().startsWith("+")?value.trim():`+1${value.trim().replace(/\D/g,"")}`;const{error:e}=await supabase.auth.signInWithOtp({phone});if(e)throw e;}
      setSent(true);setCooldown(60);
    } catch(e){if(e.message?.includes("rate limit")||e.message?.includes("after")){setError("Please wait.");setCooldown(45);}else setError(e.message||"Something went wrong.");}
    finally{setLoading(false);}
  };
  const verify = async () => {
    setError(""); if(!otp.trim()){setError("Enter the code.");return;} setLoading(true);
    try{const phone=value.trim().startsWith("+")?value.trim():`+1${value.trim().replace(/\D/g,"")}`;const{error:e}=await supabase.auth.verifyOtp({phone,token:otp.trim(),type:"sms"});if(e)throw e;}
    catch(e){if(e.message?.includes("expired")||e.message?.includes("invalid")){setError("Code expired.");setSent(false);setOtp("");}else setError(e.message||"Failed.");}
    finally{setLoading(false);}
  };
  const IS=(err)=>({width:"100%",padding:"14px 16px",borderRadius:14,boxSizing:"border-box",border:`2px solid ${err?"#e85d2b":"#eee"}`,fontSize:16,outline:"none",marginBottom:8,background:"#fafafa"});
  return (
    <div style={{minHeight:"100dvh",display:"flex",flexDirection:"column",background:"#fff",fontFamily:"'DM Sans',system-ui,sans-serif"}}>
      <div style={{background:"linear-gradient(160deg,#111 55%,#2a1a0a)",padding:"60px 28px 44px",position:"relative",overflow:"hidden"}}>
        <div style={{position:"absolute",top:-60,right:-60,width:220,height:220,borderRadius:"50%",background:"rgba(232,93,43,0.15)"}}/>
        <div style={{position:"absolute",bottom:10,left:-30,width:140,height:140,borderRadius:"50%",background:"rgba(232,93,43,0.08)"}}/>
        <div style={{position:"relative"}}>
          <div style={{display:"inline-flex",alignItems:"center",gap:6,background:"rgba(232,93,43,0.15)",borderRadius:10,padding:"5px 12px",marginBottom:18}}>
            <span style={{color:"#e85d2b",fontSize:12}}>✦</span>
            <span style={{fontSize:10,fontWeight:700,color:"#e85d2b",letterSpacing:2,textTransform:"uppercase",fontFamily:"'Syne',sans-serif"}}>Tampa Bay</span>
          </div>
          <div style={{fontFamily:"'Syne',sans-serif",fontWeight:800,color:"#fff",lineHeight:1,letterSpacing:"-1.5px"}}>
            <div style={{fontSize:44}}>HEHA</div>
            <div style={{fontSize:44}}><span style={{color:"#e85d2b"}}>·</span>swipe</div>
          </div>
          <div style={{fontSize:15,color:"rgba(255,255,255,0.5)",marginTop:12,lineHeight:1.6}}>Discover Tampa Bay's healthiest<br/>local businesses</div>
        </div>
      </div>
      <div style={{flex:1,padding:"24px 24px 40px",background:"#fff",overflowY:"auto"}}>
        {authError&&<div style={{background:"#fff4f0",border:"1px solid #ffe0d6",borderRadius:12,padding:"12px 16px",marginBottom:20,fontSize:13,color:"#c0392b",display:"flex",gap:10}}><span>⏱</span><div><strong>Link expired.</strong> {authError}</div></div>}
        <div style={{display:"flex",flexDirection:"column",gap:10,marginBottom:20}}>
          <button onClick={()=>social("google")} disabled={!!socialLoading} style={{width:"100%",padding:"13px 16px",borderRadius:14,border:"1.5px solid #eee",background:"#fff",color:"#333",fontSize:14,fontWeight:600,cursor:"pointer",display:"flex",alignItems:"center",justifyContent:"center",gap:10,boxShadow:"0 2px 8px rgba(0,0,0,0.06)"}}>
            {socialLoading==="google"?"⏳":(<svg width="18" height="18" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>)}
            {socialLoading==="google"?"Connecting…":"Continue with Google"}
          </button>
          <button onClick={()=>social("apple")} disabled={!!socialLoading} style={{width:"100%",padding:"13px 16px",borderRadius:14,border:"none",background:"#000",color:"#fff",fontSize:14,fontWeight:600,cursor:"pointer",display:"flex",alignItems:"center",justifyContent:"center",gap:10}}>
            {socialLoading==="apple"?"⏳":"🍎"} {socialLoading==="apple"?"Connecting…":"Continue with Apple"}
          </button>
          <button onClick={()=>social("facebook")} disabled={!!socialLoading} style={{width:"100%",padding:"13px 16px",borderRadius:14,border:"none",background:"#1877F2",color:"#fff",fontSize:14,fontWeight:600,cursor:"pointer",display:"flex",alignItems:"center",justifyContent:"center",gap:10}}>
            {socialLoading==="facebook"?"⏳":"f"} {socialLoading==="facebook"?"Connecting…":"Continue with Facebook"}
          </button>
        </div>
        <div style={{display:"flex",alignItems:"center",gap:12,marginBottom:20}}>
          <div style={{flex:1,height:1,background:"#eee"}}/><span style={{fontSize:12,color:"#bbb",fontWeight:600}}>or</span><div style={{flex:1,height:1,background:"#eee"}}/>
        </div>
        <div style={{display:"flex",background:"#f5f5f5",borderRadius:14,padding:4,marginBottom:20}}>
          {["email","phone"].map(m=>(
            <button key={m} onClick={()=>{setMode(m);setError("");setValue("");setSent(false);setOtp("");}}
              style={{flex:1,padding:"10px 0",borderRadius:11,border:"none",cursor:"pointer",fontSize:13,fontWeight:600,fontFamily:"'Syne',sans-serif",background:mode===m?"#fff":"transparent",color:mode===m?"#111":"#aaa",boxShadow:mode===m?"0 2px 8px rgba(0,0,0,0.08)":"none",transition:"all 0.2s"}}>
              {m==="email"?"📧  Email":"📱  Phone"}
            </button>
          ))}
        </div>
        {error&&<div style={{fontSize:13,color:"#e85d2b",marginBottom:12,padding:"10px 14px",background:"#fff4f0",borderRadius:10}}>{error}</div>}
        {mode==="email"&&!sent&&(<><input type="email" placeholder="you@example.com" value={value} onChange={e=>{setValue(e.target.value);setError("");}} onKeyDown={e=>e.key==="Enter"&&send()} style={IS(!!error)} autoFocus/><Btn onClick={send} loading={loading}>{loading?"Sending…":"Send magic link →"}</Btn><div style={{fontSize:12,color:"#bbb",textAlign:"center",marginTop:10}}>No password needed.</div></>)}
        {mode==="email"&&sent&&(<><div style={{textAlign:"center",padding:"16px 0 20px"}}><div style={{width:64,height:64,borderRadius:20,background:"#fff4f0",display:"flex",alignItems:"center",justifyContent:"center",fontSize:28,margin:"0 auto 16px"}}>📬</div><div style={{fontFamily:"'Syne',sans-serif",fontSize:22,fontWeight:800,color:"#111",marginBottom:8}}>Check your inbox</div><div style={{fontSize:14,color:"#777",lineHeight:1.7}}>Magic link sent to <strong>{value}</strong></div></div><div style={{background:"#f9f9f9",borderRadius:12,padding:"12px 16px",fontSize:13,color:"#999",marginBottom:20}}>💡 Check spam if you don't see it.</div><div style={{display:"flex",justifyContent:"space-between"}}><button onClick={()=>setSent(false)} style={{background:"none",border:"none",fontSize:13,color:"#aaa",cursor:"pointer"}}>← Change email</button><button onClick={send} disabled={cooldown>0} style={{background:"none",border:"none",fontSize:13,color:cooldown>0?"#ccc":"#e85d2b",cursor:cooldown>0?"not-allowed":"pointer",fontWeight:700}}>{cooldown>0?`Resend in ${cooldown}s`:"Resend"}</button></div></>)}
        {mode==="phone"&&!sent&&(<><input type="tel" placeholder="+1 (813) 000-0000" value={value} onChange={e=>{setValue(e.target.value);setError("");}} onKeyDown={e=>e.key==="Enter"&&send()} style={IS(!!error)} autoFocus/><Btn onClick={send} loading={loading}>{loading?"Sending…":"Send 6-digit code →"}</Btn></>)}
        {mode==="phone"&&sent&&(<><div style={{fontFamily:"'Syne',sans-serif",fontSize:20,fontWeight:800,color:"#111",marginBottom:6}}>Enter your code</div><div style={{fontSize:14,color:"#777",marginBottom:16}}>Sent to <strong>{value}</strong></div><input type="text" inputMode="numeric" placeholder="· · · · · ·" value={otp} onChange={e=>{setOtp(e.target.value.replace(/\D/g,"").slice(0,6));setError("");}} onKeyDown={e=>e.key==="Enter"&&verify()} style={{...IS(!!error),fontSize:32,fontWeight:800,letterSpacing:12,textAlign:"center"}} autoFocus/><Btn onClick={verify} loading={loading} disabled={otp.length<6}>{loading?"Verifying…":"Verify →"}</Btn><div style={{display:"flex",justifyContent:"space-between",marginTop:14}}><button onClick={()=>{setSent(false);setOtp("");}} style={{background:"none",border:"none",fontSize:13,color:"#aaa",cursor:"pointer"}}>← Change number</button><button onClick={send} disabled={cooldown>0} style={{background:"none",border:"none",fontSize:13,color:cooldown>0?"#ccc":"#e85d2b",cursor:cooldown>0?"not-allowed":"pointer",fontWeight:700}}>{cooldown>0?`Resend in ${cooldown}s`:"Resend"}</button></div></>)}
        <div style={{marginTop:24,fontSize:11,color:"#ccc",textAlign:"center"}}>By continuing, you agree to our Terms & Privacy Policy.</div>
      </div>
    </div>
  );
}
function Btn({onClick,loading,disabled,children}){const off=loading||disabled;return(<button onClick={onClick} disabled={off} style={{width:"100%",padding:15,borderRadius:14,border:"none",marginTop:4,background:off?"#f0f0f0":"linear-gradient(135deg,#e85d2b,#ff7a47)",color:off?"#bbb":"#fff",fontSize:15,fontWeight:700,cursor:off?"not-allowed":"pointer",boxShadow:off?"none":"0 6px 20px rgba(232,93,43,0.35)",fontFamily:"'Syne',sans-serif",transition:"all 0.2s"}}>{children}</button>);}
