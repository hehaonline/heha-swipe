export default function BecomePartnerEmbed() {
  const onboardingUrl = "https://hehaswipe.app/?becomePartner=1";

  return (
    <main className="embed-page become-partner-embed">
      <section className="become-partner-card">
        <div className="become-partner-mark" aria-hidden="true">H</div>
        <div>
          <p className="embed-eyebrow">HEHA partner network</p>
          <h1>Bring your business into the HEHA ecosystem.</h1>
          <p className="become-partner-lead">
            Create one HEHA business profile. HEHA reviews the request before anything becomes a public listing.
          </p>
        </div>

        <div className="become-partner-flow" aria-label="Partner onboarding steps">
          <div><strong>1</strong><span>Create a secure business account</span></div>
          <div><strong>2</strong><span>Build your HEHA partner profile</span></div>
          <div><strong>3</strong><span>HEHA reviews the listing before public visibility</span></div>
        </div>

        <a className="become-partner-cta" href={onboardingUrl} target="_top">
          Create your HEHA partner profile <span>→</span>
        </a>

        <p className="become-partner-note">
          Free listing request. Restaurants, food vendors, wellness businesses, practitioners, artists, events, and community-aligned local brands can apply.
        </p>
      </section>
    </main>
  );
}
