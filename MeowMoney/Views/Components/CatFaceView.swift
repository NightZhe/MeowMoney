import SwiftUI

/// 吉祥物「錢錢貓」的表情。全部用 SwiftUI 形狀畫，不依賴圖片資產，
/// 所以任意尺寸都清晰，也不會拖大 app 體積。
enum CatMood {
    case idle       // 待機：正常睜眼微笑
    case listening  // 聆聽：張嘴、眼睛睜大
    case happy      // 記帳成功：瞇眼笑
    case confused   // 沒聽懂：一大一小眼
    case sleepy     // 沒有資料：閉眼
}

struct CatFaceView: View {
    var mood: CatMood = .idle
    var size: CGFloat = 120
    /// 聆聽時的音量（0...1），會讓嘴巴跟著開合。
    var level: Double = 0

    private var fur: Color { Color(hex: 0xFFE3C9) }
    private var furShade: Color { Color(hex: 0xF7CEA9) }
    private var ink: Color { Cute.cocoa }

    var body: some View {
        ZStack {
            ears
            head
            features
        }
        .frame(width: size, height: size)
        .animation(Cute.bouncy, value: mood)
    }

    // MARK: - 耳朵

    private var ears: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    EarShape()
                        .fill(fur)
                        .frame(width: size * 0.30, height: size * 0.30)
                    EarShape()
                        .fill(Cute.peach.opacity(0.65))
                        .frame(width: size * 0.16, height: size * 0.16)
                        .offset(y: size * 0.06)
                }
                .rotationEffect(.degrees(side * 12))
                .offset(x: size * 0.27 * side, y: -size * 0.33)
            }
        }
    }

    // MARK: - 頭

    private var head: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [fur, furShade],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size * 0.9, height: size * 0.86)
            .shadow(color: Cute.shadow, radius: size * 0.06, x: 0, y: size * 0.03)
    }

    // MARK: - 五官

    private var features: some View {
        ZStack {
            whiskers
            eyes
            blush
            nose
            mouth
        }
    }

    private var eyes: some View {
        HStack(spacing: size * 0.24) {
            eye(isLeft: true)
            eye(isLeft: false)
        }
        .offset(y: -size * 0.05)
    }

    @ViewBuilder
    private func eye(isLeft: Bool) -> some View {
        switch mood {
        case .happy, .sleepy:
            ArcShape()
                .stroke(ink, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.08)
        case .confused where isLeft:
            openEye(scale: 0.7)
        default:
            openEye(scale: mood == .listening ? 1.15 : 1)
        }
    }

    private func openEye(scale: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Ellipse()
                .fill(ink)
                .frame(width: size * 0.13 * scale, height: size * 0.17 * scale)
            Circle()
                .fill(.white)
                .frame(width: size * 0.045 * scale, height: size * 0.045 * scale)
                .offset(x: -size * 0.015, y: size * 0.03)
        }
    }

    private var blush: some View {
        HStack(spacing: size * 0.42) {
            blushDot
            blushDot
        }
        .offset(y: size * 0.08)
    }

    private var blushDot: some View {
        Ellipse()
            .fill(Cute.peach.opacity(0.55))
            .frame(width: size * 0.16, height: size * 0.09)
            .blur(radius: size * 0.012)
    }

    private var nose: some View {
        NoseShape()
            .fill(Cute.peachDeep)
            .frame(width: size * 0.075, height: size * 0.055)
            .offset(y: size * 0.09)
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .listening:
            Ellipse()
                .fill(Cute.peachDeep.opacity(0.85))
                .frame(
                    width: size * (0.10 + 0.05 * level),
                    height: size * (0.07 + 0.10 * level)
                )
                .offset(y: size * 0.20)
                .animation(.easeOut(duration: 0.12), value: level)
        case .confused:
            ArcShape()
                .stroke(ink, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                .frame(width: size * 0.14, height: size * 0.06)
                .offset(y: size * 0.20)
        default:
            HStack(spacing: 0) {
                ArcShape(flipped: true)
                    .stroke(ink, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                    .frame(width: size * 0.10, height: size * 0.06)
                ArcShape(flipped: true)
                    .stroke(ink, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                    .frame(width: size * 0.10, height: size * 0.06)
            }
            .offset(y: size * 0.17)
        }
    }

    private var whiskers: some View {
        HStack(spacing: size * 0.5) {
            whiskerSet(mirrored: true)
            whiskerSet(mirrored: false)
        }
        .offset(y: size * 0.09)
    }

    private func whiskerSet(mirrored: Bool) -> some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: size * 0.05) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(ink.opacity(0.45))
                    .frame(width: size * (index == 1 ? 0.20 : 0.16), height: size * 0.014)
                    .rotationEffect(.degrees(Double(index - 1) * (mirrored ? -10 : 10)))
            }
        }
    }
}

// MARK: - 形狀

private struct EarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.2)
        )
        path.closeSubpath()
        return path
    }
}

private struct NoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.maxY * 0.7)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY * 0.7)
        )
        return path
    }
}

/// 預設是「⌒」（開口向下），flipped 之後是「‿」（開口向上）。
private struct ArcShape: Shape {
    var flipped: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if flipped {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6)
            )
        }
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            CatFaceView(mood: .idle, size: 100)
            CatFaceView(mood: .happy, size: 100)
        }
        HStack(spacing: 20) {
            CatFaceView(mood: .listening, size: 100, level: 0.6)
            CatFaceView(mood: .confused, size: 100)
        }
    }
    .padding(40)
    .background(Cute.background)
}
