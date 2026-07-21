import SwiftUI

/// Just-Dance-style animated move pictogram: a stylized rider on a spin bike, drawn in bold white
/// strokes, animated by continuous beat time so every motion is tempo-locked:
///   · cranks turn once per 2 beats (downstroke on the beat = the ride cadence, RPM = BPM/2)
///   · sprints double to one revolution per beat
///   · jumps rise/sit on a 4-count cycle, tap-backs push back on the "&", corners lean each 4
/// Direction arrows (yellow) pulse with the motion they describe.
struct MovePictogram: View {
    let moveName: String
    let beatTime: Double
    /// Beats since this move's block began — drives progressive animation (jump ladder, combos).
    var countsIntoMove: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            ctx.scaleBy(x: s, y: s)
            let style = Style(moveName)
            let pose = style.pose(at: beatTime, intoMove: countsIntoMove)

            // Whole-glyph lean (corners) rotates about the bottom center.
            if pose.lean != 0 {
                ctx.translateBy(x: 52, y: 82)
                ctx.rotate(by: .radians(pose.lean))
                ctx.translateBy(x: -52, y: -82)
            }

            drawBike(&ctx, pose)
            drawRider(&ctx, pose)
            drawArrows(&ctx, pose)
            if pose.speedLines > 0 { drawSpeedLines(&ctx, intensity: pose.speedLines) }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Move styles → poses

    private enum Style {
        case seatedFlat, seatedClimb, standingRun, standingClimb
        case sprintSeated, sprintStanding, jumps, tapBacks
        case pressDowns, pushups, widePushups, pushUpCombo, pushTapCombo, figure8s
        case corners, recovery

        init(_ name: String) {
            switch name {
            case "Seated Flat":               self = .seatedFlat
            case "Seated Climb":              self = .seatedClimb
            case "Standing Run":              self = .standingRun
            case "Standing Climb":            self = .standingClimb
            case "Seated Sprint":             self = .sprintSeated
            case "Standing Sprint":           self = .sprintStanding
            case "Jumps":                     self = .jumps
            case "Tap-Backs":                 self = .tapBacks
            case "Press-Downs":               self = .pressDowns
            case "Handlebar Push-Ups":        self = .pushups
            case "Wide Push-Ups":             self = .widePushups
            case "Push-Up Combo":             self = .pushUpCombo
            case "Push-Up + Tap-Back Combo":  self = .pushTapCombo
            case "Figure 8s":                 self = .figure8s
            case "Corners / Cross-Ups":       self = .corners
            default:                          self = .recovery
            }
        }

