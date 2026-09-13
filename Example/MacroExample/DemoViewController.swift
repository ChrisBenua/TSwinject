import TSwinject
import TSwinjectMacro
import UIKit

// MARK: - Domain

protocol CredentialsReading: AnyObject {
    var userID: String { get }
}

protocol TokenProviding: AnyObject {
    func token() -> String
}

protocol SessionClearing: AnyObject {
    func clear()
}

/// One concrete type exposed under three protocols — the situation `#implements`
/// exists for.
final class CredentialsService: CredentialsReading, TokenProviding, SessionClearing {
    let userID = "demo-user"
    func token() -> String { "demo-token" }
    func clear() {}
}

// MARK: - DemoViewController

final class DemoViewController: UIViewController {

    private lazy var textView = UITextView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        let container = Container()

        // The base registration is written by hand, with the real factory and the
        // scope that decides the instance's lifetime.
        container.register(CredentialsService.self, scope: .container) { _ in
            CredentialsService()
        }

        // The macro expands to one `.transient` forwarding registration per
        // protocol, each resolving the base type above.
        #implements(
            container,
            CredentialsService.self,
            CredentialsReading.self,
            TokenProviding.self,
            SessionClearing.self
        )

        let base = container.resolve(CredentialsService.self)
        let lines = [
            "CredentialsReading  -> \(container.resolve(CredentialsReading.self) === base)",
            "TokenProviding      -> \(container.resolve(TokenProviding.self) === base)",
            "SessionClearing     -> \(container.resolve(SessionClearing.self) === base)",
            "",
            "Each protocol resolves to the same container-scoped instance,",
            "with no protocol-existential cast on the resolve path."
        ]
        textView.text = lines.joined(separator: "\n")
    }
}

private extension DemoViewController {
    func setupUI() {
        title = "TSwinject #implements"
        view.backgroundColor = .systemBackground

        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate(
            [
                textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ]
        )
    }
}
