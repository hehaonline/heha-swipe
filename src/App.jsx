import{useState,useEffect,useRef}from'react'
import{createClient}from'@supabase/supabase-js'
const sb=createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_ANON_KEY)
const G='#3F8C5A'
const CAT={Restaurant:{g:'linear-gradient(135deg,#2d6a4f,#1b4332)',i:'🥗'},Vendor:{g:'linear-gradient(135deg,#7a5c00,#c9850a)',i:'🛍'},Coach:{g:'linear-gradient(135deg,#1a4a6e,#2563a8)',i:'🧠'},Service:{g:'linear-gradient(135deg,#6b3a8a,#9b59b6)',i:'✨'},Activity:{g:'linear-gradient(135deg,#7a3500,#c96f45)',i:'🏃'}},OR='#FF8A2A',DG='#173F2A',SG='#DDEBDD',CL='#C96F45',GD='#F4C95D',CH='#1E1E1E',TP='#7C746A',DV='#E8E3DB',OW='#FAF7F1',LT='#f5f0e8',BK='#111',RD='#c0392b'
const inp={width:'100%',padding:'14px',borderRadius:12,border:'1.5px solid #ddd',fontSize:15,marginBottom:10,boxSizing:'border-box',outline:'none'}
const btn=(bg='#111',col='#fff')=>({width:'100%',padding:'15px',borderRadius:30,border:'none',background:bg,color:col,fontSize:16,fontWeight:700,cursor:'pointer',marginBottom:12})
export default function App(){
  const[user,setUser]=useState(null)
  const[loading,setLoading]=useState(true)
  const[tab,setTab]=useState('swipe')
  const[deck,setDeck]=useState([])
  const[favs,setFavs]=useState([])
  const[detail,setDetail]=useState(null)
  const[filterCat,setFilterCat]=useState('All')
  const[dragX,setDragX]=useState(0)
  const[dragging,setDragging]=useState(false)
  const[swipeDir,setSwipeDir]=useState(null)
  const[heartAnim,setHeartAnim]=useState(false)
  const[authMode,setAuthMode]=useState('role')
const[userRole,setUserRole]=useState(null)
const[partner,setPartner]=useState(null)
const[bizTab,setBizTab]=useState('dash')
const[stats,setStats]=useState({s:0,sw:0,ic:0})
const[savers,setSavers]=useState([])
const[sent,setSent]=useState({})
  const[email,setEmail]=useState('')
  const[password,setPassword]=useState('')
  const[authErr,setAuthErr]=useState('')
  const[authLoading,setAuthLoading]=useState(false)
  const[screen,setScreen]=useState('main')
  const[profile,setProfile]=useState(null)
  const[bizName,setBizName]=useState('')
  const[bizCat,setBizCat]=useState('Restaurant')
  const[bizCity,setBizCity]=useState('')
  const[bizDesc,setBizDesc]=useState('');const[phone,setPhone]=useState('');const[otp,setOtp]=useState('');const[otpContact,setOtpContact]=useState('');const[otpType,setOtpType]=useState('sms');const[authTab,setAuthTab]=useState('phone');
  const dragStart=useRef(null)
  const CATS=['All','Restaurant','Vendor','Coach','Service','Activity']
  const BIZ_CATS=['Restaurant','Vendor','Coach','Service','Activity']
  useEffect(()=>{
    const{data:{subscription}}=sb.auth.onAuthStateChange((_,s)=>{setUser(s?.user??null);setLoading(false)})
    return()=>subscription.unsubscribe()
  },[])
  useEffect(()=>{if(user){loadProfile();detectRole()}},[user,filterCat])
  const detectRole=async()=>{const{data}=await sb.from('partners').select('*').eq('user_id',user.id).maybeSingle();if(data){setUserRole('partner');setPartner(data);const[{count:s},{count:sw}]=await Promise.all([sb.from('saves').select('*',{count:'exact',head:true}).eq('partner_id',data.id),sb.from('swipe_events').select('*',{count:'exact',head:true}).eq('partner_id',data.id)]);setStats({s:s||0,sw:sw||0,ic:0});const{data:sv}=await sb.from('saves').select('user_id,profiles(email)').eq('partner_id',data.id).limit(20);if(sv)setSavers(sv)}else{setUserRole('customer');loadPartners()}};const loadProfile=async()=>{
    const{data}=await sb.from('profiles').select('*').eq('id',user.id).single()
    setProfile(data)
  }
  const loadPartners=async()=>{
    let q=sb.from('partners').select('*,featured_items(id,name,description,price,emoji),partner_services(id,name,price)').eq('status','live')
    if(filterCat!=='All')q=q.eq('category',filterCat)
    const{data,error}=await q
    if(!error)setDeck(data||[])
  }
  const cardRot=swipeDir==='right'?15:swipeDir==='left'?-15:dragging?dragX*0.05:0
  const cur=deck[0]
  const doSwipe=async(dir)=>{
    if(dir==='right'){setHeartAnim(true);setTimeout(()=>setHeartAnim(false),800);setFavs(f=>f.find(x=>x.id===cur.id)?f:[...f,cur]);if(user)await sb.from('saves').upsert({user_id:user.id,partner_id:cur.id})}
    if(user)await sb.from('swipe_events').insert({user_id:user.id,partner_id:cur.id,direction:dir}).catch(()=>{})
    setSwipeDir(dir)
    setTimeout(()=>{setDeck(d=>d.slice(1));setSwipeDir(null);setDragX(0);setDragging(false);dragStart.current=null},280)
  }
  const hMD=e=>{dragStart.current=e.clientX;setDragging(true)}
  const hMM=e=>{if(dragging&&dragStart.current)setDragX(e.clientX-dragStart.current)}
  const hMU=()=>{if(Math.abs(dragX)>80)doSwipe(dragX>0?'right':'left');else setDragX(0);setDragging(false);dragStart.current=null}
  const handleAuth=async()=>{
    setAuthLoading(true);setAuthErr('')
    try{
      let res
      if(authMode==='signin'){res=await sb.auth.signInWithPassword({email,password})}
      else{res=await sb.auth.signUp({email,password})}
      if(res.error)setAuthErr(res.error.message)
    }catch(e){setAuthErr(e.message)}
    setAuthLoading(false)
  }
  const handlePartnerSignup=async()=>{
    setAuthLoading(true);setAuthErr('')
    try{
      const res=await sb.auth.signUp({email,password})
      if(res.error){setAuthErr(res.error.message);setAuthLoading(false);return}
      if(res.data?.user){
        const {error:insertErr}=await sb.from('partners').insert({name:bizName,category:bizCat,location:bizCity,bio:bizDesc,email,status:'pending',user_id:res.data.user.id});if(insertErr){setAuthErr(insertErr.message);setAuthLoading(false);return}
        setAuthMode('pending')
      }
    }catch(e){setAuthErr(e.message)}
    setAuthLoading(false)
  }
  if(loading)return(<div style={{fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',height:'100vh',display:'flex',alignItems:'center',justifyContent:'center',background:LT}}><div style={{textAlign:'center'}}><div style={{fontSize:52}}>🌿</div><div style={{color:G,fontWeight:700,marginTop:12}}>Loading HEHA...</div></div></div>)
  if(!user){
    const S={fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',minHeight:'100vh',display:'flex',alignItems:'center',justifyContent:'center',background:LT,padding:24}
    if(authMode==='role')return(<div style={S}><div style={{width:'100%'}}><div style={{textAlign:'center',marginBottom:32}}><div style={{fontSize:52}}>🌿</div><div style={{fontSize:26,fontWeight:800,color:BK}}>HEHA<span style={{color:OR}}>·</span>swipe</div><div style={{color:'#888',fontSize:16,marginTop:4}}>Tampa's healthy business community</div></div><div style={{marginBottom:12}}><button onClick={()=>setAuthMode('user-auth')} style={{...btn(G),marginBottom:12,display:'flex',alignItems:'center',justifyContent:'center',gap:10,padding:'18px',borderRadius:50}}>👤 I'm a Local User</button><button onClick={()=>setAuthMode('biz-auth')} style={{...btn('#fff','#333'),border:'1.5px solid #ddd',marginBottom:0,display:'flex',alignItems:'center',justifyContent:'center',gap:10,padding:'18px',borderRadius:50}}>🏪 I'm a Local Business</button></div><div style={{textAlign:'center',marginTop:8}}><button onClick={()=>setAuthMode('user-auth')} style={{background:'none',border:'none',color:'#888',fontSize:14,cursor:'pointer'}}>Already have an account? Sign in</button></div></div></div>)
    if(authMode==='forgot')return(<div style={S}><div style={{width:'100%'}}><button onClick={()=>setAuthMode('signin')} style={{background:'none',border:'none',fontSize:20,cursor:'pointer',marginBottom:16,color:CH}}>←</button><div style={{fontSize:22,fontWeight:800,color:CH,marginBottom:6}}>Reset your password</div><div style={{color:TP,fontSize:14,marginBottom:20,lineHeight:1.6}}>Enter your email and we'll send you a link to reset your password.</div><input style={inp} placeholder="Email" value={email} onChange={e=>setEmail(e.target.value)}/>{authErr&&<div style={{color:'#c0392b',fontSize:13,marginBottom:10}}>{authErr}</div>}<button onClick={handleForgot} disabled={authLoad||!email} style={pill(!email||authLoad?'#ccc':OR,'#fff',0)}>{authLoad?'Sending...':'Send reset link'}</button></div></div>)
if(authMode==='forgot_sent')return(<div style={S}><div style={{width:'100%',textAlign:'center'}}><div style={{fontSize:52}}>✉️</div><div style={{fontSize:22,fontWeight:800,color:CH,marginTop:16,marginBottom:8}}>Check your email</div><div style={{color:TP,fontSize:14,lineHeight:1.7}}>We sent a password reset link to <strong style={{color:CH}}>{email}</strong>. Click the link in the email to set a new password.</div><div style={{marginTop:16,padding:14,background:'#fff',borderRadius:14,border:'0.5px solid '+DV,fontSize:13,color:TP}}>Didn't get it? Check your spam folder or try again.</div><button onClick={()=>setAuthMode('signin')} style={{...pill(OW,DG,0),border:'1px solid '+DG,marginTop:20}}>Back to sign in</button></div></div>)
if(authMode==='pending')return(<div style={S}><div style={{width:'100%',textAlign:'center'}}><div style={{fontSize:52}}>⏳</div><div style={{fontSize:22,fontWeight:700,color:G,marginTop:16}}>Application received!</div><div style={{color:'#555',fontSize:15,marginTop:12,lineHeight:1.6}}>We'll review your listing and reach out within 48 hours. You'll be able to complete your profile and optionally sponsor the app after approval.</div><div style={{marginTop:24,padding:16,background:'#fff',borderRadius:12,border:'1px solid #eee'}}><div style={{fontSize:13,color:'#888'}}>Submitted for</div><div style={{fontWeight:700,color:BK,fontSize:16}}>{bizName}</div></div><button onClick={()=>{setAuthMode('role');setEmail('');setPassword('');setBizName('');setBizCity('');setBizDesc('')}} style={{...btn(LT,G),border:'1px solid '+G,marginTop:20}}>Back to home</button></div></div>)
    if(authMode==='user-auth'||authMode==='biz-auth'){const isBiz=authMode==='biz-auth';return(<div style={S}><div style={{padding:'24px 20px',maxWidth:390,margin:'0 auto',width:'100%'}}><button onClick={()=>setAuthMode('role')} style={{background:'none',border:'none',fontSize:22,cursor:'pointer',color:'#555',marginBottom:8}}>&#8592;</button><h2 style={{fontWeight:700,fontSize:22,marginBottom:4}}>{isBiz?'Business sign in':'Welcome back'}</h2><p style={{color:'#888',fontSize:14,marginBottom:24}}>{isBiz?'Sign in to manage your listing':'Sign in or create your account'}</p><div style={{display:'flex',background:'#f0f0f0',borderRadius:12,padding:3,marginBottom:20}}><button onClick={()=>{setAuthTab('phone');setAuthErr('')}} style={{flex:1,padding:'9px 0',borderRadius:10,border:'none',background:authTab==='phone'?'#fff':'transparent',fontWeight:authTab==='phone'?600:400,cursor:'pointer',fontSize:14,transition:'all 0.2s'}}>&#128241; Phone</button><button onClick={()=>{setAuthTab('email');setAuthErr('')}} style={{flex:1,padding:'9px 0',borderRadius:10,border:'none',background:authTab==='email'?'#fff':'transparent',fontWeight:authTab==='email'?600:400,cursor:'pointer',fontSize:14,transition:'all 0.2s'}}>&#128140; Email</button></div>{authTab==='phone'&&<div><div style={{position:'relative'}}><span style={{position:'absolute',left:14,top:'50%',transform:'translateY(-50%)',fontSize:14,color:'#555',fontWeight:600}}>+1</span><input style={{...inp,paddingLeft:40}} type='tel' inputMode='numeric' placeholder='(813) 555-0000' value={phone} onChange={e=>setPhone(e.target.value)} onKeyDown={e=>e.key==='Enter'&&handleSendOTP()}/></div></div>}{authTab==='email'&&<input style={inp} type='email' placeholder='you@example.com' value={email} onChange={e=>setEmail(e.target.value)} onKeyDown={e=>e.key==='Enter'&&handleSendOTP()}/>}{authErr&&<div style={{color:'#e33',fontSize:13,margin:'8px 0'}}>{authErr}</div>}<button onClick={handleSendOTP} disabled={authLoading||(authTab==='phone'?!phone:!email)} style={{width:'100%',padding:'14px',marginTop:12,borderRadius:30,border:'none',background:authLoading?'#ccc':'#3F8C5A',color:'#fff',fontSize:15,fontWeight:600,cursor:'pointer'}}>{authLoading?'Sending...':'Send verification code'}</button><div style={{display:'flex',alignItems:'center',gap:10,margin:'20px 0'}}><div style={{flex:1,height:'1px',background:'#e0e0e0'}}/><span style={{color:'#aaa',fontSize:12}}>or continue with</span><div style={{flex:1,height:'1px',background:'#e0e0e0'}}/></div><button onClick={()=>handleOAuth('google')} style={{width:'100%',padding:'12px 0',marginBottom:8,border:'1px solid #ddd',borderRadius:12,background:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}><svg width='18' height='18' viewBox='0 0 48 48'><path fill='#4285F4' d='M44.5 20H24v8.5h11.8C34.7 33.9 30.1 37 24 37c-7.2 0-13-5.8-13-13s5.8-13 13-13c3.1 0 5.9 1.1 8.1 2.9l6.4-6.4C34.6 4.1 29.6 2 24 2 11.8 2 2 11.8 2 24s9.8 22 22 22c11 0 21-8 21-22 0-1.3-.2-2.7-.5-4z'/></svg>Continue with Google</button><button onClick={()=>handleOAuth('apple')} style={{width:'100%',padding:'12px 0',marginBottom:8,border:'none',borderRadius:12,background:'#000',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}>🍎 Continue with Apple</button><button onClick={()=>handleOAuth('facebook')} style={{width:'100%',padding:'12px 0',marginBottom:isBiz?8:0,border:'none',borderRadius:12,background:'#1877F2',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}><svg width='18' height='18' viewBox='0 0 24 24' fill='white'><path d='M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z'/></svg>Continue with Facebook</button>{isBiz&&<button onClick={()=>handleOAuth('linkedin_oidc')} style={{width:'100%',padding:'12px 0',marginTop:0,border:'none',borderRadius:12,background:'#0077B5',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}><svg width='18' height='18' viewBox='0 0 24 24' fill='white'><path d='M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z'/></svg>Continue with LinkedIn</button>}</div></div>)}if(authMode==='otp-verify')return(<div style={S}><div style={{padding:'24px 20px',maxWidth:390,margin:'0 auto',width:'100%',textAlign:'center'}}><button onClick={()=>setAuthMode(otpType==='sms'?'user-auth':'user-auth')} style={{background:'none',border:'none',fontSize:22,cursor:'pointer',color:'#555',display:'block',marginBottom:16}}>&#8592;</button><div style={{fontSize:48,marginBottom:12}}>&#128241;</div><h2 style={{fontWeight:700,fontSize:22,marginBottom:8}}>Enter your code</h2><p style={{color:'#888',fontSize:14,marginBottom:28}}>We sent a 6-digit code to<br/><strong style={{color:'#333'}}>{otpContact}</strong></p><div style={{display:'flex',gap:8,justifyContent:'center',marginBottom:24}}>{[0,1,2,3,4,5].map(i=>(<input key={i} id={'otp'+i} type='tel' inputMode='numeric' maxLength={1} value={otp[i]||''} onChange={e=>{const v=e.target.value.replace(/\D/,'').slice(-1);const a=(otp+'      ').split('');a[i]=v;setOtp(a.slice(0,6).join('').trimEnd());if(v&&i<5)document.getElementById('otp'+(i+1))?.focus()}} onKeyDown={e=>{if(e.key==='Backspace'&&!otp[i]&&i>0){const a=(otp+'      ').split('');a[i-1]='';setOtp(a.slice(0,6).join('').trimEnd());document.getElementById('otp'+(i-1))?.focus()}}} style={{width:44,height:54,textAlign:'center',fontSize:24,fontWeight:700,border:otp[i]?'2px solid #3F8C5A':'1.5px solid #ddd',borderRadius:10,background:'#fff',outline:'none'}}/>))}</div>{authErr&&<div style={{color:'#e33',fontSize:13,marginBottom:12}}>{authErr}</div>}<button onClick={handleVerifyOTP} disabled={authLoading||otp.length<6} style={{width:'100%',padding:'14px',borderRadius:30,border:'none',background:otp.length<6?'#ccc':'#3F8C5A',color:'#fff',fontSize:15,fontWeight:600,cursor:otp.length<6?'default':'pointer'}}>{authLoading?'Verifying...':'Verify code'}</button><button onClick={handleResendOTP} style={{background:'none',border:'none',color:'#3F8C5A',fontSize:14,cursor:'pointer',marginTop:16,display:'block',width:'100%'}}>Didn&#39;t receive it? Resend</button></div></div>);if(authMode==='partner')return(<div style={{...S,alignItems:'flex-start',paddingTop:48}}><div style={{width:'100%'}}><button onClick={()=>setAuthMode('role')} style={{background:'none',border:'none',fontSize:22,cursor:'pointer',marginBottom:16}}>←</button><div style={{fontSize:22,fontWeight:800,color:BK,marginBottom:4}}>List your business</div><div style={{color:'#888',fontSize:14,marginBottom:24}}>We'll review and approve within 48 hours</div><input style={inp} placeholder="Business name" value={bizName} onChange={e=>setBizName(e.target.value)}/><select style={{...inp,marginBottom:10}} value={bizCat} onChange={e=>setBizCat(e.target.value)}>{BIZ_CATS.map(c=><option key={c}>{c}</option>)}</select><input style={inp} placeholder="City (e.g. Tampa)" value={bizCity} onChange={e=>setBizCity(e.target.value)}/><textarea style={{...inp,height:80,resize:'none'}} placeholder="Short description (optional)" value={bizDesc} onChange={e=>setBizDesc(e.target.value)}/><div style={{fontSize:13,color:'#888',marginBottom:12,lineHeight:1.5}}>Your login credentials</div><input style={inp} placeholder="Email" value={email} onChange={e=>setEmail(e.target.value)}/><input style={inp} type="password" placeholder="Password" value={password} onChange={e=>setPassword(e.target.value)}/>{authErr&&<div style={{color:RD,fontSize:13,marginBottom:10}}>{authErr}</div>}<button onClick={handlePartnerSignup} disabled={authLoading||!bizName||!email||!password} style={btn(authLoading||!bizName||!email||!password?'#ccc':G)}><div style={{margin:'20px 0 8px'}}><div style={{display:'flex',alignItems:'center',gap:8,marginBottom:14}}><div style={{flex:1,height:'1px',background:'#e0e0e0'}}/><span style={{color:'#aaa',fontSize:12,whiteSpace:'nowrap'}}>or sign in with</span><div style={{flex:1,height:'1px',background:'#e0e0e0'}}/></div><button onClick={()=>handleOAuth('google')} style={{width:'100%',padding:'10px 0',marginBottom:8,border:'1px solid #ddd',borderRadius:10,background:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}><svg width='16' height='16' viewBox='0 0 48 48'><path fill='#4285F4' d='M44.5 20H24v8.5h11.8C34.7 33.9 30.1 37 24 37c-7.2 0-13-5.8-13-13s5.8-13 13-13c3.1 0 5.9 1.1 8.1 2.9l6.4-6.4C34.6 4.1 29.6 2 24 2 11.8 2 2 11.8 2 24s9.8 22 22 22c11 0 21-8 21-22 0-1.3-.2-2.7-.5-4z'/></svg>Google</button><button onClick={()=>handleOAuth('apple')} style={{width:'100%',padding:'10px 0',marginBottom:8,border:'none',borderRadius:10,background:'#000',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}><svg width='16' height='16' viewBox='0 0 814 1000'><path fill='#fff' d='M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76 0-103.7 40.8-165.9 40.8s-105-37.5-155.5-120.8c-37-72.5-64-191.2-64-301 0-153.4 100-234.6 198-234.6 52 0 95.5 34.2 129.2 34.2 31.8 0 81.7-36.9 142.2-36.9 41.3 0 114.9 15.5 155.5 75zm-98.1-173.7c23.9-28.3 39.1-67.5 39.1-107.3 0-7.4-.6-14.5-1.6-20.6C638.2 47.3 605 62.5 585.4 87.5c-21.6 25.8-38.1 65.8-38.1 104.7 0 6.8.6 14.2 2.5 20.2 1.6.3 3.5.6 5.5.6 20.9 0 45.8-14.1 64.7-38.8z'/></svg>Apple</button><div style={{display:'flex',gap:8}}><button onClick={()=>handleOAuth('facebook')} style={{flex:1,padding:'10px 0',border:'none',borderRadius:10,background:'#1877F2',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:8,fontWeight:500}}><svg width='16' height='16' viewBox='0 0 24 24' fill='white'><path d='M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z'/></svg>Facebook</button><button onClick={()=>handleOAuth('linkedin_oidc')} style={{flex:1,padding:'10px 0',border:'none',borderRadius:10,background:'#0077B5',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:8,fontWeight:500}}><svg width='16' height='16' viewBox='0 0 24 24' fill='white'><path d='M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z'/></svg>LinkedIn</button></div></div>{authLoading?'Submitting...':'Submit application'}</button></div></div>)
    return(<div style={S}><div style={{width:'100%'}}><div style={{textAlign:'center',marginBottom:28}}><div style={{fontSize:52}}>🌿</div><div style={{fontSize:26,fontWeight:800,color:BK}}>HEHA<span style={{color:OR}}>·</span>swipe</div></div>{authMode==='signup'&&<button onClick={()=>setAuthMode('role')} style={{background:'none',border:'none',fontSize:20,cursor:'pointer',marginBottom:8,color:'#555',display:'flex',alignItems:'center',gap:4}}>&#8592; Back</button>}<input style={inp} placeholder="Email" value={email} onChange={e=>setEmail(e.target.value)}/><input style={inp} type="password" placeholder="Password" value={password} onChange={e=>setPassword(e.target.value)}/>{authErr&&<div style={{color:RD,fontSize:13,marginBottom:10}}>{authErr}</div>}<button onClick={handleAuth} disabled={authLoading} style={btn(authLoading?'#ccc':BK)}>{authLoading?'Loading...':authMode==='signin'?'Sign in':'Create account'}</button><div style={{textAlign:'center'}}><div style={{margin:'20px 0 8px'}}><div style={{display:'flex',alignItems:'center',gap:8,marginBottom:14}}><div style={{flex:1,height:'1px',background:'#e0e0e0'}}/><span style={{color:'#aaa',fontSize:12,whiteSpace:'nowrap'}}>or continue with</span><div style={{flex:1,height:'1px',background:'#e0e0e0'}}/></div><button onClick={()=>handleOAuth('google')} style={{width:'100%',padding:'11px 0',marginBottom:8,border:'1px solid #ddd',borderRadius:10,background:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}><svg width='18' height='18' viewBox='0 0 48 48'><path fill='#4285F4' d='M44.5 20H24v8.5h11.8C34.7 33.9 30.1 37 24 37c-7.2 0-13-5.8-13-13s5.8-13 13-13c3.1 0 5.9 1.1 8.1 2.9l6.4-6.4C34.6 4.1 29.6 2 24 2 11.8 2 2 11.8 2 24s9.8 22 22 22c11 0 21-8 21-22 0-1.3-.2-2.7-.5-4z'/></svg>Continue with Google</button><button onClick={()=>handleOAuth('apple')} style={{width:'100%',padding:'11px 0',marginBottom:8,border:'none',borderRadius:10,background:'#000',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}>🍎 Continue with Apple</button><button onClick={()=>handleOAuth('facebook')} style={{width:'100%',padding:'11px 0',marginBottom:8,border:'none',borderRadius:10,background:'#1877F2',color:'#fff',cursor:'pointer',fontSize:14,display:'flex',alignItems:'center',justifyContent:'center',gap:10,fontWeight:500}}><svg width='18' height='18' viewBox='0 0 24 24' fill='white'><path d='M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z'/></svg>Continue with Facebook</button></div><button onClick={handleForgot} style={{background:'none',border:'none',color:'#aaa',fontSize:12,cursor:'pointer',marginTop:4,display:'block',width:'100%',textAlign:'right'}}>Forgot password?</button><button onClick={()=>setAuthMode(authMode==='signin'?'signup':'signin')} style={{background:'none',border:'none',color:'#888',fontSize:14,cursor:'pointer'}}>{authMode==='signin'?'No account? Sign up':'Have account? Sign in'}</button></div></div></div>)
  }
  if(loading)return null
  const handleForgot=async()=>{setAuthLoad(true);setAuthErr('');const{error}=await sb.auth.resetPasswordForEmail(email,{redirectTo:'https://heha-swipe.vercel.app/'});if(error)setAuthErr(error.message);else setAuthMode('forgot_sent');setAuthLoad(false)};const handleSendOTP=async()=>{if(!email&&!phone){setAuthErr('Please enter your phone or email');return};setAuthErr('');setAuthLoading(true);try{if(authTab==='phone'){const d=phone.replace(/\D/g,'');const num=d.startsWith('1')?'+'+d:'+1'+d;const{error}=await sb.auth.signInWithOtp({phone:num});if(error)setAuthErr(error.message);else{setOtpContact(num);setOtpType('sms');setAuthMode('otp-verify');setOtp('');}} else {const{error}=await sb.auth.signInWithOtp({email,options:{shouldCreateUser:true}});if(error)setAuthErr(error.message);else{setOtpContact(email);setOtpType('email');setAuthMode('otp-verify');setOtp('');}}}catch(e){setAuthErr(e.message)};setAuthLoading(false)};const handleVerifyOTP=async()=>{if(otp.length<6){setAuthErr('Enter the full 6-digit code');return};setAuthErr('');setAuthLoading(true);try{const params=otpType==='sms'?{phone:otpContact,token:otp,type:'sms'}:{email:otpContact,token:otp,type:'email'};const{error}=await sb.auth.verifyOtp(params);if(error){setAuthErr(error.message);setOtp('')}}catch(e){setAuthErr(e.message)};setAuthLoading(false)};const handleResendOTP=async()=>{setOtp('');setAuthErr('');if(otpType==='sms'){await sb.auth.signInWithOtp({phone:otpContact})}else{await sb.auth.signInWithOtp({email:otpContact,options:{shouldCreateUser:true}})}};const handleOAuth=async(provider)=>{setAuthErr('');const{error}=await sb.auth.signInWithOAuth({provider,options:{redirectTo:'https://heha-swipe.vercel.app/'}});if(error)setAuthErr(error.message)};const signOut=()=>{setUserRole(null);setPartner(null);setAuthMode('role');sb.auth.signOut()}
const sendIce=async(uid)=>{setSent(s=>({...s,[uid]:true}));setStats(st=>({...st,ic:(st.ic||0)+1}))}
  if(screen==='main')return(
    <div style={{fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',height:'100vh',display:'flex',flexDirection:'column',background:LT,userSelect:'none'}}>
      <div style={{background:G,color:'#fff',padding:'14px 16px',display:'flex',justifyContent:'space-between',alignItems:'center',flexShrink:0}}>
        <span style={{fontWeight:800,fontSize:17}}>HEHA<span style={{color:OR}}>·</span>swipe</span>
        <button onClick={signOut} style={{background:'none',border:'1px solid rgba(255,255,255,0.4)',color:'#fff',borderRadius:20,padding:'4px 12px',fontSize:12,cursor:'pointer'}}>sign out</button>
      </div>
      {tab==='swipe'&&<>
        <div style={{display:'flex',gap:8,padding:'10px 12px',overflowX:'auto',flexShrink:0}}>
          {CATS.map(c=><button key={c} onClick={()=>setFilterCat(c)} style={{padding:'6px 14px',borderRadius:20,border:'none',background:filterCat===c?G:'#e8e4dc',color:filterCat===c?'#fff':BK,fontSize:13,cursor:'pointer',whiteSpace:'nowrap',fontWeight:filterCat===c?700:400}}>{c}</button>)}
        </div>
        <div style={{flex:1,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',padding:'0 16px'}}>
          {heartAnim&&<div style={{position:'fixed',top:'40%',left:'50%',transform:'translate(-50%,-50%)',fontSize:80,pointerEvents:'none',animation:'pop .6s ease-out',zIndex:99}}>❤️</div>}
          {cur?(
            <div onMouseDown={hMD} onMouseMove={hMM} onMouseUp={hMU} onMouseLeave={hMU} style={{width:'100%',maxWidth:360,background:'#fff',borderRadius:20,padding:20,boxShadow:'0 4px 24px rgba(0,0,0,0.10)',cursor:'grab',transform:`rotate(${cardRot}deg) translateX(${dragX*0.3}px)`,transition:dragging?'none':'transform .2s',position:'relative'}}>
              {swipeDir==='right'&&<div style={{position:'absolute',top:20,left:20,color:'#2ecc71',border:'3px solid #2ecc71',borderRadius:8,padding:'4px 12px',fontSize:20,fontWeight:800,transform:'rotate(-15deg)',opacity:.9}}>SAVE ❤️</div>}
              {swipeDir==='left'&&<div style={{position:'absolute',top:20,right:20,color:RD,border:'3px solid '+RD,borderRadius:8,padding:'4px 12px',fontSize:20,fontWeight:800,transform:'rotate(15deg)',opacity:.9}}>SKIP</div>}
              <div onClick={()=>setDetail(cur)} style={{cursor:'pointer'}}>
                <div style={{fontSize:48,textAlign:'center',marginBottom:8}}>{CAT[cur.category]?.i||'🌿'}</div>
                <div style={{fontWeight:800,fontSize:20,color:BK}}>{cur.name}</div>
                {cur.partner_type&&<div style={{display:'inline-block',background:LT,color:G,borderRadius:20,padding:'2px 10px',fontSize:12,fontWeight:700,marginTop:4}}>{cur.partner_type}</div>}
                <div style={{color:'#555',fontSize:14,marginTop:8,lineHeight:1.5}}>{cur.bio}</div>
                {cur.location&&<div style={{color:'#888',fontSize:13,marginTop:6}}>📍 {cur.location}</div>}
                {cur.featured_items?.length>0&&<div style={{marginTop:12}}><div style={{fontWeight:700,fontSize:13,color:G,marginBottom:6}}>Featured</div>{cur.featured_items.slice(0,2).map(t=><div key={t.id} style={{display:'flex',justifyContent:'space-between',fontSize:13,padding:'4px 0',borderBottom:'1px solid #f0ede6'}}><span>{t.emoji} {t.name}</span><span style={{fontWeight:700}}>${t.price}</span></div>)}</div>}
              </div>
              <div style={{display:'flex',gap:12,marginTop:16}}>
                <button onClick={()=>doSwipe('left')} style={{flex:1,height:56,borderRadius:'50%',border:'2px solid #eee',background:'#fff',fontSize:22,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}>✕</button>
                <button onClick={()=>doSwipe('right')} style={{flex:1,height:56,borderRadius:'50%',border:'2px solid #22c55e',background:'#fff',fontSize:22,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}>❤️</button>
              </div>
            </div>
          ):(
            <div style={{textAlign:'center',padding:40}}>
              <div style={{fontSize:52}}>🌱</div>
              <div style={{fontWeight:700,fontSize:18,color:BK,marginTop:12}}>No businesses yet</div>
              <div style={{color:'#888',fontSize:14,marginTop:8}}>Be the first to list your healthy business on HEHA</div>
              <button onClick={()=>{sb.auth.signOut();setAuthMode('partner')}} style={{...btn(G),marginTop:20,width:'auto',padding:'12px 24px'}}>List your business</button>
            </div>
          )}
        </div>
      </>}
      {tab==='favs'&&<div style={{flex:1,overflowY:'auto',padding:16}}>
        {favs.length===0?<div style={{textAlign:'center',marginTop:60,color:'#888'}}>No saves yet — swipe right to save ❤️</div>:
        favs.map(p=><div key={p.id} onClick={()=>setDetail(p)} style={{background:'#fff',borderRadius:16,padding:16,marginBottom:12,cursor:'pointer',boxShadow:'0 2px 8px rgba(0,0,0,0.06)'}}><div style={{display:'flex',gap:12,alignItems:'center'}}><div style={{fontSize:32}}>{p.emoji||'🌿'}</div><div><div style={{fontWeight:700,color:BK}}>{p.name}</div><div style={{color:'#888',fontSize:13}}>{p.location}</div></div></div></div>)
        }
      </div>}
      {tab==='profile'&&<div style={{flex:1,overflowY:'auto',padding:20}}>
        <div style={{background:'#fff',borderRadius:16,padding:20,marginBottom:12}}>
          <div style={{fontWeight:800,fontSize:18,color:BK,marginBottom:4}}>My account</div>
          <div style={{color:'#888',fontSize:14}}>{user.email}</div>
        </div>
        {profile&&<div style={{background:'#fff',borderRadius:16,padding:20,marginBottom:12}}>
          {profile.full_name&&<div style={{marginBottom:8}}><span style={{color:'#888',fontSize:13}}>Name</span><div style={{fontWeight:600,color:BK}}>{profile.full_name}</div></div>}
          {profile.phone&&<div style={{marginBottom:8}}><span style={{color:'#888',fontSize:13}}>Phone</span><div style={{fontWeight:600,color:BK}}>{profile.phone}</div></div>}
          {profile.location&&<div style={{marginBottom:8}}><span style={{color:'#888',fontSize:13}}>Location</span><div style={{fontWeight:600,color:BK}}>{profile.location}</div></div>}
          <div style={{background:LT,borderRadius:12,padding:'10px 14px',marginTop:8,borderLeft:'3px solid '+OR}}>
            <div style={{fontSize:12,color:'#888',marginBottom:2}}>Subscription</div>
            <div style={{fontWeight:700,color:profile.subscription_type&&profile.subscription_type!=='none'?G:'#888',fontSize:14}}>{profile.subscription_type&&profile.subscription_type!=='none'?profile.subscription_type:'No active subscription'}</div>
          </div>
        </div>}
        <div style={{background:'#fff',borderRadius:16,padding:20,marginBottom:12}}>
          <div style={{fontWeight:700,color:BK,marginBottom:8}}>Support local businesses</div>
          <div style={{color:'#888',fontSize:13,lineHeight:1.6,marginBottom:12}}>95% of every dollar you contribute goes directly to the local businesses listed on HEHA. We keep 5% to keep the platform running.</div>
          <button onClick={()=>setScreen('subscribe')} style={btn(OR)}>Choose a plan</button>
        </div>
        <button onClick={signOut} style={{...btn('transparent',RD),border:'1px solid '+RD}}>Sign out</button>
      </div>}
      <div style={{display:'flex',borderTop:'1px solid #e8e4dc',background:'#fff',flexShrink:0}}>
        {[['swipe','🔥','Discover'],['favs','❤️','Saved'],['profile','👤','Profile']].map(([t,ic,lb])=>
          <button key={t} onClick={()=>setTab(t)} style={{flex:1,padding:'10px 0',border:'none',background:'none',cursor:'pointer',color:tab===t?G:'#999',fontSize:12,display:'flex',flexDirection:'column',alignItems:'center',gap:2}}>
            <span style={{fontSize:20}}>{ic}</span><span style={{fontWeight:tab===t?700:400}}>{lb}</span>
          </button>)}
      </div>
      <style>{`@keyframes pop{0%{transform:translate(-50%,-50%) scale(0)}50%{transform:translate(-50%,-50%) scale(1.3)}100%{transform:translate(-50%,-50%) scale(0) }}`}</style>
      {detail&&(
        <div style={{position:'fixed',inset:0,background:'rgba(0,0,0,0.5)',display:'flex',alignItems:'flex-end',zIndex:200}} onClick={()=>setDetail(null)}>
          <div style={{background:'#fff',borderRadius:'24px 24px 0 0',padding:24,width:'100%',maxHeight:'80vh',overflowY:'auto'}} onClick={e=>e.stopPropagation()}>
            <div style={{fontSize:56,textAlign:'center'}}>{detail.emoji||'🌿'}</div>
            <div style={{fontWeight:800,fontSize:22,color:BK,marginTop:8}}>{detail.name}</div>
            {detail.location&&<div style={{color:'#888',fontSize:14,marginTop:4}}>📍 {detail.location}</div>}
            <div style={{color:'#555',fontSize:14,marginTop:12,lineHeight:1.6}}>{detail.bio}</div>
            {detail.instagram&&<a href={'https://instagram.com/'+detail.instagram.replace('@','')} target="_blank" rel="noreferrer" style={{display:'block',color:OR,fontWeight:700,marginTop:12,textDecoration:'none'}}>📸 @{detail.instagram.replace('@','')}</a>}
            {detail.featured_items?.length>0&&<div style={{marginTop:16}}><div style={{fontWeight:700,fontSize:15,color:G,marginBottom:8}}>Menu / items</div>{detail.featured_items.map(t=><div key={t.id} style={{display:'flex',justifyContent:'space-between',padding:'8px 0',borderBottom:'1px solid #f0ede6',fontSize:14}}><div><div style={{fontWeight:600}}>{t.emoji} {t.name}</div><div style={{color:'#888',fontSize:12,marginTop:2}}>{t.description}</div></div><div style={{fontWeight:700,color:G,marginLeft:12}}>${t.price}</div></div>)}</div>}
            {detail.partner_services?.length>0&&<div style={{marginTop:16}}><div style={{fontWeight:700,fontSize:15,color:G,marginBottom:8}}>Services</div>{detail.partner_services.map(s=><div key={s.id} style={{display:'flex',justifyContent:'space-between',padding:'8px 0',borderBottom:'1px solid #f0ede6',fontSize:14}}><span style={{fontWeight:600}}>{s.name}</span><span style={{fontWeight:700,color:G}}>${s.price}</span></div>)}</div>}
            <button onClick={()=>setDetail(null)} style={{...btn(G),marginTop:20}}>Close</button>
          </div>
        </div>
      )}
    </div>
  )
  if(screen==='subscribe')return(
    <div style={{fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',minHeight:'100vh',background:LT,padding:24}}>
      <button onClick={()=>setScreen('main')} style={{background:'none',border:'none',fontSize:22,cursor:'pointer',marginBottom:16}}>←</button>
      <div style={{fontSize:24,fontWeight:800,color:BK,marginBottom:8}}>Support local Tampa</div>
      <div style={{color:'#555',fontSize:15,lineHeight:1.7,marginBottom:24}}>95 cents of every dollar you put in goes directly to the local businesses you discover on HEHA. We keep just 5 cents to keep the platform running. You are not just a customer — you are a community investor.</div>
      <div style={{background:'#fff',borderRadius:16,padding:20,marginBottom:12,border:'2px solid '+G}}>
        <div style={{fontWeight:800,fontSize:17,color:G}}>Free tier</div>
        <div style={{color:'#555',fontSize:14,marginTop:6,lineHeight:1.5}}>Follow <strong>@heha.online</strong> on Instagram and get full access to discover Tampa's healthiest businesses.</div>
        <button style={{...btn(LT,G),border:'1px solid '+G,marginTop:12}}>Follow on Instagram →</button>
      </div>
      <div style={{background:'#fff',borderRadius:16,padding:20,marginBottom:12,border:'2px solid '+OR}}>
        <div style={{fontWeight:800,fontSize:17,color:OR}}>Community supporter — $1+/month</div>
        <div style={{color:'#555',fontSize:14,marginTop:6,lineHeight:1.5}}>Choose your amount. Every dollar split: 95% to local businesses, 5% to HEHA.</div>
        <button style={{...btn(OR),marginTop:12}}>Choose my amount →</button>
      </div>
      <div style={{color:'#aaa',fontSize:12,textAlign:'center',marginTop:8}}>Payment processing coming soon</div>
    </div>
  )
  return null
}