        func pose(at t: Double, intoMove m: Double) -> Pose {
            // Base cadence: one crank revolution per 2 beats; sprints ride the beat itself.
            // Phase: +π/2 puts the NEAR (right) foot at bottom-dead-center exactly ON the beat —
            // the traditional spin convention (downstroke lands on the downbeat; legs alternate,
            // so the right foot marks the 1-3-5-7 counts and the left the 2-4-6-8).
            let isSprint = self == .sprintSeated || self == .sprintStanding
            let crank = (isSprint ? 2 * .pi : .pi) * t + .pi / 2

            var p = Pose(crankAngle: crank)
            switch self {
            case .recovery:
                p.hip = CGPoint(x: 39, y: 42); p.torsoLean = 0.12
            case .seatedFlat:
                p.hip = CGPoint(x: 39, y: 43); p.torsoLean = 0.35
            case .seatedClimb:
                p.hip = CGPoint(x: 39, y: 43); p.torsoLean = 0.55
            case .standingRun:
                let bob = 1.2 * sin(.pi * t)
                p.hip = CGPoint(x: 47, y: 33 + bob); p.torsoLean = 0.45; p.standing = true
            case .standingClimb:
                let bob = 1.0 * sin(.pi * t)
                p.hip = CGPoint(x: 44, y: 35 + bob); p.torsoLean = 0.62; p.standing = true
            case .sprintSeated:
                p.hip = CGPoint(x: 39, y: 43); p.torsoLean = 0.75; p.speedLines = pulse(t, per: 1)
            case .sprintStanding:
                let bob = 0.8 * sin(2 * .pi * t)
                p.hip = CGPoint(x: 47, y: 33 + bob); p.torsoLean = 0.7; p.standing = true
                p.speedLines = pulse(t, per: 1)
            case .jumps:
                // Cadence LADDER (the early-ride blood-pumper): the block starts on an 8-count
                // jump cycle, tightens to 4s, then 2s — driven by how far into the block we are.
                let cycle: Double = m < 8 ? 8 : (m < 16 ? 4 : 2)
                let c = (t.truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle)
                let half = cycle / 2
                let up = c < half ? smooth(c / half) : smooth(1 - (c - half) / half)
                p.hip = lerp(CGPoint(x: 39, y: 43), CGPoint(x: 47, y: 32), up)
                p.torsoLean = 0.35 + 0.15 * up
                p.standing = up > 0.5
                p.arrows = [Arrow(dir: c < half ? .up : .down,
                                  at: CGPoint(x: 30, y: 22),
                                  opacity: 0.35 + 0.65 * up)]
            case .tapBacks:
                // Hips tap back on the "&": one push-back per 2 beats.
                let back = max(0, sin(.pi * t))
                p.hip = CGPoint(x: 39 - 6 * back, y: 43 - 1.5 * back)
                p.torsoLean = 0.4 + 0.18 * back
                p.arrows = [Arrow(dir: .left, at: CGPoint(x: 22, y: 40), opacity: 0.35 + 0.65 * back)]
            case .pressDowns:
                let press = max(0, sin(.pi * t))
                p.hip = CGPoint(x: 39, y: 43); p.torsoLean = 0.4 + 0.1 * press
                p.elbowSag = 2 + 4 * press
                p.arrows = [Arrow(dir: .down, at: CGPoint(x: 80, y: 26), opacity: 0.35 + 0.65 * press)]
            case .pushups:
                // Chest dips toward the bars every 2 counts.
                let dip = max(0, sin(.pi * t))
                p.hip = CGPoint(x: 44, y: 37); p.standing = true
                p.torsoLean = 0.5 + 0.35 * dip
                p.elbowSag = 2 + 5 * dip
                p.arrows = [Arrow(dir: dip > 0.5 ? .down : .up, at: CGPoint(x: 82, y: 24),
                                  opacity: 0.35 + 0.65 * dip)]
            case .widePushups:
                // Same dip, elbows flared wide (second splayed arm renders the width).
                let dip = max(0, sin(.pi * t))
                p.hip = CGPoint(x: 44, y: 37); p.standing = true
                p.torsoLean = 0.5 + 0.35 * dip
                p.elbowSag = 3 + 5 * dip
                p.armSplay = 1
                p.arrows = [Arrow(dir: dip > 0.5 ? .down : .up, at: CGPoint(x: 82, y: 24),
                                  opacity: 0.35 + 0.65 * dip)]
            case .pushUpCombo:
                // Alternating sets: narrow 4 counts, wide 4 counts.
                let dip = max(0, sin(.pi * t))
                let wide = (m.truncatingRemainder(dividingBy: 8)) >= 4
                p.hip = CGPoint(x: 44, y: 37); p.standing = true
                p.torsoLean = 0.5 + 0.35 * dip
                p.elbowSag = (wide ? 3 : 2) + 5 * dip
                p.armSplay = wide ? 1 : 0
                p.arrows = [Arrow(dir: dip > 0.5 ? .down : .up, at: CGPoint(x: 82, y: 24),
                                  opacity: 0.35 + 0.65 * dip)]
            case .pushTapCombo:
                // 4 counts of push-ups into 4 counts of tap-backs, repeating.
                if (m.truncatingRemainder(dividingBy: 8)) < 4 {
                    let dip = max(0, sin(.pi * t))
                    p.hip = CGPoint(x: 44, y: 37); p.standing = true
                    p.torsoLean = 0.5 + 0.35 * dip
                    p.elbowSag = 2 + 5 * dip
                    p.arrows = [Arrow(dir: dip > 0.5 ? .down : .up, at: CGPoint(x: 82, y: 24),
                                      opacity: 0.35 + 0.65 * dip)]
                } else {
                    let back = max(0, sin(.pi * t))
                    p.hip = CGPoint(x: 39 - 6 * back, y: 43 - 1.5 * back)
                    p.torsoLean = 0.4 + 0.18 * back
                    p.arrows = [Arrow(dir: .left, at: CGPoint(x: 22, y: 40), opacity: 0.35 + 0.65 * back)]
                }
            case .figure8s:
                // Upper body sweeps a figure-eight over the bars (lissajous on the shoulders).
                p.hip = CGPoint(x: 39, y: 43); p.torsoLean = 0.45
                p.shoulderSway = CGPoint(x: 4 * sin(.pi * t / 2), y: 2 * sin(.pi * t))
                p.elbowSag = 3
                p.arrows = [Arrow(dir: sin(.pi * t / 2) > 0 ? .right : .left, at: CGPoint(x: 52, y: 14),
                                  opacity: 0.5)]
            case .corners:
                // Lean alternates every 4 counts.
                let phase = sin(.pi * t / 2)
                p.hip = CGPoint(x: 46, y: 34); p.standing = true; p.torsoLean = 0.5
                p.lean = 0.16 * phase
                p.arrows = [Arrow(dir: phase > 0 ? .right : .left, at: CGPoint(x: 52, y: 14),
                                  opacity: 0.35 + 0.65 * abs(phase))]
            }
            return p
        }
    }

