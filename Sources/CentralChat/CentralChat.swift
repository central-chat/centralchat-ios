// Central Chat — iOS.
//
//   CentralChat.init(entry)   warms everything
//   CentralChat.show(from:)   reveals it
//   CentralChat.hide()        puts it away
//
// `entry` is the one thing the app supplies, and it names both the line and the
// visitor. See `CentralChat.init(_:)`.
//
// Info.plist, for the composer's own buttons — each string is what iOS shows
// the person when it asks, so write it in their language:
//   NSMicrophoneUsageDescription        voice messages
//   NSCameraUsageDescription            photos taken in the chat
//   NSPhotoLibraryUsageDescription      photos chosen from the library
//   NSLocationWhenInUseUsageDescription a shared location
// Leave out the ones your line never offers; an undeclared use is simply never
// asked for.
import UIKit
import WebKit

private let defaultContainerURL = URL(string: "https://web.central.chat/widget/container.html")!

// Generous against a cold renderer on a slow network. It is the backstop for
// every failure the layers below cannot see: without it a dropped handshake
// leaves the host with no success and no failure, forever.
private let readyTimeout: TimeInterval = 20

public enum CentralChatErrorCode: String {
    case entryInvalid = "ENTRY_INVALID"
    case tokenExpired = "TOKEN_EXPIRED"
    case network = "NETWORK"
    case internalError = "INTERNAL"
}

public struct CentralChatError {
    public let code: CentralChatErrorCode
    public let message: String
}

/**
 The whole public surface.

 Every method hops to the main queue if it is not already there — a WKWebView
 may only be touched there, and calling init straight from the background
 request that fetched the token is the obvious mistake to make.
 */
public enum CentralChat {

    /// Optional. Set it once if you want to hear about failures.
    public static var onError: ((CentralChatError) -> Void)?

    /// Optional. Fires once per init, when the chat is warm and ready to show.
    public static var onReady: (() -> Void)?

    /// The page the web view loads. Set it before the first `init` to point at a
    /// staging tier; the default is the production one and needs no configuration.
    public static var containerURL: URL = defaultContainerURL

    /**
     Warms the chat. Call it as early as you have an entry — app start is right.

     `entry` is either door:
      - `"<businessId>|<chatAccountId>"` — an **anonymous** visitor on that line.
        Both ids are public; nothing is signed and no backend of yours is in the
        loop. A line configured `onlyValidatedUsers` refuses this door.
      - an **App Entry JWT** your backend minted — a **verified** visitor. The
        line comes out of the token's `bid`/`cid` protected header, so the ids
        are not passed separately. A token always wins over the ids.

     `|` is not in the base64url alphabet a JWT is spelled with, so the two can
     never be confused.

     Idempotent by design: the host may call this on every launch, and
     re-entering an identical session would throw away a warm thread for
     nothing. Only a DIFFERENT entry is a different person, and that does
     re-enter.
     */
    public static func `init`(_ entry: String) {
        onMain {
            // Refused, never trapped: an entry is a value that arrives at
            // runtime — a mint your backend returned, a key somebody pasted —
            // and a library that kills its host over one turns their bad input
            // into your crash report. ENTRY_INVALID is the same answer the page
            // gives for every other entry it will not take.
            if entry.isEmpty || entry.hasPrefix("|") || entry.hasSuffix("|") {
                refuse("not an App Entry jwt or a businessId|chatAccountId")
                return
            }
            if state.web != nil && entry == state.entryInUse {
                if state.resolved { onReady?() }
                return
            }
            state.entryInUse = entry
            state.pendingEntry = entry
            state.resolved = false
            state.retried = false
            restartTimeout()

            let web = state.web ?? makeWebView()
            if state.pageLoaded { sendInit(web) } else { web.load(URLRequest(url: containerURL)) }
        }
    }

    /// The anonymous door, spelled out: the same as `init("\(businessId)|\(chatAccountId)")`.
    public static func `init`(businessId: String, chatAccountId: String) {
        CentralChat.`init`("\(businessId)|\(chatAccountId)")
    }

    /**
     Presents the warm chat. Nothing is fetched here — that already happened.
     Safe to call before the chat is ready: the screen appears and fills in.
     */
    public static func show(from presenter: UIViewController) {
        onMain {
            precondition(state.web != nil, "CentralChat.init() must be called before show()")
            state.shown = true
            guard state.presented == nil else {
                applyVisibility()
                return
            }
            let screen = CentralChatViewController()
            screen.modalPresentationStyle = .fullScreen
            state.presented = screen
            presenter.present(screen, animated: true)
        }
    }

    /**
     Puts it away, keeping the session, the thread and the scroll position. The
     web view is detached, never destroyed — which is what makes the next show
     instant.
     */
    public static func hide() {
        onMain {
            state.shown = false
            applyVisibility()
            state.presented?.dismiss(animated: true)
            state.presented = nil
        }
    }

    // ---- machinery ----------------------------------------------------------

