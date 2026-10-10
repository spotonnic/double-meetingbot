import AVFoundation
import UIKit
import WebKit

/// Full-screen Google Meet in a WKWebView, with the robot driven over a Supabase Realtime channel.
/// Outside meetings the robot shows a branded idle screen instead of Meet.
final class MeetViewController: UIViewController {
    private var settings = Settings.load()
    private let robot = DMRobot()
    private var auth: AuthSession?
    private var channel: RealtimeChannel?
    private var authError: String?
    private var statusTimer: Timer?
    private var autoJoinTimer: Timer?
    private var autoJoinDeadline = Date.distantPast

    // Who is driving. One driver at a time; the seat frees up after 10 s without commands.
    private static let driverTimeout: TimeInterval = 10
    private var driver: String?
    private var driverSince = Date.distantPast
    private var driverLastSeen = Date.distantPast
    private var lastUser = UserDefaults.standard.string(forKey: "usage.lastUser")
    private var lastUsedAt = UserDefaults.standard.object(forKey: "usage.lastUsedAt") as? Date

    private var webView: WKWebView!
    private let statusPill = UILabel()
    private let idleView = IdleView()
    private let doneButton = BrandButton(title: "Klar", style: .primary)
    private var isSigningIn = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Brand.navy
        configureAudioSession()
        setUpWebView()
        setUpIdleView()
        setUpStatusPill()
        setUpDoneButton()

        robot.delegate = self
        robot.start()
        connectChannel()
        if settings.isInMeeting { enterMeeting(settings.meetURL) } else { showIdle() }

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

