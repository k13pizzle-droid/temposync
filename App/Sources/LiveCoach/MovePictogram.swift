import SwiftUI

/// Just-Dance-style animated move pictogram: a stylized rider on a spin bike, drawn in bold white
/// strokes, animated by continuous beat time so every motion is tempo-locked:
///   · cranks turn once per 2 beats (downstroke on the beat = the ride cadence, RPM = BPM/2)
///   · sprints double to one revolution per beat
///   · jumps rise/sit on a 4-count cycle, tap-backs push back on the "&", corners lean each 4
/// Direction arrows (yellow) pulse with the motion they describe.
/// User-selectable bike rendering (Settings → Ride → Figure style).
enum PictogramStyle: String, CaseIterable, Identifiable {
    case spin      // stationary spin bike: floor rail, front flywheel, upright masts (default)
    case classic   // the original two-wheel road-bike glyph
    case minimal   // rider only, faint seat/bar references

    var id: String { rawValue }
    static let defaultsKey = "pictogram_style"
    var label: String {
        switch self {
        case .spin: return "Spin bike"
        case .classic: return "Road bike"
        case .minimal: return "Minimal"
        }
    }
}

struct MovePictogram: View {
    let moveName: String
    let beatTime: Double
    /// Beats since this move's block began — drives progressive animation (jump ladder, combos).
    var countsIntoMove: Double = 0
    /// Crank revolutions per beat — how fast the legs turn (grind 0.25 / base 0.5 / sprint 1.0).
    var cadenceRevsPerBeat: Double = 0.5
    /// Static display (the Watch): the body holds the move's most characteristic mid-motion
    /// instant while the crank pins to the "one" — right foot planted at bottom-dead-center.
    var frozenOnTheOne: Bool = false
    var bikeStyle: PictogramStyle = .spin

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            ctx.scaleBy(x: s, y: s)
            let style = Style(moveName)
            var pose = style.pose(at: frozenOnTheOne ? 0.5 : beatTime,
                                  intoMove: frozenOnTheOne ? 8 : countsIntoMove,
                                  revsPerBeat: cadenceRevsPerBeat)
            if frozenOnTheOne { pose.crankAngle = .pi / 2 }   // right foot on the one

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
        case heavyClimb, standingHeavyClimb
        case sprintSeated, sprintStanding, jumps, tapBacks
        case pressDowns, pushups, widePushups, pushUpCombo, pushTapCombo, figure8s
        case hovers, crunches, combo64
        case corners, recovery

        init(_ name: String) {
            switch name {
            case "Seated Flat":               self = .seatedFlat
            case "Seated Climb":              self = .seatedClimb
            case "Standing Run":              self = .standingRun
            case "Standing Climb":            self = .standingClimb
            case "Heavy Climb":               self = .heavyClimb
            case "Standing Heavy Climb":      self = .standingHeavyClimb
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
            case "Hovers":                    self = .hovers
            case "Crunches":                  self = .crunches
            case "64-Count Combo":            self = .combo64
            case "Corners / Cross-Ups":       self = .corners
            default:                          self = .recovery
            }
        }

