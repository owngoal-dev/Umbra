import UIKit

/// The app icon's eclipse rebuilt from Core Animation layers so the Moon can
/// drift across the Sun. Closest approach reproduces the icon exactly and the
/// animation rests there before the Moon moves on.
///
/// Geometry and colours mirror `Tools/make-icon.swift`, expressed in the same
/// 1024-unit design space and scaled to whatever size the view is given.
final class EclipseView: UIView {
    // MARK: Design space

    private static let design: CGFloat = 1024
    private static let sunRadius: CGFloat = 352
    private static let moonRadius: CGFloat = 356
    private static let sunCentre = CGPoint(x: 536, y: 488)
    private static let totality = CGPoint(x: 496, y: 528)
    /// The Moon travels down-right, perpendicular to its offset from the Sun at
    /// totality, so the icon composition is its closest approach.
    private static let track = CGPoint(x: 0.7071, y: 0.7071)
    /// Far enough along the track that the Moon is entirely outside the view, so
    /// the loop can restart without a visible jump.
    private static let reach: CGFloat = 1260

    /// One cycle starts and ends on the icon composition: rest there, sweep out,
    /// wait off-screen (the two off-screen keyframes hide the jump back to the
    /// entry side), then sweep in and settle again.
    private static let cycle: CFTimeInterval = 14
    /// Easter egg: the header sits on the icon for this long before the first
    /// eclipse begins, so only people who linger in Settings ever see it move.
    private static let dormancy: CFTimeInterval = 30
    private static let keyTimes: [NSNumber] = [0, 0.36, 0.62, 0.71, 0.711, 0.72, 1]

