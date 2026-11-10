import Foundation
import WebKit

/// Remplissage des pages de connexion avec l'identifiant du trousseau.
///
/// Le script tourne dans un « monde » JavaScript à part : la page ne voit ni ses variables ni le canal
/// par lequel il demande l'identifiant à l'app. L'app ne répond que si la demande vient de l'hôte du
/// service (un cadre d'un autre site n'obtient rien), et le mot de passe n'est lu dans le trousseau
/// qu'au moment où un formulaire de connexion apparaît.
enum Autofill {
    static let world = WKContentWorld.world(name: "LabPanelAutofill")
    static let handlerName = "labpanelAutofill"

    /// Installe le script et le canal dans la configuration d'une page.
    @MainActor
    static func install(in configuration: WKWebViewConfiguration, handler: AutofillHandler) {
        let controller = configuration.userContentController
        controller.addScriptMessageHandler(handler, contentWorld: world, name: handlerName)
        controller.addUserScript(WKUserScript(
            source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: world
        ))
    }

    /// Remplit tout de suite le formulaire affiché (commande « Remplir l'identifiant »).
    @MainActor
    static func fillNow(in webView: WKWebView) {
        webView.callAsyncJavaScript(
            "if (window.__labpanelAutofill) { await window.__labpanelAutofill.run(true); }",
            arguments: [:], in: nil, in: world
        ) { _ in }
    }