        func pose(at t: Double, intoMove m: Double, revsPerBeat: Double) -> Pose {
            // Crank speed is the move's cadence: base 0.5 rev/beat (one rev per 2 beats), sprints
            // 1.0 (ride the beat), heavy grinds 0.25 (cut the beat in half). Phase +π/2 puts the
            // NEAR (right) foot at bottom-dead-center exactly ON the beat — the traditional spin
            // convention (downstroke on the downbeat; legs alternate, so the right foot marks the
            // 1-3-5-7 counts and the left the 2-4-6-8).
            let crank = 2 * .pi * revsPerBeat * t + .pi / 2

            // The 64-count combo is a sequence: it delegates to a sub-move's pose for each 16-count
            // quarter, so the rider actually rides tap-backs → push-ups → hovers → crunches.
            if self == .combo64 {
                let quarter = Int((m / 16).rounded(.down)) % 4
                let sub: Style = [.tapBacks, .pushups, .hovers, .crunches][quarter]
                var cp = sub.pose(at: t, intoMove: m, revsPerBeat: revsPerBeat)
                cp.arrows.append(Arrow(dir: .up, at: CGPoint(x: 52, y: 12), opacity: 0.5))  // "combo" marker
                return cp
            }

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
            case .heavyClimb:
                // Half-time grind: deep forward drive, heavy body. Crank already turns slow (0.25
                // rev/beat via revsPerBeat); a small downbeat surge sells the "push" each stroke.
                let push = 0.06 * pulse(t, per: 2)
                p.hip = CGPoint(x: 39, y: 43); p.torsoLean = 0.62 + push
                p.speedLines = 0
            case .standingHeavyClimb:
                let heave = 1.4 * sin(.pi * t / 2)      // slow rise/fall, matches the half-time crank
                p.hip = CGPoint(x: 43, y: 35 + heave); p.torsoLean = 0.68; p.standing = true
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
            case .hovers:
                // Hips pushed BACK and lifted UP off the saddle, held — a slight breathing float.
                let float = 0.6 * sin(.pi * t)
                p.hip = CGPoint(x: 35, y: 39 - float); p.torsoLean = 0.5; p.standing = true
                p.arrows = [Arrow(dir: .up, at: CGPoint(x: 22, y: 44), opacity: 0.5),
                            Arrow(dir: .left, at: CGPoint(x: 24, y: 52), opacity: 0.4)]
            case .crunches:
                // Seated ab crunch: chest curls toward the bars, elbows drop, on the beat.
                let curl = max(0, sin(.pi * t))
                p.hip = CGPoint(x: 39, y: 43); p.torsoLean = 0.4 + 0.3 * curl
                p.elbowSag = 3 + 4 * curl
                p.arrows = [Arrow(dir: .down, at: CGPoint(x: 60, y: 20), opacity: 0.35 + 0.65 * curl)]
            case .corners:
                // Lean alternates every 4 counts.
                let phase = sin(.pi * t / 2)
                p.hip = CGPoint(x: 46, y: 34); p.standing = true; p.torsoLean = 0.5
                p.lean = 0.16 * phase
                p.arrows = [Arrow(dir: phase > 0 ? .right : .left, at: CGPoint(x: 52, y: 14),
                                  opacity: 0.35 + 0.65 * abs(phase))]
            case .combo64:
                break   // handled by the early return above; here only for exhaustiveness
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
        let crank = CGPoint(x: 52, y: 70)
        switch bikeStyle {
        case .spin:
            // Keiser-style studio bike (modeled on Kevin's M3i reference): the flywheel rides LOW
            // at the REAR behind the seat mast, the seat and bar masts form a V from the bottom
            // bracket, and everything stands on a long floor rail.
            stroke(&ctx, [CGPoint(x: 20, y: 88), CGPoint(x: 76, y: 88)], width: 3.6)   // floor rail
            stroke(&ctx, [CGPoint(x: 24, y: 88), CGPoint(x: 21, y: 93)], width: 3)     // rear foot
            stroke(&ctx, [CGPoint(x: 72, y: 88), CGPoint(x: 75, y: 93)], width: 3)     // front foot
            // Rear flywheel: heavy disc + rim, belt line back from the crank.
            let flywheel = CGPoint(x: 29, y: 75)
            ctx.fill(Path(ellipseIn: CGRect(x: flywheel.x - 10, y: flywheel.y - 10, width: 20, height: 20)),
                     with: .color(.white.opacity(0.28)))
            circle(&ctx, flywheel, 10, width: 2.6)
            circle(&ctx, flywheel, 1.8, fill: true)
            stroke(&ctx, [crank, flywheel], width: 2.8, shading: Self.dim)             // drive arm
            // Frame: forward strut down to the rail; the V of seat mast + bar mast meets at the
            // bottom bracket (the M3i's signature open-V silhouette). The drive arm to the flywheel
            // is a solid member on the real bike, not just a belt line.
            stroke(&ctx, [crank, CGPoint(x: 58, y: 88)], width: 3)                     // strut
            stroke(&ctx, [crank, CGPoint(x: 40, y: 49)], width: 3)                     // seat mast
            stroke(&ctx, [CGPoint(x: 40, y: 49), CGPoint(x: 40, y: 46)], width: 2.6)   // seat post
            stroke(&ctx, [CGPoint(x: 34, y: 46), CGPoint(x: 45, y: 46)], width: 3.6)   // saddle
            stroke(&ctx, [crank, CGPoint(x: 71, y: 47)], width: 3)                     // bar mast
            stroke(&ctx, [CGPoint(x: 71, y: 47), CGPoint(x: 74, y: 39)], width: 3)     // stem
            // Bullhorn bars: flat rear grip rising into a modest forward horn, like the M3i's.
            stroke(&ctx, [CGPoint(x: 68, y: 40), CGPoint(x: 74, y: 39),
                          CGPoint(x: 76.5, y: 38), CGPoint(x: 78, y: 36)], width: 3.4)
            // Transport rollers on the front foot.
            circle(&ctx, CGPoint(x: 73, y: 90.5), 1.5, width: 1.8)
        case .classic:
            let rear = CGPoint(x: 26, y: 78), front = CGPoint(x: 78, y: 78)
            circle(&ctx, rear, 11); circle(&ctx, front, 11)
            stroke(&ctx, [rear, crank], width: 3)
            stroke(&ctx, [crank, CGPoint(x: 72, y: 46)], width: 3)                 // down tube to head
            stroke(&ctx, [CGPoint(x: 72, y: 46), front], width: 3)                 // fork
            stroke(&ctx, [crank, CGPoint(x: 40, y: 46)], width: 3)                 // seat tube
            stroke(&ctx, [CGPoint(x: 34, y: 46), CGPoint(x: 45, y: 46)], width: 3.6)   // seat
            stroke(&ctx, [CGPoint(x: 72, y: 46), CGPoint(x: 74, y: 39)], width: 3)     // bar stem
            stroke(&ctx, [CGPoint(x: 69, y: 39), CGPoint(x: 79, y: 39)], width: 3.6)   // bars
        case .minimal:
            // Rider is the star: just faint seat/bar references so the poses stay legible.
            stroke(&ctx, [CGPoint(x: 34, y: 46), CGPoint(x: 45, y: 46)], width: 3, shading: Self.dim)
            stroke(&ctx, [CGPoint(x: 69, y: 39), CGPoint(x: 79, y: 39)], width: 3, shading: Self.dim)
            stroke(&ctx, [CGPoint(x: 40, y: 46), CGPoint(x: 46, y: 62)], width: 2, shading: Self.dim)
            stroke(&ctx, [CGPoint(x: 74, y: 39), CGPoint(x: 68, y: 56)], width: 2, shading: Self.dim)
        }
    }

