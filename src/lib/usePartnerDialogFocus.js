import { useEffect, useRef } from "react";

// Owner editor/media dialogs must keep keyboard and assistive focus inside the
// active dialog and return to the action that opened it. No account data lives here.
export function usePartnerDialogFocus(onClose) {
  const dialogRef = useRef(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    const opener = document.activeElement;
    const focusable = () => [...dialog.querySelectorAll(
      'button:not(:disabled), input:not(:disabled), textarea:not(:disabled), select:not(:disabled), a[href], [tabindex="0"]'
    )].filter((element) => element.getClientRects().length && !element.closest('[inert]'));
    const enter = () => (focusable()[0] || dialog).focus();
    const background = [];
    for (let node = dialog; node.parentElement; node = node.parentElement) {
      for (const sibling of node.parentElement.children) {
        if (sibling !== node && !sibling.inert) {
          sibling.inert = true;
          background.push(sibling);
        }
      }
      if (node.parentElement === document.body) break;
    }
    const onKeyDown = (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        closeRef.current?.();
      } else if (event.key === "Tab") {
        const elements = focusable();
        const first = elements[0] || dialog;
        const last = elements.at(-1) || dialog;
        if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }
    };
    const onFocus = (event) => {
      if (!dialog.contains(event.target)) enter();
    };
    dialog.addEventListener("keydown", onKeyDown);
    document.addEventListener("focusin", onFocus);
    enter();
    return () => {
      dialog.removeEventListener("keydown", onKeyDown);
      document.removeEventListener("focusin", onFocus);
      for (const sibling of background) sibling.inert = false;
      if (opener?.isConnected) opener.focus();
    };
  }, []);

  return dialogRef;
}