    /// Repère un formulaire de connexion (y compris dans le shadow DOM, comme chez Home Assistant,
    /// et sans balise <form>, comme chez Proxmox), le remplit, puis le valide si demandé.
    /// Deux étapes gérées : identifiant seul d'abord (DSM 7), mot de passe ensuite.
    /// Un même champ n'est jamais rempli deux fois : si la connexion échoue, rien ne recommence en boucle.
    static let script = #"""
    (() => {
      if (window.__labpanelAutofill) return;
      const channel = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.labpanelAutofill;
      if (!channel) return;

      const USER_HINT = /user|login|account|e-?mail|identifi|utilisateur|nom/i;
      const SUBMIT_TEXT = /^(log ?in|sign ?in|se connecter|connexion|connect|next|suivant|continuer|continue)$/i;
      const TEXT_TYPES = new Set(['', 'text', 'email', 'tel']);

      function isUsable(el) {
        if (!el || el.disabled || el.readOnly) return false;
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return false;
        const style = getComputedStyle(el);
        return style.visibility !== 'hidden' && style.display !== 'none' && style.opacity !== '0';
      }

      // Tous les champs, y compris ceux des shadow roots ouverts.
      function collect(root, inputs, buttons) {
        for (const el of root.querySelectorAll('*')) {
          const tag = el.tagName;
          if (tag === 'INPUT') {
            const type = (el.getAttribute('type') || '').toLowerCase();
            if (type === 'submit' || type === 'button') buttons.push(el); else inputs.push(el);
          } else if (tag === 'BUTTON' || el.getAttribute('role') === 'button' || (tag === 'A' && el.classList.contains('x-btn'))) {
            buttons.push(el);
          }
          if (el.shadowRoot) collect(el.shadowRoot, inputs, buttons);
        }
      }

      function describe(el) {
        return [el.name, el.id, el.getAttribute('autocomplete'), el.placeholder, el.getAttribute('aria-label')].join(' ');
      }

      function findFields() {
        const inputs = [], buttons = [];
        collect(document, inputs, buttons);
        const usable = inputs.filter(isUsable);
        const passwords = usable.filter((el) => el.type === 'password');
        const texts = usable.filter((el) => TEXT_TYPES.has((el.getAttribute('type') || '').toLowerCase()));
        const visibleButtons = buttons.filter(isUsable);

        if (passwords.length === 1) {
          // Plusieurs champs mot de passe : changement de mot de passe, on n'y touche pas.
          const password = passwords[0];
          const sameRoot = texts.filter((el) => el.getRootNode() === password.getRootNode());
          let user = null;
          for (const el of sameRoot) {
            if (el.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING) user = el;
          }
          if (!user) user = texts.find((el) => USER_HINT.test(describe(el))) || null;
          return { user, password, buttons: visibleButtons };
        }
        if (passwords.length === 0 && texts.length > 0 && texts.length <= 2) {
          const user = texts.find((el) => (el.getAttribute('autocomplete') || '') === 'username')
            || texts.find((el) => USER_HINT.test(describe(el)));
          if (user) return { user, password: null, buttons: visibleButtons };
        }
        return null;
      }

      const valueSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;

      function setValue(el, value) {
        el.focus();
        valueSetter.call(el, value);
        el.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, inputType: 'insertText', data: value }));
        el.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, composed: true, key: 'Unidentified' }));
      }

      function pressEnter(el) {
        for (const type of ['keydown', 'keypress', 'keyup']) {
          el.dispatchEvent(new KeyboardEvent(type, {
            bubbles: true, cancelable: true, composed: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13
          }));
        }
      }

      function submit(fields) {
        const field = fields.password || fields.user;
        const form = field.form;
        if (form && typeof form.requestSubmit === 'function') {
          const formButton = form.querySelector('button[type=submit], input[type=submit], button:not([type])');
          form.requestSubmit(formButton && isUsable(formButton) ? formButton : undefined);
          return;
        }
        const button = fields.buttons.find((b) => SUBMIT_TEXT.test(((b.innerText || b.textContent || b.value || '') + '').trim()));
        if (button) { button.click(); return; }
        pressEnter(field);
      }

      const filled = new WeakSet();
      let busy = false;

      async function run(force) {
        if (busy) return;
        const fields = findFields();
        if (!fields) return;
        const target = fields.password || fields.user;
        if (!force && filled.has(target)) return;
        busy = true;
        try {
          const reply = await channel.postMessage({ kind: 'credentials', force: !!force, step: fields.password ? 'password' : 'username' });
          if (!reply) return;
          if (fields.user && reply.username && (force || !fields.user.value)) setValue(fields.user, reply.username);
          if (fields.password) setValue(fields.password, reply.password);
          filled.add(target);
          if (reply.submit) setTimeout(() => submit(fields), 300);
        } catch (error) {
          // Pas de réponse de l'app : on n'insiste pas.
        } finally {
          busy = false;
        }
      }

      window.__labpanelAutofill = { run };

      channel.postMessage({ kind: 'config' }).then((config) => {
        if (!config || !config.enabled) return;
        let timer = null;
        const schedule = () => {
          if (timer) return;
          timer = setTimeout(() => { timer = null; run(false); }, 400);
        };
        schedule();
        // Les pages qui construisent leur formulaire après coup (Proxmox, DSM…), et le retour
        // de la fenêtre de connexion quand une session expire.
        new MutationObserver(schedule).observe(document, {
          subtree: true, childList: true, attributes: true, attributeFilter: ['style', 'class', 'hidden']
        });
        // Le shadow DOM échappe à l'observateur : quelques passages de plus après le chargement.
        let polls = 0;
        const poll = setInterval(() => { run(false); if (++polls >= 15) clearInterval(poll); }, 1500);
        window.addEventListener('focus', schedule);
        document.addEventListener('visibilitychange', schedule);
      }).catch(() => {});
    })();
    """#
}

/// Répond aux demandes du script, pour une page (et ses fenêtres surgissantes).
@MainActor
final class AutofillHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var session: WebSession?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let session,
              let body = message.body as? [String: Any],
              let kind = body["kind"] as? String
        else { return (nil, nil) }
        let host = message.frameInfo.securityOrigin.host
        let force = body["force"] as? Bool ?? false
        return (session.autofillReply(kind: kind, force: force, frameHost: host), nil)
    }
}
