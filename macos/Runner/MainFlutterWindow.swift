import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import Darwin

class MainFlutterWindow: NSWindow {
  private var privacyShield: DesktopPrivacyShield?
  private var documentInput: DesktopDocumentInput?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    privacyShield = DesktopPrivacyShield(window: self, messenger: flutterViewController.engine.binaryMessenger)
    documentInput = DesktopDocumentInput(window: self, messenger: flutterViewController.engine.binaryMessenger)
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }
}

extension MainFlutterWindow: NSDraggingDestination {
  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    documentInput?.accepts(sender.draggingPasteboard) == true ? .copy : []
  }
  func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    documentInput?.accepts(sender.draggingPasteboard) == true
  }
  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    documentInput?.drop(sender.draggingPasteboard) == true
  }
}

private enum DocumentReadFailure: String, Error { case io, tooLarge, unsupported, metadata, open, read }

// Read-only local URL capabilities. No promised-file receiver, bookmark storage,
// thumbnails, downloaded URLs, document copies, or temporary output files.
@MainActor
private final class DesktopDocumentInput {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var enabled = false
  private var token: String?
  private var url: URL?
  private var expiry: Timer?
  private var reading = false
  private var panel: NSOpenPanel?
  private var lastReadStage = "none"
  private static let extensions = Set(["png", "jpg", "jpeg", "heic", "heif", "pdf"])
  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "com.smallbizcompliance/input", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
      switch call.method {
      case "enable":
        self.enabled = call.arguments as? Bool ?? false
        if !self.enabled { self.clear(); self.panel?.cancel(nil) }
        result(nil)
      case "pick": self.pick(result)
      case "read": self.read(call.arguments as? String, result)
      case "release":
        if call.arguments as? String == self.token { self.clear() }
        result(nil)
      case "status": result(["pending": self.token == nil ? 0 : 1, "enabled": self.enabled, "readStage": self.lastReadStage])
      #if DEBUG
      case "stageTestFile":
        // Only selects an existing test source. It does not grant sandbox access,
        // create a fixture, or bypass the active-window/read authorization checks.
        guard self.enabled, let path = call.arguments as? String else {
          result(FlutterError(code: "inactive", message: nil, details: nil)); return
        }
        result(self.stage(URL(fileURLWithPath: path)))
      case "stageTestDrop":
        guard self.enabled, let path = call.arguments as? String else {
          result(FlutterError(code: "inactive", message: nil, details: nil)); return
        }
        let board = NSPasteboard.withUniqueName()
        board.writeObjects([URL(fileURLWithPath: path) as NSURL])
        let accepted = self.drop(board)
        board.clearContents()
        if accepted { result(self.token) } else { result(FlutterError(code: "unsupported", message: nil, details: nil)) }
      #endif
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func localURLs(_ pasteboard: NSPasteboard) -> [URL] {
    guard pasteboard.types?.contains(.fileURL) == true else { return [] }
    return (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
  }
  func accepts(_ pasteboard: NSPasteboard) -> Bool {
    let urls = localURLs(pasteboard)
    return enabled && urls.count == 1 && urls[0].isFileURL && Self.extensions.contains(urls[0].pathExtension.lowercased())
  }
  func drop(_ pasteboard: NSPasteboard) -> Bool {
    guard accepts(pasteboard), let source = localURLs(pasteboard).first, let selected = stage(source) else { return false }
    window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    channel.invokeMethod("drop", arguments: selected)
    return true
  }
  private func stage(_ source: URL) -> String? {
    guard enabled, source.isFileURL, source.host == nil || source.host == "localhost",
          Self.extensions.contains(source.pathExtension.lowercased()) else { return nil }
    clear()
    let selected = UUID().uuidString
    token = selected; url = source
    expiry = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.clear() }
    }
    return selected
  }
  private func clear() { expiry?.invalidate(); expiry = nil; token = nil; url = nil; reading = false }
  private func pick(_ result: @escaping FlutterResult) {
    guard enabled, panel == nil, let window else { result(FlutterError(code: "inactive", message: nil, details: nil)); return }
    let picker = NSOpenPanel(); panel = picker
    picker.canChooseFiles = true; picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
    picker.resolvesAliases = false
    picker.allowedContentTypes = [.png, .jpeg, .heic, .pdf]
    picker.beginSheetModal(for: window) { [weak self] response in
      guard let self else { result(nil); return }
      self.panel = nil
      if response == .OK, let source = picker.url { result(self.stage(source)) } else { result(nil) }
    }
  }
  private func read(_ requested: String?, _ result: @escaping FlutterResult) {
    guard enabled, NSApp.isActive, window?.isKeyWindow == true else {
      result(FlutterError(code: "inactive", message: nil, details: nil)); return
    }
    guard let requested, requested == token, let source = url, !reading else {
      result(FlutterError(code: "expired", message: nil, details: nil)); return
    }
    reading = true
    // Disk I/O must not delay synchronous privacy covers on the UI thread.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let outcome: Result<Data, DocumentReadFailure>
      do { outcome = .success(try DesktopDocumentInput.readLocal(source)) }
      catch let error as DocumentReadFailure { outcome = .failure(error) }
      catch { outcome = .failure(.io) }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.enabled, self.token == requested else {
          result(FlutterError(code: "expired", message: nil, details: nil)); return
        }
        switch outcome {
        case .success(var bytes):
          self.lastReadStage = "complete"
          result(FlutterStandardTypedData(bytes: bytes))
          bytes.resetBytes(in: 0..<bytes.count)
        case .failure(let error):
          self.lastReadStage = error.rawValue
          result(FlutterError(code: error == .tooLarge ? "too_large" : error == .unsupported ? "unsupported" : "io", message: nil, details: nil))
        }
      }
    }
  }
  nonisolated private static func readLocal(_ source: URL) throws -> Data {
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    let properties: URLResourceValues
    do { properties = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .volumeIsLocalKey, .isUbiquitousItemKey]) }
    catch { throw DocumentReadFailure.metadata }
    guard properties.isRegularFile == true, properties.isSymbolicLink != true,
          properties.volumeIsLocal == true, properties.isUbiquitousItem != true else { throw DocumentReadFailure.unsupported }
    let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { throw DocumentReadFailure.open }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? file.close() }
    var info = stat()
    guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw DocumentReadFailure.unsupported }
    let maximum = 20 * 1024 * 1024
    guard info.st_size > 0, info.st_size <= maximum else { throw DocumentReadFailure.tooLarge }
    var bytes: Data
    do { bytes = try file.read(upToCount: maximum + 1) ?? Data() }
    catch { throw DocumentReadFailure.read }
    guard bytes.count <= maximum else { bytes.resetBytes(in: 0..<bytes.count); throw DocumentReadFailure.tooLarge }
    return bytes
  }
}

