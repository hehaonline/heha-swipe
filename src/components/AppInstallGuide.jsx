import { useEffect, useMemo, useState } from "react";
import { hehaLocalInstallUrl, isHehaLocalInstallEnabled } from "../lib/hehaLocalRouting";
import { useModalDialog } from "../lib/useModalDialog";
import {
  getInstallState,
  requestSwipeInstall,
  subscribeToInstallState,
} from "../lib/pwaInstall";

const DEVICE_INSTALL_KEY = "heha_partner_install_device_v1";

function savedState(listingId) {
  if (!listingId) return {};
  try {
    return JSON.parse(localStorage.getItem(DEVICE_INSTALL_KEY) || "{}");
  } catch {
    return {};
  }
}

function ManualSteps({ appleMobile, appName }) {
  const steps = appleMobile
    ? [
        { icon: "1", title: "Open in Safari", copy: "If needed, copy this page into Safari before continuing." },
        { icon: "2", title: "Tap Share", copy: "Use the square-and-arrow button, then choose Add to Home Screen." },
        { icon: "3", title: "Confirm Add", copy: `Confirm “${appName}”, then check that its icon appears.` },
      ]
    : [
        { icon: "1", title: "Open browser menu", copy: "Tap ⋮ or the menu control in your current browser." },
        { icon: "2", title: "Choose Install", copy: "Choose Install app or Add to Home screen." },
        { icon: "3", title: "Confirm", copy: `Approve “${appName}”, then check that the HEHA icon appears.` },
      ];

  return (
    <>
      <img
        className="install-guide-picture"
        src={appleMobile ? "/install-guides/ios-add-to-home.svg" : "/install-guides/android-add-to-home.svg"}
        alt={appleMobile
          ? `Illustrated iPhone steps for adding ${appName}: Safari, Share, Add to Home Screen.`
          : `Illustrated Android steps for adding ${appName}: browser menu, Install app, confirm.`}
      />
      <ol className="install-visual-steps">
        {steps.map((step, index) => (
          <li key={step.title}>
            <span className="install-visual-icon" aria-hidden="true">{step.icon}</span>
            <div>
              <strong>{index + 1}. {step.title}</strong>
              <small>{step.copy}</small>
            </div>
          </li>
        ))}
      </ol>
    </>
  );
}

