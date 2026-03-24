import SwiftUI
import WebKit
import Combine
import UserNotifications
import AppKit

// MARK: - Menu Bar Notifications
extension Notification.Name {
    static let menuBarStartPause = Notification.Name("MenuBarStartPause")
    static let menuBarReset = Notification.Name("MenuBarReset")
    static let menuBarOpenPortal = Notification.Name("MenuBarOpenPortal")
}

// MARK: - ContentView
struct ContentView: View {
    // Persistent settings
    @AppStorage("ssid") private var ssid: String = "aainflight.com"
    @AppStorage("portalURLString") private var portalURLString: String = "https://example.com"
    @AppStorage("durationMinutes") private var durationMinutes: Int = 19
    @AppStorage("headsUpEnabled") private var headsUpEnabled: Bool = true
    @AppStorage("lastGeneratedMAC") private var lastGeneratedMAC: String = ""

    // Timer state
    @State private var remaining: TimeInterval = 19 * 60
    @State private var isRunning: Bool = false
    @State private var timer: Timer?
    @State private var headsUpSent: Bool = false

    // Command runner state
    @State private var commandInput: String = ""
    @State private var commandOutput: String = ""

    // UI state
    @State private var overlayEnabled: Bool = true
    @State private var showFinishedAlert: Bool = false