    struct Arrow { enum Dir { case up, down, left, right }
        let dir: Dir; let at: CGPoint; let opacity: Double }

    struct Pose {
        var crankAngle: Double
        var hip = CGPoint(x: 39, y: 43)
        var torsoLean = 0.35            // radians forward from vertical
        var standing = false
        var elbowSag: Double = 2
        var armSplay: Double = 0        // 0 = single arm; 1 = wide grip (second splayed arm drawn)
        var shoulderSway: CGPoint = .zero   // figure-8s: lissajous offset applied at the shoulders
        var lean: Double = 0            // whole-glyph lean (corners)
        var speedLines: Double = 0
        var arrows: [Arrow] = []
    }

    // MARK: - Drawing

    private static let white = GraphicsContext.Shading.color(.white)
    private static let dim = GraphicsContext.Shading.color(.white.opacity(0.45))

    private func stroke(_ ctx: inout GraphicsContext, _ pts: [CGPoint], width: Double = 3.6,
                        shading: GraphicsContext.Shading = MovePictogram.white) {
        var path = Path()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func circle(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: Double, width: Double = 3.2,
                        fill: Bool = false) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        if fill { ctx.fill(Path(ellipseIn: rect), with: Self.white) }
        else { ctx.stroke(Path(ellipseIn: rect), with: Self.white, style: StrokeStyle(lineWidth: width)) }
    }

    private func drawBike(_ ctx: inout GraphicsContext, _ pose: Pose) {
        let rear = CGPoint(x: 26, y: 78), front = CGPoint(x: 78, y: 78)
        let crank = CGPoint(x: 52, y: 70)
        circle(&ctx, rear, 11); circle(&ctx, front, 11)
        // Frame
        stroke(&ctx, [rear, crank], width: 3)
        stroke(&ctx, [crank, CGPoint(x: 72, y: 46)], width: 3)                 // down tube to head
        stroke(&ctx, [CGPoint(x: 72, y: 46), front], width: 3)                 // fork
        stroke(&ctx, [crank, CGPoint(x: 40, y: 46)], width: 3)                 // seat tube
        stroke(&ctx, [CGPoint(x: 34, y: 46), CGPoint(x: 45, y: 46)], width: 3.6)   // seat
        stroke(&ctx, [CGPoint(x: 72, y: 46), CGPoint(x: 74, y: 39)], width: 3)     // bar stem
        stroke(&ctx, [CGPoint(x: 69, y: 39), CGPoint(x: 79, y: 39)], width: 3.6)   // bars
    }

