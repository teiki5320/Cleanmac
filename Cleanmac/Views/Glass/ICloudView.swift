import CleanmacCore
import QuickLook
import SwiftUI

/// Écran iCloud Drive : fichiers téléchargés sur le Mac, à libérer sans les supprimer d'iCloud.
struct ICloudScreen: View {
    let scan: ICloudScan
    @Environment(AppModel.self) private var app
    @State private var container: String?
    @State private var preview: URL?
    @State private var showReview = false

    private var files: [ICloudFile] {
        container.map { wanted in scan.files.filter { $0.container == wanted } } ?? scan.files
    }

    var body: some View {
        let model = app.icloud
        let shown = files
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(
                symbol: "icloud",
                title: "iCloud Drive",
                subtitle: scan.files.isEmpty ? "Aucun gros fichier iCloud sur ce Mac"
                    : "\(plural(scan.files.count, "fichier")), \(Bytes.text(scan.totalBytes)) sur le Mac — \(Bytes.text(scan.evictableBytes)) libérables"
                    + (scan.cloudOnlyCount > 0 ? " — \(scan.cloudOnlyCount.formatted()) déjà dans iCloud seulement" : ""))
            if scan.files.isEmpty {
                EmptyStatePanel(symbol: "checkmark.icloud", title: "Rien à libérer",
                                detail: "Aucun fichier de plus de 1 Mo d'iCloud Drive n'est téléchargé sur ce Mac.")
            } else {
                toolbar(shown, model: model)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shown) { file in
                            ICloudRow(file: file, model: model) { preview = URL(fileURLWithPath: file.path) }
                        }
                    }
                    .padding(10)
                }
                .glassPanel(padding: 6)
                .quickLookPreview($preview, in: shown.map { URL(fileURLWithPath: $0.path) })
            }
            Label("Libérer retire la copie locale : le fichier reste dans iCloud, visible dans le Finder, et se retélécharge quand vous l'ouvrez. Rien n'est supprimé.",
                  systemImage: "icloud.and.arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .moduleScreenPadding()
        .sheet(isPresented: $showReview) {
            CleanReviewSheet(
                palette: Module.icloud.palette,
                title: "Vérification avant de libérer",
                totalBytes: model.selectedBytes,
                sections: [ReviewSection(title: "Libérés du Mac, gardés dans iCloud", symbol: "icloud.and.arrow.up",
                                         lines: model.selectedFiles.map {
                                             ReviewLine(id: $0.path, name: $0.name, detail: DisplayPath.short($0.path),
                                                        bytes: $0.allocatedBytes, symbol: "folder")
                                         })],
                notes: ["Juste avant, Cleanmac revérifie que chaque fichier est entièrement envoyé dans iCloud ; sinon il reste sur le Mac."],
                confirmTitle: "Libérer \(Bytes.text(model.selectedBytes))",
                phase: model.cleanState,
                cleaningTitle: "Libération en cours…",
                onConfirm: { model.evictSelection() },
                onClose: { model.dismissCleanResult() })
        }
    }

    private var containers: [String] {
        Array(Set(scan.files.map(\.container))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func toolbar(_ shown: [ICloudFile], model: ICloudModel) -> some View {
        let count = model.selectedFiles.count
        let old = model.notOpened(since: 90, in: shown)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filter
                selection(shown, old: old, model: model)
                Spacer(minLength: 8)
                action(count: count, bytes: model.selectedBytes)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    filter
                    selection(shown, old: old, model: model)
                }
                action(count: count, bytes: model.selectedBytes)
            }
        }
    }

    private var filter: some View {
        Picker("Dossier", selection: $container) {
            Text("Tous les dossiers").tag(String?.none)
            ForEach(containers, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.large)
        .fixedSize()
    }

    @ViewBuilder
    private func selection(_ shown: [ICloudFile], old: [ICloudFile], model: ICloudModel) -> some View {
        if shown.contains(where: model.isSelected) {
            Button("Tout décocher") { model.deselect(shown) }.controlSize(.large)
        } else {
            Button("Cocher les non ouverts depuis 3 mois (\(old.count))") { model.select(old) }
                .controlSize(.large)
                .disabled(old.isEmpty)
            Button("Tout cocher") { model.select(shown) }.controlSize(.large)
        }
    }

    private func action(count: Int, bytes: Int64) -> some View {
        PrimaryActionButton(
            title: count == 0 ? "Aucun fichier coché" : "Vérifier et libérer \(plural(count, "fichier")) (\(Bytes.text(bytes)))",
            symbol: "icloud.and.arrow.up", tint: Module.icloud.palette.mid, enabled: count > 0
        ) { showReview = true }
    }
}

private struct ICloudRow: View {
    let file: ICloudFile
    let model: ICloudModel
    let preview: () -> Void

    var body: some View {
        let selected = model.isSelected(file)
        HStack(spacing: 12) {
            GlassCheckbox(state: !file.isUploaded ? .locked : selected ? .on : .off,
                          tint: Module.icloud.palette.light,
                          label: "Libérer \(file.name)") { model.toggle(file) }
                .help(file.isUploaded ? "Libérer du Mac" : "Pas encore entièrement envoyé dans iCloud")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(file.name).font(.system(size: 16)).lineLimit(1).truncationMode(.middle)
                    Pill(text: file.container, color: .blue)
                    if !file.isUploaded { Pill(text: "envoi en cours", color: .orange) }
                }
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Bytes.text(file.allocatedBytes)).font(.system(size: 16, weight: .semibold).monospacedDigit())
            QuickLookButton(action: preview)
            FinderButton(path: file.path)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(selected ? Module.icloud.palette.light.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(file.path)
    }

    private var detail: String {
        var parts = ["modifié \(file.modified.formatted(date: .abbreviated, time: .omitted))"]
        if let opened = file.lastOpened { parts.append("ouvert \(opened.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " — ")
    }
}
