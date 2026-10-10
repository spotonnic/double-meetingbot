import AVFoundation
import UIKit
import WebKit

/// Full-screen Google Meet in a WKWebView, with the robot driven over a Supabase Realtime channel.
final class MeetViewController: UIViewController {
    private var settings = Settings.load()
    private let robot = DMRobot()
    private var channel: RealtimeChannel?
    private var statusTimer: Timer?
    private var autoJoinTimer: Timer?
    private var autoJoinDeadline = Date.distantPast

    private var webView: WKWebView!
    private let statusPill = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureAudioSession()
        setUpWebView()
        setUpStatusPill()

        robot.delegate = self
        robot.start()
        connectChannel()
        loadMeet(settings.meetURL)

        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.publishStatus()
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appWillResignActive),
                           name: UIApplication.willResignActiveNotification, object: nil)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    @objc private func appWillResignActive() {
        robot.stop()
    }

    // MARK: - Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .videoChat,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }

    private func setUpWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Present as desktop Safari; Google rejects unknown embedded browsers.
        config.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        config.defaultWebpagePreferences.preferredContentMode = .desktop

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)
    }

    private func setUpStatusPill() {
        statusPill.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        statusPill.textColor = .white
        statusPill.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusPill.layer.cornerRadius = 12
        statusPill.layer.masksToBounds = true
        statusPill.textAlignment = .center
        statusPill.isUserInteractionEnabled = true
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusPill)
        NSLayoutConstraint.activate([
            statusPill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            statusPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            statusPill.heightAnchor.constraint(equalToConstant: 26),
        ])
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(showSettings(_:)))
        hold.minimumPressDuration = 2
        statusPill.addGestureRecognizer(hold)
        updateStatusPill()
    }

    private func connectChannel() {
        channel?.disconnect()
        channel = nil
        guard settings.isRealtimeConfigured,
              let channel = RealtimeChannel(projectURL: settings.supabaseURL,
                                            apiKey: settings.supabaseKey,
                                            room: settings.room) else {
            updateStatusPill()
            return
        }
        channel.onBroadcast = { [weak self] event, payload in self?.handle(event: event, payload: payload) }
        channel.onJoinedChange = { [weak self] joined in
            if !joined { self?.robot.stop() }
            self?.updateStatusPill()
            self?.publishStatus()
        }
        self.channel = channel
        channel.connect()
    }

    // MARK: - Remote commands

    private func handle(event: String, payload: [String: Any]) {
        switch event {
        case "drive":
            let drive = (payload["d"] as? NSNumber)?.floatValue ?? 0
            let turn = (payload["t"] as? NSNumber)?.floatValue ?? 0
            let pole = (payload["p"] as? NSNumber)?.intValue ?? 0
            robot.setDrive(drive, turn: turn)
            robot.setPole(pole)
        case "stop":
            robot.stop()
        case "park":
            robot.park()
        case "unpark":
            robot.unpark()
        case "meet":
            if let url = payload["url"] as? String {
                settings.meetURL = url
                settings.save()
                loadMeet(url)
            }
        case "join":
            startAutoJoin()
        case "reload":
            webView.reload()
        case "ping":
            publishStatus()
        default:
            break
        }
    }

    private func publishStatus() {
        guard let channel = channel, channel.isJoined else { return }
        var status: [String: Any] = [
            "robot": robot.connected,
            "battery": robot.batteryPercent,
            "charging": robot.batteryIsCharging,
            "pole": robot.poleHeightPercent,
            "kickstand": robot.kickstand.rawValue,
            "meet": webView.url?.absoluteString ?? "",
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if let firmware = robot.firmwareVersion { status["firmware"] = firmware }
        channel.broadcast("status", status)
    }

    private func updateStatusPill() {
        let base = robot.connected ? "Bas ✓ \(Int(batteryPercentForDisplay))%" : "Bas –"
        let link: String
        if !settings.isRealtimeConfigured {
            link = "Styrning: ej konfigurerad"
        } else {
            link = (channel?.isJoined ?? false) ? "Styrning ✓" : "Styrning …"
        }
        statusPill.text = "  \(base)  ·  \(link)  "
    }

    private var batteryPercentForDisplay: Float {
        let value = robot.batteryPercent
        return value <= 1 ? value * 100 : value
    }

    // MARK: - Meet

    private func loadMeet(_ string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" else { return }
        webView.load(URLRequest(url: url))
    }

    /// Best effort: fill in the guest name and press "Join now" / "Ask to join" for up to 60 s.
    private func startAutoJoin() {
        autoJoinDeadline = Date().addingTimeInterval(60)
        autoJoinTimer?.invalidate()
        autoJoinTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if Date() > self.autoJoinDeadline { timer.invalidate(); return }
            self.webView.evaluateJavaScript(Self.autoJoinScript(name: self.settings.guestName)) { result, _ in
                if (result as? String) == "clicked" { timer.invalidate() }
            }
        }
    }

    private static func autoJoinScript(name: String) -> String {
        let nameJSON = (try? JSONSerialization.data(withJSONObject: [name]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"Double\"]"
        return """
        (function () {
          var name = \(nameJSON)[0];
          var input = document.querySelector('input[type="text"][aria-label], input[type="text"][placeholder]');
          if (input && !input.value) {
            var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            setter.call(input, name);
            input.dispatchEvent(new Event('input', { bubbles: true }));
          }
          var labels = /^(join now|ask to join|delta nu|gå med nu|be om att få delta|be om att få gå med|anslut nu)$/i;
          var buttons = document.querySelectorAll('button, [role="button"]');
          for (var i = 0; i < buttons.length; i++) {
            var text = (buttons[i].innerText || '').trim();
            if (labels.test(text) && !buttons[i].disabled) { buttons[i].click(); return 'clicked'; }
          }
          return 'waiting';
        })();
        """
    }

    // MARK: - Settings

    @objc private func showSettings(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Inställningar", message: nil, preferredStyle: .alert)
        let fields: [(String, String)] = [
            ("Supabase URL", settings.supabaseURL),
            ("Supabase-nyckel", settings.supabaseKey),
            ("Rum (hemlig sträng)", settings.room),
            ("Meet-länk", settings.meetURL),
            ("Gästnamn", settings.guestName),
        ]
        for (placeholder, value) in fields {
            alert.addTextField { field in
                field.placeholder = placeholder
                field.text = value
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
                field.clearButtonMode = .whileEditing
            }
        }
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
        alert.addAction(UIAlertAction(title: "Spara", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let values = alert?.textFields?.map({ $0.text ?? "" }), values.count == 5 else { return }
            let meetChanged = values[3] != self.settings.meetURL
            self.settings.supabaseURL = values[0].trimmingCharacters(in: .whitespaces)
            self.settings.supabaseKey = values[1].trimmingCharacters(in: .whitespaces)
            self.settings.room = values[2].trimmingCharacters(in: .whitespaces)
            self.settings.meetURL = values[3].trimmingCharacters(in: .whitespaces)
            self.settings.guestName = values[4]
            self.settings.save()
            self.connectChannel()
            if meetChanged { self.loadMeet(self.settings.meetURL) }
        })
        alert.addAction(UIAlertAction(title: "Ladda om Meet", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.loadMeet(self.settings.meetURL)
        })
        present(alert, animated: true)
    }
}

// MARK: - DMRobotDelegate

extension MeetViewController: DMRobotDelegate {
    func robotDidChange() {
        updateStatusPill()
    }
}

// MARK: - WKUIDelegate / WKNavigationDelegate

extension MeetViewController: WKUIDelegate, WKNavigationDelegate {
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let host = origin.host
        decisionHandler(host == "meet.google.com" || host.hasSuffix(".google.com") ? .grant : .deny)
    }

    // Links that want a new window open in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.host == "meet.google.com", webView.url?.path.count ?? 0 > 1 {
            startAutoJoin()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
