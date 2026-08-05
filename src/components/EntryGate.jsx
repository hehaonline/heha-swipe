// First-party HEHA entry gate shown to unauthenticated visitors who arrive from
// the HEHA Wix landing page (https://hehaswipe.app/?entry=landing).
//
// It offers three calm choices -- browse as a guest, log in, or create an
// account -- and delegates the actual behavior to the parent (App), which owns
// session state, guest persistence, and URL normalization. This component holds
// no auth or routing logic itself.

function GuestIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <circle cx="12" cy="12" r="9" />
      <path d="m15.5 8.5-2 5-5 2 2-5 5-2Z" />
    </svg>
  );
}

function LoginIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M10 17v2a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2h-6a2 2 0 0 0-2 2v2" />
      <path d="M3 12h11" />
      <path d="m11 8 4 4-4 4" />
    </svg>
  );
}

function CreateIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M12 5v14" />
      <path d="M5 12h14" />
    </svg>
  );
}

export default function EntryGate({ onGuest, onLogin, onCreate }) {
  return (
    <main className="auth-screen entry-gate-screen">
      <section className="auth-card entry-gate-card" aria-labelledby="entry-gate-title">
        <div className="auth-hero">
          <div className="brand-mark large" role="img" aria-label="HEHA Swipe">H</div>
          <p className="eyebrow">Welcome to HEHA Swipe</p>
          <h1 id="entry-gate-title">How would you like to explore?</h1>
          <p>
            Browse HEHA Swipe freely as a guest, or sign in to save favorites and
            personalize your experience. You can create an account anytime.
          </p>
        </div>

        <div className="choice-grid entry-gate-grid" role="group" aria-label="Choose how to continue">
          <button type="button" className="choice-card entry-choice" onClick={onGuest}>
            <span className="choice-icon"><GuestIcon /></span>
            <h2>Continue as guest</h2>
            <p>Explore local healthy places right away. No account needed.</p>
          </button>

          <button type="button" className="choice-card entry-choice" onClick={onLogin}>
            <span className="choice-icon"><LoginIcon /></span>
            <h2>Log in</h2>
            <p>Welcome back. Pick up your saved spots and preferences.</p>
          </button>

          <button type="button" className="choice-card entry-choice featured" onClick={onCreate}>
            <span className="choice-icon"><CreateIcon /></span>
            <h2>Create an account</h2>
            <p>Save favorites, personalize discovery, and support what you love.</p>
          </button>
        </div>

        <p className="fine-print entry-gate-note">
          Guest browsing shows only public discovery. Saving, personalizing, and
          business tools stay protected behind sign-in.
        </p>
      </section>
    </main>
  );
}
