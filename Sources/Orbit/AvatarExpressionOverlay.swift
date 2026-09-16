import SwiftUI
import OrbitCore

/// Live facial details aligned to the user's 1568 × 1576 cutout. The source
/// image stays untouched; this view must share its full, uncropped image frame.
struct AvatarExpressionOverlay: View {
    let kind: ReminderKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, _ in
                    context.scaleBy(x: geometry.size.width / 1568, y: geometry.size.height / 1576)
                    drawSocket(in: &context)
                    var mirrored = context
                    mirrored.translateBy(x: 1575, y: 0)
                    mirrored.scaleBy(x: -1, y: 1)
                    drawSocket(in: &mirrored)
                    drawFacePatch(in: &context)
                    drawEye(in: &context)
                    drawEye(in: &mirrored)
                    drawMouth(in: &context)
                }
                .id(kind)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: kind)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private let eyeWhite = Color(red: 0.81, green: 0.91, blue: 1)
    private let eyeBlue = Color(red: 0.37, green: 0.56, blue: 0.85)
    private let ink = Color(red: 0.025, green: 0.025, blue: 0.04)

    private func drawSocket(in context: inout GraphicsContext) {
        let socket = Path { path in
            path.move(to: CGPoint(x: 626, y: 475))
            path.addCurve(to: CGPoint(x: 731, y: 520), control1: CGPoint(x: 645, y: 473), control2: CGPoint(x: 701, y: 508))
            path.addQuadCurve(to: CGPoint(x: 759, y: 540), control: CGPoint(x: 751, y: 529))
            path.addQuadCurve(to: CGPoint(x: 743, y: 557), control: CGPoint(x: 773, y: 558))
            path.addCurve(to: CGPoint(x: 635, y: 535), control1: CGPoint(x: 706, y: 560), control2: CGPoint(x: 654, y: 546))
            path.addQuadCurve(to: CGPoint(x: 616, y: 499), control: CGPoint(x: 615, y: 521))
            path.addQuadCurve(to: CGPoint(x: 626, y: 475), control: CGPoint(x: 613, y: 478))
            path.closeSubpath()
        }
        context.fill(socket, with: .linearGradient(
            Gradient(colors: [Color(red: 0.025, green: 0.07, blue: 0.15), Color(red: 0.009, green: 0.025, blue: 0.063)]),
            startPoint: CGPoint(x: 632, y: 478), endPoint: CGPoint(x: 717, y: 565)))
    }

    private func drawFacePatch(in context: inout GraphicsContext) {
        // Follow the lower cowl edge beneath its central nose, keeping the
        // original cheek and jaw boundaries outside this small print area.
        let face = Path { path in
            path.move(to: CGPoint(x: 646, y: 616))
            path.addCurve(to: CGPoint(x: 766, y: 644), control1: CGPoint(x: 692, y: 622), control2: CGPoint(x: 732, y: 635))
            path.addQuadCurve(to: CGPoint(x: 807, y: 646), control: CGPoint(x: 789, y: 653))
            path.addCurve(to: CGPoint(x: 929, y: 615), control1: CGPoint(x: 853, y: 634), control2: CGPoint(x: 888, y: 620))
            path.addCurve(to: CGPoint(x: 787, y: 706), control1: CGPoint(x: 918, y: 687), control2: CGPoint(x: 875, y: 704))
            path.addCurve(to: CGPoint(x: 646, y: 616), control1: CGPoint(x: 698, y: 705), control2: CGPoint(x: 660, y: 684))
            path.closeSubpath()
        }
        context.fill(face, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.17, green: 0.125, blue: 0.15), location: 0),
                .init(color: Color(red: 0.19, green: 0.14, blue: 0.16), location: 0.5),
                .init(color: Color(red: 0.115, green: 0.085, blue: 0.10), location: 1)
            ]), startPoint: CGPoint(x: 787, y: 618), endPoint: CGPoint(x: 787, y: 708)))
    }

    private func drawEye(in context: inout GraphicsContext) {
        if kind == .eyes || kind == .rest {
            let lid = Path { path in
                path.move(to: CGPoint(x: 635, y: kind == .eyes ? 516 : 523))
                path.addQuadCurve(to: CGPoint(x: 741, y: 533), control: CGPoint(x: 684, y: kind == .eyes ? 552 : 542))
            }
            context.stroke(lid, with: .color(eyeBlue.opacity(0.85)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            context.stroke(lid, with: .color(eyeWhite.opacity(kind == .eyes ? 0.94 : 0.7)), style: StrokeStyle(lineWidth: kind == .eyes ? 7 : 5, lineCap: .round))
            return
        }

        let eye = Path { path in
            switch kind {
            case .water:
                path.move(to: CGPoint(x: 632, y: 509))
                path.addCurve(to: CGPoint(x: 677, y: 496), control1: CGPoint(x: 637, y: 488), control2: CGPoint(x: 654, y: 485))
                path.addQuadCurve(to: CGPoint(x: 744, y: 532), control: CGPoint(x: 715, y: 510))
                path.addCurve(to: CGPoint(x: 632, y: 509), control1: CGPoint(x: 718, y: 549), control2: CGPoint(x: 646, y: 532))
            case .stretch:
                path.move(to: CGPoint(x: 632, y: 524))
                path.addCurve(to: CGPoint(x: 741, y: 531), control1: CGPoint(x: 654, y: 488), control2: CGPoint(x: 705, y: 510))
                path.addCurve(to: CGPoint(x: 632, y: 524), control1: CGPoint(x: 701, y: 523), control2: CGPoint(x: 665, y: 511))
            case .meal:
                path.move(to: CGPoint(x: 633, y: 505))
                path.addCurve(to: CGPoint(x: 680, y: 498), control1: CGPoint(x: 639, y: 486), control2: CGPoint(x: 657, y: 487))
                path.addQuadCurve(to: CGPoint(x: 743, y: 529), control: CGPoint(x: 719, y: 513))
                path.addCurve(to: CGPoint(x: 633, y: 505), control1: CGPoint(x: 728, y: 551), control2: CGPoint(x: 643, y: 541))
            case .custom:
                path.addEllipse(in: CGRect(x: 651, y: 496, width: 68, height: 45))
            case .eyes, .rest:
                break
            }
            path.closeSubpath()
        }
        context.stroke(eye, with: .color(eyeBlue.opacity(0.9)), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
        context.fill(eye, with: .linearGradient(
            Gradient(colors: [Color(red: 0.95, green: 0.975, blue: 1), eyeWhite]),
            startPoint: CGPoint(x: 684, y: 495), endPoint: CGPoint(x: 684, y: 546)))
    }

    private func drawMouth(in context: inout GraphicsContext) {
        switch kind {
        case .water:
            strokeMouth(in: &context, start: CGPoint(x: 751, y: 665), end: CGPoint(x: 825, y: 663), control: CGPoint(x: 790, y: 690), width: 7)
        case .stretch:
            let grin = Path { path in
                path.move(to: CGPoint(x: 733, y: 658))
                path.addQuadCurve(to: CGPoint(x: 843, y: 658), control: CGPoint(x: 789, y: 679))
                path.addCurve(to: CGPoint(x: 733, y: 658), control1: CGPoint(x: 832, y: 706), control2: CGPoint(x: 748, y: 706))
                path.closeSubpath()
            }
            context.fill(grin, with: .color(ink))
            let teeth = Path { path in
                path.move(to: CGPoint(x: 743, y: 665))
                path.addQuadCurve(to: CGPoint(x: 833, y: 665), control: CGPoint(x: 789, y: 681))
                path.addLine(to: CGPoint(x: 829, y: 676))
                path.addQuadCurve(to: CGPoint(x: 748, y: 676), control: CGPoint(x: 788, y: 689))
                path.closeSubpath()
            }
            context.fill(teeth, with: .color(Color(red: 0.87, green: 0.86, blue: 0.80)))
        case .eyes:
            strokeMouth(in: &context, start: CGPoint(x: 762, y: 671), end: CGPoint(x: 813, y: 671), control: CGPoint(x: 788, y: 681), width: 6)
        case .meal:
            strokeMouth(in: &context, start: CGPoint(x: 742, y: 664), end: CGPoint(x: 833, y: 660), control: CGPoint(x: 789, y: 689), width: 8)
            let tongue = Path { path in
                path.move(to: CGPoint(x: 802, y: 674))
                path.addQuadCurve(to: CGPoint(x: 820, y: 655), control: CGPoint(x: 814, y: 648))
                path.addQuadCurve(to: CGPoint(x: 825, y: 682), control: CGPoint(x: 836, y: 664))
                path.addQuadCurve(to: CGPoint(x: 802, y: 674), control: CGPoint(x: 813, y: 690))
                path.closeSubpath()
            }
            context.fill(tongue, with: .color(Color(red: 0.48, green: 0.25, blue: 0.29)))
            context.stroke(tongue, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        case .rest:
            let mouth = Path(ellipseIn: CGRect(x: 769, y: 654, width: 36, height: 42))
            context.fill(mouth, with: .color(ink))
            context.fill(Path(ellipseIn: CGRect(x: 779, y: 683, width: 18, height: 7)), with: .color(Color(red: 0.32, green: 0.17, blue: 0.20)))
        case .custom:
            context.fill(Path(ellipseIn: CGRect(x: 770, y: 657, width: 35, height: 34)), with: .color(ink))
        }
    }

    private func strokeMouth(in context: inout GraphicsContext, start: CGPoint, end: CGPoint, control: CGPoint, width: CGFloat) {
        let mouth = Path { path in
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
        context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
