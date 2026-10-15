import UIKit

final class ViewController: UIViewController, InspectorPanelViewDelegate {
    private let overlayView = RegionOverlayView()
    private let inspector = InspectorPanelView()
    private let keyboardField = UITextField()

    private var enabledLayers: Set<OverlayLayer> = [.safeArea, .division, .occlusion, .regionMargins, .bars]
    private var latestHinge: UIHinge?
    private var latestSnapshot: LayoutSnapshot?
    private var displayLink: CADisplayLink?
    private var hasScheduledSecondPass = false
    private var inspectorLeading: NSLayoutConstraint!
    private var inspectorBottom: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.enabledLayers = enabledLayers
        view.addSubview(overlayView)

        inspector.translatesAutoresizingMaskIntoConstraints = false
        inspector.delegate = self
        view.addSubview(inspector)

        keyboardField.translatesAutoresizingMaskIntoConstraints = false
        keyboardField.alpha = 0.01
        keyboardField.keyboardType = .default
        keyboardField.autocorrectionType = .no
        keyboardField.spellCheckingType = .no
        view.addSubview(keyboardField)

        inspectorLeading = inspector.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12)
        inspectorBottom = inspector.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)

        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            inspectorLeading,
            inspectorBottom,
            inspector.widthAnchor.constraint(equalToConstant: 360),
            inspector.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24),

            keyboardField.widthAnchor.constraint(equalToConstant: 1),
            keyboardField.heightAnchor.constraint(equalToConstant: 1),
            keyboardField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardField.topAnchor.constraint(equalTo: view.topAnchor)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleInspectorPan(_:)))
        inspector.addGestureRecognizer(pan)

        view.addInteraction(UIHingeInteraction { [weak self] _, update in
            guard let self else { return }
            self.latestHinge = update.hinge
            self.refreshSnapshot(reason: "hinge")
            self.updateDisplayLink()
        })

        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self, UITraitDisplayScale.self]) { (self: ViewController, _) in
            self.refreshSnapshot(reason: "traits")
        }

        NotificationCenter.default.addObserver(self, selector: #selector(sceneGeometryChanged), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged), name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshSnapshot(reason: "appear")
        scheduleSecondPassIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshSnapshot(reason: "layout")
        scheduleSecondPassIfNeeded()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        refreshSnapshot(reason: "safeArea")
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        refreshSnapshot(reason: "margins")
    }

    override var prefersHomeIndicatorAutoHidden: Bool { false }

    func inspectorPanelView(_ panel: InspectorPanelView, didToggle layer: OverlayLayer) {
        if enabledLayers.contains(layer) {
            enabledLayers.remove(layer)
        } else {
            enabledLayers.insert(layer)
        }
        overlayView.enabledLayers = enabledLayers
        if let latestSnapshot {
            inspector.configure(snapshot: latestSnapshot, enabledLayers: enabledLayers)
        }
    }

    func inspectorPanelViewDidTapCopy(_ panel: InspectorPanelView) {
        guard let report = latestSnapshot?.report else { return }
        UIPasteboard.general.string = report
        print(report)
    }

    func inspectorPanelViewDidTapKeyboard(_ panel: InspectorPanelView) {
        if keyboardField.isFirstResponder {
            keyboardField.resignFirstResponder()
            inspector.setKeyboardShown(false)
        } else {
            keyboardField.becomeFirstResponder()
            inspector.setKeyboardShown(true)
        }
    }

    @objc private func sceneGeometryChanged() {
        refreshSnapshot(reason: "scene")
    }

    @objc private func keyboardFrameChanged() {
        inspector.setKeyboardShown(keyboardField.isFirstResponder)
        view.setNeedsLayout()
        refreshSnapshot(reason: "keyboard")
    }

    @objc private func handleInspectorPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        inspectorLeading.constant += translation.x
        inspectorBottom.constant += translation.y
        gesture.setTranslation(.zero, in: view)
        view.layoutIfNeeded()
        clampInspector()
    }

    private func clampInspector() {
        let margin: CGFloat = 8
        let safe = view.convert(view.safeAreaLayoutGuide.layoutFrame, from: view)
        var frame = inspector.frame
        frame.origin.x = min(max(frame.origin.x, safe.minX + margin), max(safe.minX + margin, safe.maxX - frame.width - margin))
        frame.origin.y = min(max(frame.origin.y, safe.minY + margin), max(safe.minY + margin, safe.maxY - frame.height - margin))
        inspectorLeading.constant = frame.minX - safe.minX
        inspectorBottom.constant = frame.maxY - safe.maxY
    }

    private func refreshSnapshot(reason: String) {
        let snapshot = LayoutSnapshot.capture(from: view, viewController: self, hinge: latestHinge)
        let changed = snapshot != latestSnapshot
        latestSnapshot = snapshot
        overlayView.snapshot = snapshot
        if changed || reason == "hinge" {
            inspector.configure(snapshot: snapshot, enabledLayers: enabledLayers)
        }
        if reason == "hinge" || reason == "appear" {
            print("[\(reason)] reserved=\(snapshot.reserved.count) hinge=\(snapshot.hinge?.statusTitle ?? "nil") view=\(LayoutSnapshot.rect(snapshot.viewBounds))")
        }
    }

    private func scheduleSecondPassIfNeeded() {
        guard hasScheduledSecondPass == false else { return }
        hasScheduledSecondPass = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshSnapshot(reason: "second-pass")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshSnapshot(reason: "delayed-pass")
        }
    }

    private func updateDisplayLink() {
        let shouldRun = latestHinge?.status == .partiallyOpen
        if shouldRun {
            if displayLink == nil {
                let link = view.window?.windowScene?.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
                link?.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        refreshSnapshot(reason: "displayLink")
    }
}
