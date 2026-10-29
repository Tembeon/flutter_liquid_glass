import Accessibility
import Flutter
import UIKit

public class AppleLiquidGlassAccessibilityPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "apple_liquid_glass_accessibility",
      binaryMessenger: registrar.messenger())
    channel.setStreamHandler(AppleLiquidGlassAccessibilityPlugin())
  }

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    var names = [
      UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      UIAccessibility.prefersCrossFadeTransitionsStatusDidChange,
    ]
    if #available(iOS 26.1, *) {
      names.append(AccessibilitySettings.showBordersEnabledStatusDidChangeNotification)
    } else {
      names.append(UIAccessibility.buttonShapesEnabledStatusDidChangeNotification)
    }
    observers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in self?.report()
      }
    }
    report()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    sink = nil
    return nil
  }

  private func report() {
    let showBorders: Bool
    if #available(iOS 26.1, *) {
      showBorders = AccessibilitySettings.showBordersEnabled
    } else {
      showBorders = UIAccessibility.buttonShapesEnabled
    }
    sink?([
      "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
      "showBorders": showBorders,
      "prefersCrossFade": UIAccessibility.prefersCrossFadeTransitions,
    ])
  }
}
