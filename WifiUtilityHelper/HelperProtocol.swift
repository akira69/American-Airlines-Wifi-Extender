import Foundation

@objc public protocol HelperProtocol {
    func runCommand(_ command: String, withReply reply: @escaping (String) -> Void)
}
