import CleanmacCore
import Foundation

/// Mode « tests d'interface » : activé par la variable d'environnement `CLEANMAC_UI_TEST=1`
/// (posée seulement par la cible CleanmacUITests). Dans ce mode, rien ne peut être supprimé,
/// libéré, modifié ni remis en place, même si un test cliquait sur un bouton de confirmation.
enum TestMode {
    static let isActive = ProcessInfo.processInfo.environment["CLEANMAC_UI_TEST"] == "1"
    static let refusal = "Mode test : aucune modification"
}

/// Suppresseur du mode test : refuse tout.
struct RefusingRemover: FileRemoving {
    struct Refused: LocalizedError {
        var errorDescription: String? { TestMode.refusal }
    }

    func trash(_ path: String) throws -> String? { throw Refused() }
    func removePermanently(_ path: String) throws { throw Refused() }
}