    // MARK: Palette

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        ).cgColor
    }

    private static let backgroundCore: UInt32 = 0x0E1424
    private static let backgroundEdge: UInt32 = 0x05070D
    private static let sunWarm: UInt32 = 0xFFD27A
    private static let sunDeep: UInt32 = 0xFF7A3D
    private static let coronaWarm: UInt32 = 0xFF9A4D
    private static let coronaBright: UInt32 = 0xFFD9A0
    private static let umbraCore: UInt32 = 0x1A1714
    private static let umbraEdge: UInt32 = 0x0B0A08
    private static let rimAmbient: UInt32 = 0xC8B8A0

    // MARK: Layers

    private let space = CAGradientLayer()
    private let glare = CAGradientLayer()
    private let corona = CAGradientLayer()
    private let streamers = CAGradientLayer()
    private let spokes = CAReplicatorLayer()
    private let spoke = CAGradientLayer()
    private let wisps = CAGradientLayer()
    private let wispSpokes = CAReplicatorLayer()
    private let wisp = CAGradientLayer()
    private let rimGlow = CAGradientLayer()
    private let sun = CAGradientLayer()
    private let moon = CALayer()
    private let moonBase = CAGradientLayer()
    private let moonSurface = CALayer()
    private let moonSheen = CAGradientLayer()
    private let moonSheenMask = CAGradientLayer()
    private let moonWrap = CAGradientLayer()
    private let moonWrapMask = CAGradientLayer()
    private let moonLimb = CAShapeLayer()
    private let diamond = CAGradientLayer()

    private var laidOutSize = CGSize.zero

    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        isAccessibilityElement = false
        backgroundColor = UIColor(cgColor: Self.color(Self.backgroundEdge))
        buildLayers()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(syncAnimations),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(
            self, selector: #selector(syncAnimations),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncAnimations()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0 else { return }
        laidOutSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutLayers()
        CATransaction.commit()
        syncAnimations()
    }

    // MARK: Construction

    private func buildLayers() {
        func radial(_ gradient: CAGradientLayer) {
            gradient.type = .radial
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1)
        }

        radial(space)
        space.colors = [Self.color(Self.backgroundCore), Self.color(Self.backgroundEdge)]

        // Uncovered Sun: a broad warm bloom that fades as the Moon closes in.
        radial(glare)
        glare.colors = [
            Self.color(Self.sunWarm, 0.75), Self.color(Self.sunWarm, 0.55),
            Self.color(Self.sunWarm, 0.18), Self.color(Self.sunWarm, 0),
        ]
        glare.locations = [0, 0.59, 0.80, 1]
        glare.opacity = 0

        radial(corona)
        corona.colors = [
            Self.color(Self.coronaWarm, 0.60), Self.color(Self.coronaWarm, 0.60),
            Self.color(Self.coronaWarm, 0.30), Self.color(Self.coronaWarm, 0.09),
            Self.color(Self.coronaWarm, 0),
        ]
        corona.locations = [0, 0.469, 0.602, 0.788, 1]

        // Coronal streamers: a radial glow seen through tapered spokes, so each
        // ray fades with distance. Two rings turn in opposite directions.
        radial(streamers)
        streamers.colors = [
            Self.color(Self.coronaBright, 0.42), Self.color(Self.coronaBright, 0.20),
            Self.color(Self.coronaBright, 0),
        ]
        streamers.locations = [0.48, 0.74, 1]
        // Each ray is a soft-edged beam: opaque along its centre line, clear at
        // both sides, so the replicated mask has no hard edges.
        let beam = [Self.color(0xFFFFFF, 0), Self.color(0xFFFFFF, 1), Self.color(0xFFFFFF, 0)]
        spoke.colors = beam
        spoke.startPoint = CGPoint(x: 0, y: 0.5)
        spoke.endPoint = CGPoint(x: 1, y: 0.5)
        spokes.instanceCount = 16
        spokes.instanceTransform = CATransform3DMakeRotation(2 * .pi / 16, 0, 0, 1)
        spokes.instanceAlphaOffset = -0.03
        spokes.addSublayer(spoke)
        streamers.mask = spokes
        streamers.opacity = 0

        radial(wisps)
        wisps.colors = [
            Self.color(Self.coronaWarm, 0.32), Self.color(Self.coronaWarm, 0.12),
            Self.color(Self.coronaWarm, 0),
        ]
        wisps.locations = [0.40, 0.68, 1]
        wisp.colors = beam
        wisp.startPoint = CGPoint(x: 0, y: 0.5)
        wisp.endPoint = CGPoint(x: 1, y: 0.5)
        wispSpokes.instanceCount = 7
        wispSpokes.instanceTransform = CATransform3DMakeRotation(2 * .pi / 7, 0, 0, 1)
        wispSpokes.instanceAlphaOffset = -0.06
        wispSpokes.addSublayer(wisp)
        wisps.mask = wispSpokes
        wisps.opacity = 0

        radial(rimGlow)
        rimGlow.colors = [
            Self.color(Self.coronaBright, 0.85), Self.color(Self.coronaBright, 0.85),
            Self.color(Self.coronaBright, 0.35), Self.color(Self.coronaBright, 0),
        ]
        rimGlow.locations = [0, 0.825, 0.904, 1]

        sun.colors = [Self.color(Self.sunWarm), Self.color(Self.sunDeep)]
        sun.startPoint = CGPoint(x: 1, y: 0)
        sun.endPoint = CGPoint(x: 0, y: 1)

        moon.masksToBounds = true
        moon.backgroundColor = Self.color(Self.umbraEdge)

        radial(moonBase)
        moonBase.colors = [Self.color(Self.umbraCore), Self.color(Self.umbraEdge)]

        moonSurface.contents = UIImage(named: "MoonDisk")?.cgImage
        moonSurface.contentsGravity = .resizeAspect
        moonSurface.opacity = 0.10

        // Faint cool-neutral sheen on the limb facing away from the Sun.
        radial(moonSheen)
        moonSheen.colors = [
            Self.color(Self.rimAmbient, 0), Self.color(Self.rimAmbient, 0),
            Self.color(Self.rimAmbient, 0.056), Self.color(Self.rimAmbient, 0.16),
        ]
        moonSheen.locations = [0, 0.62, 0.90, 1]
        moonSheenMask.colors = [
            Self.color(0xFFFFFF, 1), Self.color(0xFFFFFF, 0.35), Self.color(0xFFFFFF, 0),
        ]
        moonSheenMask.startPoint = CGPoint(x: 0, y: 1)
        moonSheenMask.endPoint = CGPoint(x: 1, y: 0)
        moonSheen.mask = moonSheenMask

        // Warm light wrapping onto the limb that faces the Sun.
        radial(moonWrap)
        moonWrap.colors = [
            Self.color(Self.coronaBright, 0), Self.color(Self.coronaBright, 0),
            Self.color(Self.coronaBright, 0.19), Self.color(Self.coronaBright, 0.55),
        ]
        moonWrap.locations = [0, 0.70, 0.90, 1]
        moonWrapMask.colors = moonSheenMask.colors
        moonWrapMask.startPoint = CGPoint(x: 1, y: 0)
        moonWrapMask.endPoint = CGPoint(x: 0, y: 1)
        moonWrap.mask = moonWrapMask

        moonLimb.fillColor = nil
        moonLimb.strokeColor = Self.color(Self.rimAmbient, 0.25)

        for sublayer in [moonBase, moonSurface, moonSheen, moonWrap, moonLimb] {
            moon.addSublayer(sublayer)
        }

        // The "diamond ring": a flash where the last sliver of Sun disappears.
        radial(diamond)
        diamond.colors = [
            Self.color(0xFFFFFF, 1), Self.color(Self.coronaBright, 0.7),
            Self.color(Self.coronaWarm, 0),
        ]
        diamond.locations = [0, 0.25, 1]
        diamond.opacity = 0

        for sublayer in [space, glare, corona, wisps, streamers, rimGlow, sun, moon, diamond] {
            layer.addSublayer(sublayer)
        }
    }

    // MARK: Layout

    private var unit: CGFloat { bounds.width / Self.design }

    private func point(_ design: CGPoint) -> CGPoint {
        CGPoint(x: design.x * unit, y: design.y * unit)
    }

    private func square(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        let r = radius * unit
        return CGRect(x: centre.x * unit - r, y: centre.y * unit - r, width: r * 2, height: r * 2)
    }

    private func layoutLayers() {
        space.frame = bounds

        let sunCentre = Self.sunCentre
        let sunRadius = Self.sunRadius
        glare.frame = square(sunCentre, sunRadius * 1.70)
        corona.frame = square(sunCentre, sunRadius * 1.92)
        rimGlow.frame = square(sunCentre, sunRadius * 1.20)
        sun.frame = square(sunCentre, sunRadius)
        sun.cornerRadius = sunRadius * unit

        func beamFrame(in bounds: CGRect, base: CGFloat, tip: CGFloat, halfWidth: CGFloat)
            -> CGRect
        {
            CGRect(
                x: bounds.midX - halfWidth * unit, y: bounds.midY - tip * unit,
                width: halfWidth * 2 * unit, height: (tip - base) * unit)
        }
        streamers.frame = square(sunCentre, sunRadius * 2.0)
        spokes.frame = streamers.bounds
        spoke.frame = beamFrame(
            in: streamers.bounds, base: sunRadius * 0.95, tip: sunRadius * 1.95,
            halfWidth: sunRadius * 0.07)
        wisps.frame = square(sunCentre, sunRadius * 2.5)
        wispSpokes.frame = wisps.bounds
        wisp.frame = beamFrame(
            in: wisps.bounds, base: sunRadius * 1.0, tip: sunRadius * 2.45,
            halfWidth: sunRadius * 0.05)

        let moonRadius = Self.moonRadius
        moon.bounds = CGRect(origin: .zero, size: square(.zero, moonRadius).size)
        moon.position = point(Self.totality)
        moon.cornerRadius = moonRadius * unit
        for sublayer in [moonBase, moonSurface, moonSheen, moonWrap, moonLimb] {
            sublayer.frame = moon.bounds
        }
        moonSheenMask.frame = moon.bounds
        moonWrapMask.frame = moon.bounds
        moonLimb.lineWidth = 3 * unit
        moonLimb.path =
            UIBezierPath(
                ovalIn: moon.bounds.insetBy(dx: 1.5 * unit, dy: 1.5 * unit)
            ).cgPath

        let contact = CGPoint(
            x: sunCentre.x + sunRadius * 0.7071, y: sunCentre.y - sunRadius * 0.7071)
        diamond.frame = square(contact, sunRadius * 0.55)
    }

    // MARK: Animation

    @objc private func syncAnimations() {
        removeAnimations()
        guard window != nil, bounds.width > 0, !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        installAnimations()
    }

    private var animatedLayers: [CALayer] {
        [moon, moonWrapMask, moonSheenMask, corona, streamers, wisps, rimGlow, glare, diamond]
    }

    private func removeAnimations() {
        for animated in animatedLayers {
            animated.removeAllAnimations()
        }
    }

    private func installAnimations() {
        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        let linear = CAMediaTimingFunction(name: .linear)
        let tot = point(Self.totality)
        let wake = CACurrentMediaTime() + Self.dormancy
        let step = CGPoint(x: Self.track.x * Self.reach * unit, y: Self.track.y * Self.reach * unit)
        let start = CGPoint(x: tot.x - step.x, y: tot.y - step.y)
        let end = CGPoint(x: tot.x + step.x, y: tot.y + step.y)

        func cycle(
            _ keyPath: String, _ values: [Any], _ keyTimes: [NSNumber],
            timing: [CAMediaTimingFunction]? = nil
        ) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = keyTimes
            animation.timingFunctions = timing
            animation.duration = Self.cycle
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            animation.beginTime = wake
            return animation
        }

        // Moon: rest at totality, sweep out, wait off-screen, sweep back in.
        let travel = [linear, easeInOut, linear, linear, linear, easeInOut]
        moon.add(
            cycle(
                "position", [tot, tot, end, end, start, start, tot], Self.keyTimes,
                timing: travel),
            forKey: "position")

        // The limb lighting keeps facing the Sun as the Moon passes it.
        let downRight = CGPoint(x: 1, y: 1)
        let upRight = CGPoint(x: 1, y: 0)
        let upLeft = CGPoint(x: 0, y: 0)
        let downLeft = CGPoint(x: 0, y: 1)
        let towards = [upRight, upRight, upLeft, upLeft, downRight, downRight, upRight]
        let away = [downLeft, downLeft, downRight, downRight, upLeft, upLeft, downLeft]
        moonWrapMask.add(cycle("startPoint", towards, Self.keyTimes, timing: travel), forKey: "s")
        moonWrapMask.add(cycle("endPoint", away, Self.keyTimes, timing: travel), forKey: "e")
        moonSheenMask.add(cycle("startPoint", away, Self.keyTimes, timing: travel), forKey: "s")
        moonSheenMask.add(cycle("endPoint", towards, Self.keyTimes, timing: travel), forKey: "e")

        // Corona and streamers emerge only around totality; glare does the opposite.
        let coronaTimes: [NSNumber] = [0, 0.36, 0.45, 0.72, 0.91, 1]
        let coronaValues: [Float] = [1, 1, 0, 0, 0, 1]
        corona.add(cycle("opacity", coronaValues, coronaTimes), forKey: "opacity")

        // Totality begins as the plain icon; the streamers bloom while it rests.
        let bloomTimes: [NSNumber] = [0, 0.03, 0.15, 0.26, 0.36, 1]
        streamers.add(cycle("opacity", [0, 0, 1, 1, 0, 0], bloomTimes), forKey: "opacity")
        wisps.add(cycle("opacity", [0, 0, 0.8, 0.8, 0, 0], bloomTimes), forKey: "opacity")
        rimGlow.add(
            cycle("opacity", [1, 1, 0.35, 0.35, 0.35, 1], [0, 0.36, 0.49, 0.72, 0.87, 1]),
            forKey: "opacity")
        glare.add(
            cycle("opacity", [0, 0, 0.7, 1, 0.7, 0, 0], [0, 0.37, 0.50, 0.72, 0.86, 0.99, 1]),
            forKey: "opacity")

        // Diamond ring flashes as totality begins and ends.
        diamond.add(
            cycle(
                "opacity", [0, 0, 1, 0, 0, 1, 0],
                [0, 0.345, 0.37, 0.395, 0.95, 0.975, 1]),
            forKey: "opacity")

        // Slow, continuous life: the corona breathes and the streamers turn.
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 1.0
        breathe.toValue = 1.05
        breathe.duration = 2.6
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = easeInOut
        breathe.beginTime = wake
        corona.add(breathe, forKey: "breathe")

        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * CGFloat.pi
        turn.duration = 70
        turn.repeatCount = .infinity
        turn.beginTime = wake
        streamers.add(turn, forKey: "turn")

        let drift = CABasicAnimation(keyPath: "transform.rotation.z")
        drift.fromValue = 0
        drift.toValue = -2 * CGFloat.pi
        drift.duration = 110
        drift.repeatCount = .infinity
        drift.beginTime = wake
        wisps.add(drift, forKey: "drift")
    }
}
