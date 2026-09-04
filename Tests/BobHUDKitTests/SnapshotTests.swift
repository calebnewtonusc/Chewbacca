import AppKit
import SwiftUI
import Testing

@testable import BobHUDKit

/// Render every surface to a bitmap and prove it drew something.
///
/// A heads-up display is the hardest kind of UI to review, because seeing it
/// needs a machine somebody is sitting at, unlocked, with the right things
/// already behind it. `ImageRenderer` removes all of that: it takes a SwiftUI
/// view and hands back pixels, so the interface becomes reviewable from a
/// terminal or a build server.
///
/// The assertion is deliberately crude and it is the one that matters. Each
/// surface is drawn over a backdrop, and the test checks that a meaningful
/// share of the pixels changed. A view that renders nothing is pixel-identical
/// to its backdrop, and "renders nothing" is the failure mode this project keeps
/// producing: a `matchedGeometryEffect` applied to a generated tree blanked the
/// entire display, and the only reason it was caught was that somebody happened
/// to take a screenshot.
///
/// Set `HUD_SNAPSHOT_DIR` to keep the PNGs and look at them.
@Suite("Snapshots")
@MainActor
struct SnapshotTests {
    /// Where to keep the images, if anybody asked for them.
    private var keepDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["HUD_SNAPSHOT_DIR"] else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Light and dark, because the one thing this UI cannot control is what is
    /// behind it. A card that reads on a dark desktop and turns to grey mud over
    /// a white document is the failure worth catching, and it is one this
    /// project has actually shipped.
    enum Ground: String, CaseIterable {
        case light, dark

        var color: Color {
            self == .light
                ? Color(red: 0.97, green: 0.97, blue: 0.96)
                : Color(red: 0.09, green: 0.10, blue: 0.12)
        }

        var ink: Color {
            self == .light ? .black.opacity(0.75) : .white.opacity(0.7)
        }
    }

    /// Draw a view over a backdrop, and report how much of it changed.
    private func coverage(
        _ name: String, size: CGSize, ground: Ground,
        @ViewBuilder _ content: () -> some View
    ) -> Double {
        let backdrop = Backdrop(ground: ground, size: size)
        let bare = render(
            backdrop.frame(width: size.width, height: size.height).ignoresSafeArea())
        let over = render(
            ZStack {
                backdrop
                content()
            }
            .frame(width: size.width, height: size.height)
            // The real overlay ignores the safe area. A renderer that does not
            // insets every child, which put marks tens of points away from the
            // rectangle they were describing and made the view look wrong when
            // the harness was.
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
            // AppKit cannot draw without a window, so the vibrancy material
            // swaps to its SwiftUI stand-in for the render.
            .environment(\.hudOffscreen, true)
        )
        guard let bare, let over else { return 0 }

        if let directory = keepDirectory {
            write(over, to: directory.appendingPathComponent("\(name)-\(ground.rawValue).png"))
        }
        return difference(bare, over)
    }

