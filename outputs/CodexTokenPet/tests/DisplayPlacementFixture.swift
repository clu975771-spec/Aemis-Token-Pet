import AppKit

@main
struct DisplayPlacementFixture {
    static func main() {
        let builtIn = PetDisplay(id: 1, visible: CGRect(x: 0, y: 82, width: 1512, height: 867), stableID: "internal")
        let external = PetDisplay(id: 2, visible: CGRect(x: -185, y: 982, width: 1920, height: 1080), stableID: "hdmi")
        let size = CGSize(width: 252, height: 280)
        let original = CGRect(x: 1210, y: 1630, width: size.width, height: size.height)
        let saved = PetDisplayPlacement.capture(frame: original, screens: [builtIn, external])!
        assert(saved.displayID == 2)
        assert(saved.frame(size: size, screens: [builtIn]) == nil, "late monitor must not replace the anchor")
        assert(saved.frame(size: size, screens: [builtIn, external]) == original, "reconnection restores position")

        let moved = PetDisplay(id: 42, visible: CGRect(x: 1512, y: 0, width: 2560, height: 1440), stableID: "hdmi")
        let target = saved.frame(size: size, screens: [builtIn, moved])!
        assert(target.minX >= moved.visible.minX && target.maxX <= moved.visible.maxX)
        assert(target.minY >= moved.visible.minY && target.maxY <= moved.visible.maxY)
        let resized = saved.frame(size: CGSize(width: 360, height: 400), screens: [builtIn, moved])!
        assert(resized.maxX <= moved.visible.maxX && resized.maxY <= moved.visible.maxY)
        assert(abs((target.minX - moved.visible.minX) / (moved.visible.width - target.width) - CGFloat(saved.x)) < 0.00001)
        assert(abs((resized.minX - moved.visible.minX) / (moved.visible.width - resized.width) - CGFloat(saved.x)) < 0.00001)
        let reusedID = PetDisplay(id: 2, visible: builtIn.visible, stableID: "different-monitor")
        assert(saved.frame(size: size, screens: [reusedID]) == nil, "reused numeric ID must not steal the anchor")

        let encoded = try! JSONEncoder().encode(saved)
        assert(try! JSONDecoder().decode(PetDisplayPlacement.self, from: encoded) == saved)
        let oldEncoding = Data("{\"displayID\":2,\"x\":0.5,\"y\":0.25}".utf8)
        assert((try! JSONDecoder().decode(PetDisplayPlacement.self, from: oldEncoding)).stableID == nil)

        let fallback = PetDisplayPlacementGeometry.fallback(size: size, pointer: CGPoint(x: 8000, y: 8000), screen: builtIn.visible)
        assert(builtIn.visible.contains(fallback), "fallback must be visible")
        assert(saved.frame(size: size, screens: [builtIn, external]) == original, "fallback does not mutate anchor")

        let legacy = PetDisplayPlacement.capture(frame: original, screens: [builtIn, external])!
        assert(legacy == saved, "legacy absolute coordinates migrate to the correct display")
        assert(PetDisplayPlacement.capture(frame: original, screens: [builtIn]) == nil, "missing legacy monitor must wait for migration")
        print("PASS: late display, reconnection, changed display ID, new coordinates, new resolution, new pet size, temporary fallback, legacy migration")
    }
}
