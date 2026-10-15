import UIKit

enum OverlayLayer: String, CaseIterable, Hashable {
    case bounds
    case safeArea
    case margins
    case readable
    case keyboard
    case division
    case occlusion
    case regionMargins
    case bars

    var title: String {
        switch self {
        case .bounds: "Bounds"
        case .safeArea: "Safe Area"
        case .margins: "Margins"
        case .readable: "Readable"
        case .keyboard: "Keyboard"
        case .division: "Division"
        case .occlusion: "Occlusion"
        case .regionMargins: "Region Margins"
        case .bars: "Bars 56"
        }
    }

    var color: UIColor {
        switch self {
        case .bounds: UIColor.white
        case .safeArea: UIColor.systemGreen
        case .margins: UIColor.systemYellow
        case .readable: UIColor.systemTeal
        case .keyboard: UIColor.systemPurple
        case .division: UIColor.systemPink
        case .occlusion: UIColor.systemOrange
        case .regionMargins: UIColor.systemRed
        case .bars: UIColor.systemCyan
        }
    }
}

struct GuideSnapshot: Equatable {
    var name: String
    var frame: CGRect
    var insets: UIEdgeInsets
}

struct ReservedRegionSnapshot: Equatable {
    var idDescription: String
    var kind: UIView.ReservedRegion.Kind
    var frame: CGRect
    var margins: UIEdgeInsets
    var isActive: Bool

    var coreFrame: CGRect {
        frame.inset(by: margins)
    }

    var overlayLayer: OverlayLayer {
        kind == .division ? .division : .occlusion
    }
}

struct HingeSnapshot: Equatable {
    var status: UIHinge.Status
    var angleRadians: CGFloat

    var angleDegrees: CGFloat {
        angleRadians * 180 / .pi
    }

    var statusTitle: String {
        switch status {
        case .unknown: "unknown"
        case .closed: "closed"
        case .partiallyOpen: "partiallyOpen"
        case .fullyOpen: "fullyOpen"
        @unknown default: "status(\(status.rawValue))"
        }
    }
}

struct LayoutSnapshot: Equatable {
    var viewBounds: CGRect
    var windowBounds: CGRect
    var sceneBounds: CGRect
    var screenMainBounds: CGRect
    var scale: CGFloat
    var horizontalSizeClass: UIUserInterfaceSizeClass
    var verticalSizeClass: UIUserInterfaceSizeClass
    var interfaceOrientation: UIInterfaceOrientation
    var isInteractivelyResizing: Bool
    var hinge: HingeSnapshot?
    var safeArea: GuideSnapshot
    var layoutRegionSafeArea: GuideSnapshot
    var margins: GuideSnapshot
    var layoutRegionMargins: GuideSnapshot
    var readable: GuideSnapshot
    var layoutRegionReadable: GuideSnapshot
    var keyboard: GuideSnapshot
    var directionalLayoutMargins: NSDirectionalEdgeInsets
    var additionalSafeAreaInsets: UIEdgeInsets
    var reserved: [ReservedRegionSnapshot]
    var bars: [GuideSnapshot]

    var divisionRegions: [ReservedRegionSnapshot] {
        reserved.filter { $0.kind == .division }
    }

    var occlusionRegions: [ReservedRegionSnapshot] {
        reserved.filter { $0.kind == .occlusion }
    }

