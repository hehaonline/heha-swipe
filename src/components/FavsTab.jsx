import{G,DG,TP,OW,CAT,SG}from'../lib/constants'
export default function FavsTab({favs,setDetail}){
  return(
    <div style={{flex:1,overflowY:'auto',padding:16,background:OW}}>
      {favs.length===0?(
        <div style={{display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',height:'60vh',textAlign:'center'}}>
          <div style={{fontSize:48,marginBottom:12}}>♥️</div>
          <div style={{fontWeight:700,fontSize:18,color:DG,marginBottom:8}}>No saved businesses yet</div>
          <div style={{color:TP,fontSize:14}}>Swipe right on businesses you love to save them here.</div>
        </div>
      ):(
        <div style={{display:'flex',flexDirection:'column',gap:12}}>
          {favs.map(p=>(
            <div key={p.id}onClick={()=>setDetail(p)}style={{background:'#fff',borderRadius:16,overflow:'hidden',boxShadow:'0 2px 12px rgba(0,0,0,0.07)',cursor:'pointer',display:'flex',alignItems:'center',gap:0}}>
              <div style={{background:CAT[p.category]?.g||'linear-gradient(135deg,#2d6a4f,#1b4332)',width:64,minHeight:72,display:'flex',alignItems:'center',justifyContent:'center',fontSize:28,flexShrink:0}}>
                {CAT[p.category]?.i||'Ἶ2'}
              </div>
              <div style={{padding:'12px 16px',flex:1}}>
                <div style={{fontWeight:700,fontSize:16,color:'#111'}}>{p.name}</div>
                <div style={{display:'flex',gap:8,marginTop:4,alignItems:'center'}}>
                  <span style={{background:SG,color:DG,padding:'2px 8px',borderRadius:8,fontSize:12,fontWeight:600}}>{p.category}</span>
                  {p.neighborhood&&<span style={{color:TP,fontSize:13}}>{p.neighborhood}</span>}
                </div>
                {p.tagline&&<div style={{color:TP,fontSize:12,marginTop:4,fontStyle:'italic'}}>“{p.tagline}”</div>}
              </div>
              <div style={{padding:'0 16px',color:G,fontSize:20}}>❯</div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
