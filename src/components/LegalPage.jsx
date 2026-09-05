const SUPPORT_EMAIL = "hello@heha.online";

const pages = {
  "/privacy": {
    eyebrow: "Legal",
    title: "HEHA Swipe Privacy Notice",
    updated: "Effective September 3, 2026",
    sections: [
      ["Who we are", "HEHA Swipe is provided by Healthy Habit LLC. Questions or privacy requests can be sent to hello@heha.online."],
      ["Information we use", "HEHA Swipe uses your account email and identifier, saved businesses, swipe activity, and optional profile details such as name, phone number, and general location or address. Our infrastructure providers may also process limited network, device, and security-log information needed to deliver and protect the service."],
      ["How we use information", "We use this information to create and secure your account, provide local business discovery, remember saved businesses and preferences, support you, prevent abuse, and maintain the service."],
      ["What store builds do not use", "The store release does not request precise device location, run social sign-in, send marketing webhooks, offer in-app payment flows, or collect phone numbers and free-text notes through discount requests."],
      ["Service providers and sharing", "We use infrastructure providers to operate HEHA Swipe, including Supabase for authentication and database services and Vercel for web hosting. They process information to provide those services. We do not sell personal information or use it for cross-app advertising. We may disclose limited information when legally required or when needed to protect users, HEHA, or the service."],
      ["Partners", "The store client requests only the public business-card fields needed for discovery. It does not request private owner, contact, moderation, routing, or internal analytics fields. Your personal profile and swipe history are not shown to listed businesses through the store client."],
      ["Security", "We use HTTPS, authenticated account access, access controls, and a limited client data contract to protect personal information. No online service can guarantee absolute security, so please contact us if you believe your account or information is at risk."],
      ["Retention and deletion", "We keep profile, saved-business, and swipe data while your account is active or while it is needed to provide and secure HEHA Swipe. After a verified deletion request is processed, we delete or de-identify associated application data except limited records that must be retained for legal compliance, fraud prevention, security, or dispute resolution. Those exceptions are kept only while the applicable purpose or legal requirement lasts; backup and security-log copies expire through normal retention cycles."],
      ["Your choices", "You can review or update optional profile details in the app. You can request account deletion from Profile or through the public account-deletion page. You may also contact us about access, correction, or privacy questions."],
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
    cta: "Request account deletion by email",
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
        <a className="primary-button public-info-link" href={`mailto:${SUPPORT_EMAIL}`}>{page.cta || "Email HEHA support"}</a>
        <a className="text-button center public-info-link" href="/">Back to HEHA Swipe</a>
      </section>
    </main>
  );
}
