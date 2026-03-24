import Foundation

final class Helper: NSObject, HelperProtocol {
    func runCommand(_ command: String, withReply reply: @escaping (String) -> Void) {
        // TODO: Implement robust client validation via SecCode APIs.
        let output = Shell.runSync(command: command)
        reply(output)
    }
}

enum Shell {
    static func runSync(command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-lc", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        var output = ""

        task.launch()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if let outStr = String(data: outData, encoding: .utf8) {
            output += outStr
        }
        if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
            output += errStr
        }
        task.waitUntilExit()
        return output
    }
}
