import{useState,useEffect,useRef}from'react'
import{createClient}from'@supabase/supabase-js'
const sb=createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_ANON_KEY)
const G='#1e4d1e',OR='#e07a2a',LT='#f5f0e8',BK='#111'
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
  const[authMode,setAuthMode]=useState('signin')
  const[email,setEmail]=useState('')
  const[password,setPassword]=useState('')
  const[authErr,setAuthErr]=useState('')
  const[authLoading,setAuthLoading]=useState(false)
  const[screen,setScreen]=useState('main')
  const[step,setStep]=useState(0)
  const[pd,setPd]=useState({name:'',category:'',location:'',contact:'',instagram:'',bio:'',services:'',contribution:39})
  const dragStart=useRef(null)
  useEffect(()=>{
    const{data:{subscription}}=sb.auth.onAuthStateChange((_,s)=>{setUser(s?.user??null);setLoading(false)})
    return()=>subscription.unsubscribe()
  },[])
  useEffect(()=>{if(user)loadPartners()},[user,filterCat])
  const loadPartners=async()=>{
    try{
      let q=sb.from('partners').select('*,featured_items(id,name,description,price,emoji),partner_services(id,name,price)').eq('status','live')
      if(filterCat!=='All')q=q.eq('category',filterCat)
      const{data,error}=await q
      if(!error)setDeck(data||[])
    }catch(e){console.log(e)}
  }
  const doSwipe=async(dir)=>{
    const c=deck[0];if(!c)return
    setSwipeDir(dir)
    if(dir==='right'){setHeartAnim(true);setTimeout(()=>setHeartAnim(false),800);setFavs(f=>f.find(x=>x.id===c.id)?f:[...f,c]);if(user)await sb.from('saves').upsert({user_id:user.id,partner_id:c.id})}
    if(user)await sb.from('swipe_events').insert({user_id:user.id,partner_id:c.id,direction:dir}).catch(()=>{})
    setTimeout(()=>{setDeck(d=>d.slice(1));setSwipeDir(null);setDragX(0)},280)
  }
  const hMD=e=>{dragStart.current=e.clientX;setDragging(true)}
  const hMM=e=>{if(dragging&&dragStart.current)setDragX(e.clientX-dragStart.current)}
  const hMU=()=>{if(Math.abs(dragX)>80)doSwipe(dragX>0?'right':'left');else setDragX(0);setDragging(false);dragStart.current=null}
  const handleAuth=async()=>{
    setAuthLoading(true);setAuthErr('')
    try{let res;if(authMode==='signin'){res=await sb.auth.signInWithPassword({email,password})}else{res=await sb.auth.signUp({email,password})};if(res.error)setAuthErr(res.error.message)}catch(e){setAuthErr(e.message)}
    setAuthLoading(false)
  }
  const cardRot=swipeDir==='right'?15:swipeDir==='left'?-15:dragging?dragX*0.05:0
  const cur=deck[0]
  const CATS=['All','Restaurant','Vendor','Coach','Service','Activity']
  if(loading)return <div style={{fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',height:'100vh',display:'flex',alignItems:'center',justifyContent:'center',background:LT}}><div style={{textAlign:'center'}}><div style={{fontSize:52}}>🌿</div><div style={{color:G,fontWeight:700,marginTop:12}}>Loading HEHA...</div></div></div>
  if(!user)return(
    <div style={{fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',minHeight:'100vh',background:'#fff',display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',padding:'40px 28px'}}>
      <div style={{fontSize:52,marginBottom:8}}>🌿</div>
      <div style={{fontWeight:800,fontSize:28,color:BK,marginBottom:4}}>HEHA<span style={{color:OR}}>•</span>swipe</div>
      <div style={{fontSize:14,color:'#aaa',marginBottom:36,textAlign:'center'}}>Tampa's healthy business community</div>
      <input value={email} onChange={e=>setEmail(e.target.value)} placeholder='Email' type='email' style={{width:'100%',padding:'14px',borderRadius:12,border:'1.5px solid #ddd',fontSize:15,marginBottom:10,boxSizing:'border-box',outline:'none'}}/>
      <input value={password} onChange={e=>setPassword(e.target.value)} placeholder='Password' type='password' style={{width:'100%',padding:'14px',borderRadius:12,border:'1.5px solid #ddd',fontSize:15,marginBottom:14,boxSizing:'border-box',outline:'none'}}/>
      {authErr&&<div style={{color:'#ef4444',fontSize:13,marginBottom:10}}>{authErr}</div>}
      <button onClick={handleAuth} disabled={authLoading} style={{width:'100%',padding:'15px',borderRadius:30,border:'none',background:BK,color:'#fff',fontSize:16,fontWeight:700,cursor:'pointer',marginBottom:12}}>{authLoading?'Loading...':authMode==='signin'?'Sign in':'Create account'}</button>
      <button onClick={()=>setAuthMode(m=>m==='signin'?'signup':'signin')} style={{background:'none',border:'none',color:'#888',fontSize:14,cursor:'pointer'}}>{authMode==='signin'?'No account? Sign up':'Have account? Sign in'}</button>
    </div>
  )
  return(
    <div style={{fontFamily:'sans-serif',maxWidth:390,margin:'0 auto',minHeight:'100vh',background:LT,display:'flex',flexDirection:'column'}}>
      {detail&&<div style={{position:'fixed',inset:0,background:'rgba(0,0,0,0.7)',zIndex:100,display:'flex',alignItems:'flex-end',maxWidth:390,margin:'0 auto'}} onClick={()=>setDetail(null)}><div style={{background:'#fff',width:'100%',borderRadius:'20px 20px 0 0',padding:'20px',maxHeight:'85vh',overflowY:'auto'}} onClick={e=>e.stopPropagation()}><div style={{display:'flex',justifyContent:'space-between',marginBottom:12}}><div style={{fontWeight:800,fontSize:18}}>{detail.name}</div><button onClick={()=>setDetail(null)} style={{background:'#f5f5f5',border:'none',borderRadius:'50%',width:32,height:32,cursor:'pointer'}}>×</button></div><div style={{background:detail.color||G,borderRadius:12,padding:'16px',marginBottom:12,display:'flex',gap:12,alignItems:'center'}}><span style={{fontSize:36}}>{detail.photo_emoji||'🌿'}</span><div><div style={{color:'#fff',fontWeight:700}}>{detail.category}</div><div style={{color:'rgba(255,255,255,0.8)',fontSize:13}}>📍 {detail.location}</div></div></div><div style={{fontSize:14,color:'#555',lineHeight:1.6,marginBottom:12}}>{detail.bio}</div>{(detail.featured_items||[]).length>0&&<div style={{marginBottom:12}}><div style={{fontWeight:700,fontSize:14,marginBottom:8}}>Featured via HEHA</div>{(detail.featured_items||[]).map(i=><div key={i.id} style={{display:'flex',alignItems:'center',gap:10,background:LT,borderRadius:10,padding:'10px',marginBottom:6}}><span style={{fontSize:24}}>{i.emoji||'🍽️'}</span><div style={{flex:1}}><div style={{fontWeight:600,fontSize:13}}>{i.name}</div><div style={{fontSize:12,color:'#888'}}>{i.description}</div></div><div style={{fontWeight:700,color:OR}}>{i.price===0?'Free':'$'+Number(i.price).toFixed(2)}</div></div>)}</div>}{detail.heha_partner&&<button style={{width:'100%',padding:'14px',borderRadius:12,border:'none',background:G,color:'#fff',fontSize:14,cursor:'pointer',fontWeight:700,marginTop:8}}>Order via HEHA →</button>}</div></div>}
      <div style={{flex:1,overflowY:'auto'}}>
        {tab==='swipe'&&<div style={{display:'flex',flexDirection:'column',minHeight:'100vh'}}>
          <div style={{background:G,padding:'16px 20px 12px',display:'flex',alignItems:'center',justifyContent:'space-between'}}><span style={{color:'#fff',fontWeight:800,fontSize:22}}>HEHA<span style={{color:OR}}>•</span>swipe</span><button onClick={()=>sb.auth.signOut()} style={{background:'transparent',border:'1px solid rgba(255,255,255,0.3)',borderRadius:6,color:'#fff',fontSize:11,padding:'4px 8px',cursor:'pointer'}}>sign out</button></div>
          <div style={{display:'flex',gap:6,overflowX:'auto',padding:'12px 16px 8px',scrollbarWidth:'none'}}>{CATS.map(c=><button key={c} onClick={()=>setFilterCat(c)} style={{flexShrink:0,padding:'6px 14px',borderRadius:20,border:'none',background:filterCat===c?G:'#fff',color:filterCat===c?'#fff':'#555',fontSize:12,fontWeight:filterCat===c?700:400,cursor:'pointer'}}>{c}</button>)}</div>
          <div style={{flex:1,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',padding:'0 16px 8px',position:'relative'}}>
            {heartAnim&&<div style={{position:'absolute',top:'30%',fontSize:72,zIndex:50,pointerEvents:'none'}}>❤️</div>}
            {deck.length===0?<div style={{textAlign:'center',padding:30}}><div style={{fontSize:48,marginBottom:14}}>🌱</div><div style={{fontWeight:800,fontSize:20,color:BK,marginBottom:6}}>No businesses yet</div><div style={{fontSize:14,color:'#888',marginBottom:20}}>Be the first to list your healthy business on HEHA</div><button onClick={()=>{setScreen('onboard');setStep(0)}} style={{background:OR,border:'none',borderRadius:25,color:'#fff',padding:'13px 28px',fontSize:14,cursor:'pointer',fontWeight:700}}>List your business</button></div>:(
            <>{deck[1]&&<div style={{width:'88%',height:420,borderRadius:20,background:'#fff',border:'0.5px solid #ddd',position:'absolute',marginTop:8,zIndex:0}}/>}
            <div onMouseDown={hMD} onMouseMove={hMM} onMouseUp={hMU} onMouseLeave={hMU} style={{width:'92%',borderRadius:22,background:'#fff',border:'0.5px solid #ddd',overflow:'hidden',cursor:'grab',userSelect:'none',position:'relative',zIndex:1,transform:`rotate(${cardRot}deg) translateX(${swipeDir?'':dragX}px)`,opacity:swipeDir?0:1,transition:swipeDir?'all 0.28s':dragging?'none':'transform 0.15s'}}>
              {dragX>40&&<div style={{position:'absolute',top:20,left:16,background:'#22c55e',color:'#fff',borderRadius:8,padding:'5px 14px',fontSize:15,fontWeight:800,zIndex:10,transform:'rotate(-12deg)'}}>❤️ SAVE</div>}
              {dragX<-40&&<div style={{position:'absolute',top:20,right:16,background:'#ef4444',color:'#fff',borderRadius:8,padding:'5px 14px',fontSize:15,fontWeight:800,zIndex:10,transform:'rotate(12deg)'}}>✕ PASS</div>}
              <button onClick={e=>{e.stopPropagation();setDetail(cur)}} style={{position:'absolute',top:12,right:12,zIndex:10,width:34,height:34,borderRadius:'50%',background:'rgba(255,255,255,0.25)',border:'1.5px solid rgba(255,255,255,0.5)',color:'#fff',fontSize:15,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}>ℹ</button>
              <div style={{background:cur.color||G,padding:'26px 20px 18px',display:'flex',flexDirection:'column',alignItems:'center'}}><span style={{fontSize:52,marginBottom:6}}>{cur.photo_emoji||'🌿'}</span><div style={{color:'#fff',fontWeight:800,fontSize:18,textAlign:'center'}}>{cur.name}</div><div style={{color:'rgba(255,255,255,0.8)',fontSize:13,marginTop:3}}>{cur.category}</div>{cur.heha_partner&&<span style={{background:OR,color:'#fff',fontSize:10,borderRadius:4,padding:'2px 7px',marginTop:6,fontWeight:700}}>HEHA Partner</span>}</div>
              <div style={{padding:'14px 16px'}}><div style={{fontSize:13,color:'#555',marginBottom:10,lineHeight:1.6}}>{cur.bio}</div><div style={{display:'flex',flexWrap:'wrap',gap:5,marginBottom:8}}>{(cur.tags||[]).map(t=><span key={t} style={{background:LT,color:G,fontSize:11,borderRadius:5,padding:'3px 9px',fontWeight:600}}>{t}</span>)}</div><div style={{fontSize:12,color:'#aaa'}}>📍 {cur.location}</div></div>
            </div>
            <div style={{display:'flex',gap:18,justifyContent:'center',padding:'14px 0',zIndex:2}}><button onClick={()=>doSwipe('left')} style={{width:56,height:56,borderRadius:'50%',border:'2px solid #ef4444',background:'#fff',fontSize:22,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}>✕</button><button onClick={()=>doSwipe('right')} style={{width:56,height:56,borderRadius:'50%',border:'2px solid #22c55e',background:'#fff',fontSize:22,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}>❤️</button></div></>
            )}
          </div>
        </div>}
        {tab==='favorites'&&<div><div style={{background:G,padding:'16px 20px 12px'}}><div style={{color:'#fff',fontWeight:800,fontSize:22}}>HEHA<span style={{color:OR}}>•</span>saved</div></div><div style={{padding:16}}>{favs.length===0&&<div style={{color:'#888',fontSize:15,textAlign:'center',marginTop:60}}>Swipe right on businesses you love ❤️</div>}{favs.map(b=><div key={b.id} onClick={()=>setDetail(b)} style={{background:'#fff',borderRadius:16,border:'0.5px solid #ddd',marginBottom:10,overflow:'hidden',cursor:'pointer'}}><div style={{background:b.color||G,padding:'14px 16px',display:'flex',alignItems:'center',gap:12}}><span style={{fontSize:28}}>{b.photo_emoji||'🌿'}</span><div style={{flex:1}}><div style={{color:'#fff',fontWeight:700,fontSize:15}}>{b.name}</div><div style={{color:'rgba(255,255,255,0.75)',fontSize:12}}>{b.category}</div></div>{b.heha_partner&&<span style={{background:OR,color:'#fff',fontSize:10,borderRadius:4,padding:'2px 7px',fontWeight:700}}>HEHA</span>}</div><div style={{padding:'10px 16px',display:'flex',justifyContent:'space-between'}}><div style={{display:'flex',gap:5}}>{(b.tags||[]).slice(0,2).map(t=><span key={t} style={{background:LT,color:G,fontSize:11,borderRadius:5,padding:'3px 8px',fontWeight:600}}>{t}</span>)}</div><span style={{fontSize:12,color:G,fontWeight:700}}>View →</span></div></div>)}</div></div>}
        {tab==='profile'&&<div style={{background:'#1a1a1a',minHeight:'100vh',padding:'24px 20px'}}><div style={{display:'flex',alignItems:'center',gap:14,marginBottom:24,paddingBottom:20,borderBottom:'0.5px solid rgba(255,255,255,0.1)'}}><div style={{width:64,height:64,borderRadius:'50%',background:G,display:'flex',alignItems:'center',justifyContent:'center',fontSize:28}}>🌿</div><div><div style={{fontWeight:800,fontSize:18,color:'#fff'}}>{user.email?.split('@')[0]}</div><div style={{fontSize:13,color:'rgba(255,255,255,0.5)'}}>{user.email}</div></div></div><button onClick={()=>{setScreen('onboard');setStep(0)}} style={{width:'100%',padding:'15px',borderRadius:14,border:'none',background:OR,color:'#fff',fontSize:15,cursor:'pointer',fontWeight:700,marginBottom:12}}>List my business 🏪</button><button onClick={()=>sb.auth.signOut()} style={{width:'100%',padding:'15px',borderRadius:14,border:'none',background:'#2a2a2a',color:'rgba(255,255,255,0.8)',fontSize:15,cursor:'pointer',fontWeight:600,marginBottom:12}}>Log out</button><div style={{textAlign:'center',marginTop:16}}><div style={{fontSize:22}}>🌿</div><div style={{fontSize:12,color:'rgba(255,255,255,0.3)',marginTop:4}}>HEHA Swipe v1.0.0</div></div></div>}
      </div>
      <div style={{background:'#fff',borderTop:'0.5px solid #eee',display:'flex',padding:'10px 0 18px',position:'sticky',bottom:0}}>{[{id:'swipe',icon:'🔥',label:'Discover'},{id:'favorites',icon:'❤️',label:favs.length?`Saved (${favs.length})`:'Saved'},{id:'profile',icon:'👤',label:'Profile'}].map(t=><button key={t.id} onClick={()=>setTab(t.id)} style={{flex:1,border:'none',background:'transparent',cursor:'pointer',display:'flex',flexDirection:'column',alignItems:'center',gap:3,padding:0}}><span style={{fontSize:20}}>{t.icon}</span><span style={{fontSize:10,color:tab===t.id?G:'#aaa',fontWeight:tab===t.id?700:400}}>{t.label}</span></button>)}</div>
    </div>
  )
}
