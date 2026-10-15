import UIKit

protocol InspectorPanelViewDelegate: AnyObject {
    func inspectorPanelView(_ panel: InspectorPanelView, didToggle layer: OverlayLayer)
    func inspectorPanelViewDidTapCopy(_ panel: InspectorPanelView)
    func inspectorPanelViewDidTapKeyboard(_ panel: InspectorPanelView)
}

final class InspectorPanelView: UIView {
    weak var delegate: InspectorPanelViewDelegate?

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let header = UIButton(type: .system)
    private let subtitle = UILabel()
    private let chipStack = UIStackView()
    private let reportView = UITextView()
    private let reportButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let keyboardButton = UIButton(type: .system)

    private var chipButtons: [OverlayLayer: UIButton] = [:]
    private var isExpanded = true
    private var showsReport = false
    private let bodyStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(snapshot: LayoutSnapshot, enabledLayers: Set<OverlayLayer>) {
        let hingeText: String
        if let hinge = snapshot.hinge {
            hingeText = "\(hinge.statusTitle)  \(String(format: "%.0f°", hinge.angleDegrees))"
        } else {
            hingeText = "no hinge"
        }
        header.setTitle(isExpanded ? "▾  Layout Playground" : "▸  Layout Playground", for: .normal)
        subtitle.text = "\(hingeText)   H \(LayoutSnapshot.sizeClass(snapshot.horizontalSizeClass))  V \(LayoutSnapshot.sizeClass(snapshot.verticalSizeClass))   \(snapshot.divisionRegions.count) div  \(snapshot.occlusionRegions.count) occ"
        reportView.text = snapshot.report
        for layer in OverlayLayer.allCases {
            applyChipAppearance(chipButtons[layer], layer: layer, isOn: enabledLayers.contains(layer))
        }
    }

    func setKeyboardShown(_ shown: Bool) {
        keyboardButton.setTitle(shown ? "Hide Keyboard" : "Show Keyboard", for: .normal)
    }

    private func setup() {
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = UIColor.black.withAlphaComponent(0.28)

        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        header.translatesAutoresizingMaskIntoConstraints = false
        header.contentHorizontalAlignment = .leading
        header.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        header.setTitleColor(.white, for: .normal)
        header.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)

        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.75)
        subtitle.numberOfLines = 2

        chipStack.translatesAutoresizingMaskIntoConstraints = false
        chipStack.axis = .vertical
        chipStack.spacing = 6
        chipStack.alignment = .leading

        let chipRows: [[OverlayLayer]] = [
            [.division, .occlusion, .safeArea],
            [.regionMargins, .bounds, .margins],
            [.readable, .keyboard, .bars]
        ]
        for rowLayers in chipRows {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.alignment = .fill
            row.distribution = .fill
            for layer in rowLayers {
                let button = makeChip(layer)
                chipButtons[layer] = button
                row.addArrangedSubview(button)
            }
            chipStack.addArrangedSubview(row)
        }

        reportView.translatesAutoresizingMaskIntoConstraints = false
        reportView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        reportView.textColor = UIColor.white.withAlphaComponent(0.92)
        reportView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        reportView.isEditable = false
        reportView.isSelectable = true
        reportView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        reportView.layer.cornerRadius = 10
        reportView.alwaysBounceVertical = true

        reportButton.translatesAutoresizingMaskIntoConstraints = false
        reportButton.setTitle("Show Report", for: .normal)
        reportButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        reportButton.addTarget(self, action: #selector(toggleReport), for: .touchUpInside)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setTitle("Copy Report", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

        keyboardButton.translatesAutoresizingMaskIntoConstraints = false
        keyboardButton.setTitle("Show Keyboard", for: .normal)
        keyboardButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        keyboardButton.addTarget(self, action: #selector(keyboardTapped), for: .touchUpInside)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        for button in [reportButton, copyButton, keyboardButton] {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let buttonRow = UIStackView(arrangedSubviews: [reportButton, copyButton, spacer, keyboardButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 16
        buttonRow.alignment = .center

        bodyStack.axis = .vertical
        bodyStack.spacing = 8
        bodyStack.alignment = .fill
        bodyStack.addArrangedSubview(chipStack)
        bodyStack.addArrangedSubview(reportView)
        bodyStack.addArrangedSubview(buttonRow)
        reportView.isHidden = true

        let root = UIStackView(arrangedSubviews: [header, subtitle, bodyStack])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.axis = .vertical
        root.spacing = 6
        root.alignment = .fill
        addSubview(root)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),

            root.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            reportView.heightAnchor.constraint(equalToConstant: 180)
        ])
    }

    private func makeChip(_ layer: OverlayLayer) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = layer.title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 12, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.inspectorPanelView(self, didToggle: layer)
        }, for: .touchUpInside)
        applyChipAppearance(button, layer: layer, isOn: true)
        return button
    }

    private func applyChipAppearance(_ button: UIButton?, layer: OverlayLayer, isOn: Bool) {
        guard let button else { return }
        var configuration = button.configuration ?? .plain()
        configuration.background.backgroundColor = isOn ? layer.color : UIColor.white.withAlphaComponent(0.12)
        configuration.baseForegroundColor = isOn ? .black : layer.color
        button.configuration = configuration
        button.layer.borderWidth = 1
        button.layer.borderColor = layer.color.cgColor
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        header.setTitle(isExpanded ? "▾  Layout Playground" : "▸  Layout Playground", for: .normal)
        animateLayout { self.bodyStack.isHidden = !self.isExpanded }
    }

    @objc private func toggleReport() {
        showsReport.toggle()
        reportButton.setTitle(showsReport ? "Hide Report" : "Show Report", for: .normal)
        animateLayout { self.reportView.isHidden = !self.showsReport }
    }

    private func animateLayout(_ changes: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2) {
            changes()
            self.superview?.layoutIfNeeded()
        }
    }

    @objc private func copyTapped() {
        delegate?.inspectorPanelViewDidTapCopy(self)
    }

    @objc private func keyboardTapped() {
        delegate?.inspectorPanelViewDidTapKeyboard(self)
    }
}
