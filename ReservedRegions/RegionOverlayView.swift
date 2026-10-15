import UIKit

final class RegionOverlayView: UIView {
    var snapshot: LayoutSnapshot? {
        didSet { setNeedsDisplay() }
    }

    var enabledLayers: Set<OverlayLayer> = [.safeArea, .division, .occlusion, .regionMargins, .bars] {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let snapshot else { return }

        drawGrid(in: context, bounds: snapshot.viewBounds)
        var occupiedLabels: [CGRect] = []

        if enabledLayers.contains(.bounds) {
            stroke(snapshot.viewBounds, color: OverlayLayer.bounds.color, lineWidth: 1, dashed: true)
            label("bounds", in: snapshot.viewBounds, color: OverlayLayer.bounds.color, originOffset: CGPoint(x: 6, y: 6), occupied: &occupiedLabels)
        }

        if enabledLayers.contains(.safeArea) {
            fillStroke(snapshot.safeArea.frame, color: OverlayLayer.safeArea.color)
            label("safe area", in: snapshot.safeArea.frame, color: OverlayLayer.safeArea.color, occupied: &occupiedLabels)
        }

        if enabledLayers.contains(.margins) {
            fillStroke(snapshot.margins.frame, color: OverlayLayer.margins.color)
            label("margins", in: snapshot.margins.frame, color: OverlayLayer.margins.color, occupied: &occupiedLabels)
        }

        if enabledLayers.contains(.readable) {
            fillStroke(snapshot.readable.frame, color: OverlayLayer.readable.color)
            label("readable", in: snapshot.readable.frame, color: OverlayLayer.readable.color, occupied: &occupiedLabels)
        }

        if enabledLayers.contains(.keyboard) {
            fillStroke(snapshot.keyboard.frame, color: OverlayLayer.keyboard.color)
            label("keyboard", in: snapshot.keyboard.frame, color: OverlayLayer.keyboard.color, occupied: &occupiedLabels)
        }

        if enabledLayers.contains(.bars) {
            for bar in snapshot.bars {
                fillStroke(bar.frame, color: OverlayLayer.bars.color)
                label(bar.name, in: bar.frame, color: OverlayLayer.bars.color, occupied: &occupiedLabels)
            }
        }

        if enabledLayers.contains(.division) {
            for region in snapshot.divisionRegions {
                drawReservedRegion(region, color: OverlayLayer.division.color, occupied: &occupiedLabels)
            }
        }

        if enabledLayers.contains(.occlusion) {
            for region in snapshot.occlusionRegions {
                drawReservedRegion(region, color: OverlayLayer.occlusion.color, occupied: &occupiedLabels)
            }
        }
    }

    private func drawGrid(in context: CGContext, bounds: CGRect) {
        context.saveGState()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.06).cgColor)
        context.setLineWidth(1)

        let step: CGFloat = 20
        var x = bounds.minX
        while x <= bounds.maxX {
            context.move(to: CGPoint(x: x, y: bounds.minY))
            context.addLine(to: CGPoint(x: x, y: bounds.maxY))
            x += step
        }
        var y = bounds.minY
        while y <= bounds.maxY {
            context.move(to: CGPoint(x: bounds.minX, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y))
            y += step
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawReservedRegion(_ region: ReservedRegionSnapshot, color: UIColor, occupied: inout [CGRect]) {
        let frame = visibleFrame(for: region.frame)
        fillStroke(frame, color: color, dashed: region.isActive == false)

        if enabledLayers.contains(.regionMargins), region.margins != .zero {
            let core = visibleFrame(for: region.coreFrame)
            let corePath = UIBezierPath(rect: core)
            color.withAlphaComponent(0.35).setFill()
            corePath.fill()
            color.setStroke()
            corePath.lineWidth = 1
            corePath.stroke()
        }

        let kind = region.kind == .division ? "division" : "occlusion"
        let state = region.isActive ? "active" : "inactive"
        let size = String(format: "%.0f×%.0f", region.frame.width, region.frame.height)
        label("\(kind) \(state) \(size)", in: frame, color: color, occupied: &occupied)
    }

    private func visibleFrame(for frame: CGRect) -> CGRect {
        var visible = frame
        if visible.width < 2 {
            visible.size.width = 2
            visible.origin.x -= 1
        }
        if visible.height < 2 {
            visible.size.height = 2
            visible.origin.y -= 1
        }
        return visible
    }

    private func fillStroke(_ frame: CGRect, color: UIColor, dashed: Bool = false) {
        let path = UIBezierPath(rect: frame)
        color.withAlphaComponent(0.16).setFill()
        path.fill()
        color.withAlphaComponent(0.95).setStroke()
        path.lineWidth = dashed ? 2 : 2
        if dashed {
            path.setLineDash([5, 4], count: 2, phase: 0)
        }
        path.stroke()
    }

    private func stroke(_ frame: CGRect, color: UIColor, lineWidth: CGFloat, dashed: Bool) {
        let path = UIBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
        color.withAlphaComponent(0.8).setStroke()
        path.lineWidth = lineWidth
        if dashed {
            path.setLineDash([4, 4], count: 2, phase: 0)
        }
        path.stroke()
    }

    private func label(_ text: String, in frame: CGRect, color: UIColor, originOffset: CGPoint = CGPoint(x: 4, y: 4), occupied: inout [CGRect]) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.black,
            .backgroundColor: color.withAlphaComponent(0.92)
        ]
        let string = NSAttributedString(string: " \(text) ", attributes: attributes)
        let size = string.size()
        var origin = CGPoint(x: frame.minX + originOffset.x, y: frame.minY + originOffset.y)
        if origin.x + size.width > bounds.maxX - 4 {
            origin.x = max(4, frame.minX - size.width - 4)
        }
        var labelFrame = CGRect(origin: origin, size: size)
        var guardCount = 0
        while occupied.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(labelFrame) }) && guardCount < 12 {
            labelFrame.origin.y += size.height + 3
            guardCount += 1
        }
        if labelFrame.maxY > bounds.maxY - 4 {
            labelFrame.origin.y = max(4, frame.maxY - size.height - 4)
        }
        occupied.append(labelFrame)
        string.draw(at: labelFrame.origin)
    }
}
