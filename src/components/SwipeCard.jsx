import { useState, useRef } from "react";
import ShareSheet from "./ShareSheet";
export default function SwipeCard({ partner, onSwipe, onSuperSwipe }) {
  const [dragging, setDragging] = useState(false);
  const [offset, setOffset] = useState({ x:0, y:0 });
  const [showShare, setShowShare] = useState(false);
  const startRef = useRef(null);
  const cardRef = useRef(null);
  const rot = () => Math.min(Math.max(offset.x/12,-18),18);
  const getOv = () => {
    if (offset.y < -80 && Math.abs(offset.x) < 60) return { label:"⚡",text:"SUPER",color:"rgba(232,93,43,0.92)" };
    if (offset.x > 50) return { label:"♥",text:"LIKE",color:"rgba(42,124,63,0.88)" };
    if (offset.x < -50) return { label:"✕",text:"PASS",color:"rgba(17,17,17,0.88)" };
    return null;
  };
  const onPD = (e) => { setDragging(true); startRef.current={x:e.clientX,y:e.clientY}; cardRef.current?.setPointerCapture(e.pointerId); };
  const onPM = (e) => { if (!dragging||!startRef.current) return; setOffset({x:e.clientX-startRef.current.x,y:e.clientY-startRef.current.y}); };
  const onPU = () => {
    setDragging(false);
    if (offset.y < -100 && Math.abs(offset.x) < 60) onSuperSwipe?.(partner);
    else if (offset.x > 80) onSwipe("right");
    else if (offset.x < -80) onSwipe("left");
    setOffset({x:0,y:0}); startRef.current=null;
  };
  const ov = getOv();
  const isSuper = offset.y < -40 && Math.abs(offset.x) < 60;
  return (
    <>
      <div ref={cardRef} onPointerDown={onPD} onPointerMove={onPM} onPointerUp={onPU}
        style={{ position:"absolute",width:"100%",transform:`translateX(${offset.x}px) translateY(${offset.y*0.5}px) rotate(${rot()}deg)`,transition:dragging?"box-shadow 0.2s":"transform 0.4s cubic-bezier(0.25,0.46,0.45,0.94)",cursor:dragging?"grabbing":"grab",userSelect:"none",touchAction:"none",borderRadius:24,overflow:"hidden",boxShadow:isSuper?"0 12px 48px rgba(232,93,43,0.5)":"0 12px 40px rgba(0,0,0,0.15)",zIndex:1 }}>
        {isSuper && <div style={{ position:"absolute",top:0,left:0,right:0,height:4,background:"linear-gradient(90deg,#e85d2b,#ff7a47)",zIndex:10 }} />}
        <div style={{ background:partner.color||"#1e4d1e",padding:"28px 22px 22px",minHeight:190,display:"flex",flexDirection:"column",justifyContent:"flex-end",position:"relative",overflow:"hidden" }}>
          <div style={{ position:"absolute",top:-30,right:-30,width:120,height:120,borderRadius:"50%",background:"rgba(255,255,255,0.07)" }} />
          <button onPointerDown={e=>e.stopPropagation()} onClick={e=>{e.stopPropagation();setShowShare(true);}}
            style={{ position:"absolute",top:16,right:16,width:36,height:36,borderRadius:12,background:"rgba(255,255,255,0.2)",border:"none",cursor:"pointer",display:"flex",alignItems:"center",justifyContent:"center",fontSize:16,zIndex:5 }}>↗</button>
          <div style={{ fontSize:58,marginBottom:10,lineHeight:1 }}>{partner.photo_emoji||"🏷️"}</div>
          <div style={{ fontFamily:"'Syne',sans-serif",color:"#fff",fontWeight:800,fontSize:24,lineHeight:1.2,marginBottom:10 }}>{partner.name}</div>
          <div style={{ display:"flex",gap:8,alignItems:"center",flexWrap:"wrap" }}>
            <span style={{ background:"rgba(255,255,255,0.18)",color:"#fff",padding:"4px 12px",borderRadius:20,fontSize:11,fontWeight:700,textTransform:"uppercase" }}>{partner.category}</span>
            {partner.neighborhood && <span style={{ color:"rgba(255,255,255,0.7)",fontSize:12 }}>📍 {partner.neighborhood}</span>}
          </div>
        </div>
        <div style={{ background:"#fff",padding:"16px 20px 18px" }}>
          {(partner.tagline||partner.bio) && <p style={{ margin:"0 0 12px",fontSize:14,color:"#555",lineHeight:1.65,fontStyle:"italic" }}>"{partner.tagline||partner.bio?.slice(0,100)}"</p>}
          <div style={{ display:"flex",gap:14,fontSize:12,color:"#aaa",flexWrap:"wrap",marginBottom:12 }}>
            {partner.phone && <span><span style={{color:"#e85d2b"}}>📞</span> {partner.phone}</span>}
            {partner.website && <span style={{color:"#e85d2b",fontWeight:600}}>🌐 Website</span>}
            {partner.instagram && <span style={{color:"#e85d2b",fontWeight:600}}>📸 @{partner.instagram}</span>}
          </div>
          <div style={{ display:"flex",gap:8,fontSize:11,color:"#ddd",alignItems:"center" }}>
            <span>← pass</span>
            <span style={{flex:1,height:1,background:"#f0f0f0"}} />
            <span style={{color:"#e85d2b"}}>⚡ super swipe up</span>
            <span style={{flex:1,height:1,background:"#f0f0f0"}} />
            <span>like →</span>
          </div>
        </div>
        {ov && <div style={{ position:"absolute",inset:0,display:"flex",flexDirection:"column",alignItems:"center",justifyContent:"center",background:ov.color,borderRadius:24,gap:8 }}><div style={{fontSize:64}}>{ov.label}</div><div style={{fontFamily:"'Syne',sans-serif",fontWeight:800,fontSize:30,color:"#fff",letterSpacing:3}}>{ov.text}</div></div>}
      </div>
      {showShare && <ShareSheet partner={partner} onClose={()=>setShowShare(false)} />}
    </>
  );
}
