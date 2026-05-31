import{G,CAT,OW,CH,SG,DG,TP,RD,btn}from'../lib/constants'
export default function SwipeTab({deck,filterCat,setFilterCat,heartAnim,dragX,dragging,hMD,hTD,hTM,hTU,doSwipe,setDetail,loadDeck}){
  const cur=deck[0]||null
  return(
    <div style={{flex:1,display:'flex',flexDirection:'column',overflow:'hidden'}}>
      <div style={{display:'flex',gap:8,padding:'10px 16px',overflowX:'auto',background:OW,borderBottom:'1px solid #e0d8cc'}}>
        {['All',...Object.keys(CAT)].map(c=>
          <button key={c}onClick={()=>setFilterCat(c)}style={{flex:'none',padding:'6px 14px',borderRadius:20,border:'none',background:filterCat===c?G:'#e8e3db',color:filterCat===c?'#fff':CH,fontWeight:700,fontSize:13,cursor:'pointer',whiteSpace:'nowrap'}}>
            {filterCat===c?'✓ ':''}{c}
          </button>
        )}
      </div>
      {heartAnim&&<div style={{position:'fixed',top:'40%',left:'50%',transform:'translate(-50%,-50%)',fontSize:80,pointerEvents:'none',animation:'pop .6s ease-out',zIndex:99}}>❤️</div>}
      {deck.length===0?(
        <div style={{flex:1,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',padding:32,textAlign:'center'}}>
          <div style={{fontSize:48,marginBottom:16}}>Ὁa</div>
          <div style={{fontWeight:700,fontSize:20,color:DG,marginBottom:8}}>You've seen everyone!</div>
          <div style={{color:TP,fontSize:15,marginBottom:24}}>Check back soon for new local businesses.</div>
          <button onClick={loadDeck}style={{...btn(G),width:'auto',padding:'12px 28px'}}>Reload ↻</button>
        </div>
      ):cur?(
        <div style={{flex:1,display:'flex',flexDirection:'column',alignItems:'center',padding:'12px 16px 0',userSelect:'none'}}>
          <div style={{display:'flex',gap:4,marginBottom:10}}>
            {deck.slice(0,Math.min(3,deck.length)).map((_,i)=><div key={i}style={{width:i===0?32:24,height:4,borderRadius:2,background:i===0?G:'#ccc'}}/>)}
          </div>
          <div onMouseDown={hMD}onTouchStart={hTD}onTouchMove={hTM}onTouchEnd={hTU}style={{width:'100%',maxWidth:380,borderRadius:20,overflow:'hidden',boxShadow:'0 8px 32px rgba(0,0,0,0.13)',background:'#fff',cursor:'grab',transform:`rotate(${dragX/30}deg) translateX(${dragX}px)`,transition:dragging?'none':'transform 0.3s ease',position:'relative'}}>
            {dragX>30&&<div style={{position:'absolute',top:20,left:20,background:G,color:'#fff',padding:'6px 16px',borderRadius:20,fontWeight:700,fontSize:18,transform:'rotate(-15deg)',zIndex:5}}>LIKE ❤️</div>}
            {dragX<-30&&<div style={{position:'absolute',top:20,right:20,background:RD,color:'#fff',padding:'6px 16px',borderRadius:20,fontWeight:700,fontSize:18,transform:'rotate(15deg)',zIndex:5}}>SKIP ❌</div>}
            <div style={{background:CAT[cur.category]?.g||'linear-gradient(135deg,#2d6a4f,#1b4332)',padding:'28px 20px 20px'}}>
              <div style={{fontSize:44,marginBottom:8}}>{CAT[cur.category]?.i||'Ἶ2'}</div>
              <div style={{fontWeight:800,fontSize:22,color:'#fff',marginBottom:4}}>{cur.name}</div>
              <div style={{display:'flex',alignItems:'center',gap:8}}>
                <span style={{background:'rgba(255,255,255,0.2)',color:'#fff',padding:'3px 10px',borderRadius:12,fontSize:12,fontWeight:600}}>{cur.category}</span>
                {cur.neighborhood&&<span style={{color:'rgba(255,255,255,0.85)',fontSize:13}}>{cur.neighborhood}</span>}
              </div>
            </div>
            <div style={{padding:'16px 20px'}}>
              {cur.tagline&&<div style={{fontStyle:'italic',color:TP,fontSize:14,marginBottom:12,lineHeight:1.4}}>“{cur.tagline}”</div>}
              {cur.featured_items?.length>0&&<div style={{marginBottom:12}}>
                <div style={{fontWeight:600,fontSize:12,color:TP,marginBottom:6,textTransform:'uppercase',letterSpacing:1}}>Featured</div>
                <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
                  {cur.featured_items.slice(0,3).map((t,i)=><div key={i}style={{background:SG,color:DG,padding:'4px 12px',borderRadius:12,fontSize:13,fontWeight:600}}>{t.name||t}</div>)}
                </div>
              </div>}
              <div style={{display:'flex',gap:16,marginTop:8}}>
                {cur.phone&&<a href={'tel:'+cur.phone}style={{color:G,fontSize:13,fontWeight:600,textDecoration:'none'}}>Ὅe {cur.phone}</a>}
                {cur.website&&<a href={cur.website}target='_blank'rel='noreferrer'style={{color:G,fontSize:13,fontWeight:600,textDecoration:'none'}}>ἱ0 Website</a>}
              </div>
            </div>
          </div>
          <div style={{display:'flex',gap:24,alignItems:'center',justifyContent:'center',marginTop:20,paddingBottom:16}}>
            <button onClick={()=>doSwipe('left')}style={{width:60,height:60,borderRadius:30,border:'2px solid #f0e0d6',background:'#fff',fontSize:26,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center',boxShadow:'0 2px 8px rgba(0,0,0,0.08)'}}>❌</button>
            <button onClick={()=>setDetail(cur)}style={{width:48,height:48,borderRadius:24,border:'2px solid #e8e3db',background:'#fff',fontSize:20,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}>ℹ️</button>
            <button onClick={()=>doSwipe('right')}style={{width:60,height:60,borderRadius:30,border:'2px solid #c8e6c9',background:'#fff',fontSize:26,cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center',boxShadow:'0 2px 8px rgba(0,0,0,0.08)'}}>❤️</button>
          </div>
          <div style={{color:TP,fontSize:12,textAlign:'center',marginBottom:8}}>{deck.length} left to explore</div>
        </div>
      ):null}
    </div>
  )
}
