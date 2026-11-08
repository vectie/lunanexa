///|
/// Install once for both portals. Only an explicit cancel control dismisses a
/// dialog; Escape and the backdrop never submit or confirm an operation.
pub extern "js" fn install_dialog_interactions() -> Unit =
  #| () => {
  #|   if (globalThis.__lunanexaDialogInteractions) return;
  #|   globalThis.__lunanexaDialogInteractions = true;
  #|   let active = null, previous = null;
  #|   const modal = d => d?.getAttribute('aria-modal') === 'true';
  #|   const tabbables = d => [...d.querySelectorAll('button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),summary,[tabindex="0"]')].filter(e => e.getClientRects().length && e.tabIndex >= 0);
  #|   const dismiss = () => {
  #|     const cancel = active?.querySelector('#api-key-issue-cancel,#api-key-revoke-cancel,#api-key-secret-dismiss,#api-key-connection-dismiss,#contract-confirmation-dismiss,#operator-confirmation-dismiss,#commerce-confirmation-dismiss');
  #|     if (!cancel || cancel.disabled) return false;
  #|     cancel.click(); return true;
  #|   };
  #|   const sync = () => {
  #|     const dialogs = document.querySelectorAll('[aria-modal="true"],[role="alertdialog"]');
  #|     const next = dialogs[dialogs.length - 1] || null;
  #|     if (next === active) return;
  #|     if (!active && next) previous = document.activeElement;
  #|     active = next;
  #|     if (active) { active.tabIndex = -1; (tabbables(active)[0] || active).focus(); }
  #|     else if (previous?.isConnected) { previous.focus(); previous = null; }
  #|   };
  #|   new MutationObserver(sync).observe(document.documentElement, {childList:true, subtree:true});
  #|   document.addEventListener('keydown', e => {
  #|     if (!active) return;
  #|     if (e.key === 'Escape' && dismiss()) e.preventDefault();
  #|     else if (e.key === 'Tab' && modal(active)) {
  #|       const els = tabbables(active), first = els[0] || active, last = els[els.length - 1] || active;
  #|       if (e.shiftKey && (document.activeElement === first || !active.contains(document.activeElement))) { e.preventDefault(); last.focus(); }
  #|       else if (!e.shiftKey && (document.activeElement === last || !active.contains(document.activeElement))) { e.preventDefault(); first.focus(); }
  #|     }
  #|   });
  #|   document.addEventListener('click', e => { if (active && e.target === active.closest('.modal-backdrop')) dismiss(); });
  #|   document.addEventListener('focusin', e => { if (modal(active) && !active.contains(e.target)) (tabbables(active)[0] || active).focus(); });
  #|   sync();
  #| }
