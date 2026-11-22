import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CompliancePrivacy") {
      PrivacyShield.shared.install(registrar.messenger())
    }
  }
}

// Synchronous UIKit covers run before app-switcher snapshots. UIKit cannot
// universally prohibit screenshots; no secure-text-field screenshot workaround.
@MainActor
final class PrivacyShield: NSObject {
  static let shared = PrivacyShield()
  private var channel: FlutterMethodChannel?
  private var covers: [UIView] = []
  private var epoch: Int64 = 0
  private var filesProtected = false
  private var protectedData = true
  private var observing = false
  private var observedWindows = Set<ObjectIdentifier>()
  private var windows: [UIWindow] {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
  }
  private var recorded: Bool {
    windows.contains { window in
      if #available(iOS 17.0, *) { return window.traitCollection.sceneCaptureState == .active }
      return window.screen.isCaptured
    }
  }
  private var active: Bool {
    protectedData && !recorded && windows.contains { $0.windowScene?.activationState == .foregroundActive }
  }
  func install(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.smallbizcompliance/privacy", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
      switch call.method {
      case "configure":
        do { try self.protectCache(); self.observeTraits(); result(self.status()) }
        catch { result(FlutterError(code: "protection_unavailable", message: nil, details: nil)) }
      case "cover": self.conceal(); result(self.status())
      case "reveal":
        let requested = (call.arguments as? [String: Any])?["epoch"] as? NSNumber
        if self.active && requested?.int64Value == self.epoch {
          self.covers.forEach { $0.removeFromSuperview() }; self.covers.removeAll()
        }
        result(self.status())
      case "status": result(self.status())
      default: result(FlutterMethodNotImplemented)
      }
    }
    guard !observing else { return }; observing = true
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(inactive), name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(self, selector: #selector(foreground), name: UIScene.didActivateNotification, object: nil)
    center.addObserver(self, selector: #selector(background), name: UIScene.didEnterBackgroundNotification, object: nil)
    center.addObserver(self, selector: #selector(dataLocked), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    center.addObserver(self, selector: #selector(dataAvailable), name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    center.addObserver(self, selector: #selector(captureChanged), name: UIScreen.capturedDidChangeNotification, object: nil)
  }
  private func observeTraits() {
    if #available(iOS 17.0, *) {
      for window in windows where observedWindows.insert(ObjectIdentifier(window)).inserted {
        window.registerForTraitChanges([UITraitSceneCaptureState.self]) { (_: UIWindow, _: UITraitCollection) in
          PrivacyShield.shared.captureChanged()
        }
      }
    }
  }
  private func conceal() {
    epoch += 1
    for window in windows where !covers.contains(where: { $0.superview === window }) {
      let cover = UIView(frame: window.bounds)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.backgroundColor = .systemBackground
      cover.isAccessibilityElement = true; cover.accessibilityLabel = "화면 보호 중"
      cover.accessibilityViewIsModal = true
      let label = UILabel(); label.text = "화면 보호 중"; label.textColor = .secondaryLabel
      label.translatesAutoresizingMaskIntoConstraints = false; cover.addSubview(label)
      NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: cover.centerXAnchor), label.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
      window.addSubview(cover); covers.append(cover)
    }
  }
  private func emit(_ state: String) { channel?.invokeMethod("visibility", arguments: ["epoch": epoch, "state": state]) }
  @objc private func inactive() { conceal(); emit("inactive") }
  @objc private func background() { conceal(); emit("background") }
  @objc private func foreground() { observeTraits(); epoch += 1; emit(active ? "foreground" : "inactive") }
  @objc private func dataLocked() { protectedData = false; conceal(); emit("locked") }
  @objc private func dataAvailable() { protectedData = true; foreground() }
  @objc private func captureChanged() { if recorded { conceal(); emit("inactive") } else { foreground() } }
  private func protectCache() throws {
    let manager = FileManager.default
    let base = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let cache = base.appendingPathComponent("cache", isDirectory: true)
    try manager.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
    try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cache.path)
    if let items = manager.enumerator(at: cache, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsSubdirectoryDescendants]) {
      for case let item as URL in items {
        if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { continue }
        if [".db", ".db-wal", ".db-shm", ".db-journal"].contains(where: { item.lastPathComponent.hasSuffix($0) }) {
          try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: item.path)
        }
      }
    }
    #if targetEnvironment(simulator)
    // Simulator file attributes do not prove device Data Protection. Keep the
    // capability unavailable; the preview never opens a customer cache.
    filesProtected = false
    #else
    let attributes = try manager.attributesOfItem(atPath: cache.path)
    let protection = attributes[.protectionKey]
    let verified = (protection as? FileProtectionType) == .complete ||
                   (protection as? String) == FileProtectionType.complete.rawValue
    guard verified else {
      throw NSError(domain: "CompliancePrivacy", code: 1)
    }
    filesProtected = true
    #endif
  }
  private func status() -> [String: Any] {
    ["epoch": epoch, "active": active, "cover": true, "capture": false,
     "files": filesProtected, "covered": !covers.isEmpty]
  }
}
