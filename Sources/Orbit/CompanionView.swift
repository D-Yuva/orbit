import SwiftUI
import OrbitCore

/// Uses the matching expression when available, with the supplied portrait as
/// the final fallback while cutout artwork is being prepared.
struct CompanionView: View {
    let style: CompanionStyle
    var size: CGFloat = 80
    var kind: ReminderKind = .water
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            CompanionPortrait(kind: kind, width: size, height: size, peeking: false)
                .id(kind)
                .transition(.opacity)
        }
        .frame(width: size, height: size, alignment: .bottom)
        .saturation(style == .sage ? 0 : style == .rose ? 0.8 : 1)
        .contrast(style == .rose ? 0.92 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: kind)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Batman avatar. \(kind.title)")
    }
}

/// Transparent upper-body artwork rests on the notch's bottom edge. The raw
/// reference fallback retains its existing framing without editing its pixels.
struct PeekingCompanionView: View {
    let style: CompanionStyle
    var width: CGFloat = 126
    var height: CGFloat = 110
    var kind: ReminderKind = .water
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            CompanionPortrait(kind: kind, width: width, height: height, peeking: true)
                .id(kind)
                .transition(.opacity)
        }
        .frame(width: width, height: height, alignment: .bottom)
        .saturation(style == .sage ? 0 : style == .rose ? 0.8 : 1)
        .contrast(style == .rose ? 0.92 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: kind)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Batman in the notch. \(kind.title)")
    }
}

private struct CompanionPortrait: View {
    let kind: ReminderKind
    let width: CGFloat
    let height: CGFloat
    let peeking: Bool

    var body: some View {
        let artwork = CompanionArtwork.artwork(for: kind)
        if artwork.mode == .cutout, let image = artwork.image {
            CutoutPortrait(image: image, kind: kind, width: width, height: height, peeking: peeking)
        } else if artwork.mode == .variant, let image = artwork.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: width, height: height, alignment: .bottom)
        } else if peeking {
            ReferencePortrait(image: artwork.image, width: width, height: max(0, height - 7), cropWidthFraction: 0.50)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14,
                                                 bottomLeadingRadius: 0,
                                                 bottomTrailingRadius: 0,
                                                 topTrailingRadius: 14))
                .padding(.top, 7)
        } else {
            ReferencePortrait(image: artwork.image, width: width, height: height, cropWidthFraction: 0.44)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous))
        }
    }
}

/// A small native character rig. The supplied PNG remains intact: view masks
/// frame the upper body, while eyes, mouth, and gripping hands are UI layers.
private struct CutoutPortrait: View {
    let image: NSImage
    let kind: ReminderKind
    let width: CGFloat
    let height: CGFloat
    let peeking: Bool

    private let sourceSize = CGSize(width: 1568, height: 1576)
    private let crop = CGRect(x: 280, y: 40, width: 1020, height: 1020)