    final class State {
        var web: WKWebView?
        var presented: CentralChatViewController?
        var entryInUse: String?
        var pendingEntry: String?
        var pageLoaded = false
        var resolved = false
        var retried = false
        // What show()/hide() asked for, kept here because the page is reloaded
        // on retry and the screen can be recreated under it.
        var shown = false
        var timeout: DispatchWorkItem?
    }

    static let state = State()
    private static let delegate = WebDelegate()

    static var web: WKWebView? { state.web }

    /// The one origin this web view is allowed to stay on.
    static var containerHost: String { containerURL.host ?? "" }

    private static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(Bridge(), name: "CentralChatNative")
        // Voice notes record and play in place rather than taking over the screen.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // The session survives restarts: this is the store the chat keeps its
        // keys and its thread in. Named and persistent on purpose — an app's own
        // "clear cache" feature must not take the chat history with it, because
        // history is encrypted to devices and a wipe drops the keys.
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = delegate
        web.uiDelegate = delegate
        state.web = web
        return web
    }

    // The page's own inline script defines CentralChat, so the document has to
    // have been parsed before anything is sent to it.
    static func sendInit(_ web: WKWebView) {
        guard let entry = state.pendingEntry else { return }
        state.pendingEntry = nil
        // JSONSerialization does the quoting; nothing is spliced into JavaScript.
        guard let data = try? JSONSerialization.data(withJSONObject: [entry], options: []),
              let array = String(data: data, encoding: .utf8) else { return }
        // The capability goes in the SAME evaluate, ahead of init: the page
        // reads it when it mounts, and a second evaluate could land after that.
        //
        // Guarded, and not optionally so: the page ships on the CDN
        // independently of this app, so a library is ALWAYS newer than some
        // container out there. Calling a method an older page does not define
        // throws before init() on the same line, and the chat never starts —
        // which is a blank screen and a 20-second INTERNAL, from a feature that
        // was meant to be optional.
        web.evaluateJavaScript(
            "if(CentralChat.useNativeStorage)CentralChat.useNativeStorage();"
                + "CentralChat.init(\(array)[0])"
        )
    }

    /**
     Replays the current visibility into the page.

     show() is allowed before the chat is ready, and the screen can be recreated
     at any time, so the page is never the record of what is shown — `shown` is,
     and this is how the page catches up with it.
     */
    static func applyVisibility() {
        guard let web = state.web, state.pageLoaded else { return }
        web.evaluateJavaScript(state.shown ? "CentralChat.show()" : "CentralChat.hide()")
    }

    private static func restartTimeout() {
        state.timeout?.cancel()
        let work = DispatchWorkItem {
            fail(CentralChatError(code: .internalError, message: "the chat never became ready"))
        }
        state.timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + readyTimeout, execute: work)
    }

    static func ready() {
        onMain {
            state.timeout?.cancel()
            guard !state.resolved else { return }
            state.resolved = true
            onReady?()
        }
    }

    /// Turn away an entry this library can see is malformed, loading nothing.
    static func refuse(_ message: String) {
        state.timeout?.cancel()
        state.entryInUse = nil
        state.pendingEntry = nil
        state.resolved = true
        onError?(CentralChatError(code: .entryInvalid, message: message))
    }

    /**
     One automatic reload, for transport failures only.

     The page's HTML and its scripts come from two origins, each with its own
     DNS and TLS; a stalled second fetch leaves a document that looks healthy and
     never boots. A reload usually just works. A rejected entry is never retried
     — the same one is rejected identically, and minting another is the host's
     call, not ours.
     */
    static func fail(_ error: CentralChatError) {
        onMain {
            state.timeout?.cancel()
            guard !state.resolved else { return }
            if !state.retried, error.code == .network, let web = state.web {
                state.retried = true
                state.pageLoaded = false
                state.pendingEntry = state.entryInUse
                web.load(URLRequest(url: containerURL))
                restartTimeout()
                return
            }
            state.resolved = true
            onError?(error)
        }
    }

    /// Answer one storage request. The Keychain work is off the main queue.
    static func answerStorage(_ event: [String: Any]) {
        guard let rid = event["rid"] as? String, !rid.isEmpty else { return }
        let payload = event["payload"] as? [String: Any] ?? [:]
        storageQueue.async {
            do {
                let body: [String: Any]
                switch payload["op"] as? String {
                case "get":
                    let key = try required(payload, "key")
                    // NSNull, not a missing field: a key that is not there is an
                    // answer, and the page reads either as "nothing".
                    body = ["value": SecureStorage.get(key) as Any? ?? NSNull()]
                // The batch a boot actually sends: sixty keys as one frame
                // rather than sixty round trips before the first paint.
                case "getMany":
                    let keys = payload["keys"] as? [String] ?? []
                    // Positional and exactly as long as what was asked for;
                    // a miss is NSNull, never a hole that shortens the array.
                    body = ["values": keys.map { SecureStorage.get($0) as Any? ?? NSNull() }]
                case "setMany":
                    for pair in payload["entries"] as? [[String]] ?? [] where pair.count == 2 {
                        try SecureStorage.set(pair[0], pair[1])
                    }
                    body = [:]
                case "set":
                    try SecureStorage.set(try required(payload, "key"), try required(payload, "value"))
                    body = [:]
                case "remove":
                    try SecureStorage.remove(try required(payload, "key"))
                    body = [:]
                case "list":
                    body = ["keys": SecureStorage.list(prefix: payload["prefix"] as? String ?? "")]
                default:
                    throw NSError(domain: "chat.central.widget.storage", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "unknown storage op"])
                }
                replyStorage(rid, ok: true, body: body)
            } catch {
                // A Keychain that cannot answer has told the truth, and the
                // widget treats a refusal as an answer. Swallowing it into an
                // empty value would look like "no session" and silently sign
                // the visitor out.
                replyStorage(rid, ok: false, body: error.localizedDescription)
            }
        }
    }

    private static let storageQueue = DispatchQueue(label: "chat.central.widget.storage")

    private static func required(_ payload: [String: Any], _ field: String) throws -> String {
        guard let value = payload[field] as? String else {
            throw NSError(domain: "chat.central.widget.storage", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "storage request has no \(field)"])
        }
        return value
    }

    private static func replyStorage(_ rid: String, ok: Bool, body: Any) {
        // One array through JSONSerialization does every bit of the quoting —
        // the rid and the body alike — so nothing is spliced into JavaScript.
        guard let data = try? JSONSerialization.data(withJSONObject: [rid, body], options: []),
              let args = String(data: data, encoding: .utf8) else { return }
        onMain {
            state.web?.evaluateJavaScript(
                "(function(a){CentralChat.storageResult(a[0],\(ok),a[1])})(\(args))"
            )
        }
    }

    private static func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    /// Every chat event arrives here as one JSON string.
    private final class Bridge: NSObject, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let text = message.body as? String,
                  let data = text.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            switch event["type"] as? String {
            // Not an event: a REQUEST, and the only frame this bridge has to
            // answer rather than observe.
            case "storage":
                CentralChat.answerStorage(event)
            case "ready":
                CentralChat.ready()
            // The page never navigates itself away from the bundle: it turns a
            // tapped link into this event and waits for the host to act.
            // Nothing here means a dead link.
            case "linkActivated":
                let payload = event["payload"] as? [String: Any] ?? [:]
                if let text = payload["url"] as? String, let url = URL(string: text) {
                    DispatchQueue.main.async { UIApplication.shared.open(url) }
                }
            case "error":
                let payload = event["payload"] as? [String: Any] ?? [:]
                let code = CentralChatErrorCode(rawValue: payload["code"] as? String ?? "") ?? .internalError
                CentralChat.fail(CentralChatError(code: code, message: payload["message"] as? String ?? ""))
            default:
                break
            }
        }
    }

    private final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            CentralChat.state.pageLoaded = true
            CentralChat.sendInit(web)
            CentralChat.applyVisibility()
        }

        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            CentralChat.fail(CentralChatError(code: .network, message: "could not load the chat"))
        }

        func webView(_ web: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            CentralChat.fail(CentralChatError(code: .network, message: "could not load the chat"))
        }

        // Returning early says this was handled — without it a renderer killed
        // under memory pressure takes the whole host app down with it.
        func webViewWebContentProcessDidTerminate(_ web: WKWebView) {
            CentralChat.state.pageLoaded = false
            CentralChat.fail(CentralChatError(code: .network, message: "the chat renderer stopped"))
        }

        // Pinned to one origin: anything else is a link inside a message, and
        // belongs in the browser, not in a web view holding a live session.
        func webView(_ web: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.host == CentralChat.containerHost || action.targetFrame?.isMainFrame == false {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }

        /**
         The chat itself is a SUBFRAME, and the line it is asked for is in its
         path — so this is where a channel key that names no line shows up, as a
         404 on an inner document nobody else is watching. Without it the entry
         is only caught by the ready timeout: reported as a transient failure,
         when it is a permanent one no retry can fix.

         WebKit hands over subframe responses here; the React Native package
         cannot do the same, because `react-native-webview` drops everything but
         the main frame before JavaScript ever sees it.
         */
        func webView(_ web: WKWebView,
                     decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(.allow)
            guard !response.isForMainFrame,
                  let http = response.response as? HTTPURLResponse,
                  (400...499).contains(http.statusCode),
                  let url = response.response.url,
                  url.host == CentralChat.containerHost,
                  url.path.hasSuffix("/host.html")
            else { return }
            CentralChat.fail(
                CentralChatError(code: .entryInvalid, message: "no line answers this entry")
            )
        }

        // The composer's microphone and camera. iOS still asks the person the
        // first time, using the Info.plist strings above — this only says the
        // page is allowed to ask.
        func webView(_ web: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host == CentralChat.containerHost ? .prompt : .deny)
        }
    }
}