function GuideBody({ listingId }) {
  const [installState, setInstallState] = useState(getInstallState);
  const [progress, setProgress] = useState(() => savedState(listingId));
  const [message, setMessage] = useState("");
  const localUrl = useMemo(() => hehaLocalInstallUrl(), []);
  const localInstallEnabled = isHehaLocalInstallEnabled();

  useEffect(() => subscribeToInstallState(setInstallState), []);

  useEffect(() => {
    if (!installState.installed || progress.swipeConfirmed) return;
    const next = {
      ...progress,
      swipeConfirmed: true,
      swipeConfirmationSource: "standalone-detected",
      swipeConfirmedAt: new Date().toISOString(),
    };
    setProgress(next);
    localStorage.setItem(DEVICE_INSTALL_KEY, JSON.stringify(next));
  }, [installState.installed, progress]);

  const save = (changes) => {
    const next = { ...progress, ...changes };
    setProgress(next);
    if (listingId) localStorage.setItem(DEVICE_INSTALL_KEY, JSON.stringify(next));
  };

  const installSwipe = async () => {
    const result = await requestSwipeInstall();
    if (result.outcome === "disabled") {
      setMessage("HEHA Swipe installation stays locked until its real-device release proof passes.");
      return;
    }
    if (result.outcome === "accepted" || result.outcome === "installed") {
      save({ swipeConfirmed: true });
      setMessage("HEHA Swipe was added on this device.");
      return;
    }
    setMessage(result.outcome === "manual"
      ? "Use the device steps below, then confirm when the icon appears."
      : "Installation was not completed. You can try again or use the manual steps.");
  };

  const openLocal = () => {
    if (!localInstallEnabled) {
      setMessage("HEHA Local installation stays locked until its independent release proof passes.");
      return;
    }
    window.open(localUrl, "_blank", "noopener,noreferrer");
    save({ localOpened: true });
    setMessage("HEHA Local opened in a new tab. Add it from that tab's browser menu, then return here.");
  };

  const swipeDone = installState.installed || progress.swipeConfirmed;

  return (
    <div className="install-guide-body">
      <p className="eyebrow">Keep both HEHA apps one tap away</p>
      <h2 id="app-install-guide-title">Add Swipe and Local to this device</h2>
      <p className="install-guide-intro">
        These are user-controlled device steps. HEHA Swipe can detect its own standalone install on many devices,
        but it cannot install or verify HEHA Local on a different website.
      </p>

      {!installState.enabled && (
        <div className="agreement-gate warning" role="status">
          Review preview only: HEHA Swipe installation unlocks after the service worker, icons,
          standalone launch, and rollback cleanup pass on real iPhone and Android devices.
        </div>
      )}

      <article className={swipeDone ? "install-app-card complete" : "install-app-card"}>
        <div className="install-app-heading">
          <img src="/icons/icon-192.png" alt="" />
          <div>
            <span>Step 1</span>
            <h3>HEHA Swipe</h3>
          </div>
          <strong>{swipeDone ? "Added ✓" : "Not confirmed"}</strong>
        </div>

        {!swipeDone && installState.enabled && (
          <>
            {installState.canPrompt && !installState.appleMobile ? (
              <button className="primary-button" type="button" onClick={installSwipe}>Add HEHA Swipe</button>
            ) : (
              <ManualSteps appleMobile={installState.appleMobile} appName="HEHA Swipe" />
            )}
            <label className="install-confirm-row">
              <input
                type="checkbox"
                checked={Boolean(progress.swipeConfirmed)}
                onChange={(event) => save({ swipeConfirmed: event.target.checked })}
              />
              <span>I can see the HEHA Swipe icon on this device.</span>
            </label>
          </>
        )}
      </article>

      <article className={progress.localConfirmed ? "install-app-card complete" : "install-app-card"}>
        <div className="install-app-heading">
          <img src="/heha-logo.svg" alt="" />
          <div>
            <span>Step 2</span>
            <h3>HEHA Local</h3>
          </div>
          <strong>{progress.localConfirmed ? "Added ✓" : "Not confirmed"}</strong>
        </div>

        {!progress.localConfirmed && (
          <>
            {!localInstallEnabled && (
              <div className="agreement-gate warning">
                Review preview only: Local installation unlocks after its exact origin, manifest,
                service worker, icon, standalone launch, and rollback proof pass.
              </div>
            )}
            <button className="primary-button" type="button" onClick={openLocal} disabled={!localInstallEnabled}>Open HEHA Local</button>
            {localInstallEnabled && <ManualSteps appleMobile={installState.appleMobile} appName="HEHA Local" />}
            <label className="install-confirm-row">
              <input
                type="checkbox"
                checked={Boolean(progress.localConfirmed)}
                disabled={!localInstallEnabled}
                onChange={(event) => save({ localConfirmed: event.target.checked })}
              />
              <span>I returned after adding HEHA Local to this device.</span>
            </label>
          </>
        )}
      </article>

      <div className="install-guide-note">
        Next, open each icon once. Swipe is for discovery and partner setup; Local is where orderable menus,
        products, group orders, and fulfillment are verified.
      </div>
      {message && <div className="cp-billing-note" role="status" aria-live="polite">{message}</div>}
    </div>
  );
}

export default function AppInstallGuide({ listingId, onClose = null }) {
  const dialogRef = useModalDialog(onClose);

  if (!onClose) {
    return <section className="app-install-guide inline"><GuideBody listingId={listingId} /></section>;
  }

  return (
    <div ref={dialogRef} className="preview-backdrop" role="dialog" aria-modal="true" aria-labelledby="app-install-guide-title" onClick={onClose}>
      <section className="partner-preview-sheet app-install-guide" onClick={(event) => event.stopPropagation()}>
        <button className="preview-close" type="button" onClick={onClose} aria-label="Close install guide">×</button>
        <GuideBody listingId={listingId} />
      </section>
    </div>
  );
}
