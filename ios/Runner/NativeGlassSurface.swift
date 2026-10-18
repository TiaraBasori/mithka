import Flutter
import UIKit

/// A glass-surface-only platform view behind the app-owned tab row:
///
/// - On iOS 26+ the glass is the public `UIGlassEffect(style: .regular)` inside
///   a `UIVisualEffectView`, carrying the theme's veil colour as its tint and
///   styled with `overrideUserInterfaceStyle`.
/// - Before iOS 26 it uses a system material `UIBlurEffect` with the same veil
///   over it, because a `UIBlurEffect` takes no tint of its own.
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
private final class GlassSurfaceHost: UIView {
  private let effectView = UIVisualEffectView(effect: nil)

  /// Carries the veil over the material on iOS versions whose material cannot
  /// be tinted itself. Hidden while the iOS 26 glass is installed, which takes
  /// the same colour through `UIGlassEffect.tintColor`.
  private let veilView = UIView()

  /// The last configuration, kept for `tintColorDidChange`: the effect view
  /// reads its inherited tint when the material is resolved, so a tint that
  /// arrives later has to re-resolve it.
  private var appliedConfiguration: [String: Any] = [:]

  /// The blur style currently installed, so repeated `update` calls do not
  /// re-install the same effect.
  private var appliedBlurStyle: UIBlurEffect.Style?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    effectView.isUserInteractionEnabled = false
    effectView.layer.masksToBounds = true
    addSubview(effectView)
    veilView.isUserInteractionEnabled = false
    veilView.isHidden = true
    effectView.contentView.addSubview(veilView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(_ configuration: [String: Any]) {
    self.appliedConfiguration = configuration
    let dark = configuration["dark"] as? Bool == true
    overrideUserInterfaceStyle = dark ? .dark : .light
    effectView.overrideUserInterfaceStyle = dark ? .dark : .light
    let cornerRadius = (configuration["radius"] as? NSNumber)?.doubleValue ?? 0
    effectView.layer.cornerRadius = cornerRadius
    let tint = Self.tint(from: configuration)

    if #available(iOS 26.0, *) {
      veilView.isHidden = true
      if let current = effectView.effect as? UIGlassEffect {
        if current.tintColor != tint { installGlass(tint: tint) }
      } else {
        installGlass(tint: tint)
      }
      appliedBlurStyle = nil
    } else {
      let desiredStyle: UIBlurEffect.Style = dark ? .systemMaterialDark : .systemMaterialLight
      if appliedBlurStyle != desiredStyle {
        appliedBlurStyle = desiredStyle
        effectView.effect = UIBlurEffect(style: desiredStyle)
      }
      veilView.backgroundColor = tint
      veilView.isHidden = false
    }
  }

  /// Builds a fresh `UIGlassEffect` with [tint] and installs it. The effect
  /// resolves its tint when the material is built, so a theme change has to
  /// arrive as a new effect rather than a mutation of the installed one.
  private func installGlass(tint: UIColor?) {
    let glass = UIGlassEffect(style: .regular)
    glass.isInteractive = false
    glass.tintColor = tint
    effectView.effect = glass
  }

  private static func tint(from configuration: [String: Any]) -> UIColor? {
    guard let argb = configuration["tint"] as? NSNumber else { return nil }
    let value = argb.uint32Value
    return UIColor(
      red: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255,
      alpha: CGFloat((value >> 24) & 255) / 255
    )
  }

  override func tintColorDidChange() {
    super.tintColorDidChange()
    guard !appliedConfiguration.isEmpty else { return }
    if #available(iOS 26.0, *), effectView.effect is UIGlassEffect {
      installGlass(tint: Self.tint(from: appliedConfiguration))
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    effectView.frame = bounds
    veilView.frame = effectView.bounds
  }
}
