import UIKit

/// Settings sheet, opened by holding a finger on the screen for 2 seconds.
final class SettingsViewController: UIViewController, UITextFieldDelegate {
    var onSave: ((Settings) -> Void)?
    var onGoogleSignIn: (() -> Void)?
    var onLeaveMeeting: (() -> Void)?

    private var settings: Settings
    private var fields: [UITextField] = []

    private enum Field: Int, CaseIterable {
        case supabaseURL, supabaseKey, room, robotEmail, robotPassword, controllerURL, guestName

        var label: String {
            switch self {
            case .supabaseURL: return "Supabase URL"
            case .supabaseKey: return "Publishable key"
            case .room: return "Kanal"
            case .robotEmail: return "Robotkontots e-post"
            case .robotPassword: return "Robotkontots lösenord"
            case .controllerURL: return "Styrsidans adress (visas på viloskärmen)"
            case .guestName: return "Namn i Meet"
            }
        }
    }

    init(settings: Settings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Brand.navy

        let title = UILabel()
        title.text = "Inställningar"
        title.font = Brand.sans(34, .bold)
        title.textColor = Brand.cream

        let eyebrow = UILabel()
        eyebrow.attributedText = Brand.eyebrow("DoubleMeet")

        let stack = UIStackView(arrangedSubviews: [eyebrow, title])
        stack.axis = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(28, after: title)

        for field in Field.allCases {
            stack.addArrangedSubview(makeField(field))
            stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
        }

        let save = BrandButton(title: "Spara", style: .primary)
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        let cancel = BrandButton(title: "Avbryt", style: .secondary)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [cancel, save])
        row.spacing = 12
        row.distribution = .fillEqually
        stack.setCustomSpacing(28, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(row)

        let toolsLabel = UILabel()
        toolsLabel.attributedText = Brand.eyebrow("Verktyg")
        stack.setCustomSpacing(36, after: row)
        stack.addArrangedSubview(toolsLabel)
        stack.setCustomSpacing(10, after: toolsLabel)

        let google = BrandButton(title: "Logga in roboten på Google", style: .secondary)
        google.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)
        let leave = BrandButton(title: "Lämna mötet", style: .danger)
        leave.addTarget(self, action: #selector(leaveTapped), for: .touchUpInside)
        stack.addArrangedSubview(google)
        stack.setCustomSpacing(12, after: google)
        stack.addArrangedSubview(leave)

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -32),
        ])
    }

    private func makeField(_ field: Field) -> UIView {
        let label = UILabel()
        label.attributedText = Brand.eyebrow(field.label)

        let input = UITextField()
        input.tag = field.rawValue
        input.text = value(of: field)
        input.font = Brand.sans(18)
        input.textColor = Brand.cream
        input.tintColor = Brand.yellow
        input.backgroundColor = Brand.navyLight
        input.layer.cornerRadius = 8
        input.layer.borderWidth = 1
        input.layer.borderColor = Brand.skiffer.cgColor
        input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        input.leftViewMode = .always
        input.autocapitalizationType = .none
        input.autocorrectionType = .no
        input.clearButtonMode = .whileEditing
        input.isSecureTextEntry = field == .robotPassword
        input.keyboardType = (field == .supabaseURL || field == .controllerURL) ? .URL
            : (field == .robotEmail ? .emailAddress : .default)
        input.returnKeyType = field == Field.allCases.last ? .done : .next
        input.delegate = self
        input.heightAnchor.constraint(equalToConstant: 52).isActive = true
        fields.append(input)

        let group = UIStackView(arrangedSubviews: [label, input])
        group.axis = .vertical
        group.spacing = 8
        return group
    }

    private func value(of field: Field) -> String {
        switch field {
        case .supabaseURL: return settings.supabaseURL
        case .supabaseKey: return settings.supabaseKey
        case .room: return settings.room
        case .robotEmail: return settings.robotEmail
        case .robotPassword: return settings.robotPassword
        case .controllerURL: return settings.controllerURL
        case .guestName: return settings.guestName
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let next = fields.first { $0.tag == textField.tag + 1 }
        if let next = next { next.becomeFirstResponder() } else { textField.resignFirstResponder() }
        return true
    }

    @objc private func saveTapped() {
        func text(_ field: Field) -> String {
            (fields.first { $0.tag == field.rawValue }?.text ?? "").trimmingCharacters(in: .whitespaces)
        }
        settings.supabaseURL = text(.supabaseURL)
        settings.supabaseKey = text(.supabaseKey)
        settings.room = text(.room)
        settings.robotEmail = text(.robotEmail)
        settings.robotPassword = fields.first { $0.tag == Field.robotPassword.rawValue }?.text ?? ""
        settings.controllerURL = text(.controllerURL)
        settings.guestName = text(.guestName)
        let saved = settings
        dismiss(animated: true) { [onSave] in onSave?(saved) }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func googleTapped() {
        dismiss(animated: true) { [onGoogleSignIn] in onGoogleSignIn?() }
    }

    @objc private func leaveTapped() {
        dismiss(animated: true) { [onLeaveMeeting] in onLeaveMeeting?() }
    }
}
