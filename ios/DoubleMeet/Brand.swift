import UIKit

/// Glanser brand tokens: navy and cream as base, yellow only as accent.
enum Brand {
    static let navy = UIColor(hex: 0x1A2332)
    static let navyLight = UIColor(hex: 0x2D3848)
    static let cream = UIColor(hex: 0xF8F6F2)
    static let yellow = UIColor(hex: 0xE8FF00)
    static let blueFog = UIColor(hex: 0x7A8C99)
    static let skiffer = UIColor(hex: 0x455060)
    static let terrakotta = UIColor(hex: 0xE8AFA1)

    enum Weight { case regular, medium, bold }

    /// Space Grotesk, bundled in Fonts/. Falls back to the system font if registration failed.
    static func sans(_ size: CGFloat, _ weight: Weight = .regular) -> UIFont {
        let name: String
        let fallback: UIFont.Weight
        switch weight {
        case .regular: name = "SpaceGrotesk-Regular"; fallback = .regular
        case .medium: name = "SpaceGrotesk-Medium"; fallback = .medium
        case .bold: name = "SpaceGrotesk-Bold"; fallback = .bold
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallback)
    }

    /// DM Mono, used for labels, metadata and numbers.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> UIFont {
        let name = weight == .regular ? "DMMono-Regular" : "DMMono-Medium"
        return UIFont(name: name, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight == .regular ? .regular : .medium)
    }

    /// Uppercase mono label with wide tracking, the brand's eyebrow style.
    static func eyebrow(_ text: String, size: CGFloat = 12, color: UIColor = blueFog) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: mono(size, .medium),
            .foregroundColor: color,
            .kern: size * 0.1,
        ])
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Filled button in brand style. `primary` is the yellow call to action; use it once per screen.
final class BrandButton: UIButton {
    enum Style { case primary, secondary, danger }

    init(title: String, style: Style) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = Brand.sans(18, .medium)
        layer.cornerRadius = 8
        contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        switch style {
        case .primary:
            backgroundColor = Brand.yellow
            setTitleColor(Brand.navy, for: .normal)
        case .secondary:
            backgroundColor = Brand.navyLight
            setTitleColor(Brand.cream, for: .normal)
            layer.borderWidth = 1
            layer.borderColor = Brand.skiffer.cgColor
        case .danger:
            backgroundColor = Brand.navyLight
            setTitleColor(Brand.terrakotta, for: .normal)
            layer.borderWidth = 1
            layer.borderColor = Brand.terrakotta.withAlphaComponent(0.5).cgColor
        }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.75 : 1 }
    }
}
