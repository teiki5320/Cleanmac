import Foundation

// Outil d'aide privilégié de Cleanmac.
// Démon lancé par launchd (enregistré par l'appli via SMAppService).
// N'accepte que les connexions de l'appli Cleanmac signée par la même équipe,
// et n'exécute que les commandes de `HelperCommand`.

final class HelperService: NSObject, CleanmacHelperProtocol {
    func version(reply: @escaping @Sendable (String) -> Void) {
        reply(HelperConstants.helperVersion)
    }

    func run(command rawValue: String, reply: @escaping @Sendable (Bool, String) -> Void) {
        guard let command = HelperCommand(rawValue: rawValue) else {
            NSLog("CleanmacHelper : commande refusée « %@ »", rawValue)
            reply(false, "Commande refusée : \(rawValue)")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let (ok, message) = CommandRunner.run(command)
            reply(ok, message)
        }
    }
}

enum CommandRunner {
    static func run(_ command: HelperCommand) -> (Bool, String) {
        var output: [String] = []
        for step in command.steps {
            guard FileManager.default.isExecutableFile(atPath: step.executable) else {
                return (false, "Programme introuvable : \(step.executable)")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: step.executable)
            process.arguments = step.arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (false, "Échec du lancement de \(step.executable) : \(error.localizedDescription)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { output.append(text) }
            if process.terminationStatus != 0 {
                return (false, "\(step.executable) a échoué (code \(process.terminationStatus)). \(text)")
            }
        }
        return (true, output.isEmpty ? "\(command.label) : terminé." : output.joined(separator: "\n"))
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Seule l'appli Cleanmac signée par notre équipe peut parler à l'outil d'aide.
        connection.setCodeSigningRequirement(HelperConstants.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: CleanmacHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
NSLog("CleanmacHelper %@ prêt", HelperConstants.helperVersion)
dispatchMain()
