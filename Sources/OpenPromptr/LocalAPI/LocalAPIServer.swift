import CoreGraphics
import Foundation
import OSLog
import OpenPromptrCore
import Swifter

/// Blocks the calling thread until `body` — a synchronous `@MainActor`
/// closure — has run on the main actor, and returns its result.
///
/// Used only for state reads that touch no `await`: the block is bounded to
/// however long it takes to read a handful of `@Published` properties, never
/// to arbitrarily long async work, which is what would make a bridge like
/// this a deadlock risk. Actions that need real work (starting output, etc.)
/// must NOT use this — see `LocalAPIServer`'s route handlers, which dispatch
/// those as fire-and-forget `Task`s instead.
private func runOnMainActorSync<T: Sendable>(_ body: @escaping @MainActor () -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = LocalAPIResultBox<T>()
    Task { @MainActor in
        box.value = body()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value!
}

private final class LocalAPIResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// The local control API from issue #4: a loopback-only HTTP server that
/// lets an external tool (a script, a Stream Deck plugin) start/stop output
/// and read status, since the menu bar isn't reachable from outside the app.
///
/// Deliberately not `@MainActor`: Swifter invokes route/middleware closures
/// on its own background dispatch queue, never on the main actor. A closure
/// written lexically inside a `@MainActor` type inherits that isolation
/// implicitly, and the Swift runtime enforces it dynamically even though the
/// closure's declared type carries no isolation annotation — calling it from
/// Swifter's queue then traps with `EXC_BREAKPOINT` in
/// `dispatch_assert_queue`. Every actual touch of `AppModel`'s `@MainActor`
/// state below goes through an explicit hop (`runOnMainActorSync` for reads,
/// `Task { @MainActor in ... }` for actions) instead.
final class LocalAPIServer {
    private static let logger = Logger(
        subsystem: "com.github.trsdn.OpenPromptr",
        category: "local-api"
    )

    private weak var model: AppModel?
    private var server: HttpServer?
    private var token: String?

    init(model: AppModel) {
        self.model = model
    }

    var isRunning: Bool { server != nil }

    func start() {
        guard server == nil, let model else {
            return
        }

        let token = LocalAPICredentials.generateToken()
        let server = HttpServer()
        server.listenAddressIPv4 = "127.0.0.1"
        installMiddleware(on: server, token: token)
        installRoutes(on: server, model: model)

        do {
            try server.start(0, forceIPv4: true)
            let port = try server.port()
            self.server = server
            self.token = token
            LocalAPICredentials.publish(port: port, token: token)
            Self.logger.info("Local API listening on 127.0.0.1:\(port, privacy: .public).")
        } catch {
            Self.logger.error("Local API failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        token = nil
        LocalAPICredentials.remove()
    }

    // MARK: - Middleware

    private func installMiddleware(on server: HttpServer, token: String) {
        server.middleware.append { request in
            if LocalAPIAuth.isOriginRejected(headers: request.headers) {
                return Self.textResponse(
                    403, "Forbidden", "Requests with an Origin header are not accepted."
                )
            }
            let provided = LocalAPIAuth.bearerToken(
                fromAuthorizationHeader: request.headers["authorization"]
            )
            guard LocalAPIAuth.tokenMatches(provided: provided, expected: token) else {
                return Self.textResponse(401, "Unauthorized", "Missing or invalid bearer token.")
            }
            return nil
        }
    }

    // MARK: - Routes

    private func installRoutes(on server: HttpServer, model: AppModel) {
        server.get["/v1/state"] = { [weak model] _ in
            guard let model else {
                return .internalServerError
            }
            let state = runOnMainActorSync { Self.state(of: model) }
            return Self.jsonResponse(state)
        }

        server.post["/v1/output/start"] = { [weak model] _ in
            guard let model else {
                return .internalServerError
            }
            Task { @MainActor in await model.start() }
            return Self.acceptedResponse()
        }

        server.post["/v1/output/stop"] = { [weak model] _ in
            guard let model else {
                return .internalServerError
            }
            Task { @MainActor in model.requestStop(message: "Stopped via the local API.") }
            return Self.acceptedResponse()
        }

        server.post["/v1/output/toggle"] = { [weak model] _ in
            guard let model else {
                return .internalServerError
            }
            let isRunning = runOnMainActorSync { model.isRunning }
            Task { @MainActor in
                if isRunning {
                    model.requestStop(message: "Stopped via the local API.")
                } else {
                    await model.start()
                }
            }
            return Self.acceptedResponse()
        }

        server.post["/v1/transform"] = { [weak model] request in
            guard let model else {
                return .internalServerError
            }
            guard let patch = Self.decode(TransformPatch.self, from: request.body) else {
                return .badRequest(
                    .text("Body must be a JSON object with optional rotation/mirrorH/mirrorV."))
            }
            Task { @MainActor in
                model.setTransform(patch.apply(to: model.transform))
            }
            return Self.acceptedResponse()
        }

        server.post["/v1/display"] = { [weak model] request in
            guard let model else {
                return .internalServerError
            }
            guard let selection = Self.decode(DisplaySelectionPatch.self, from: request.body) else {
                return .badRequest(.text("Body must be a JSON object with an integer \"id\"."))
            }
            Task { @MainActor in
                model.selectDisplay(CGDirectDisplayID(selection.id))
            }
            return Self.acceptedResponse()
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func state(of model: AppModel) -> LocalAPIState {
        let display = model.displays.first { $0.id == model.selectedDisplayID }
        return LocalAPIState(
            running: model.isRunning,
            busy: model.isBusy,
            status: model.statusText,
            error: model.statusIsError,
            permissionGranted: model.permissionGranted,
            source: model.sourceKind.localizedName,
            display: display.map { LocalAPIDisplay(id: $0.id, name: $0.name) },
            transform: LocalAPITransform(
                rotation: model.transform.rotation.rawValue,
                mirrorH: model.transform.mirrorHorizontally,
                mirrorV: model.transform.mirrorVertically
            )
        )
    }

    private static func jsonResponse(_ state: LocalAPIState) -> HttpResponse {
        guard let data = try? JSONEncoder().encode(state),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return .internalServerError
        }
        return .ok(.json(object))
    }

    private static func acceptedResponse() -> HttpResponse {
        .ok(.json(["ok": true]))
    }

    /// `.unauthorized`/`.forbidden` carry no body in this version of
    /// Swifter, so a response that needs explanatory text for either goes
    /// through `.raw` instead.
    private static func textResponse(_ statusCode: Int, _ reason: String, _ message: String)
        -> HttpResponse
    {
        .raw(statusCode, reason, ["Content-Type": "text/plain; charset=utf-8"]) { writer in
            try writer.write([UInt8](message.utf8))
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from body: [UInt8]) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(body))
    }
}
