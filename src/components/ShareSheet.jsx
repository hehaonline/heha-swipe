import { useState } from "react";
export default function ShareSheet({ partner, onClose }) {
  const [copied, setCopied] = useState(false);
  const shareText = `🌿 Check out ${partner.name} on HEHA Swipe!\n${partner.tagline || ""}\n📍 ${partner.neighborhood || "Tampa Bay"}\n\nhehaswipe.app`;
  const url = "https://hehaswipe.app";
  const copy = async () => { await navigator.clipboard.writeText(shareText + "\n" + url); setCopied(true); setTimeout(() => setCopied(false), 2000); };
  const opts = [
    { label: "WhatsApp", icon: "💬", bg: "#25D366", action: () => window.open(`https://wa.me/?text=${encodeURIComponent(shareText + "\n" + url)}`, "_blank") },
    { label: "Instagram", icon: "📸", bg: "linear-gradient(135deg,#f09433,#dc2743,#bc1888)", action: () => { navigator.clipboard.writeText(shareText); window.open("https://instagram.com", "_blank"); }},
    { label: "Twitter/X", icon: "𝕏", bg: "#000", action: () => window.open(`https://twitter.com/intent/tweet?text=${encodeURIComponent(shareText)}&url=${encodeURIComponent(url)}`, "_blank") },
    { label: "SMS", icon: "💬", bg: "#34C759", action: () => window.open(`sms:?body=${encodeURIComponent(shareText + "\n" + url)}`, "_blank") },
    { label: "Email", icon: "📧", bg: "#e85d2b", action: () => window.open(`mailto:?subject=Check out ${partner.name}&body=${encodeURIComponent(shareText + "\n\n" + url)}`, "_blank") },
  ];
  return (
    <>
      <div onClick={onClose} style={{ position:"fixed",inset:0,background:"rgba(0,0,0,0.5)",zIndex:200,backdropFilter:"blur(4px)" }} />
      <div style={{ position:"fixed",bottom:0,left:"50%",transform:"translateX(-50%)",width:"100%",maxWidth:480,background:"#fff",borderRadius:"24px 24px 0 0",zIndex:201,padding:"20px 20px 40px",animation:"slideUp 0.3s ease" }}>
        <div style={{ width:40,height:4,borderRadius:2,background:"#e0e0e0",margin:"0 auto 20px" }} />
        <div style={{ display:"flex",gap:12,alignItems:"center",marginBottom:20,padding:14,background:"#f9f9f9",borderRadius:16 }}>
          <div style={{ width:48,height:48,borderRadius:14,background:partner.color||"#1e4d1e",display:"flex",alignItems:"center",justifyContent:"center",fontSize:22,flexShrink:0 }}>{partner.photo_emoji||"🏷️"}</div>
          <div>
            <div style={{ fontFamily:"'Syne',sans-serif",fontWeight:800,fontSize:15,color:"#111" }}>{partner.name}</div>
            <div style={{ fontSize:12,color:"#e85d2b",fontWeight:600 }}>{partner.category} · {partner.neighborhood}</div>
          </div>
        </div>
        {navigator.share && (
          <button onClick={() => navigator.share({ title:partner.name, text:shareText, url }).catch(()=>{})}
            style={{ width:"100%",padding:14,borderRadius:14,border:"none",background:"linear-gradient(135deg,#e85d2b,#ff7a47)",color:"#fff",fontSize:15,fontWeight:700,cursor:"pointer",marginBottom:16,fontFamily:"'Syne',sans-serif" }}>
            Share via... ↗
          </button>
        )}
        <div style={{ display:"flex",gap:12,overflowX:"auto",paddingBottom:16,scrollbarWidth:"none" }}>
          {opts.map(o => (
            <button key={o.label} onClick={o.action} style={{ display:"flex",flexDirection:"column",alignItems:"center",gap:8,background:"none",border:"none",cursor:"pointer",flexShrink:0,minWidth:60 }}>
              <div style={{ width:52,height:52,borderRadius:16,background:o.bg,display:"flex",alignItems:"center",justifyContent:"center",fontSize:22,color:"#fff",boxShadow:"0 4px 12px rgba(0,0,0,0.15)" }}>{o.icon}</div>
              <span style={{ fontSize:10,color:"#888",fontWeight:600,textAlign:"center" }}>{o.label}</span>
            </button>
          ))}
        </div>
        <button onClick={copy} style={{ width:"100%",padding:14,borderRadius:14,border:"1.5px solid #eee",background:copied?"#f0f8f0":"#fff",color:copied?"#2a7c3f":"#555",fontSize:14,fontWeight:600,cursor:"pointer",display:"flex",alignItems:"center",justifyContent:"center",gap:8 }}>
          {copied ? "✓ Copied!" : "📋 Copy link"}
        </button>
      </div>
    </>
  );
}
