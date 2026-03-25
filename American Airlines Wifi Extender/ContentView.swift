import SwiftUI
import WebKit
import Combine
import UserNotifications
import AppKit
import CoreWLAN

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
    @AppStorage("portalURLString") private var portalURLString: String = "https://aainflight.com"
    @AppStorage("durationMinutes") private var durationMinutes: Int = 19
    @State private var durationText: String = "19"
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
    @State private var isEditingSSID: Bool = false
    @State private var isEditingPortal: Bool = false
    @State private var wifiPowerEnabled: Bool = true
    @State private var currentWiFiStateLabel: String = "Wi-Fi Off"

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sidebarHero
                    timerCard
                    connectionCard
                    commandRunnerCard
                }
                .padding(16)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .underPageBackgroundColor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle("Wi‑Fi Utility")
            .frame(minWidth: 380)
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
                durationText = String(durationMinutes)
                if portalURLString == "https://example.com" || portalURLString == "aainflight.com" {
                    portalURLString = "https://aainflight.com"
                }
                refreshWiFiStatus()
                setupMenuBar()
                requestNotificationAuthorization()
            }
            .onChange(of: durationMinutes) { _, newValue in
                durationText = String(newValue)
            }
            .onChange(of: durationText) { _, newValue in
                let filtered = newValue.filter { $0.isNumber }
                if filtered != newValue {
                    durationText = filtered
                }
                guard let value = Int(filtered) else { return }
                let clamped = min(max(value, 1), 180)
                if clamped != durationMinutes {
                    durationMinutes = clamped
                    remaining = TimeInterval(clamped * 60)
                }
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

    private var sidebarHero: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AA Wi-Fi Extender")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Rotate MAC commands, reconnect quickly, and keep the portal close at hand.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.red.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var timerCard: some View {
        SidebarCard(title: "Timer") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remaining")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(formattedRemaining)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Duration")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            TextField("", text: $durationText)
                                .frame(width: 52)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                            Text("min")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Stepper("", value: $durationMinutes, in: 1...180)
                                .labelsHidden()
                        }

                        HStack(spacing: 14) {
                            Toggle("Warning", isOn: $headsUpEnabled)
                                .toggleStyle(.checkbox)
                            Toggle("Overlay", isOn: $overlayEnabled)
                                .toggleStyle(.checkbox)
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }

                AdaptiveButtonRow(spacing: 10) {
                    Button(isRunning ? "Pause" : "Start") { toggleTimer() }
                    Button("Reset") { resetTimer() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var connectionCard: some View {
        SidebarCard(title: "Connection", accessory: {
            HStack(spacing: 8) {
                Text(currentWiFiStateLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)

                Button {
                    toggleWiFiCommand()
                } label: {
                    Image(systemName: wifiPowerEnabled ? "wifi" : "wifi.slash")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(wifiPowerEnabled ? Color.white : Color.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            wifiPowerEnabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(wifiPowerEnabled ? "Prepare disconnect Wi-Fi command" : "Prepare connect Wi-Fi command")
            }
        }) {
            HStack(alignment: .top, spacing: 12) {
                editableConnectionRow(
                    label: "SSID",
                    value: $ssid,
                    isEditing: $isEditingSSID,
                    prompt: "SSID",
                    help: "Edit SSID"
                )

                editableConnectionRow(
                    label: "Portal",
                    value: $portalURLString,
                    isEditing: $isEditingPortal,
                    prompt: "Portal URL",
                    help: "Edit portal"
                )
            }
        }
    }

    private var commandRunnerCard: some View {
        SidebarCard(title: "Command Runner", accessory: {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button("Generate MAC") {
                    generateMACCommand()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: Capsule())
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                AdaptiveButtonRow(spacing: 10) {
                    Button("Run") { runUserCommand() }
                    Button("Run as Admin") { runUserCommandAdmin() }
                    Button("Copy") { copyCommandToClipboard() }
                    Button("Clear") { commandInput = ""; commandOutput = "" }
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                        Text(">_")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("Command")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $commandInput)
                        .frame(minHeight: 72)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.08))
                        )
                }

                if !lastGeneratedMAC.isEmpty {
                    Label(lastGeneratedMAC, systemImage: "network")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(commandOutput.isEmpty ? "Command output will appear here." : commandOutput)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(commandOutput.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(minHeight: 108)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func editableConnectionRow(
        label: String,
        value: Binding<String>,
        isEditing: Binding<Bool>,
        prompt: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if isEditing.wrappedValue {
                    TextField(prompt, text: value)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(value.wrappedValue)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(.primary)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    isEditing.wrappedValue.toggle()
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .help(help)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

        Task {
            let result = await Shell.runAsAdmin(command: cmd)
            await MainActor.run {
                commandOutput = result
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
        commandInput = "/bin/zsh -lc 'iface=$(networksetup -listallhardwareports | awk \"/Wi-Fi/{getline; print \\$NF}\"); if [ -z \"$iface\" ]; then echo \"Wi-Fi interface not found\" >&2; exit 1; fi; networksetup -setairportpower \"$iface\" off'"
    }

    private func prepareConnectWiFiCommand() {
        let escapedSSID = ssid.replacingOccurrences(of: "\"", with: "\\\"")
        commandInput = "/bin/zsh -lc 'iface=$(networksetup -listallhardwareports | awk \"/Wi-Fi/{getline; print \\$NF}\"); if [ -z \"$iface\" ]; then echo \"Wi-Fi interface not found\" >&2; exit 1; fi; networksetup -setairportpower \"$iface\" on; networksetup -setairportnetwork \"$iface\" \"\(escapedSSID)\"'"
    }

    private func copyCommandToClipboard() {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(commandInput, forType: .string)
        #endif
    }

    private func toggleWiFiCommand() {
        if wifiPowerEnabled {
            prepareDisconnectWiFiCommand()
        } else {
            prepareConnectWiFiCommand()
        }
        wifiPowerEnabled.toggle()
    }

    private func refreshWiFiStatus() {
        if let interface = CWWiFiClient.shared().interface() {
            wifiPowerEnabled = interface.powerOn()
            currentWiFiStateLabel = interface.powerOn() ? "Wi-Fi On" : "Wi-Fi Off"
        } else {
            wifiPowerEnabled = false
            currentWiFiStateLabel = "Wi-Fi Off"
        }
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

private struct SidebarCard<Content: View, Accessory: View>: View {
    let title: String
    let accessory: Accessory
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.accessory = EmptyView()
        self.content = content()
    }

    init(title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                accessory
            }

            content
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        )
    }
}

// MARK: - Adaptive wrapping button row
private struct AdaptiveButtonRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        FlowLayout(spacing: spacing) {
            content
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                width = max(width, rowWidth - spacing)
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        if rowWidth > 0 {
            width = max(width, rowWidth - spacing)
            height += rowHeight
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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

    static func runAsAdmin(command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = [
                    "-e",
                    "do shell script " + appleScriptString(for: command) + " with administrator privileges"
                ]

                let outPipe = Pipe()
                let errPipe = Pipe()
                task.standardOutput = outPipe
                task.standardError = errPipe

                do {
                    try task.run()
                } catch {
                    continuation.resume(returning: "Failed to run admin command: \(error.localizedDescription)")
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                let outString = String(data: outData, encoding: .utf8) ?? ""
                let errString = String(data: errData, encoding: .utf8) ?? ""
                let output = outString + errString

                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(returning: task.terminationStatus == 0 ? "Command completed." : "Admin command failed.")
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }

    private static func appleScriptString(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

#Preview {
    ContentView()
}
