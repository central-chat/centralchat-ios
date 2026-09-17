// The Central Chat example — one screen, and the only file worth reading.
//
// It asks for a key and opens the chat. The whole integration is three lines;
// everything else here is the box around them:
//
//   CentralChat.init(entry)
//   CentralChat.show(from:)
//   CentralChat.hide()
//
// YOUR app has no key field. It asks its own backend for a mint user key on
// every launch — the key names the person and expires in minutes — and calls
// init with it.
import UIKit
import CentralChat

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class ViewController: UIViewController {

    private let field = UITextField()
    private let openButton = UIButton(type: .system)
    private let status = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        layout()

        CentralChat.onReady = { [weak self] in
            self?.openButton.isEnabled = true
            self?.status.text = ""
        }
        CentralChat.onError = { [weak self] error in
            // The library retries a transport failure by itself, so this only
            // reports. A refused key is the one an app has to answer, by minting
            // another — this demo has no backend, so it asks for another by hand.
            self?.openButton.isEnabled = false
            self?.status.text = "\(error.code.rawValue): \(error.message)"
        }
    }

    @objc private func test() {
        let entry = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !entry.isEmpty else { return }
        CentralChat.`init`(entry)          // step 1 — warms everything
        openButton.isHidden = false
    }

    @objc private func open() {
        CentralChat.show(from: self)     // step 2 — nothing is fetched here
    }

    private func layout() {
        let title = UILabel()
        title.text = "Central.chat test demo app"
        title.font = .boldSystemFont(ofSize: 26)

        let label = UILabel()
        label.text = "Channel key or mint user key"
        label.font = .boldSystemFont(ofSize: 13)

        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no

        let test = UIButton(type: .system)
        test.setTitle("Test", for: .normal)
        test.addTarget(self, action: #selector(self.test), for: .touchUpInside)

        openButton.setTitle("Open central.chat", for: .normal)
        openButton.isEnabled = false          // until onReady says otherwise
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(open), for: .touchUpInside)

        status.font = .systemFont(ofSize: 14)
        status.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [title, label, field, test, openButton, status])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
}
