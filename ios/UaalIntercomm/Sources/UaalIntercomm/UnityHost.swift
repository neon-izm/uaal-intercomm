import Darwin
import Foundation
import MachO
import UIKit
import UnityFramework

public enum PrefabId: String, Sendable {
    case carA
    case carB
    case carC
}

public enum UnityHostError: Error, CustomStringConvertible, Sendable {
    case missingFramework
    case timedOut(String)
    case bridge(op: String, message: String)
    case unexpected(String)

    public var description: String {
        switch self {
        case .missingFramework:
            return "UnityFramework がアプリに入っていません"
        case .timedOut(let event):
            return "\(event) が時間内に返りませんでした"
        case .bridge(let op, let message):
            return "\(op): \(message)"
        case .unexpected(let message):
            return message
        }
    }
}

@_silgen_name("UaalSetBridgeEventHandler")
private func UaalSetBridgeEventHandler(
    _ handler: @convention(c) (UnsafePointer<CChar>?) -> Void
)

private func uaalBridgeEvent(_ json: UnsafePointer<CChar>?) {
    let text = json.map { String(cString: $0) } ?? ""
    let deliver = {
        MainActor.assumeIsolated {
            UnityHost.shared.handle(text)
        }
    }
    if Thread.isMainThread {
        deliver()
    } else {
        DispatchQueue.main.sync(execute: deliver)
    }
}

@MainActor
public final class UnityHost {
    public static let shared = UnityHost()

    public var rootView: UIView? {
        framework?.appController()?.rootView
    }

    private weak var attachedHost: UIView?
    private let parking = UIView(frame: .zero)
    private var concealed = false
    private var framework: UnityFramework?
    private var embedded = false
    private var ready = false
    private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    private var initializeTask: Task<Void, Error>?
    private var waiter: Waiter?
    private var errorSink: ((String) -> Void)?
    private var errorSinkOp: String?

    private init() {}

    public func initialize() async throws {
        if ready { return }
        if let initializeTask {
            try await initializeTask.value
            return
        }
        let task = Task { try await self.boot() }
        initializeTask = task
        do {
            try await task.value
        } catch {
            initializeTask = nil
            throw error
        }
    }

    public func load() async throws {
        try await command(event: "loaded", json: "{\"op\":\"load\"}", timeout: 60)
    }

    public func loadPrefab(_ id: PrefabId) async throws {
        let event = try await command(
            event: "prefabLoaded",
            json: "{\"op\":\"loadPrefab\",\"id\":\"\(id.rawValue)\"}",
            timeout: 120
        )
        guard event.id == id.rawValue else {
            throw UnityHostError.unexpected("prefab id が \(event.id ?? "空") でした")
        }
    }

    public func setColor(r: Float, g: Float, b: Float) throws {
        try sendExpectingNoError(
            op: "setColor",
            json: "{\"op\":\"setColor\",\"r\":\(number(r)),\"g\":\(number(g)),\"b\":\(number(b))}"
        )
    }

    public func setCamera(_ index: Int) throws {
        try sendExpectingNoError(op: "setCamera", json: "{\"op\":\"setCamera\",\"index\":\(index)}")
    }

