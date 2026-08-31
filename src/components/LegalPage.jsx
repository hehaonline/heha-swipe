const SUPPORT_EMAIL = "hello@heha.online";

const pages = {
  "/privacy": {
    eyebrow: "Legal",
    title: "HEHA Swipe Privacy Notice",
    updated: "Effective August 31, 2026",
    sections: [
      ["What HEHA Swipe uses", "HEHA Swipe uses your account email and identifier, saved businesses, swipe activity, and optional profile details such as name, phone number, and general location or address to operate local discovery and account features."],
      ["What store builds do not use", "The store release does not request precise device location, run social sign-in, send marketing webhooks, offer in-app payment flows, or collect phone numbers and free-text notes through discount requests."],
      ["Partners", "The store client requests only the public business-card fields needed for discovery. It does not request private owner, contact, moderation, routing, or internal analytics fields."],
      ["Retention and deletion", "We retain account data while your account is active or as required to operate and secure the service. You can request deletion inside Profile or by using the account-deletion page."],
      ["Contact", `Questions can be sent to ${SUPPORT_EMAIL}.`],
    ],
  },
  "/support": {
    eyebrow: "Help",
    title: "HEHA Swipe Support",
    updated: "Effective August 31, 2026",
    sections: [
      ["Get help", "For sign-in, listing, privacy, accessibility, or account questions, email HEHA support. Include the email address on your account, but never send your password or verification code."],
      ["Response", "HEHA will review support messages during normal business operations. Urgent safety or emergency issues should be directed to the appropriate local service."],
    ],
  },
  "/account-deletion": {
    eyebrow: "Account controls",
    title: "Delete your HEHA Swipe account",
    updated: "Effective August 31, 2026",
    sections: [
      ["In the app", "Sign in, open Profile, and choose Request account deletion. The app submits an authenticated request without sending your user ID as a client-controlled argument."],
      ["If you cannot sign in", `Email ${SUPPORT_EMAIL} from the address connected to your account and ask for HEHA Swipe account deletion.`],
      ["What happens", "HEHA verifies and processes the request, removes the account and associated personal app data, and retains only records that must legally or operationally be retained. The app does not claim deletion is complete until processing is confirmed."],
    ],
  },
};

export function isPublicInfoPath(pathname) {
  return Boolean(pages[pathname]);
}

export default function LegalPage({ pathname }) {
  const page = pages[pathname] || pages["/support"];
  return (
    <main className="onboarding-screen public-info-page">
      <section className="join-card card-like">
        <p className="eyebrow">{page.eyebrow}</p>
        <h1>{page.title}</h1>
        <p className="fine-print">{page.updated}</p>
        {page.sections.map(([title, body]) => (
          <section key={title} className="public-info-section">
            <h2>{title}</h2>
            <p>{body}</p>
          </section>
        ))}
        <a className="primary-button public-info-link" href={`mailto:${SUPPORT_EMAIL}`}>Email HEHA support</a>
        <a className="text-button center public-info-link" href="/">Back to HEHA Swipe</a>
      </section>
    </main>
  );
}