    var report: String {
        var lines: [String] = []
        lines.append("LAYOUT PLAYGROUND")
        lines.append("Simulator: hold Option and drag to fold. On device, open, book-fold, and close the Duo.")
        lines.append("")
        lines.append("SCENE")
        lines.append("  view               \(Self.rect(viewBounds))")
        lines.append("  window             \(Self.rect(windowBounds))")
        lines.append("  scene              \(Self.rect(sceneBounds))")
        lines.append("  UIScreen.main      \(Self.rect(screenMainBounds))  (do not lay out from this)")
        lines.append("  scale              \(String(format: "%.0f", scale))x")
        lines.append("  size class         \(Self.sizeClass(horizontalSizeClass)) × \(Self.sizeClass(verticalSizeClass))")
        lines.append("  orientation        \(Self.orientation(interfaceOrientation))")
        lines.append("  interactive resize \(isInteractivelyResizing)")
        if let hinge {
            lines.append("  hinge              \(hinge.statusTitle)  \(String(format: "%.1f°", hinge.angleDegrees))  (\(String(format: "%.3f rad", hinge.angleRadians)))")
        } else {
            lines.append("  hinge              nil (no hinge in this hierarchy)")
        }
        lines.append("")
        lines.append("GUIDES")
        lines.append(Self.guideLine(safeArea))
        lines.append(Self.guideLine(layoutRegionSafeArea))
        lines.append(Self.guideLine(margins))
        lines.append(Self.guideLine(layoutRegionMargins))
        lines.append(Self.guideLine(readable))
        lines.append(Self.guideLine(layoutRegionReadable))
        lines.append(Self.guideLine(keyboard))
        lines.append("  directionalMargins \(Self.directional(directionalLayoutMargins))")
        lines.append("  additionalSafeArea \(Self.insets(additionalSafeAreaInsets))")
        for bar in bars { lines.append(Self.guideLine(bar)) }
        lines.append("")
        lines.append("RESERVED REGIONS  includeInactive  count \(reserved.count)")
        if reserved.isEmpty {
            lines.append("  (none intersecting this view)")
        } else {
            for (index, region) in reserved.enumerated() {
                let kind = region.kind == .division ? "division" : "occlusion"
                let active = region.isActive ? "ACTIVE" : "inactive"
                lines.append("  [\(index)] \(kind)  \(active)")
                lines.append("      id       \(region.idDescription)")
                lines.append("      frame    \(Self.rect(region.frame))")
                lines.append("      margins  \(Self.insets(region.margins))")
                lines.append("      core     \(Self.rect(region.coreFrame))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static let barExtent: CGFloat = 56.0

    static func capture(from view: UIView, viewController: UIViewController?, hinge: UIHinge?) -> LayoutSnapshot {
        view.layoutIfNeeded()

        let window = view.window
        let scene = window?.windowScene
        let geometry = scene?.effectiveGeometry

        let occlusions = view.reservedRegions(kind: .occlusion, options: .includeInactive)
        let divisions = view.reservedRegions(kind: .division, options: .includeInactive)
        let reserved = (occlusions + divisions).map { region in
            ReservedRegionSnapshot(
                idDescription: String(describing: region.id),
                kind: region.kind,
                frame: region.frame,
                margins: region.margins,
                isActive: region.isActive
            )
        }

        let safeAreaGuide = view.safeAreaLayoutGuide.layoutFrame
        let marginGuide = view.layoutMarginsGuide.layoutFrame
        let readableGuide = view.readableContentGuide.layoutFrame
        let keyboardGuide = view.keyboardLayoutGuide.layoutFrame

        let regionSafe = view.layoutGuide(for: .safeArea()).layoutFrame
        let regionMargins = view.layoutGuide(for: .margins()).layoutFrame
        let regionReadable = view.layoutGuide(for: .readableContent()).layoutFrame

        let bars: [GuideSnapshot] = [
            ("top", NSDirectionalRectEdge.top), ("leading", .leading),
            ("bottom", .bottom), ("trailing", .trailing)
        ].map { name, edge in
            let region = UIView.LayoutRegion.bar(onEdge: edge, extent: barExtent)
            return GuideSnapshot(
                name: "LayoutRegion.bar(\(name), \(barExtent))",
                frame: view.layoutGuide(for: region).layoutFrame,
                insets: view.edgeInsets(for: region)
            )
        }

        return LayoutSnapshot(
            viewBounds: view.bounds,
            windowBounds: window?.bounds ?? .null,
            sceneBounds: geometry?.coordinateSpace.bounds ?? .null,
            screenMainBounds: UIScreen.main.bounds,
            scale: window?.screen.scale ?? view.traitCollection.displayScale,
            horizontalSizeClass: view.traitCollection.horizontalSizeClass,
            verticalSizeClass: view.traitCollection.verticalSizeClass,
            interfaceOrientation: geometry?.interfaceOrientation ?? .unknown,
            isInteractivelyResizing: geometry?.isInteractivelyResizing ?? false,
            hinge: hinge.map { HingeSnapshot(status: $0.status, angleRadians: $0.angle) },
            safeArea: GuideSnapshot(name: "safeAreaLayoutGuide", frame: safeAreaGuide, insets: view.safeAreaInsets),
            layoutRegionSafeArea: GuideSnapshot(
                name: "LayoutRegion.safeArea",
                frame: regionSafe,
                insets: view.edgeInsets(for: .safeArea())
            ),
            margins: GuideSnapshot(name: "layoutMarginsGuide", frame: marginGuide, insets: view.layoutMargins),
            layoutRegionMargins: GuideSnapshot(
                name: "LayoutRegion.margins",
                frame: regionMargins,
                insets: view.edgeInsets(for: .margins())
            ),
            readable: GuideSnapshot(
                name: "readableContentGuide",
                frame: readableGuide,
                insets: insets(from: view.bounds, to: readableGuide)
            ),
            layoutRegionReadable: GuideSnapshot(
                name: "LayoutRegion.readableContent",
                frame: regionReadable,
                insets: view.edgeInsets(for: .readableContent())
            ),
            keyboard: GuideSnapshot(
                name: "keyboardLayoutGuide",
                frame: keyboardGuide,
                insets: insets(from: view.bounds, to: keyboardGuide)
            ),
            directionalLayoutMargins: view.directionalLayoutMargins,
            additionalSafeAreaInsets: viewController?.additionalSafeAreaInsets ?? .zero,
            reserved: reserved,
            bars: bars
        )
    }

    static func rect(_ rect: CGRect) -> String {
        guard rect.isNull == false, rect.isInfinite == false else { return "null" }
        return String(
            format: "(%.1f, %.1f)  %.1f×%.1f",
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height
        )
    }

    static func insets(_ insets: UIEdgeInsets) -> String {
        String(format: "t%.1f l%.1f b%.1f r%.1f", insets.top, insets.left, insets.bottom, insets.right)
    }

    static func directional(_ insets: NSDirectionalEdgeInsets) -> String {
        String(format: "t%.1f leading%.1f b%.1f trailing%.1f", insets.top, insets.leading, insets.bottom, insets.trailing)
    }

    static func sizeClass(_ sizeClass: UIUserInterfaceSizeClass) -> String {
        switch sizeClass {
        case .compact: "compact"
        case .regular: "regular"
        case .unspecified: "unspecified"
        @unknown default: "unknown"
        }
    }

    static func orientation(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }

    private static func guideLine(_ guide: GuideSnapshot) -> String {
        "  \(guide.name)\n      frame \(rect(guide.frame))\n      insets \(insets(guide.insets))"
    }

    private static func insets(from bounds: CGRect, to frame: CGRect) -> UIEdgeInsets {
        UIEdgeInsets(
            top: frame.minY - bounds.minY,
            left: frame.minX - bounds.minX,
            bottom: bounds.maxY - frame.maxY,
            right: bounds.maxX - frame.maxX
        )
    }
}
