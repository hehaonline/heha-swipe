import { useEffect, useMemo, useState } from "react";
import { agreementDraftForListing, renderAgreementText } from "../contracts/partnerAgreements";
import { useModalDialog } from "../lib/useModalDialog";
import {
  loadPartnerAgreementForAcceptance,
  recordPartnerAgreementAcceptance,
} from "../services/partnerAgreementRepository";

const REVIEW_ACCEPTANCE_TEXT =
  "I am authorized to sign for the named partner, I reviewed the complete agreement identified above, and I agree that my typed name is my electronic signature.";

function normalizedName(value) {
  return String(value || "").normalize("NFKC").trim().replace(/\s+/g, " ").toLowerCase();
}

function safeFileName(value) {
  return String(value || "partner").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "partner";
}

function downloadText(filename, text, type = "text/plain;charset=utf-8") {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function reviewDraftForDownload(template, listing) {
  return [
    renderAgreementText(template, listing?.name),
    "",
    "IMPORTANT",
    "This file is a review draft. It is not an accepted agreement or permission to publish, take orders, activate payments, or represent this business as a HEHA partner.",
  ].join("\n");
}

function requestStorageKey(userId, partnerId, agreementVersionId) {
  return `heha_agreement_request_v1:${userId}:${partnerId}:${agreementVersionId}`;
}

export default function PartnerAgreementFlow({ user, listing, onClose, onAccepted }) {
  const template = useMemo(() => agreementDraftForListing(listing), [listing]);
  const dialogRef = useModalDialog(onClose);
  const runtimeEnabled = import.meta.env.VITE_ENABLE_PARTNER_AGREEMENT_ACCEPTANCE === "true";
  const [serverAgreement, setServerAgreement] = useState(null);
  const [loadState, setLoadState] = useState(runtimeEnabled ? "loading" : "locked");
  const [signer, setSigner] = useState({ legalName: "", title: "", signature: "" });
  const [authority, setAuthority] = useState(false);
  const [electronicConsent, setElectronicConsent] = useState(false);
  const [reviewed, setReviewed] = useState(false);
  const [termsOpenedAt] = useState(() => new Date().toISOString());
  const [downloadedAt, setDownloadedAt] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [receipt, setReceipt] = useState(null);
  const [acceptanceRequestKey, setAcceptanceRequestKey] = useState(null);

  useEffect(() => {
    if (!runtimeEnabled || !listing?.id || !user?.id) return undefined;
    let cancelled = false;
    setLoadState("loading");
    loadPartnerAgreementForAcceptance(listing.id, user.id)
      .then((agreement) => {
        if (cancelled) return;
        setServerAgreement(agreement);
        const storageKey = requestStorageKey(user.id, listing.id, agreement.agreement_version_id);
        const existingRequestKey = sessionStorage.getItem(storageKey);
        const stableRequestKey = existingRequestKey || crypto.randomUUID();
        if (!existingRequestKey) sessionStorage.setItem(storageKey, stableRequestKey);
        setAcceptanceRequestKey(stableRequestKey);
        setLoadState("ready");
      })
      .catch((loadError) => {
        if (cancelled) return;
        setServerAgreement(null);
        setLoadState("blocked");
        setError(loadError.message || "The protected agreement could not be loaded.");
      });
    return () => { cancelled = true; };
  }, [listing?.id, runtimeEnabled, user?.id]);

  const canAccept = loadState === "ready" && Boolean(serverAgreement && acceptanceRequestKey);
  const typedNameMatches = Boolean(
    normalizedName(signer.legalName)
    && normalizedName(signer.legalName) === normalizedName(signer.signature)
  );
  const complete = Boolean(
    signer.legalName.trim() && signer.title.trim() && authority
    && electronicConsent && reviewed && typedNameMatches
  );
  const agreementText = serverAgreement?.document_snapshot
    || (template ? renderAgreementText(template, listing?.name) : "");
  const agreementTitle = serverAgreement?.title || template?.title || "Category agreement needed";
  const agreementVersion = serverAgreement?.agreement_version || template?.version || "Not assigned";
  const assentText = serverAgreement?.assent_text || REVIEW_ACCEPTANCE_TEXT;

  const set = (field, value) => {
    setSigner((current) => ({ ...current, [field]: value }));
    setError(null);
  };

  const downloadAgreement = () => {
    if (!agreementText) return;
    downloadText(
      `${safeFileName(listing?.name)}-${safeFileName(agreementVersion)}${serverAgreement ? "" : "-review-draft"}.txt`,
      serverAgreement ? agreementText : reviewDraftForDownload(template, listing),
    );
    setDownloadedAt(new Date().toISOString());
  };

  const acceptAgreement = async () => {
    if (!canAccept || !serverAgreement) {
      setError("No server-approved category agreement is enabled for this signer.");
      return;
    }
    if (!complete) {
      setError("Complete the signer fields, review confirmations, and matching typed signature.");
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const assertions = {
        assertions_version: "heha-partner-acceptance-v1",
        signer_legal_name: signer.legalName.trim().replace(/\s+/g, " "),
        signer_title: signer.title.trim().replace(/\s+/g, " "),
        typed_signature: signer.signature.trim().replace(/\s+/g, " "),
        signer_authority_confirmed: authority,
        electronic_records_consent: electronicConsent,
        reviewed_complete_agreement: reviewed,
        assent_text: assentText,
        terms_opened_at_client: termsOpenedAt,
        terms_downloaded_at_client: downloadedAt,
        timezone_client: Intl.DateTimeFormat().resolvedOptions().timeZone || null,
        locale_client: navigator.language || null,
      };
      const serverReceipt = await recordPartnerAgreementAcceptance({
        partnerId: listing.id,
        actorId: user.id,
        agreement: serverAgreement,
        requestKey: acceptanceRequestKey,
        assertions,
      });
      const verifiedReceipt = {
        ...serverReceipt,
        agreement_text: agreementText,
        agreement_title: agreementTitle,
        signer_email: serverAgreement.signer_email,
        assertions: serverReceipt.assertions_snapshot,
      };
      sessionStorage.removeItem(requestStorageKey(user.id, listing.id, serverAgreement.agreement_version_id));
      setReceipt(verifiedReceipt);
      await onAccepted?.(verifiedReceipt);
    } catch (acceptanceError) {
      setError(acceptanceError.message || "The agreement could not be accepted yet.");
    } finally {
      setBusy(false);
    }
  };

  const downloadReceipt = () => {
    if (!receipt) return;
    const agreementHtml = receipt.agreement_text.split("\n")
      .map((line) => `<p>${escapeHtml(line) || "&nbsp;"}</p>`).join("");
    const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(receipt.agreement_title)} — Acceptance Receipt</title>
<style>body{font:15px/1.55 system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 22px;color:#1f2a24}h1{line-height:1.1}.meta{padding:16px;background:#f7f3ec;border-radius:14px}.meta p{margin:4px 0}.terms{margin-top:24px;border-top:2px solid #f28122;padding-top:18px}.terms p{margin:7px 0}code{overflow-wrap:anywhere}@media print{body{margin:0}.no-print{display:none}}</style>
</head><body>
<h1>${escapeHtml(receipt.agreement_title)}</h1>
<p>Verified electronic acceptance receipt for ${escapeHtml(listing?.name)}</p>
<div class="meta">
<p><strong>Receipt ID:</strong> <code>${escapeHtml(receipt.acceptance_id)}</code></p>
<p><strong>Agreement version:</strong> ${escapeHtml(receipt.agreement_version)}</p>
<p><strong>Legal relationship:</strong> ${escapeHtml(receipt.legal_relationship_type)}</p>
<p><strong>Accepted by account:</strong> <code>${escapeHtml(receipt.accepted_by)}</code></p>
<p><strong>Accepted:</strong> ${escapeHtml(receipt.accepted_at)}</p>
<p><strong>Signer:</strong> ${escapeHtml(receipt.assertions.signer_legal_name)}, ${escapeHtml(receipt.assertions.signer_title)}</p>
<p><strong>Verified account email:</strong> ${escapeHtml(receipt.signer_email)}</p>
<p><strong>Authority confirmed:</strong> Yes</p>
<p><strong>Electronic records consent:</strong> Yes</p>
<p><strong>Complete agreement reviewed:</strong> Yes</p>
<p><strong>Assent:</strong> ${escapeHtml(receipt.assertions.assent_text)}</p>
<p><strong>Document SHA-256:</strong> <code>${escapeHtml(receipt.document_sha256)}</code></p>
<p><strong>Assertions SHA-256:</strong> <code>${escapeHtml(receipt.assertions_sha256)}</code></p>
<p><strong>Request key:</strong> <code>${escapeHtml(receipt.request_key)}</code></p>
</div>
<section class="terms"><h2>Exact accepted agreement</h2>${agreementHtml}</section>
<p class="no-print">Save this file or print it to PDF for your records.</p>
</body></html>`;
    downloadText(
      `${safeFileName(listing?.name)}-${safeFileName(receipt.agreement_version)}-verified-receipt.html`,
      html,
      "text/html;charset=utf-8",
    );
  };

  return (
    <div ref={dialogRef} className="preview-backdrop" role="dialog" aria-modal="true" aria-labelledby="partner-agreement-title" onClick={onClose}>
      <section className="partner-preview-sheet agreement-sheet" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close agreement">×</button>
        <div className="agreement-body">
          <p className="eyebrow">In-app partner agreement</p>
          <h2 id="partner-agreement-title">{agreementTitle}</h2>

          {!agreementText ? (
            <div className="agreement-gate warning">
              HEHA has not mapped this business to one verified legal relationship yet. Discovery categories—and multi-category profiles—cannot choose a contract by themselves.
            </div>
          ) : (
            <>
              <div className="agreement-version-row">
                <span>{agreementVersion}</span>
                <strong>{canAccept ? "Server approved" : "Legal review required"}</strong>
              </div>

              {!canAccept && <div className="agreement-gate warning">{template?.notice || "Signing is not enabled."}</div>}
              {template?.summary && !serverAgreement && <p className="agreement-summary">{template.summary}</p>}

              <div className="agreement-document" tabIndex="0" aria-label={serverAgreement ? "Exact approved agreement" : "Complete agreement review draft"}>
                {serverAgreement
                  ? agreementText.split("\n").map((line, index) => <p key={`${index}-${line.slice(0, 20)}`}>{line || "\u00a0"}</p>)
                  : template.sections.map((section, index) => (
                    <section key={section.title}>
                      <h3>{index + 1}. {section.title}</h3>
                      {section.paragraphs.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
                    </section>
                  ))}
                {!serverAgreement && (
                  <section>
                    <h3>Activation gates</h3>
                    <ul>{template.activationGates.map((gate) => <li key={gate}>{gate}</li>)}</ul>
                  </section>
                )}
              </div>

              <button className="secondary-button" type="button" onClick={downloadAgreement}>
                {serverAgreement ? "Download exact agreement" : "Download review draft"}
              </button>

              <section className={canAccept ? "agreement-signature-panel" : "agreement-signature-panel locked"}>
                <p className="eyebrow">Authorized signer</p>
                <h3>Accept inside HEHA Swipe</h3>
                {!canAccept && (
                  <div className="agreement-gate">
                    {loadState === "loading"
                      ? "Checking the protected agreement and signer authority…"
                      : "Signing stays locked until a recipient-bound business claim, category-specific counsel approval, immutable document, server kill switch, and protected receipt are verified."}
                  </div>
                )}

                <label className="field-block">
                  <span>Signer full legal name</span>
                  <input autoComplete="name" value={signer.legalName} onChange={(event) => set("legalName", event.target.value)} disabled={!canAccept || busy} />
                </label>
                <label className="field-block">
                  <span>Title / authority</span>
                  <input value={signer.title} onChange={(event) => set("title", event.target.value)} disabled={!canAccept || busy} placeholder="Owner or verified authorized representative" />
                </label>
                <label className="field-block">
                  <span>Verified account email</span>
                  <input type="email" value={serverAgreement?.signer_email || user?.email || ""} readOnly disabled />
                </label>

                <label className="agreement-check-row">
                  <input type="checkbox" checked={reviewed} onChange={(event) => setReviewed(event.target.checked)} disabled={!canAccept || busy} />
                  <span>I opened and reviewed the complete {agreementTitle}, version {agreementVersion}.</span>
                </label>
                <label className="agreement-check-row">
                  <input type="checkbox" checked={authority} onChange={(event) => setAuthority(event.target.checked)} disabled={!canAccept || busy} />
                  <span>I am the claimed owner or a separately verified authorized signer for {listing?.name || "the named partner"}.</span>
                </label>
                <label className="agreement-check-row">
                  <input type="checkbox" checked={electronicConsent} onChange={(event) => setElectronicConsent(event.target.checked)} disabled={!canAccept || busy} />
                  <span>I consent to electronic records and signatures and can retain this agreement electronically.</span>
                </label>

                <label className="field-block agreement-signature-field">
                  <span>Type your full legal name to sign</span>
                  <input value={signer.signature} onChange={(event) => set("signature", event.target.value)} disabled={!canAccept || busy} autoComplete="name" />
                  {signer.signature && !typedNameMatches && <small>The typed signature must match the signer name.</small>}
                </label>

                <p className="agreement-acceptance-text">{assentText}</p>
                {error && <div className="error-banner" role="alert">{error}</div>}
                {receipt && (
                  <div className="success-banner" role="status">
                    Verified acceptance recorded. Receipt ID: {receipt.acceptance_id}
                    <button className="text-button" type="button" onClick={downloadReceipt}>Download signed receipt</button>
                  </div>
                )}
                <button className="primary-button" type="button" disabled={!canAccept || !complete || busy || Boolean(receipt)} onClick={acceptAgreement}>
                  {busy ? "Recording acceptance…" : receipt ? "Agreement accepted" : "Accept and sign agreement"}
                </button>
                <p className="agreement-fineprint">
                  Acceptance never auto-publishes a profile, activates payment, or makes a listing orderable. Those require separate verified gates.
                </p>
              </section>
            </>
          )}
        </div>
      </section>
    </div>
  );
}
