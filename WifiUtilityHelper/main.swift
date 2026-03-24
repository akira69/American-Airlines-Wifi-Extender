//
//  main.swift
//  WifiUtilityHelper
//
//  Created by Daniel Finch on 3/20/26.
//

import Foundation

class XPCDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = Helper()
        newConnection.resume()
        return true
    }
}

let serviceName = "com.Finch13.WifiUtilityHelper"
let listener = NSXPCListener(machServiceName: serviceName)
let delegate = XPCDelegate()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
