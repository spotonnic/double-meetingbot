import UIKit

/// What the robot shows in the office when it is not in a meeting.
final class IdleView: UIView {
    struct State {
        var baseConnected: Bool
        var battery: Int
        var charging: Bool
        var linkText: String
        var linkOK: Bool
        var controllerURL: String
    }

    private let logo = UIImageView(image: UIImage(named: "Logo"))
    private let stars = UIImageView(image: UIImage(named: "Stars"))
    private let eyebrow = UILabel()
    private let headline = UILabel()
    private let body = UILabel()
    private let urlLabel = UILabel()
    private let baseRow = StatusRow()
    private let linkRow = StatusRow()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Brand.navy

        logo.contentMode = .scaleAspectFit
        stars.contentMode = .scaleAspectFit
        stars.alpha = 0.9

        eyebrow.attributedText = Brand.eyebrow("Glanser · Kontorsrobot", size: 14)
        headline.text = "Ledig"
        headline.font = Brand.sans(88, .bold)
        headline.textColor = Brand.cream
        body.text = "Skicka in mig i ett möte från styrsidan, så kör jag dit."
        body.font = Brand.sans(26)
        body.textColor = Brand.cream.withAlphaComponent(0.8)
        body.numberOfLines = 0
        urlLabel.font = Brand.mono(20, .medium)
        urlLabel.textColor = Brand.yellow
        urlLabel.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [eyebrow, headline, body, urlLabel])
        text.axis = .vertical
        text.spacing = 16
        text.setCustomSpacing(4, after: eyebrow)
        text.setCustomSpacing(32, after: body)

        let status = UIStackView(arrangedSubviews: [baseRow, linkRow])
        status.axis = .vertical
        status.spacing = 12

        let divider = UIView()
        divider.backgroundColor = Brand.skiffer

        for v in [logo, stars, text, divider, status] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let guide = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            logo.topAnchor.constraint(equalTo: guide.topAnchor, constant: 64),
            logo.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 64),
            logo.widthAnchor.constraint(equalToConstant: 220),
            logo.heightAnchor.constraint(equalTo: logo.widthAnchor, multiplier: 380.0 / 1080.0),

            stars.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -48),
            stars.topAnchor.constraint(equalTo: guide.topAnchor, constant: 40),
            stars.widthAnchor.constraint(equalToConstant: 160),
            stars.heightAnchor.constraint(equalTo: stars.widthAnchor),

            text.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 64),
            text.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -64),
            text.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),

            status.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 64),
            status.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -64),
            status.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -64),

            divider.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -24),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ state: State) {
        urlLabel.text = state.controllerURL
        urlLabel.isHidden = state.controllerURL.isEmpty
        let base = state.baseConnected
            ? "Basen ansluten · \(state.battery)%" + (state.charging ? " · laddar" : "")
            : "Basen är inte ansluten"
        baseRow.set(base, ok: state.baseConnected)
        linkRow.set(state.linkText, ok: state.linkOK)
    }
}

/// Dot plus mono label.
final class StatusRow: UIView {
    private let dot = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        dot.layer.cornerRadius = 6
        label.font = Brand.mono(18, .medium)
        label.textColor = Brand.cream
        for v in [dot, label] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(_ text: String, ok: Bool) {
        label.text = text.uppercased()
        dot.backgroundColor = ok ? Brand.yellow : Brand.terrakotta
    }
}