    var body: some View {
        NavigationSplitView {
            VStack {
                Form {
                    Section("Timer Settings") {
                        Stepper(value: $durationMinutes, in: 1...180) {
                            Text("Duration: \(durationMinutes) min")
                        }
                        Toggle("1‑minute warning", isOn: $headsUpEnabled)
                        HStack {
                            Button(isRunning ? "Pause" : "Start") { toggleTimer() }
                            Button("Reset") { resetTimer() }
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Remaining: \(formattedRemaining)")
                            .font(.title2).monospacedDigit()

                        Toggle("Show overlay", isOn: $overlayEnabled)
                    }

                    Section("Connection Info (user-provided)") {
                        TextField("SSID", text: $ssid)
                        TextField("Portal URL", text: $portalURLString)
                    }

                    Section("Command Runner (user-driven)") {
                        TextEditor(text: $commandInput)
                            .frame(minHeight: 100)
                            .font(.system(.body, design: .monospaced))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary))

                        Button("Generate MAC command") {
                            generateMACCommand()
                        }
                        .buttonStyle(.bordered)

                        if !lastGeneratedMAC.isEmpty {
                            Text("Last MAC: \(lastGeneratedMAC)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Button("Prepare Disconnect Wi‑Fi") { prepareDisconnectWiFiCommand() }
                            Button("Prepare Connect Wi‑Fi") { prepareConnectWiFiCommand() }
                        }
                        .buttonStyle(.bordered)

                        HStack {
                            Button("Run") { runUserCommand() }
                            Button("Run as Admin") { runUserCommandAdmin() }
                            Button("Copy Command") { copyCommandToClipboard() }
                            Button("Clear") { commandInput = ""; commandOutput = "" }
                        }
                        .buttonStyle(.bordered)

                        Text("Output:")
                            .font(.headline)
                        ScrollView {
                            Text(commandOutput)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                        .frame(minHeight: 120)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .navigationTitle("Wi‑Fi Utility")
            }
            .frame(minWidth: 360)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text("Portal: ")
                    Text(portalURLString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Open") { webPage.load(urlString: portalURLString) }
                        .buttonStyle(.bordered)
                }
                .padding(8)

                WebView(page: webPage)
                    .overlay(alignment: .topTrailing) {
                        if overlayEnabled {
                            TimerOverlay(remaining: remaining, isRunning: isRunning)
                                .padding(8)
                        }
                    }
            }
            .onAppear {
                // Initialize timer with persisted duration
                remaining = TimeInterval(durationMinutes * 60)
                setupMenuBar()
                requestNotificationAuthorization()
            }
            .onChange(of: remaining) { _, newValue in
                MenuBarController.shared.update(remaining: newValue, isRunning: isRunning)
                if Int(newValue) == 60 && headsUpEnabled && !headsUpSent {
                    headsUpSent = true
                    sendHeadsUpNotification()
                }
            }
            .onChange(of: isRunning) { _, newValue in
                MenuBarController.shared.update(remaining: remaining, isRunning: newValue)
            }
            .alert("Timer finished", isPresented: $showFinishedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your countdown has completed.")
            }
        }
    }

    // MARK: - WebView state
    @State private var webPage: WebPage = .init()

    // MARK: - Timer logic
    private var formattedRemaining: String {
        let total = max(0, Int(remaining))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func toggleTimer() {
        if isRunning { pauseTimer() } else { startTimer() }
    }

    private func startTimer() {
        if remaining <= 0 { remaining = TimeInterval(durationMinutes * 60) }
        isRunning = true
        headsUpSent = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if remaining > 0 {
                remaining -= 1
            } else {
                pauseTimer()
                showFinishedAlert = true
                sendTimerFinishedNotification()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func resetTimer() {
        pauseTimer()
        remaining = TimeInterval(durationMinutes * 60)
    }

    // MARK: - Notifications
    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendHeadsUpNotification() {
        let content = UNMutableNotificationContent()
        content.title = "1‑minute remaining"
        content.body = "Your countdown will finish in one minute."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func sendTimerFinishedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = "Your countdown has completed."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Command Runner
    private func runUserCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        commandOutput = ""

        Task {
            let result = await Shell.run(command: cmd)
            commandOutput = result
        }
    }

    private func runUserCommandAdmin() {
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        commandOutput = ""

        Task { @MainActor in
            do {
                try BlessedHelperClient.shared.registerIfNeeded()
                BlessedHelperClient.shared.runCommand(cmd) { output in
                    DispatchQueue.main.async {
                        self.commandOutput = output
                    }
                }
            } catch {
                self.commandOutput = "Helper registration failed: \(error.localizedDescription)"
            }
        }
    }

    private func generateMACCommand() {
        let command = "/bin/zsh -lc 'iface=$(networksetup -listallhardwareports | awk \"/Wi-Fi/{getline; print $NF}\"); if [ -z \"$iface\" ]; then echo \"Wi-Fi interface not found\" >&2; exit 1; fi; rand(){ printf \"%02X\" $(( RANDOM % 256 )); }; first=$(( (RANDOM % 256 | 0x02) & ~0x01 )); mac=$(printf \"%02X\" $first); for i in {1..5}; do mac=\"$mac:$(rand)\"; done; echo \"Using interface: $iface\"; echo \"Generated MAC: $mac\"; sudo ifconfig \"$iface\" ether \"$mac\"'"
        // Not available until runtime; clear lastGeneratedMAC so runtime output is authoritative.
        lastGeneratedMAC = ""
        commandInput = command
    }

    private func generateRandomMAC() -> String {
        func hexByte(_ value: Int) -> String { String(format: "%02X", value & 0xFF) }
        // First byte: locally administered (bit1 = 1), unicast (bit0 = 0)
        var first = Int.random(in: 0...255)
        first = (first | 0x02) & ~0x01
        let b2 = Int.random(in: 0...255)
        let b3 = Int.random(in: 0...255)
        let b4 = Int.random(in: 0...255)
        let b5 = Int.random(in: 0...255)
        let b6 = Int.random(in: 0...255)
        return [hexByte(first), hexByte(b2), hexByte(b3), hexByte(b4), hexByte(b5), hexByte(b6)].joined(separator: ":")
    }
    
    private func prepareDisconnectWiFiCommand() {
        commandInput = "networksetup -setairportpower en0 off"
    }

    private func prepareConnectWiFiCommand() {
        let escapedSSID = ssid.replacingOccurrences(of: "\"", with: "\\\"")
        commandInput = "networksetup -setairportpower en0 on; networksetup -setairportnetwork en0 \"\(escapedSSID)\""
    }

    private func copyCommandToClipboard() {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(commandInput, forType: .string)
        #endif
    }

    // MARK: - Menu Bar setup
    private func setupMenuBar() {
        MenuBarController.shared.configureMenu(
            startPauseTitle: isRunning ? "Pause" : "Start",
            onStartPause: {
                NotificationCenter.default.post(name: .menuBarStartPause, object: nil)
            },
            onReset: {
                NotificationCenter.default.post(name: .menuBarReset, object: nil)
            },
            onOpenPortal: {
                NotificationCenter.default.post(name: .menuBarOpenPortal, object: nil)
            }
        )
        MenuBarController.shared.update(remaining: remaining, isRunning: isRunning)
    }
}

// MARK: - Timer Overlay View
private struct TimerOverlay: View {
    let remaining: TimeInterval
    let isRunning: Bool

    private var display: String {
        let total = max(0, Int(remaining))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isRunning ? "timer" : "pause")
            Text(display).monospacedDigit().bold()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThickMaterial, in: Capsule())
        .shadow(radius: 4)
        .accessibilityLabel("Countdown timer \(display)")
    }
}

// MARK: - Simple WebKit wrapper
final class WebPage: ObservableObject {
    @Published var webView: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: config)
    }

    func load(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }
}

struct WebView: NSViewRepresentable {
    @ObservedObject var page: WebPage

