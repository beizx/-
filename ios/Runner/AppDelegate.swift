import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var readerChannel: FlutterMethodChannel?
  private var filesChannel: FlutterMethodChannel?
  private var pendingImport: [String: String]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReaderSystem") {
      let channel = FlutterMethodChannel(
        name: "com.yiyue.translation_app/reader",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "keepScreenOn":
          UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
          result(nil)
        case "openBackgroundSettings":
          guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
          }
          UIApplication.shared.open(url, options: [:]) { opened in
            result(opened)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      readerChannel = channel
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ExternalFiles") {
      let channel = FlutterMethodChannel(
        name: "com.yiyue.translation_app/files",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(nil)
          return
        }
        switch call.method {
        case "takePendingFile":
          let pending = self.pendingImport
          self.pendingImport = nil
          result(pending)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      filesChannel = channel
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if handleIncomingFile(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  @discardableResult
  func handleIncomingFile(_ url: URL) -> Bool {
    guard let payload = copyToCache(url) else { return false }
    pendingImport = payload
    filesChannel?.invokeMethod("onFileOpened", arguments: payload)
    return true
  }

  /// Copies the document iOS handed us into the app cache so Dart can read it
  /// with ordinary file APIs (Files / QQ "用其他应用打开" both arrive as URLs).
  private func copyToCache(_ url: URL) -> [String: String]? {
    let name = url.lastPathComponent
    let ext = url.pathExtension.lowercased()
    guard ext == "txt" || ext == "epub" else { return nil }

    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }

    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory.appendingPathComponent("external_import")
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")

    do {
      if fileManager.fileExists(atPath: target.path) {
        try fileManager.removeItem(at: target)
      }
      try fileManager.copyItem(at: url, to: target)
      return ["path": target.path, "name": name]
    } catch {
      return nil
    }
  }
}
