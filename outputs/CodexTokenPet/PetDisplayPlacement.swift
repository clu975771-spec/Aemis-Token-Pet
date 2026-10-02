import AppKit

/// A compact window's position within the usable part of one display.
/// Fractions use the travel range (visible size minus window size), so a
/// remembered edge remains an edge when the display or mascot size changes.
struct PetDisplayPlacement: Codable, Equatable {
    let displayID: UInt32
    let stableID: String?
    let x: Double
    let y: Double

    init(displayID: UInt32, stableID: String? = nil, x: Double, y: Double) {
        self.displayID = displayID
        self.stableID = stableID
        self.x = x
        self.y = y
    }

    static func capture(frame: CGRect, screens: [PetDisplay], preferredID: UInt32? = nil) -> Self? {
        let screen = screens.first(where: { $0.id == preferredID })
            ?? screens.max(by: { $0.visible.intersection(frame).area < $1.visible.intersection(frame).area })
        guard let screen, screen.visible.intersection(frame).area > 0 else { return nil }
        return Self(displayID: screen.id, stableID: screen.stableID,
                    x: fraction(frame.minX - screen.visible.minX, travel: screen.visible.width - frame.width),
                    y: fraction(frame.minY - screen.visible.minY, travel: screen.visible.height - frame.height))
    }

    func frame(size: CGSize, screens: [PetDisplay]) -> CGRect? {
        guard let screen = stableID.flatMap({ identity in screens.first(where: { $0.stableID == identity }) })
            ?? (stableID == nil ? screens.first(where: { $0.id == displayID }) : nil) else { return nil }
        return CGRect(x: screen.visible.minX + CGFloat(x) * max(0, screen.visible.width - size.width),
                      y: screen.visible.minY + CGFloat(y) * max(0, screen.visible.height - size.height),
                      width: size.width, height: size.height)
    }

    private static func fraction(_ offset: CGFloat, travel: CGFloat) -> Double {
        guard travel > 0 else { return 0 }
        return Double(min(1, max(0, offset / travel)))
    }
}

struct PetDisplay {
    let id: UInt32
    let visible: CGRect
    let stableID: String?

    init(id: UInt32, visible: CGRect, stableID: String? = nil) {
        self.id = id
        self.visible = visible
        self.stableID = stableID
    }
}

enum PetDisplayPlacementGeometry {
    static func fallback(size: CGSize, pointer: CGPoint, screen: CGRect, margin: CGFloat = 20) -> CGRect {
        let minX = screen.minX + min(margin, max(0, (screen.width - size.width) / 2))
        let minY = screen.minY + min(margin, max(0, (screen.height - size.height) / 2))
        return CGRect(x: min(max(pointer.x - size.width / 2, minX), max(minX, screen.maxX - size.width - margin)),
                      y: min(max(pointer.y - size.height / 2, minY), max(minY, screen.maxY - size.height - margin)),
                      width: size.width, height: size.height)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : max(0, width) * max(0, height) }
}