    func makeNSView(context: Context) -> WKWebView {
        page.webView.navigationDelegate = context.coordinator
        return page.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - Menu Bar controller
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let startPauseItem = NSMenuItem(title: "Start", action: #selector(startPauseAction), keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "Reset", action: #selector(resetAction), keyEquivalent: "")
    private let openPortalItem = NSMenuItem(title: "Open Portal", action: #selector(openPortalAction), keyEquivalent: "")

    private var onStartPause: (() -> Void)?
    private var onReset: (() -> Void)?
    private var onOpenPortal: (() -> Void)?

    override init() {
        super.init()
        statusItem.button?.title = "--:--"
        startPauseItem.target = self
        resetItem.target = self
        openPortalItem.target = self

        menu.items = [startPauseItem, resetItem, NSMenuItem.separator(), openPortalItem]
        statusItem.menu = menu
    }

    func configureMenu(startPauseTitle: String, onStartPause: @escaping () -> Void, onReset: @escaping () -> Void, onOpenPortal: @escaping () -> Void) {
        self.onStartPause = onStartPause
        self.onReset = onReset
        self.onOpenPortal = onOpenPortal
        startPauseItem.title = startPauseTitle

        // Wire up notifications to decouple from view
        NotificationCenter.default.addObserver(self, selector: #selector(handleMenuNotification(_:)), name: .menuBarStartPause, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMenuNotification(_:)), name: .menuBarReset, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMenuNotification(_:)), name: .menuBarOpenPortal, object: nil)
    }

    func update(remaining: TimeInterval, isRunning: Bool) {
        let total = max(0, Int(remaining))
        let m = total / 60
        let s = total % 60
        let text = String(format: "%@ %02d:%02d", isRunning ? "▶︎" : "⏸", m, s)
        statusItem.button?.title = text
        startPauseItem.title = isRunning ? "Pause" : "Start"
    }

    @objc private func startPauseAction() { onStartPause?() }
    @objc private func resetAction() { onReset?() }
    @objc private func openPortalAction() { onOpenPortal?() }

    @objc private func handleMenuNotification(_ note: Notification) {
        switch note.name {
        case .menuBarStartPause: onStartPause?()
        case .menuBarReset: onReset?()
        case .menuBarOpenPortal: onOpenPortal?()
        default: break
        }
    }
}

// MARK: - Shell execution (user-driven)
enum Shell {
    static func run(command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = "/bin/zsh"
                task.arguments = ["-lc", command]

                let outPipe = Pipe()
                let errPipe = Pipe()
                task.standardOutput = outPipe
                task.standardError = errPipe

                do {
                    try task.run()
                } catch {
                    continuation.resume(returning: "Failed to run command: \(error.localizedDescription)")
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                var output = ""
                if let outString = String(data: outData, encoding: .utf8) {
                    output += outString
                }
                if let errString = String(data: errData, encoding: .utf8) {
                    output += errString
                }

                continuation.resume(returning: output)
            }
        }
    }
}

#Preview {
    ContentView()
}