    private func setUpIdleView() {
        idleView.frame = view.bounds
        idleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(idleView)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(showSettings(_:)))
        hold.minimumPressDuration = 2
        idleView.addGestureRecognizer(hold)
    }

    private func setUpDoneButton() {
        doneButton.isHidden = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(finishSignIn), for: .touchUpInside)
        view.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
    }

    private func setUpStatusPill() {
        statusPill.font = Brand.mono(13, .medium)
        statusPill.textColor = Brand.cream
        statusPill.backgroundColor = Brand.navy.withAlphaComponent(0.88)
        statusPill.layer.cornerRadius = 8
        statusPill.layer.masksToBounds = true
        statusPill.textAlignment = .center
        statusPill.isUserInteractionEnabled = true
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusPill)
        NSLayoutConstraint.activate([
            statusPill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            statusPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            statusPill.heightAnchor.constraint(equalToConstant: 32),
        ])
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(showSettings(_:)))
        hold.minimumPressDuration = 2
        statusPill.addGestureRecognizer(hold)
        updateStatusPill()
    }

    private func connectChannel() {
        auth?.stop()
        auth = nil
        channel?.disconnect()
        channel = nil
        authError = nil
        guard settings.isRealtimeConfigured,
              let auth = AuthSession(projectURL: settings.supabaseURL, apiKey: settings.supabaseKey,
                                     email: settings.robotEmail, password: settings.robotPassword),
              let channel = RealtimeChannel(projectURL: settings.supabaseURL,
                                            apiKey: settings.supabaseKey,
                                            room: settings.room) else {
            updateStatusPill()
            return
        }
        auth.onToken = { [weak self, weak channel] token in
            self?.authError = nil
            channel?.setAccessToken(token)
            self?.updateStatusPill()
        }
        auth.onError = { [weak self] message in
            self?.authError = message
            self?.updateStatusPill()
        }
        channel.onBroadcast = { [weak self] event, payload in self?.handle(event: event, payload: payload) }
        channel.onJoinedChange = { [weak self] joined in
            if !joined { self?.robot.stop() }
            self?.updateStatusPill()
            self?.publishStatus()
        }
        self.channel = channel
        self.auth = auth
        auth.start()
    }

    // MARK: - Remote commands

    private func handle(event: String, payload: [String: Any]) {
        let sender = payload["by"] as? String ?? "okänd"
        let driverCommands: Set<String> = ["drive", "park", "unpark"]
        if driverCommands.contains(event) && !claimDriverSeat(for: sender) {
            return
        }
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
            if let url = payload["url"] as? String { enterMeeting(url) }
        case "leave":
            leaveMeeting()
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

    /// Returns false while someone else holds the seat.
    private func claimDriverSeat(for sender: String) -> Bool {
        let now = Date()
        if let current = driver, current != sender, now.timeIntervalSince(driverLastSeen) < Self.driverTimeout {
            return false
        }
        if driver != sender {
            driver = sender
            driverSince = now
        }
        driverLastSeen = now
        if now.timeIntervalSince(lastUsedAt ?? .distantPast) > 30 || lastUser != sender {
            lastUser = sender
            lastUsedAt = now
            UserDefaults.standard.set(sender, forKey: "usage.lastUser")
            UserDefaults.standard.set(now, forKey: "usage.lastUsedAt")
        }
        return true
    }

    private var activeDriver: String? {
        guard let driver = driver, Date().timeIntervalSince(driverLastSeen) < Self.driverTimeout else { return nil }
        return driver
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
            "screen": isSigningIn ? "signin" : (idleView.isHidden ? "meeting" : "idle"),
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if let firmware = robot.firmwareVersion { status["firmware"] = firmware }
        if let driver = activeDriver {
            status["driver"] = driver
            status["driverSince"] = Int(driverSince.timeIntervalSince1970 * 1000)
        }
        if let lastUser = lastUser, let lastUsedAt = lastUsedAt {
            status["lastUser"] = lastUser
            status["lastUsedAt"] = Int(lastUsedAt.timeIntervalSince1970 * 1000)
        }
        if let url = webView.url, url.host == "meet.google.com", url.path.count > 1 {
            status["meeting"] = String(url.path.dropFirst())
        }
        channel.broadcast("status", status)
    }

    private func updateStatusPill() {
        let linkOK = channel?.isJoined ?? false
        let link: String
        if !settings.isRealtimeConfigured {
            link = "Styrning ej konfigurerad"
        } else if authError != nil {
            link = "Inloggningen misslyckades"
        } else {
            link = linkOK ? "Styrning online" : "Ansluter styrning"
        }
        let battery = Int(batteryPercentForDisplay)
        let base = robot.connected ? "BAS \(battery)%" : "BAS SAKNAS"
        statusPill.text = "   \(base)  ·  \(link.uppercased())   "
        statusPill.textColor = robot.connected && linkOK ? Brand.cream : Brand.terrakotta

        idleView.update(IdleView.State(baseConnected: robot.connected, battery: battery,
                                       charging: robot.batteryIsCharging, linkText: link, linkOK: linkOK,
                                       controllerURL: settings.controllerURL))
    }

    private var batteryPercentForDisplay: Float {
        let value = robot.batteryPercent
        return value <= 1 ? value * 100 : value
    }

    // MARK: - Meet

    private func enterMeeting(_ string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https", url.host == "meet.google.com" else { return }
        settings.meetURL = url.absoluteString
        settings.save()
        isSigningIn = false
        doneButton.isHidden = true
        webView.load(URLRequest(url: url))
        setIdleVisible(false)
    }

    private func leaveMeeting() {
        autoJoinTimer?.invalidate()
        settings.meetURL = ""
        settings.save()
        showIdle()
    }

    private func showIdle() {
        isSigningIn = false
        doneButton.isHidden = true
        // Unloading the page ends the call and releases camera and microphone.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        setIdleVisible(true)
    }

    private func setIdleVisible(_ visible: Bool) {
        statusPill.isHidden = visible
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut]) {
            self.idleView.alpha = visible ? 1 : 0
        } completion: { _ in
            self.idleView.isHidden = !visible
        }
        if visible { idleView.isHidden = false }
        updateStatusPill()
        publishStatus()
    }

    /// Lets someone sign the robot's browser in to Google once, so it joins as a named account.
    private func startGoogleSignIn() {
        isSigningIn = true
        webView.load(URLRequest(url: URL(string: "https://accounts.google.com/ServiceLogin?continue=https://meet.google.com/")!))
        setIdleVisible(false)
        statusPill.isHidden = true
        doneButton.isHidden = false
        view.bringSubviewToFront(doneButton)
    }

    @objc private func finishSignIn() {
        if settings.isInMeeting { enterMeeting(settings.meetURL) } else { showIdle() }
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
        let sheet = SettingsViewController(settings: settings)
        sheet.onSave = { [weak self] updated in
            guard let self = self else { return }
            self.settings = updated
            self.settings.save()
            self.connectChannel()
        }
        sheet.onGoogleSignIn = { [weak self] in self?.startGoogleSignIn() }
        sheet.onLeaveMeeting = { [weak self] in self?.leaveMeeting() }
        present(sheet, animated: true)
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
        if !isSigningIn, webView.url?.host == "meet.google.com", webView.url?.path.count ?? 0 > 1 {
            startAutoJoin()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
