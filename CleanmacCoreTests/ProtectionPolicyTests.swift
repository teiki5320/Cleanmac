import Foundation
import Testing
@testable import CleanmacCore

@Suite("Protections")
struct ProtectionPolicyTests {
    let policy = ProtectionPolicy(home: "/Users/test", userExclusions: ["~/Library/Caches/Garder"])

    @Test("Emplacements protégés d'office", arguments: [
        "/Users/test/Documents/rapport.pdf",
        "/Users/test/Desktop/x",
        "/Users/test/Pictures/Photos Library.photoslibrary",
        "/Users/test/Library/Messages/chat.db",
        "/Users/test/Library/Keychains/login.keychain-db",
        "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/x",
        "/System/Library/Caches/x",
        "/usr/local/lib",
    ])
    func protectedLocations(path: String) {
        #expect(policy.protection(for: path) != nil)
    }

    @Test("Un dossier qui contient un emplacement protégé est protégé")
    func containsProtected() {
        #expect(policy.protection(for: "/Users/test/Library") == .containsProtectedLocation(
            "/Users/test/Library/Messages"))
    }

    @Test("Dossier personnel, racine et chemins incohérents refusés", arguments: [
        "/Users/test", "/Users", "/", "relatif/chemin", "/Users/test/Library/../Documents",
    ])
    func unsafe(path: String) {
        #expect(policy.protection(for: path) != nil)
    }

    @Test("Photothèque n'importe où")
    func photoLibraryAnywhere() {
        #expect(policy.protection(for: "/Volumes/Disque/Ancienne.photoslibrary/x") == .photoLibrary)
    }

    @Test("Exclusions de l'utilisateur")
    func userExclusion() {
        #expect(policy.protection(for: "/Users/test/Library/Caches/Garder/x") ==
            .userExclusion("/Users/test/Library/Caches/Garder"))
    }

    @Test("Un cache ordinaire n'est pas protégé")
    func ordinaryCache() {
        #expect(policy.protection(for: "/Users/test/Library/Caches/com.exemple.app") == nil)
    }

    @Test("Dossier de code git : lui-même, parent ou sous-dossier")
    func gitRepositories() throws {
        let home = try FakeHome()
        let policy = ProtectionPolicy(home: home.path)
        try home.dir("Library/Caches/projet/.git")
        try home.file("Library/Caches/projet/src/main.swift")
        try home.dir("Library/Caches/outil/vendor/lib/.git")
        try home.file("Library/Caches/normal/f")

        #expect(policy.protection(for: home.url("Library/Caches/projet")) != nil)
        #expect(policy.protection(for: home.url("Library/Caches/projet/src")) != nil)
        // Le .git est profond : seule la vérification complète le trouve.
        #expect(policy.protection(for: home.url("Library/Caches/outil")) == nil)
        #expect(policy.fullProtection(for: home.url("Library/Caches/outil")) != nil)
        #expect(policy.fullProtection(for: home.url("Library/Caches/normal")) == nil)
    }

    @Test("Enregistrement des exclusions")
    func exclusionStore() throws {
        let home = try FakeHome()
        let store = ExclusionStore(fileURL: URL(fileURLWithPath: home.url("exclusions.json")))
        #expect(store.load().isEmpty)
        try store.add("~/Library/Caches/A")
        try store.add("~/Library/Caches/B")
        try store.add("~/Library/Caches/A")
        #expect(store.load() == ["~/Library/Caches/A", "~/Library/Caches/B"])
        try store.remove("~/Library/Caches/A")
        #expect(store.load() == ["~/Library/Caches/B"])
    }
}
