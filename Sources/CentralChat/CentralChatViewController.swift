import UIKit

/**
 The only screen this library ever shows.

 It owns the presentation so the host never has to: a web view kept warm across
 hide()/show() outlives whichever screen displayed it, so it is re-parented here
 rather than rebuilt. The file picker and the location prompt are WKWebView's
 own and need nothing from us.
 */
final class CentralChatViewController: UIViewController {

    private var webBottom: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        guard let web = CentralChat.web else {
            // show() before init(), or a teardown raced it. Closing is honest.
            dismiss(animated: false)
            return
        }
        // Defensive: the web view outlives every screen that shows it.
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        // The safe area keeps the page's own composer clear of the home
        // indicator; the keyboard is the same class of inset but WKWebView
        // never shrinks for it, so `bottom` is driven by hand below.
        let bottom = web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        webBottom = bottom
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bottom,
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        observeKeyboard()

        let close = UIButton(type: .system)
        close.setTitle("\u{2715}", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 20)
        // Explicit: the chat's header is light whatever the host app's
        // appearance is, and an inherited dark-mode tint disappears into it.
        close.setTitleColor(UIColor(red: 0.24, green: 0.25, blue: 0.26, alpha: 1), for: .normal)
        close.accessibilityLabel = "Close the chat"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            close.widthAnchor.constraint(equalToConstant: 48),
            close.heightAnchor.constraint(equalToConstant: 48),
        ])

        CentralChat.applyVisibility()
    }

    @objc private func closeTapped() {
        CentralChat.hide()
    }

    private func observeKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardChanged),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
        center.addObserver(
            self,
            selector: #selector(keyboardChanged),
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
        )
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let bottom = webBottom else { return }
        let info = note.userInfo
        let end = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let hiding = note.name == UIResponder.keyboardWillHideNotification
        let covered = hiding ? 0 : max(0, view.bounds.maxY - view.convert(end, from: nil).minY)
        // The web view already stops at the safe area, so only what the
        // keyboard takes beyond it is left to give back.
        bottom.constant = -max(0, covered - view.safeAreaInsets.bottom)

        let duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = (info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int).map {
            UIView.AnimationOptions(rawValue: UInt($0) << 16)
        } ?? .curveEaseInOut
        UIView.animate(withDuration: duration, delay: 0, options: curve) {
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Detached, never destroyed: the next show() re-parents this same warm
        // instance, which is what makes re-entry instant.
        CentralChat.web?.removeFromSuperview()
    }
}
