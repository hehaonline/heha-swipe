import{G,OW,DG,TP,btn}from'../lib/constants'
export default function ProfileTab({user,profile,partner,userRole,stats,signOut}){
return(<div style={{flex:1,overflowY:'auto',background:OW}}>
<div style={{background:'linear-gradient(135deg,#173F2A,#3F8C5A)',padding:'32px 24px 24px',textAlign:'center'}}>
<div style={{width:72,height:72,borderRadius:36,background:'rgba(255,255,255,0.2)',display:'flex',alignItems:'center',justifyContent:'center',fontSize:32,margin:'0 auto 12px'}}>{String.fromCodePoint(0x1F9D1)}</div>
<div style={{fontWeight:800,fontSize:20,color:'#fff'}}>{profile?.full_name||user?.email?.split('@')[0]||'Hey!'}</div>
<div style={{color:'rgba(255,255,255,0.75)',fontSize:14,marginTop:4}}>{user?.email}</div>
<div style={{display:'inline-block',background:'rgba(255,255,255,0.15)',color:'#fff',padding:'4px 14px',borderRadius:20,fontSize:12,fontWeight:600,marginTop:8}}>{userRole==='partner'?'Ἶ2 Business Partner':'ᾝ1 Local Member'}</div>
</div>
<div style={{padding:24}}>
{userRole==='partner'&&partner&&(<div style={{background:'#fff',borderRadius:16,padding:20,marginBottom:16,boxShadow:'0 2px 12px rgba(0,0,0,0.06)'}}>
<div style={{fontWeight:700,fontSize:16,color:DG,marginBottom:12}}>Ἶ2 Your Business</div>
<div style={{fontWeight:800,fontSize:18,color:'#111'}}>{partner.name}</div>
<div style={{color:TP,fontSize:14,marginTop:4}}>{partner.category} · {partner.neighborhood||partner.location}</div>
<div style={{display:'flex',gap:16,marginTop:16}}>{[['Swipes','ὄb',partner.total_swipes||0],['Saves','❤️',partner.total_saves||0],['Views','ὄ1️',partner.total_profile_views||0]].map(([lb,ic,v])=>(<div key={lb}style={{flex:1,textAlign:'center'}}><div style={{fontSize:20}}>{ic}</div><div style={{fontWeight:700,fontSize:18,color:G}}>{v}</div><div style={{fontSize:12,color:TP}}>{lb}</div></div>))}</div>
<div style={{marginTop:12,padding:'8px 12px',background:'#f5f0e8',borderRadius:10,display:'flex',justifyContent:'space-between'}}><span style={{fontSize:13,color:TP}}>Status</span><span style={{fontWeight:700,fontSize:13,color:partner.status==='live'?G:'#e67e22'}}>{partner.status==='live'?'✅ Live':'⏳ Pending'}</span></div>
</div>)}
{stats.ic>0&&<div style={{background:'#fff',borderRadius:16,padding:20,marginBottom:16,boxShadow:'0 2px 12px rgba(0,0,0,0.06)'}}><div style={{fontWeight:700,fontSize:16,color:DG,marginBottom:4}}>❤️ Activity</div><div style={{color:TP,fontSize:14}}>You've sent {stats.ic} ice breaker{stats.ic!==1?'s':''} to local businesses!</div></div>}
<button onClick={signOut}style={{...btn('#f5f0e8','#c0392b'),marginTop:8}}>Sign out</button>
</div></div>)}