    var body: some View {
        let scale = min(width / crop.width, max(1, height - (peeking ? 7 : 0)) / crop.height)
        let visibleWidth = crop.width * scale
        let visibleHeight = crop.height * scale
        ZStack(alignment: .bottom) {
            GeometryReader { _ in
                Image(nsImage: image)
                    .resizable().interpolation(.high)
                    .overlay { AvatarExpressionOverlay(kind: kind) }
                    .mask(AvatarOutline())
                    .frame(width: sourceSize.width * scale, height: sourceSize.height * scale)
                    .offset(x: -crop.minX * scale, y: -crop.minY * scale)
            }
            .frame(width: visibleWidth, height: visibleHeight)
            .clipped()

            if peeking {
                SourceHand(image: image, crop: CGRect(x: 389, y: 1182, width: 144, height: 150), size: 17)
                    .rotationEffect(.degrees(-9))
                    .offset(x: -visibleWidth * 0.37, y: 7)
                SourceHand(image: image, crop: CGRect(x: 1106, y: 1188, width: 150, height: 154), size: 17)
                    .rotationEffect(.degrees(9))
                    .offset(x: visibleWidth * 0.37, y: 7)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

private struct SourceHand: View {
    let image: NSImage
    let crop: CGRect
    let size: CGFloat

    var body: some View {
        let scale = size / crop.width
        GeometryReader { _ in
            Image(nsImage: image)
                .resizable().interpolation(.high)
                .frame(width: 1568 * scale, height: 1576 * scale)
                .offset(x: -crop.minX * scale, y: -crop.minY * scale)
        }
        .frame(width: size, height: crop.height * scale)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.38, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 0.5, y: 0.5)
        .accessibilityHidden(true)
    }
}

/// Trims the fringe remaining in the supplied cutout as part of view clipping.
private struct AvatarOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 579, y: 727))
        p.addCurve(to: CGPoint(x: 553, y: 426), control1: CGPoint(x: 545, y: 700), control2: CGPoint(x: 550, y: 504))
        p.addCurve(to: CGPoint(x: 616, y: 65), control1: CGPoint(x: 556, y: 267), control2: CGPoint(x: 595, y: 102))
        p.addQuadCurve(to: CGPoint(x: 637, y: 58), control: CGPoint(x: 625, y: 47))
        p.addQuadCurve(to: CGPoint(x: 686, y: 192), control: CGPoint(x: 651, y: 104))
        p.addCurve(to: CGPoint(x: 893, y: 190), control1: CGPoint(x: 741, y: 175), control2: CGPoint(x: 839, y: 174))
        p.addQuadCurve(to: CGPoint(x: 935, y: 61), control: CGPoint(x: 924, y: 118))
        p.addQuadCurve(to: CGPoint(x: 957, y: 60), control: CGPoint(x: 946, y: 47))
        p.addCurve(to: CGPoint(x: 1023, y: 431), control1: CGPoint(x: 981, y: 117), control2: CGPoint(x: 1011, y: 273))
        p.addCurve(to: CGPoint(x: 1000, y: 724), control1: CGPoint(x: 1031, y: 544), control2: CGPoint(x: 1020, y: 685))
        p.addCurve(to: CGPoint(x: 1154, y: 774), control1: CGPoint(x: 1085, y: 728), control2: CGPoint(x: 1121, y: 738))
        p.addCurve(to: CGPoint(x: 1303, y: 1069), control1: CGPoint(x: 1210, y: 808), control2: CGPoint(x: 1264, y: 976))
        p.addLine(to: CGPoint(x: 1550, y: 1576))
        p.addLine(to: CGPoint(x: 22, y: 1576))
        p.addCurve(to: CGPoint(x: 413, y: 803), control1: CGPoint(x: 181, y: 1220), control2: CGPoint(x: 337, y: 932))
        p.addCurve(to: CGPoint(x: 579, y: 727), control1: CGPoint(x: 449, y: 746), control2: CGPoint(x: 494, y: 729))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 1568, y: rect.height / 1576))
    }
}

private struct ReferencePortrait: View {
    let image: NSImage?
    let width: CGFloat
    let height: CGFloat
    let cropWidthFraction: CGFloat

    var body: some View {
        GeometryReader { _ in
            if let image {
                let sourceCropWidth = image.size.width * cropWidthFraction
                let scale = width / sourceCropWidth
                // Preserve the original source's face, ears, and chest framing.
                let sourceLeft = image.size.width * 0.538 - sourceCropWidth / 2
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .offset(x: -sourceLeft * scale)
            } else {
                Text("Avatar unavailable")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

@MainActor
enum CompanionArtwork {
    enum Mode: String {
        case variant, cutout, reference, unavailable
    }

    struct Artwork {
        let mode: Mode
        let image: NSImage?
    }

    // Resolve and decode each bundled image once. A new launch picks up newly
    // installed artwork; displaying reminders does not perform file I/O.
    private static let images: [String: NSImage] = {
        let names = ReminderKind.allCases.map { "batman-\($0.rawValue)" }
            + ["batman-cutout", "batman-reference"]
        var result: [String: NSImage] = [:]
        for name in names {
            if let image = load(name) { result[name] = image }
        }
        return result
    }()

    static func hasVariant(for kind: ReminderKind) -> Bool {
        images["batman-\(kind.rawValue)"] != nil
    }

    static func currentArtworkMode(for kind: ReminderKind) -> Mode {
        artwork(for: kind).mode
    }

    static func artwork(for kind: ReminderKind) -> Artwork {
        if let image = images["batman-\(kind.rawValue)"] {
            return Artwork(mode: .variant, image: image)
        }
        if let image = images["batman-cutout"] {
            return Artwork(mode: .cutout, image: image)
        }
        if let image = images["batman-reference"] {
            return Artwork(mode: .reference, image: image)
        }
        return Artwork(mode: .unavailable, image: nil)
    }

    private static func load(_ name: String) -> NSImage? {
        // A packaged app uses only its bundled copy; never consult a development
        // fallback that could conceal a missing release resource.
        let url: URL?
        if Bundle.main.bundleURL.pathExtension == "app" {
            url = Bundle.main.resourceURL?
                .appendingPathComponent("Orbit_Orbit.bundle/\(name).png")
        } else {
            url = Bundle.module.url(forResource: name, withExtension: "png")
        }
        guard let url, let image = NSImage(contentsOf: url),
              image.isValid, image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }
}
