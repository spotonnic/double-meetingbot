import Foundation

/// Minimal Supabase Realtime client: one channel, broadcast messages only.
/// Speaks the Phoenix v1 JSON protocol over URLSessionWebSocketTask and reconnects with backoff.
/// All callbacks run on the main queue.
final class RealtimeChannel: NSObject {
    var onBroadcast: ((_ event: String, _ payload: [String: Any]) -> Void)?
    var onJoinedChange: ((Bool) -> Void)?

    private(set) var isJoined = false {
        didSet { if oldValue != isJoined { onJoinedChange?(isJoined) } }
    }

    private let url: URL
    private let topic: String
    private let apiKey: String
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var refCounter = 0
    private var joinRef: String?
    private var pendingHeartbeatRef: String?
    private var heartbeatTimer: Timer?
    private var reconnectWork: DispatchWorkItem?
    private var reconnectDelay: TimeInterval = 1
    private var running = false

    init?(projectURL: String, apiKey: String, room: String) {
        guard var comps = URLComponents(string: projectURL.trimmingCharacters(in: .whitespaces)),
              comps.host != nil else { return nil }
        comps.scheme = "wss"
        comps.path = "/realtime/v1/websocket"
        comps.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = comps.url else { return nil }
        self.url = url
        self.topic = "realtime:\(room)"
        self.apiKey = apiKey
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    func connect() {
        guard !running else { return }
        running = true
        open()
    }

    func disconnect() {
        running = false
        reconnectWork?.cancel()
        teardown()
    }

    /// Fire-and-forget broadcast to everyone else in the room.
    func broadcast(_ event: String, _ payload: [String: Any]) {
        guard isJoined else { return }
        send(event: "broadcast", payload: [
            "type": "broadcast",
            "event": event,
            "payload": payload,
        ])
    }

    // MARK: - Connection

    private func open() {
        teardown()
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive(on: task)
    }

    private func teardown() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        pendingHeartbeatRef = nil
        joinRef = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isJoined = false
    }

    private func scheduleReconnect() {
        teardown()
        guard running else { return }
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.running else { return }
            self.open()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay, execute: work)
        reconnectDelay = min(reconnectDelay * 2, 30)
    }

    private func join() {
        var payload: [String: Any] = [
            "config": [
                "broadcast": ["ack": false, "self": false],
                "presence": ["key": ""],
                "postgres_changes": [] as [Any],
                "private": false,
            ] as [String: Any],
        ]
        // Legacy anon keys are JWTs and double as the access token. New sb_publishable_ keys are not.
        if apiKey.hasPrefix("eyJ") { payload["access_token"] = apiKey }
        let ref = nextRef()
        joinRef = ref
        send(event: "phx_join", payload: payload, ref: ref)
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.pendingHeartbeatRef != nil {
                // Previous heartbeat never answered: the socket is dead even if iOS hasn't noticed.
                self.scheduleReconnect()
                return
            }
            let ref = self.nextRef()
            self.pendingHeartbeatRef = ref
            self.sendRaw(["topic": "phoenix", "event": "heartbeat", "payload": [String: Any](), "ref": ref])
        }
    }

    // MARK: - Messages

    private func nextRef() -> String {
        refCounter += 1
        return String(refCounter)
    }

    private func send(event: String, payload: [String: Any], ref: String? = nil) {
        var message: [String: Any] = [
            "topic": topic,
            "event": event,
            "payload": payload,
            "ref": ref ?? nextRef(),
        ]
        if let joinRef = joinRef { message["join_ref"] = joinRef }
        sendRaw(message)
    }

    private func sendRaw(_ message: [String: Any]) {
        guard let task = task,
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if error != nil {
                DispatchQueue.main.async { if self?.task === task { self?.scheduleReconnect() } }
            }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.task === task else { return }
                switch result {
                case .failure:
                    self.scheduleReconnect()
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text.data(using: .utf8))
                    case .data(let data): self.handle(data)
                    @unknown default: break
                    }
                    self.receive(on: task)
                }
            }
        }
    }

    private func handle(_ data: Data?) {
        guard let data = data,
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = message["event"] as? String else { return }
        let ref = message["ref"] as? String
        let payload = message["payload"] as? [String: Any] ?? [:]

        if event == "phx_reply", let ref = ref {
            if ref == pendingHeartbeatRef {
                pendingHeartbeatRef = nil
            } else if ref == joinRef {
                if payload["status"] as? String == "ok" {
                    isJoined = true
                    reconnectDelay = 1
                } else {
                    NSLog("[realtime] join rejected: \(payload)")
                    scheduleReconnect()
                }
            }
            return
        }

        guard message["topic"] as? String == topic else { return }
        switch event {
        case "broadcast":
            if let name = payload["event"] as? String {
                onBroadcast?(name, payload["payload"] as? [String: Any] ?? [:])
            }
        case "phx_close", "phx_error":
            scheduleReconnect()
        case "system":
            if payload["status"] as? String == "error" { NSLog("[realtime] system error: \(payload)") }
        default:
            break
        }
    }
}

extension RealtimeChannel: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        guard webSocketTask === task else { return }
        join()
        startHeartbeat()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === task else { return }
        scheduleReconnect()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task, error != nil else { return }
        scheduleReconnect()
    }
}