// The native cover remains until Dart acknowledges a rendered safe frame.
// macOS sharingType is not advertised as a universal screenshot blocker.
@MainActor
final class DesktopPrivacyShield: NSObject {
  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel
  private var cover: NSView?
  private var epoch: Int64 = 0
  private var sessionActive = true
  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "com.smallbizcompliance/privacy", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
      switch call.method {
      case "configure", "status": result(self.status())
      case "cover": self.conceal(); result(self.status())
      case "reveal":
        let requested = (call.arguments as? [String: Any])?["epoch"] as? NSNumber
        if self.active && requested?.int64Value == self.epoch { self.cover?.removeFromSuperview(); self.cover = nil }
        result(self.status())
      #if DEBUG
      case "activateTestWindow":
        // Integration runner focus only: real AppKit activation, never an auth
        // result/visibility override. Excluded from profile/release builds.
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        result(self.status())
      #endif
      default: result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(inactive), name: NSWindow.didResignKeyNotification, object: window)
    center.addObserver(self, selector: #selector(foreground), name: NSWindow.didBecomeKeyNotification, object: window)
    center.addObserver(self, selector: #selector(inactive), name: NSApplication.willResignActiveNotification, object: nil)
    center.addObserver(self, selector: #selector(foreground), name: NSApplication.didBecomeActiveNotification, object: nil)
    let workspace = NSWorkspace.shared.notificationCenter
    workspace.addObserver(self, selector: #selector(sessionLocked), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    workspace.addObserver(self, selector: #selector(sessionLocked), name: NSWorkspace.screensDidSleepNotification, object: nil)
    workspace.addObserver(self, selector: #selector(sessionUnlocked), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    workspace.addObserver(self, selector: #selector(sessionUnlocked), name: NSWorkspace.screensDidWakeNotification, object: nil)
  }
  private var active: Bool { sessionActive && NSApp.isActive && window?.isKeyWindow == true }
  private func conceal() {
    epoch += 1
    guard cover == nil, let content = window?.contentView else { return }
    let view = NSView(frame: content.bounds)
    view.autoresizingMask = [.width, .height]; view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let label = NSTextField(labelWithString: "화면 보호 중")
    label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
    NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    content.addSubview(view, positioned: .above, relativeTo: nil); cover = view
  }
  private func emit(_ state: String) { channel.invokeMethod("visibility", arguments: ["epoch": epoch, "state": state]) }
  @objc private func inactive() { conceal(); emit("inactive") }
  @objc private func foreground() { epoch += 1; emit(active ? "foreground" : "inactive") }
  @objc private func sessionLocked() { sessionActive = false; conceal(); emit("locked") }
  @objc private func sessionUnlocked() { sessionActive = true; foreground() }
  private func status() -> [String: Any] {
    ["epoch": epoch, "active": active, "cover": true, "capture": false, "files": false, "covered": cover != nil]
  }
}
