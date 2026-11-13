import XCTest

/// Tests d'interface : ils pilotent la vraie appli, écran par écran.
/// L'appli est lancée en « mode test » (CLEANMAC_UI_TEST=1) : elle refuse toute suppression,
/// libération ou modification, même si un test cliquait sur un bouton de confirmation.
/// Les analyses, elles, lisent réellement le disque (en lecture seule).
final class CleanmacUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Modules de la barre latérale : identifiant et titre affiché à droite.
    private let modules: [(id: String, title: String)] = [
        ("analyse", "Analyse complète"), ("systeme", "Fichiers système"), ("developpeur", "Développeur"),
        ("mail", "Mail"), ("corbeilles", "Vider les Corbeilles"), ("icloud", "iCloud Drive"),
        ("carte", "Carte du disque"), ("doublons", "Doublons"), ("purgeable", "Espace purgeable"),
        ("applications", "Applications"), ("maintenance", "Entretien"), ("historique", "Historique"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["CLEANMAC_UI_TEST"] = "1"
        // Écran d'accueil déjà vu (domaine des arguments de UserDefaults).
        app.launchArguments += ["-accueilTermine", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func open(_ id: String) {
        let row = app.buttons["module.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "module \(id) absent de la barre latérale")
        row.click()
    }

    /// Texte affiché qui contient `fragment` (sur macOS, le texte d'un `Text` est dans `value`).
    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", fragment, fragment)).firstMatch
    }

    private var roundButton: XCUIElement { app.buttons["bouton-rond"].firstMatch }

    // MARK: Navigation

    func testChaqueModuleSAfficheAvecSonTitre() {
        for module in modules {
            open(module.id)
            XCTAssertTrue(app.staticTexts[module.title].firstMatch.waitForExistence(timeout: 5),
                          "titre « \(module.title) » non affiché")
            let hasButton = module.id != "maintenance" && module.id != "historique"
            XCTAssertEqual(roundButton.waitForExistence(timeout: hasButton ? 3 : 1), hasButton,
                           "bouton rond \(hasButton ? "absent" : "en trop") dans \(module.title)")
        }
    }

    // MARK: Analyse, vérification, annulation

    func testAnalyseFichiersSystemePuisVerificationAnnulee() {
        open("systeme")
        XCTAssertTrue(roundButton.waitForExistence(timeout: 5))
        roundButton.click()
        XCTAssertTrue(text(containing: "trouvés").waitForExistence(timeout: 180), "l'analyse ne se termine pas")
        let review = app.buttons["Vérifier et nettoyer…"].firstMatch
        XCTAssertTrue(review.exists)
        guard review.isEnabled else { return }   // rien de coché : pas d'écran de vérification à ouvrir
        review.click()
        XCTAssertTrue(app.staticTexts["Vérification avant nettoyage"].waitForExistence(timeout: 5))
        app.buttons["Annuler"].firstMatch.click()
        XCTAssertFalse(app.staticTexts["Vérification avant nettoyage"].waitForExistence(timeout: 2),
                       "l'écran de vérification ne se ferme pas")
    }

    func testModeTestRefuseLeNettoyage() {
        open("systeme")
        roundButton.click()
        XCTAssertTrue(text(containing: "trouvés").waitForExistence(timeout: 180))
        let review = app.buttons["Vérifier et nettoyer…"].firstMatch
        guard review.isEnabled else { return }
        review.click()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nettoyer' OR label BEGINSWITH 'Vider définitivement'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        // En mode test, chaque élément est refusé : rien n'est supprimé.
        XCTAssertTrue(app.staticTexts["Rien n'a été supprimé"].waitForExistence(timeout: 60))
        app.buttons["Fermer"].firstMatch.click()
    }

    // MARK: Modules qui s'affichent directement

    func testEntretienMontreLesTachesEtLaMemoire() {
        open("maintenance")
        for title in ["Vider le cache DNS", "Reconstruire les services de lancement", "Libérer la mémoire vive",
                      "Réindexer Spotlight", "Mémoire vive", "Les plus gourmands"] {
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5), "« \(title) » absent")
        }
    }

    func testHistoriqueSAffiche() {
        open("historique")
        XCTAssertTrue(text(containing: "nettoyage").waitForExistence(timeout: 5)
                      || app.staticTexts["Rien encore"].waitForExistence(timeout: 2))
    }

    // MARK: Modules à inventaire

    func testApplicationsEtSesOnglets() {
        open("applications")
        roundButton.click()
        XCTAssertTrue(app.staticTexts["Choisissez une appli à gauche"].waitForExistence(timeout: 60))
        for (tab, expected) in [("Restes", "Repérés par leur identifiant"), ("Démarrage", "Vos agents"),
                                ("Mises à jour", "Sparkle"), ("Désinstaller", "Choisissez une appli à gauche")] {
            let segment = app.radioButtons[tab].exists ? app.radioButtons[tab] : app.buttons[tab].firstMatch
            XCTAssertTrue(segment.waitForExistence(timeout: 5), "onglet \(tab) absent")
            segment.click()
            XCTAssertTrue(text(containing: expected).waitForExistence(timeout: 10)
                          || (tab == "Restes" && app.staticTexts["Aucun reste repéré"].exists),
                          "contenu de l'onglet \(tab) absent")
        }
    }

    func testEspacePurgeable() {
        open("purgeable")
        roundButton.click()
        for title in ["Libre", "Purgeable", "Disponible", "Instantanés locaux"] {
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 30), "« \(title) » absent")
        }
    }

    func testCarteDuDisqueDossierPersonnel() {
        open("carte")
        roundButton.click()
        XCTAssertTrue(text(containing: "fichiers, lus en").waitForExistence(timeout: 120), "la carte ne s'affiche pas")
    }

    // MARK: Réglages

    func testReglagesEtSesOnglets() {
        app.typeKey(",", modifierFlags: .command)
        for (tab, expected) in [("Alertes", "Barre des menus"), ("Exclusions", "Dossiers et fichiers exclus"),
                                ("Accès", "Accès complet au disque"), ("À propos", "Base de règles"),
                                ("Nettoyage", "Corbeille ou suppression définitive")] {
            let button = app.toolbars.buttons[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "onglet de réglages \(tab) absent")
            button.click()
            XCTAssertTrue(text(containing: expected).waitForExistence(timeout: 5), "contenu de \(tab) absent")
        }
    }
}
