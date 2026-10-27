import Flutter
import UIKit

/// A glass-surface-only platform view behind the app-owned tab row:
///
/// - On iOS 26+ the glass is the public `UIGlassEffect(style: .regular)` inside
///   a `UIVisualEffectView`, styled with `overrideUserInterfaceStyle` and
///   `tintColor` from the active theme. The selected effect is nested in the
///   outer effect's contentView, as documented in WWDC25/284 at 21:02.
///   Do not make them siblings in UIGlassContainerEffect: overlapping effects
///   there merge into one shape, losing the distinct selection.
/// - Before iOS 26 it uses a system material `UIBlurEffect`.
/// - The view draws no tabs, icons, or badges, and disables user interaction so
///   every tap lands on the Flutter tab controls above it.
@MainActor
final class NativeGlassSurfaceFactory: NSObject, FlutterPlatformViewFactory {
  private let registrar: FlutterPluginRegistrar

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeGlassSurface(frame: frame, id: viewId, registrar: registrar, arguments: args)
  }
}

@MainActor
private final class NativeGlassSurface: NSObject, FlutterPlatformView {
  private let host: GlassSurfaceHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, id: Int64, registrar: FlutterPluginRegistrar, arguments: Any?) {
    host = GlassSurfaceHost(frame: frame)
    channel = FlutterMethodChannel(
      name: "mithka/native_glass/\(id)", binaryMessenger: registrar.messenger()
    )
    super.init()
    if let configuration = arguments as? [String: Any] { host.apply(configuration) }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "update",
        let configuration = call.arguments as? [String: Any]
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.host.apply(configuration)
      result(nil)
    }
  }

  func view() -> UIView { host }

  deinit { channel.setMethodCallHandler(nil) }
}

@MainActor
final class GlassSurfaceHost: UIView {
  private let effectView = UIVisualEffectView(effect: nil)
  private let selectionView = UIVisualEffectView(effect: nil)
  private var configuration: [String: Any] = [:]
  private var requestedCornerRadius: CGFloat = 0
  private var selection = -1
  private var itemCount = 0
  private var inset: CGFloat = 5
  private var rtl = false
  private var duration: TimeInterval = 0
  private var lastBounds: CGRect = .null
  private var animateSelection = false
  private var selectionAnimator: UIViewPropertyAnimator?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    for view in [effectView, selectionView] {
      view.isUserInteractionEnabled = false
      view.layer.masksToBounds = true
    }
    addSubview(effectView)
    // Public UIKit nested-glass hierarchy, not a second Flutter platform view
    // and not a merging UIGlassContainerEffect of overlapping sibling shapes.
    effectView.contentView.addSubview(selectionView)
    for name in [
      UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
      UIAccessibility.reduceMotionStatusDidChangeNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(accessibilityChanged), name: name, object: nil
      )
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { NotificationCenter.default.removeObserver(self) }

  func apply(_ configuration: [String: Any]) {
    // Resolve any previous pending layout before deciding whether the next move
    // is a selection change (animate) or a geometry change (snap).
    layoutIfNeeded()
    let nextSelection = (configuration["selection"] as? NSNumber)?.intValue ?? -1
    let nextCount = max(0, (configuration["itemCount"] as? NSNumber)?.intValue ?? 0)
    let nextInset = max(0, number(configuration, "selectionInset", fallback: 5))
    let nextRTL = configuration["rtl"] as? Bool == true
    animateSelection = selection >= 0 && nextSelection != selection &&
      nextCount == itemCount && nextInset == inset && nextRTL == rtl
    selection = nextSelection
    itemCount = nextCount
    inset = nextInset
    rtl = nextRTL
    duration = max(0, Double(number(configuration, "durationMs"))) / 1000
    requestedCornerRadius = number(configuration, "radius")
    let appearanceKeys = [
      "dark", "tint", "selectionTint", "opaqueBackground", "opaqueSelection",
      "contrastBorder", "highContrast",
    ]
    let appearanceChanged = appearanceKeys.contains {
      !NSObject.isEqualValue(self.configuration[$0], configuration[$0])
    }
    self.configuration = configuration
    if appearanceChanged { updateEffects() }
    setNeedsLayout()
    layoutIfNeeded()
  }

  private func number(
    _ configuration: [String: Any], _ key: String, fallback: CGFloat = 0
  ) -> CGFloat {
    let value = CGFloat((configuration[key] as? NSNumber)?.doubleValue ?? Double(fallback))
    return value.isFinite ? value : fallback
  }