    private func render(_ view: some View) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view)
        // Retina, so type is judged at the density it is actually read at.
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation
        else { return nil }
        return NSBitmapImageRep(data: data)
    }

    private func write(_ rep: NSBitmapImageRep, to url: URL) {
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// Fraction of pixels that differ by more than a rounding error.
    private func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 1 }
        var changed = 0
        var total = 0
        // Every fourth pixel in each direction. Sampling is enough to tell drawn
        // from blank and keeps the suite fast enough that nobody skips it.
        for y in stride(from: 0, to: a.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: a.pixelsWide, by: 4) {
                total += 1
                guard let left = a.colorAt(x: x, y: y),
                      let right = b.colorAt(x: x, y: y) else { continue }
                let delta = abs(left.redComponent - right.redComponent)
                    + abs(left.greenComponent - right.greenComponent)
                    + abs(left.blueComponent - right.blueComponent)
                if delta > 0.02 { changed += 1 }
            }
        }
        return total == 0 ? 0 : Double(changed) / Double(total)
    }

    // MARK: The surfaces

    private func store(_ lines: [String]) -> SurfaceStore {
        let store = SurfaceStore()
        for line in lines {
            if let op = try? LineParser.parse(line) { store.apply([op]) }
        }
        return store
    }

    private var dashboard: SurfaceStore {
        store([
            #"c s Screen title="THIS WEEK""#,
            "r s",
            "> s grid spark bars events",
            "c grid Stack direction=grid cols=2 gap=3",
            "> grid m1 m2",
            #"c m1 Metric label="Unread" value=12 thresholds=[{"at":10,"tone":"warn"}]"#,
            #"c m2 Metric label="Overdue" value=4 thresholds=[{"at":1,"tone":"bad"}]"#,
            #"c spark Sparkline label="Messages" points=[31,28,44,39,58,52,71] value="71""#,
            #"c bars Bars caption="Since last reply" rows=[{"label":"Sagar","value":2,"display":"2h"},{"label":"Ava","value":31,"display":"1d"}]"#,
            #"c events Events caption="Due" items=[{"time":"Sep 9","text":"Origin Story","accent":true}]"#,
        ])
    }

    private var diagram: SurfaceStore {
        store([
            #"c d Screen title="HOW A REQUEST REACHES THE SCREEN""#,
            "r d",
            "> d fig",
            #"c fig Diagram aspect=2.4 parts=[{"t":"node","x":0.16,"y":0.5,"w":0.22,"h":0.3,"label":"Model"},{"t":"arrow","x":0.28,"y":0.5,"x2":0.42,"y2":0.5},{"t":"node","x":0.5,"y":0.5,"w":0.2,"h":0.3,"label":"Socket"},{"t":"arrow","x":0.61,"y":0.5,"x2":0.75,"y2":0.5},{"t":"node","x":0.85,"y":0.5,"w":0.22,"h":0.3,"label":"Glass","tone":"good"}]"#,
        ])
    }

    private func card(_ store: SurfaceStore, _ chrome: Chrome, _ width: CGFloat) -> some View {
        SurfaceCard(
            surface: OverlaySurface(
                id: "s", store: store, region: .center, width: width,
                slot: 0, depth: 0, chrome: chrome),
            onDismiss: {}, onDrag: { _ in }, onGrab: {})
            .frame(width: width)
    }

    @Test("a card draws, on both grounds", arguments: Ground.allCases)
    func cardDraws(ground: Ground) {
        let drawn = coverage(
            "surface-card", size: CGSize(width: 480, height: 430), ground: ground
        ) {
            card(dashboard, .card, 400)
        }
        #expect(drawn > 0.25, "a dashboard covered only \(drawn) of the frame")
    }

    @Test("a bare surface draws even with no panel behind it", arguments: Ground.allCases)
    func bareDraws(ground: Ground) {
        // The one most likely to come out invisible, because it is defined by
        // having nothing behind it.
        let drawn = coverage(
            "surface-bare", size: CGSize(width: 620, height: 320), ground: ground
        ) {
            card(diagram, .bare, 560)
        }
        #expect(drawn > 0.05, "a bare diagram covered only \(drawn) of the frame")
    }

    @Test("a bracketed surface draws", arguments: Ground.allCases)
    func bracketDraws(ground: Ground) {
        let drawn = coverage(
            "surface-bracket", size: CGSize(width: 340, height: 300), ground: ground
        ) {
            card(dashboard, .bracket, 260)
        }
        #expect(drawn > 0.15, "a bracketed surface covered only \(drawn) of the frame")
    }

    @Test("every presence state draws something")
    func presenceDraws() {
        // Dormant is deliberately faint, so it gets its own smaller floor: the
        // point of that state is being nearly invisible while still proving the
        // thing is alive.
        for state in Presence.allCases {
            let drawn = coverage(
                "presence-\(state.rawValue)",
                size: CGSize(width: 60, height: 60), ground: .dark
            ) {
                PresenceRing(presence: state, amplitude: state == .hearing ? 0.7 : 0)
            }
            #expect(drawn > 0.01, "\(state.rawValue) drew almost nothing: \(drawn)")
        }
    }

    @Test("a mark draws over the thing it points at", arguments: Ground.allCases)
    func markerDraws(ground: Ground) {
        let drawn = coverage(
            "marker", size: CGSize(width: 460, height: 220), ground: ground
        ) {
            MarkerView(
                marker: Marker(
                    id: "m", rect: CGRect(x: 60, y: 80, width: 320, height: 90),
                    label: "This is the one failing", tone: "bad", expires: nil),
                screenHeight: 220)
        }
        #expect(drawn > 0.02, "a mark covered only \(drawn) of the frame")
    }

    @Test("a mark moves when its rectangle moves")
    func markerFollowsItsRect() {
        // The question asked directly, and the one worth keeping: two marks,
        // one high and one low. Identical images would mean position is being
        // ignored entirely, which is the failure that actually matters and the
        // only one a pixel comparison can answer without ambiguity.
        let size = CGSize(width: 460, height: 300)
        let high = image("marker-high", size: size) {
            MarkerView(
                marker: Marker(
                    id: "m", rect: CGRect(x: 40, y: 20, width: 200, height: 60),
                    expires: nil),
                screenHeight: size.height)
        }
        let low = image("marker-low", size: size) {
            MarkerView(
                marker: Marker(
                    id: "m", rect: CGRect(x: 40, y: 200, width: 200, height: 60),
                    expires: nil),
                screenHeight: size.height)
        }
        guard let high, let low else {
            Issue.record("could not render a marker")
            return
        }
        #expect(!same(high, low, rows: 0..<Int(size.height) * 2), "the mark did not move")
    }

    @Test("a label does not move the mark")
    func markerPositionIgnoresItsLabel() {
        // The label used to be a sibling in the stack, so it changed the mark's
        // size and the mark was placed by the size of the pair. A labelled mark
        // sat below the thing it pointed at, which for an annotation layer is
        // fatal: a mark near the right place is worse than no mark, because it
        // is confidently wrong.
        //
        // Compared as images rather than by hunting for coloured pixels. An
        // earlier version of this test looked for cyan and found the colour
        // fringes of subpixel-antialiased text instead, then reported the mark
        // as being seventy points from where it was. The view was right and the
        // measurement was wrong, which is the more embarrassing way round.
        let rect = CGRect(x: 60, y: 80, width: 320, height: 90)
        let size = CGSize(width: 460, height: 220)

        let plain = image("marker-plain", size: size) {
            MarkerView(
                marker: Marker(id: "m", rect: rect, expires: nil),
                screenHeight: size.height)
        }
        let labelled = image("marker-labelled", size: size) {
            MarkerView(
                marker: Marker(id: "m", rect: rect, label: "Here", expires: nil),
                screenHeight: size.height)
        }
        guard let plain, let labelled else {
            Issue.record("could not render a marker")
            return
        }

        // Everything below the label's band must be pixel-identical: the label
        // sits above the region and must change nothing inside or under it.
        //
        // Starting a few points inside the top edge, because the label's own
        // drop shadow reaches a little past it. That is the shadow doing its
        // job, not the mark moving, and the thing being checked is the
        // brackets.
        let from = (Int(rect.minY) + 10) * 2
        #expect(
            same(plain, labelled, rows: from..<Int(size.height) * 2),
            "adding a label moved the mark")
    }

    /// Render without diffing, for tests that compare two renders to each other.
    private func image(
        _ name: String, size: CGSize, @ViewBuilder _ content: () -> some View
    ) -> NSBitmapImageRep? {
        let made = render(
            ZStack {
                Backdrop(ground: .dark, size: size)
                content()
            }
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
            .environment(\.hudOffscreen, true)
        )
        if let made, let directory = keepDirectory {
            write(made, to: directory.appendingPathComponent("\(name).png"))
        }
        return made
    }

    /// Whether two renders agree over a band of rows.
    private func same(
        _ a: NSBitmapImageRep, _ b: NSBitmapImageRep, rows: Range<Int>
    ) -> Bool {
        guard a.pixelsWide == b.pixelsWide else { return false }
        for y in rows where y < a.pixelsHigh && y < b.pixelsHigh {
            for x in stride(from: 0, to: a.pixelsWide, by: 3) {
                guard let left = a.colorAt(x: x, y: y),
                      let right = b.colorAt(x: x, y: y) else { continue }
                let delta = abs(left.redComponent - right.redComponent)
                    + abs(left.greenComponent - right.greenComponent)
                    + abs(left.blueComponent - right.blueComponent)
                if delta > 0.02 { return false }
            }
        }
        return true
    }

    @Test("the command bar draws")
    func commandBarDraws() {
        let drawn = coverage(
            "command-bar", size: CGSize(width: 700, height: 150), ground: .light
        ) {
            CommandBarView(onSubmit: { _ in }, onEscape: {})
                .frame(width: 640)
        }
        #expect(drawn > 0.2, "the command bar covered only \(drawn) of the frame")
    }
}

/// Something behind the glass that is not a flat colour, so occlusion and
/// contrast are visible rather than assumed.
private struct Backdrop: View {
    let ground: SnapshotTests.Ground
    /// The frame it must not grow beyond.
    ///
    /// Its rows of text are taller than most of the frames it is used in, and a
    /// ZStack takes the size of its largest child. That made the stack taller
    /// than the frame around it, which then centred the overflow and moved every
    /// other child up with it. Marks appeared tens of points above the rectangle
    /// they were describing, and the view was right the whole time.
    let size: CGSize

    var body: some View {
        ZStack {
            ground.color
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<16, id: \.self) { row in
                    Text(String(repeating: "the quick brown fox jumps over ", count: 3))
                        .font(.system(size: 11, design: row % 3 == 0 ? .monospaced : .default))
                        .foregroundStyle(ground.ink)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
