import{G,OR,BK,btn}from'../lib/constants'
export default function PartnerDetail({detail,onClose}){
  if(!detail)return null
  return(
    <div style={{position:'fixed',inset:0,background:'rgba(0,0,0,0.5)',display:'flex',alignItems:'flex-end',zIndex:200}}onClick={onClose}>
      <div style={{background:'#fff',borderRadius:'24px 24px 0 0',padding:24,width:'100%',maxHeight:'80vh',overflowY:'auto'}}onClick={e=>e.stopPropagation()}>
        <div style={{fontSize:56,textAlign:'center'}}>{detail.emoji||'ἳf'}</div>
        <div style={{fontWeight:800,fontSize:22,color:BK,marginTop:8}}>{detail.name}</div>
        {detail.neighborhood&&<div style={{color:'#888',fontSize:14,marginTop:4}}>Ὄd {detail.neighborhood}</div>}
        {detail.tagline&&<p style={{color:'#555',fontSize:14,marginTop:12,lineHeight:1.6,fontStyle:'italic'}}>“{detail.tagline}”</p>}
        {detail.featured_items?.length>0&&<div style={{marginTop:16}}>
          <div style={{fontWeight:700,fontSize:15,color:G,marginBottom:8}}>Menu / Items</div>
          {detail.featured_items.map((t,i)=><div key={i} style={{display:'flex',justifyContent:'space-between',padding:'8px 0',borderBottom:'1px solid #f0ede6',fontSize:14}}>
            <div><div style={{fontWeight:600}}>{t.name}</div></div>
            {t.price&&<div style={{fontWeight:700,color:G,marginLeft:12}}>${t.price}</div>}
          </div>)}
        </div>}
        {detail.instagram&&<a href={'https://instagram.com/'+detail.instagram.replace('@','')}target='_blank'rel='noreferrer'style={{display:'block',color:OR,fontWeight:700,marginTop:12,textDecoration:'none'}}>὏8 @{detail.instagram.replace('@','')}</a>}
        {detail.phone&&<a href={'tel:'+detail.phone}style={{display:'block',color:G,fontWeight:700,marginTop:8,textDecoration:'none'}}>Ὅe {detail.phone}</a>}
        {detail.website&&<a href={detail.website}target='_blank'rel='noreferrer'style={{display:'block',color:G,fontWeight:700,marginTop:8,textDecoration:'none'}}>ἱ0 {detail.website}</a>}
        {detail.hours&&<div style={{marginTop:12,color:'#666',fontSize:13}}>⏰ {detail.hours}</div>}
        <button onClick={onClose}style={{...btn(G),marginTop:20}}>Close</button>
      </div>
    </div>
  )
}