  private func color(_ key: String, fallback: UIColor) -> UIColor {
    guard let argb = configuration[key] as? NSNumber else { return fallback }
    let value = argb.uint32Value
    return UIColor(
      red: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255,
      alpha: CGFloat((value >> 24) & 255) / 255
    )
  }

  @objc private func accessibilityChanged() {
    updateEffects()
    animateSelection = false
    setNeedsLayout()
    layoutIfNeeded()
  }

  private func updateEffects() {
    let dark = configuration["dark"] as? Bool == true
    overrideUserInterfaceStyle = dark ? .dark : .light
    let opaque = configuration["highContrast"] as? Bool == true ||
      UIAccessibility.isReduceTransparencyEnabled || UIAccessibility.isDarkerSystemColorsEnabled
    for (view, tintKey, opaqueKey) in [
      (effectView, "tint", "opaqueBackground"),
      (selectionView, "selectionTint", "opaqueSelection"),
    ] {
      view.overrideUserInterfaceStyle = overrideUserInterfaceStyle
      view.backgroundColor = opaque ? color(opaqueKey, fallback: .systemBackground) : .clear
      view.contentView.backgroundColor = .clear
      if opaque {
        view.effect = nil
      } else if #available(iOS 26.0, *) {
        // UIVisualEffectView copies effects. Configure a NEW effect before
        // assignment on both layers, including live theme/tint changes.
        let glass = UIGlassEffect(style: .regular)
        glass.tintColor = color(tintKey, fallback: .clear)
        glass.isInteractive = false
        view.effect = glass
      } else {
        view.effect = UIBlurEffect(style: dark ? .systemMaterialDark : .systemMaterialLight)
        if view === selectionView {
          view.contentView.backgroundColor = color("selectionTint", fallback: .clear)
        }
      }
    }
    selectionView.layer.borderWidth = opaque ? 1 : 0
    selectionView.layer.borderColor = color("contrastBorder", fallback: .label).cgColor
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let resized = lastBounds != bounds
    lastBounds = bounds
    effectView.frame = bounds
    // Oversized CALayer radii can suppress glass entirely. Clamp EACH effect
    // to its OWN live bounds, including the narrower selected capsule.
    effectView.layer.cornerRadius = min(
      max(0, requestedCornerRadius), max(0, min(bounds.width, bounds.height) / 2)
    )
    let hasSelection = itemCount > 0 && selection >= 0 && selection < itemCount
    selectionView.isHidden = !hasSelection
    let inner = bounds.insetBy(
      dx: min(inset, max(0, bounds.width / 2)),
      dy: min(inset, max(0, bounds.height / 2))
    )
    let width = hasSelection ? inner.width / CGFloat(itemCount) : 0
    let slot = rtl ? itemCount - 1 - selection : selection
    let target = CGRect(
      x: inner.minX + CGFloat(hasSelection ? slot : 0) * width,
      y: inner.minY, width: width, height: inner.height
    )
    let shouldAnimate = animateSelection && !resized && hasSelection && duration > 0 &&
      !UIAccessibility.isReduceMotionEnabled
    animateSelection = false
    // A dependency-only rebuild must not stop an in-flight move. Geometry,
    // accessibility and duration=0 changes, however, snap to the latest target.
    if shouldAnimate || resized || !hasSelection || duration == 0 ||
      UIAccessibility.isReduceMotionEnabled || selectionView.frame != target {
      stopSelectionAnimation()
      selectionView.layer.cornerRadius = min(
        max(0, requestedCornerRadius), max(0, min(target.width, target.height) / 2)
      )
      if shouldAnimate {
        let timing = UICubicTimingParameters(
          controlPoint1: CGPoint(x: 0.05, y: 0.70),
          controlPoint2: CGPoint(x: 0.10, y: 1.0)
        )
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations { self.selectionView.frame = target }
        selectionAnimator = animator
        animator.startAnimation()
      } else {
        UIView.performWithoutAnimation { self.selectionView.frame = target }
      }
    }
  }

  private func stopSelectionAnimation() {
    if let animator = selectionAnimator, animator.state == .active {
      // Finish at the presentation position, not the previous model target:
      // rapid taps reverse smoothly rather than jumping to the old endpoint.
      animator.stopAnimation(false)
      animator.finishAnimation(at: .current)
    }
    selectionAnimator = nil
  }
}

private extension NSObject {
  static func isEqualValue(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case let (lhs as NSObject, rhs as NSObject): return lhs.isEqual(rhs)
    default: return false
    }
  }
}
