import{useState,useEffect,useRef}from'react'
import{createClient}from'@supabase/supabase-js'
const sb=createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_ANON_KEY)
const G='#1e4d1e',OR='#e07a2a',LT='#f5f0e8',BK='#111',RD='#c0392b'
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
  const[email,setEmail]=useState('')
  const[password,setPassword]=useState('')
  const[authErr,setAuthErr]=useState('')
  const[authLoading,setAuthLoading]=useState(false)
  const[screen,setScreen]=useState('main')
  const[profile,setProfile]=useState(null)
  const[bizName,setBizName]=useState('')
  const[bizCat,setBizCat]=useState('Restaurant')
  const[bizCity,setBizCity]=useState('')
  const[bizDesc,setBizDesc]=useState('')
  const dragStart=useRef(null)
  const CATS=['All','Restaurant','Vendor','Coach','Service','Activity']
  const BIZ_CATS=['Restaurant','Vendor','Coach','Service','Activity']
  useEffect(()=>{
    const{data:{subscription}}=sb.auth.onAuthStateChange((_,s)=>{setUser(s?.user??null);setLoading(false)})
    return()=>subscription.unsubscribe()
  },[])
  useEffect(()=>{if(user)loadProfile();if(user)loadPartners()},[user,filterCat])
  const loadProfile=async()=>{
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
        await sb.from('partners').insert({name:bizName,category:bizCat,location:bizCity,bio:bizDesc,email,status:'pending',user_id:res.data.user.id}).catch(()=>{})
        setAuthMode('pending')
      }
    }catch(e){setAuthErr(e.message)}
    setAuthLoading(false)
  }
  if(loading)return(<div style={{fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',height:'100vh',display:'flex',alignItems:'center',justifyContent:'center',background:LT}}><div style={{textAlign:'center'}}><div style={{fontSize:52}}>🌿</div><div style={{color:G,fontWeight:700,marginTop:12}}>Loading HEHA...</div></div></div>)
  if(!user){
    const S={fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',minHeight:'100vh',display:'flex',alignItems:'center',justifyContent:'center',background:LT,padding:24}
    if(authMode==='role')return(<div style={S}><div style={{width:'100%'}}><div style={{textAlign:'center',marginBottom:32}}><div style={{fontSize:52}}>🌿</div><div style={{fontSize:26,fontWeight:800,color:BK}}>HEHA<span style={{color:OR}}>·</span>swipe</div><div style={{color:'#888',fontSize:16,marginTop:4}}>Tampa's healthy business community</div></div><div style={{marginBottom:12}}><button onClick={()=>setAuthMode('signup')} style={{...btn(G),marginBottom:12,display:'flex',alignItems:'center',justifyContent:'center',gap:10,padding:'18px',borderRadius:50}}>👤 I'm a Local User</button><button onClick={()=>setAuthMode('partner')} style={{...btn('#fff','#333'),border:'1.5px solid #ddd',marginBottom:0,display:'flex',alignItems:'center',justifyContent:'center',gap:10,padding:'18px',borderRadius:50}}>🏪 I'm a Local Business</button></div><div style={{textAlign:'center',marginTop:8}}><button onClick={()=>setAuthMode('signin')} style={{background:'none',border:'none',color:'#888',fontSize:14,cursor:'pointer'}}>Already have an account? Sign in</button></div></div></div>)
    if(authMode==='pending')return(<div style={S}><div style={{width:'100%',textAlign:'center'}}><div style={{fontSize:52}}>⏳</div><div style={{fontSize:22,fontWeight:700,color:G,marginTop:16}}>Application received!</div><div style={{color:'#555',fontSize:15,marginTop:12,lineHeight:1.6}}>We'll review your listing and reach out within 48 hours. You'll be able to complete your profile and optionally sponsor the app after approval.</div><div style={{marginTop:24,padding:16,background:'#fff',borderRadius:12,border:'1px solid #eee'}}><div style={{fontSize:13,color:'#888'}}>Submitted for</div><div style={{fontWeight:700,color:BK,fontSize:16}}>{bizName}</div></div><button onClick={()=>{setAuthMode('role');setEmail('');setPassword('');setBizName('');setBizCity('');setBizDesc('')}} style={{...btn(LT,G),border:'1px solid '+G,marginTop:20}}>Back to home</button></div></div>)
    if(authMode==='partner')return(<div style={{...S,alignItems:'flex-start',paddingTop:48}}><div style={{width:'100%'}}><button onClick={()=>setAuthMode('role')} style={{background:'none',border:'none',fontSize:22,cursor:'pointer',marginBottom:16}}>←</button><div style={{fontSize:22,fontWeight:800,color:BK,marginBottom:4}}>List your business</div><div style={{color:'#888',fontSize:14,marginBottom:24}}>We'll review and approve within 48 hours</div><input style={inp} placeholder="Business name" value={bizName} onChange={e=>setBizName(e.target.value)}/><select style={{...inp,marginBottom:10}} value={bizCat} onChange={e=>setBizCat(e.target.value)}>{BIZ_CATS.map(c=><option key={c}>{c}</option>)}</select><input style={inp} placeholder="City (e.g. Tampa)" value={bizCity} onChange={e=>setBizCity(e.target.value)}/><textarea style={{...inp,height:80,resize:'none'}} placeholder="Short description (optional)" value={bizDesc} onChange={e=>setBizDesc(e.target.value)}/><div style={{fontSize:13,color:'#888',marginBottom:12,lineHeight:1.5}}>Your login credentials</div><input style={inp} placeholder="Email" value={email} onChange={e=>setEmail(e.target.value)}/><input style={inp} type="password" placeholder="Password" value={password} onChange={e=>setPassword(e.target.value)}/>{authErr&&<div style={{color:RD,fontSize:13,marginBottom:10}}>{authErr}</div>}<button onClick={handlePartnerSignup} disabled={authLoading||!bizName||!email||!password} style={btn(authLoading||!bizName||!email||!password?'#ccc':G)}>{authLoading?'Submitting...':'Submit application'}</button></div></div>)
    return(<div style={S}><div style={{width:'100%'}}><div style={{textAlign:'center',marginBottom:28}}><div style={{fontSize:52}}>🌿</div><div style={{fontSize:26,fontWeight:800,color:BK}}>HEHA<span style={{color:OR}}>·</span>swipe</div></div>{authMode==='signup'&&<button onClick={()=>setAuthMode('role')} style={{background:'none',border:'none',fontSize:20,cursor:'pointer',marginBottom:8,color:'#555',display:'flex',alignItems:'center',gap:4}}>&#8592; Back</button>}<input style={inp} placeholder="Email" value={email} onChange={e=>setEmail(e.target.value)}/><input style={inp} type="password" placeholder="Password" value={password} onChange={e=>setPassword(e.target.value)}/>{authErr&&<div style={{color:RD,fontSize:13,marginBottom:10}}>{authErr}</div>}<button onClick={handleAuth} disabled={authLoading} style={btn(authLoading?'#ccc':BK)}>{authLoading?'Loading...':authMode==='signin'?'Sign in':'Create account'}</button><div style={{textAlign:'center'}}><button onClick={()=>setAuthMode(authMode==='signin'?'signup':'signin')} style={{background:'none',border:'none',color:'#888',fontSize:14,cursor:'pointer'}}>{authMode==='signin'?'No account? Sign up':'Have account? Sign in'}</button></div></div></div>)
  }
  if(loading)return null
  const signOut=()=>{setAuthMode('role');sb.auth.signOut()}
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
                <div style={{fontSize:48,textAlign:'center',marginBottom:8}}>{cur.emoji||'🌿'}</div>
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
      </>;}
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