    public nonisolated func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        let options = LaunchOptionsBox(value: launchOptions)
        MainActor.assumeIsolated {
            self.launchOptions = options.value
            if self.initializeTask == nil && !self.ready {
                self.initializeTask = Task { try await self.boot() }
            }
        }
    }

    public nonisolated func applicationWillResignActive(_ application: UIApplication) {
        MainActor.assumeIsolated {
            self.framework?.appController()?.applicationWillResignActive(application)
        }
    }

    public nonisolated func applicationDidEnterBackground(_ application: UIApplication) {
        MainActor.assumeIsolated {
            self.framework?.appController()?.applicationDidEnterBackground(application)
        }
    }

    public nonisolated func applicationWillEnterForeground(_ application: UIApplication) {
        MainActor.assumeIsolated {
            self.framework?.appController()?.applicationWillEnterForeground(application)
        }
    }

    public nonisolated func applicationDidBecomeActive(_ application: UIApplication) {
        MainActor.assumeIsolated {
            self.framework?.appController()?.applicationDidBecomeActive(application)
            self.syncSurface()
        }
    }

    public nonisolated func applicationWillTerminate(_ application: UIApplication) {
        MainActor.assumeIsolated {
            self.framework?.appController()?.applicationWillTerminate(application)
        }
    }

    public func keepOffscreen() {
        attachedHost = nil
        if let root = rootView, root.superview !== parking {
            root.removeFromSuperview()
            parking.addSubview(root)
        }
        hideUnityWindow()
        makeAppWindowKey()
        guard !concealed else { return }
        concealed = true
        framework?.pause(true)
    }

    func isAttached(to host: UIView) -> Bool {
        attachedHost === host
    }

    func attach(to host: UIView) {
        attachedHost = host
        if concealed {
            concealed = false
            framework?.pause(false)
        }
        guard let root = rootView else { return }
        if root.superview !== host {
            root.removeFromSuperview()
            host.addSubview(root)
        }
        root.frame = host.bounds
        root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hideUnityWindow()
        guard let window = host.window, !window.isKeyWindow else { return }
        window.makeKeyAndVisible()
    }

    func handle(_ json: String) {
        guard let event = BridgeEvent.parse(json) else { return }
        if event.event == "ready" {
            ready = true
        }
        if event.event == "error" {
            if let errorSink, event.op == errorSinkOp {
                errorSink(event.message ?? "error")
            }
            if let waiter, waiter.event == Self.eventName(forOp: event.op) {
                finish(
                    waiter,
                    throwing: UnityHostError.bridge(
                        op: event.op ?? waiter.event,
                        message: event.message ?? "error"
                    )
                )
            }
            return
        }
        if let waiter, waiter.event == event.event {
            finish(waiter, returning: event)
        }
        if event.event == "ready" {
            syncSurface()
        }
    }

    private func boot() async throws {
        if ready { return }
        UaalSetBridgeEventHandler(uaalBridgeEvent)
        let ufw = try openFramework()
        framework = ufw
        if !embedded {
            if ufw.appController() == nil {
                ufw.setExecuteHeader(try frameworkHeader())
            }
            "com.unity3d.framework".withCString { ufw.setDataBundleId($0) }
            embedded = true
            let options = launchOptions
            try await wait(for: "ready", timeout: 90) {
                ufw.runEmbedded(
                    withArgc: CommandLine.argc,
                    argv: CommandLine.unsafeArgv,
                    appLaunchOpts: options
                )
                self.syncSurface()
            }
        } else if !ready {
            try await wait(for: "ready", timeout: 90) {}
        }
        ready = true
        syncSurface()
    }

    private func syncSurface() {
        if let host = attachedHost {
            attach(to: host)
            return
        }
        hideUnityWindow()
        makeAppWindowKey()
    }

    private func hideUnityWindow() {
        framework?.appController()?.window?.isHidden = true
    }

    private func makeAppWindowKey() {
        let unityWindow = framework?.appController()?.window
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows where window !== unityWindow {
                window.makeKeyAndVisible()
                return
            }
        }
    }

    private func command(event: String, json: String, timeout: TimeInterval) async throws -> BridgeEvent {
        if !ready {
            throw UnityHostError.bridge(op: event, message: "not ready")
        }
        return try await wait(for: event, timeout: timeout) {
            self.send(json)
        }
    }

    private func sendExpectingNoError(op: String, json: String) throws {
        if !ready {
            throw UnityHostError.bridge(op: op, message: "not ready")
        }
        var failure: UnityHostError?
        errorSinkOp = op
        errorSink = { message in
            failure = .bridge(op: op, message: message)
        }
        defer {
            errorSink = nil
            errorSinkOp = nil
        }
        send(json)
        if let failure {
            throw failure
        }
    }

    private func send(_ json: String) {
        guard let ufw = framework else { return }
        "Bridge".withCString { name in
            "OnCommand".withCString { method in
                json.withCString { message in
                    ufw.sendMessageToGO(withName: name, functionName: method, message: message)
                }
            }
        }
    }

    private func wait(
        for event: String,
        timeout: TimeInterval,
        start: () -> Void
    ) async throws -> BridgeEvent {
        try await withCheckedThrowingContinuation { continuation in
            let waiter = Waiter(event: event, continuation: continuation)
            self.waiter = waiter
            start()
            if waiter.finished { return }
            let item = DispatchWorkItem { [weak waiter] in
                guard let waiter else { return }
                MainActor.assumeIsolated {
                    self.expire(waiter)
                }
            }
            waiter.timeout = item
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
        }
    }

    private func finish(_ waiter: Waiter, returning event: BridgeEvent) {
        guard !waiter.finished else { return }
        waiter.finished = true
        waiter.timeout?.cancel()
        if self.waiter === waiter {
            self.waiter = nil
        }
        waiter.continuation.resume(returning: event)
    }

    private func finish(_ waiter: Waiter, throwing error: Error) {
        guard !waiter.finished else { return }
        waiter.finished = true
        waiter.timeout?.cancel()
        if self.waiter === waiter {
            self.waiter = nil
        }
        waiter.continuation.resume(throwing: error)
    }

    private func expire(_ waiter: Waiter) {
        finish(waiter, throwing: UnityHostError.timedOut(waiter.event))
    }

    private func openFramework() throws -> UnityFramework {
        if let framework {
            return framework
        }
        let embedded = Bundle.main.bundleURL.appendingPathComponent("Frameworks/UnityFramework.framework")
        if let bundle = Bundle(url: embedded), !bundle.isLoaded {
            try bundle.loadAndReturnError()
        }
        guard let instance = UnityFramework.getInstance() else {
            throw UnityHostError.missingFramework
        }
        return instance
    }

    private func frameworkHeader() throws -> UnsafePointer<MachHeader> {
        let count = _dyld_image_count()
        for index in 0..<count {
            guard let name = _dyld_get_image_name(index),
                  String(cString: name).contains("UnityFramework.framework/UnityFramework"),
                  let header = _dyld_get_image_header(index)
            else { continue }
            return UnsafePointer(UnsafeRawPointer(header).assumingMemoryBound(to: MachHeader.self))
        }
        throw UnityHostError.missingFramework
    }

    private static func eventName(forOp op: String?) -> String? {
        switch op {
        case "load":
            return "loaded"
        case "loadPrefab":
            return "prefabLoaded"
        default:
            return nil
        }
    }

    private func number(_ value: Float) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }
}

private struct LaunchOptionsBox: @unchecked Sendable {
    let value: [UIApplication.LaunchOptionsKey: Any]?
}

private final class Waiter: @unchecked Sendable {
    let event: String
    let continuation: CheckedContinuation<BridgeEvent, Error>
    var finished = false
    var timeout: DispatchWorkItem?

    init(event: String, continuation: CheckedContinuation<BridgeEvent, Error>) {
        self.event = event
        self.continuation = continuation
    }
}

private struct BridgeEvent: Sendable {
    let event: String
    let id: String?
    let op: String?
    let message: String?

    static func parse(_ json: String) -> BridgeEvent? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String
        else { return nil }
        return BridgeEvent(
            event: event,
            id: object["id"] as? String,
            op: object["op"] as? String,
            message: object["message"] as? String
        )
    }
}