    private func drawRider(_ ctx: inout GraphicsContext, _ pose: Pose) {
        let crank = CGPoint(x: 52, y: 70)
        let grip = CGPoint(x: 74, y: 39)
        let hip = pose.hip

        // Torso as a SPINE: a gentle rearward bow instead of a straight strut — the single biggest
        // "reads human" win. Direction and length are unchanged, so every pose holds.
        let torsoLen = 17.0
        let dir = CGPoint(x: sin(pose.torsoLean), y: -cos(pose.torsoLean))
        let shoulder = CGPoint(x: hip.x + torsoLen * dir.x + pose.shoulderSway.x,
                               y: hip.y + torsoLen * dir.y + pose.shoulderSway.y)
        let mid = CGPoint(x: (hip.x + shoulder.x) / 2, y: (hip.y + shoulder.y) / 2)
        let control = CGPoint(x: mid.x + 1.6 * dir.y, y: mid.y - 1.6 * dir.x)   // bows to the back
        var spine = Path()
        spine.move(to: hip)
        spine.addQuadCurve(to: shoulder, control: control)
        ctx.stroke(spine, with: Self.white,
                   style: StrokeStyle(lineWidth: 4.4, lineCap: .round))
        circle(&ctx, hip, 2.4, fill: true)                       // pelvis node grounds the joints

        // Neck + head: a short neck with a gap reads far more human than a head fused to the spine.
        let neckEnd = CGPoint(x: shoulder.x + 3.0 * dir.x, y: shoulder.y + 3.0 * dir.y)
        stroke(&ctx, [shoulder, neckEnd], width: 3.2)
        let headC = CGPoint(x: shoulder.x + 7.4 * dir.x, y: shoulder.y + 7.4 * dir.y)
        circle(&ctx, headC, 4.2, fill: true)

        // Arm: shoulder → elbow (sags with press) → grip, with a hand node on the bars. Wide grips
        // render a second, splayed arm — the open "diamond" between them reads as elbow width.
        let elbow = CGPoint(x: (shoulder.x + grip.x) / 2, y: (shoulder.y + grip.y) / 2 + pose.elbowSag)
        stroke(&ctx, [shoulder, elbow, grip], width: 3.4)
        if pose.armSplay > 0 {
            let flare = CGPoint(x: (shoulder.x + grip.x) / 2,
                                y: (shoulder.y + grip.y) / 2 - pose.elbowSag * 0.8 * pose.armSplay)
            stroke(&ctx, [shoulder, flare, grip], width: 3.0, shading: Self.dim)
        }
        circle(&ctx, grip, 1.7, fill: true)                      // hand

        // Legs to both pedals (far leg dimmed for depth), each ending in a flat shoe on the pedal.
        let r = 8.5
        let pedalA = CGPoint(x: crank.x + r * cos(pose.crankAngle), y: crank.y + r * sin(pose.crankAngle))
        let pedalB = CGPoint(x: crank.x - r * cos(pose.crankAngle), y: crank.y - r * sin(pose.crankAngle))
        for (pedal, shading, w) in [(pedalB, Self.dim, 3.2), (pedalA, Self.white, 3.8)] {
            let knee = CGPoint(x: (hip.x + pedal.x) / 2 + 6, y: (hip.y + pedal.y) / 2 - 2)
            stroke(&ctx, [hip, knee, pedal], width: w, shading: shading)
            stroke(&ctx, [CGPoint(x: pedal.x - 1.6, y: pedal.y), CGPoint(x: pedal.x + 2.8, y: pedal.y)],
                   width: w + 0.4, shading: shading)             // shoe, flat through the stroke
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