    private func drawRider(_ ctx: inout GraphicsContext, _ pose: Pose) {
        let crank = CGPoint(x: 52, y: 70)
        let grip = CGPoint(x: 74, y: 39)
        let hip = pose.hip

        // Torso + head (figure-8s sway the shoulders on a lissajous)
        let torsoLen = 17.0
        let shoulder = CGPoint(x: hip.x + torsoLen * sin(pose.torsoLean) + pose.shoulderSway.x,
                               y: hip.y - torsoLen * cos(pose.torsoLean) + pose.shoulderSway.y)
        let headC = CGPoint(x: shoulder.x + 6.5 * sin(pose.torsoLean),
                            y: shoulder.y - 6.5 * cos(pose.torsoLean))
        stroke(&ctx, [hip, shoulder], width: 4.2)
        circle(&ctx, headC, 4.4, fill: true)

        // Arm: shoulder → elbow (sags with press) → grip. Wide grips render a second, splayed arm —
        // the open "diamond" between them reads as elbow width in side view.
        let elbow = CGPoint(x: (shoulder.x + grip.x) / 2, y: (shoulder.y + grip.y) / 2 + pose.elbowSag)
        stroke(&ctx, [shoulder, elbow, grip], width: 3.4)
        if pose.armSplay > 0 {
            let flare = CGPoint(x: (shoulder.x + grip.x) / 2,
                                y: (shoulder.y + grip.y) / 2 - pose.elbowSag * 0.8 * pose.armSplay)
            stroke(&ctx, [shoulder, flare, grip], width: 3.0, shading: Self.dim)
        }

        // Legs to both pedals (far leg dimmed for depth)
        let r = 8.5
        let pedalA = CGPoint(x: crank.x + r * cos(pose.crankAngle), y: crank.y + r * sin(pose.crankAngle))
        let pedalB = CGPoint(x: crank.x - r * cos(pose.crankAngle), y: crank.y - r * sin(pose.crankAngle))
        for (pedal, shading, w) in [(pedalB, Self.dim, 3.2), (pedalA, Self.white, 3.8)] {
            let knee = CGPoint(x: (hip.x + pedal.x) / 2 + 6, y: (hip.y + pedal.y) / 2 - 2)
            stroke(&ctx, [hip, knee, pedal], width: w, shading: shading)
        }
        circle(&ctx, crank, 2.2, fill: true)
    }

    private func drawArrows(_ ctx: inout GraphicsContext, _ pose: Pose) {
        for arrow in pose.arrows {
            let shading = GraphicsContext.Shading.color(.yellow.opacity(arrow.opacity))
            let len = 11.0, head = 4.5
            let (v, hvec): (CGPoint, CGPoint)
            switch arrow.dir {
            case .up:    (v, hvec) = (CGPoint(x: 0, y: -len), CGPoint(x: head, y: head))
            case .down:  (v, hvec) = (CGPoint(x: 0, y: len), CGPoint(x: head, y: -head))
            case .left:  (v, hvec) = (CGPoint(x: -len, y: 0), CGPoint(x: head, y: head))
            case .right: (v, hvec) = (CGPoint(x: len, y: 0), CGPoint(x: -head, y: head))
            }
            let tip = CGPoint(x: arrow.at.x + v.x / 2, y: arrow.at.y + v.y / 2)
            let tail = CGPoint(x: arrow.at.x - v.x / 2, y: arrow.at.y - v.y / 2)
            var path = Path()
            path.move(to: tail); path.addLine(to: tip)
            // Head barbs
            if arrow.dir == .up || arrow.dir == .down {
                path.move(to: CGPoint(x: tip.x - hvec.x, y: tip.y + hvec.y))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: tip.x + hvec.x, y: tip.y + hvec.y))
            } else {
                path.move(to: CGPoint(x: tip.x + hvec.x, y: tip.y - hvec.y))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: tip.x + hvec.x, y: tip.y + hvec.y))
            }
            ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawSpeedLines(_ ctx: inout GraphicsContext, intensity: Double) {
        let shading = GraphicsContext.Shading.color(.white.opacity(0.25 + 0.4 * intensity))
        for (i, y) in [30.0, 38, 46].enumerated() {
            let x = 14.0 + Double(i) * 2
            var path = Path()
            path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + 9, y: y))
            ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }
}

// MARK: - Small math helpers

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
private func smooth(_ t: Double) -> Double {   // smoothstep
    let c = min(max(t, 0), 1); return c * c * (3 - 2 * c)
}
private func pulse(_ t: Double, per: Double) -> Double {   // 0→1→0 each `per` beats
    abs(sin(.pi * t / per))
}

#Preview("Jumps") {
    TimelineView(.animation) { ctx in
        MovePictogram(moveName: "Jumps",
                      beatTime: ctx.date.timeIntervalSinceReferenceDate * (128.0 / 60.0))
            .frame(width: 220, height: 220)
            .background(.blue.gradient)
    }
}
