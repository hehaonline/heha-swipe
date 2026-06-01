import { useState } from "react";

export default function ShareSheet({ partner, onClose }) {
  const [copied, setCopied] = useState(false);
  const cleanName = partner.name || "this local business";
  const url = "https://hehaswipe.app";
  const shareText = `🌿 I found ${cleanName} on HEHA Swipe.\n${partner.tagline || "A local healthy business worth checking out."}\n📍 ${partner.neighborhood || "Tampa Bay"}\n\nDiscover more healthy local businesses:`;

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(`${shareText}\n${url}`);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      setCopied(false);
    }
  };

  const shareNative = async () => {
    try {
      await navigator.share({ title: cleanName, text: shareText, url });
    } catch {
      // User closed native share sheet.
    }
  };

  return (
    <>
      <div className="modal-backdrop" onClick={onClose} />
      <aside className="share-sheet" role="dialog" aria-modal="true" aria-label={`Share ${cleanName}`}>
        <div className="sheet-handle" />
        <div className="share-preview">
          <div style={{ background: partner.color || "var(--heha-green)" }}>{partner.photo_emoji || "🌿"}</div>
          <section>
            <h3>{cleanName}</h3>
            <p>{partner.category} · {partner.neighborhood || "Tampa Bay"}</p>
          </section>
        </div>

        {navigator.share && <button className="primary-button" onClick={shareNative}>Share with your apps ↗</button>}

        <div className="share-grid">
          <a href={`https://wa.me/?text=${encodeURIComponent(`${shareText}\n${url}`)}`} target="_blank" rel="noreferrer">WhatsApp</a>
          <a href={`sms:?body=${encodeURIComponent(`${shareText}\n${url}`)}`}>SMS</a>
          <a href={`mailto:?subject=${encodeURIComponent(`Found ${cleanName} on HEHA Swipe`)}&body=${encodeURIComponent(`${shareText}\n\n${url}`)}`}>Email</a>
          <a href={`https://twitter.com/intent/tweet?text=${encodeURIComponent(shareText)}&url=${encodeURIComponent(url)}`} target="_blank" rel="noreferrer">X</a>
        </div>

        <button className="secondary-button" onClick={copy}>{copied ? "Copied ✓" : "Copy invite text"}</button>
        <button className="text-button center" onClick={onClose}>Close</button>
      </aside>
    </>
  );
}
