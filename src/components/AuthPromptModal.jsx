// Shown when a guest attempts an action that requires identity (saving,
// personalization, business tools, etc.). It never performs the action itself;
// it routes the visitor to the existing auth flow (log in / create account) or
// lets them keep browsing. UI gating like this is a convenience prompt only --
// the real authorization stays server-side in Supabase RLS.
import { useEffect, useRef } from "react";

export default function AuthPromptModal({
  title = "Sign in to continue",
  message = "Create a free account or log in to use this. You can keep browsing as a guest in the meantime.",
  onLogin,
  onCreate,
  onCancel,
}) {
  const cardRef = useRef(null);
  const previouslyFocused = useRef(null);

  useEffect(() => {
    previouslyFocused.current = document.activeElement;
    // Move focus into the dialog for keyboard and screen-reader users.
    const firstButton = cardRef.current?.querySelector("button");
    firstButton?.focus();

    const onKeyDown = (event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        onCancel?.();
        return;
      }
      if (event.key !== "Tab") return;
      // Simple focus trap within the dialog.
      const focusable = cardRef.current?.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      if (!focusable || focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", onKeyDown, true);
    return () => {
      document.removeEventListener("keydown", onKeyDown, true);
      // Restore focus to the control that opened the dialog.
      if (previouslyFocused.current instanceof HTMLElement) {
        previouslyFocused.current.focus();
      }
    };
  }, [onCancel]);

  return (
    <div
      className="modal-backdrop auth-prompt-backdrop"
      onClick={onCancel}
      role="presentation"
    >
      <div
        className="auth-prompt-card"
        role="dialog"
        aria-modal="true"
        aria-labelledby="auth-prompt-title"
        aria-describedby="auth-prompt-message"
        ref={cardRef}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="auth-prompt-mark" aria-hidden="true">H</div>
        <h2 id="auth-prompt-title">{title}</h2>
        <p id="auth-prompt-message">{message}</p>

        <div className="auth-prompt-actions">
          <button type="button" className="primary-button" onClick={onCreate}>
            Create an account
          </button>
          <button type="button" className="secondary-button auth-prompt-secondary" onClick={onLogin}>
            Log in
          </button>
          <button type="button" className="text-button center" onClick={onCancel}>
            Continue browsing
          </button>
        </div>
      </div>
    </div>
  );
}
