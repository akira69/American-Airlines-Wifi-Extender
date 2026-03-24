// BlessedHelperClient.swift
// App-side XPC client for SMJobBless helper

import Foundation
import ServiceManagement

@objc protocol HelperProtocol {
    func runCommand(_ command: String, withReply reply: @escaping (String) -> Void)
}

final class BlessedHelperClient {
    static let shared = BlessedHelperClient()

    private var connection: NSXPCConnection?

    // Helper identifiers
    private let helperBundleID = "com.Finch13.WifiUtilityHelper"
    private let machServiceName = "com.Finch13.WifiUtilityHelper"

    // Install/update the helper. macOS will prompt the user.
    func blessIfNeeded() throws {
        var cfError: Unmanaged<CFError>?
        let ok = SMJobBless(kSMDomainSystemLaunchd, helperBundleID as CFString, nil, &cfError)
        if !ok {
            let error = (cfError?.takeRetainedValue()) as Error?
            throw error ?? NSError(domain: "BlessError", code: 1, userInfo: [NSLocalizedDescriptionKey: "SMJobBless failed"])
        }
    }

    // Connect to the helper's XPC service
    func connect() {
        if connection != nil { return }
        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.resume()
        self.connection = conn
    }

    // Execute a command via the helper
    func runCommand(_ command: String, completion: @escaping (String) -> Void) {
        connect()
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            completion("XPC error: \(error.localizedDescription)")
        }) as? HelperProtocol else {
            completion("Failed to obtain helper proxy")
            return
        }
        proxy.runCommand(command) { output in
            completion(output)
        }
    }
}
