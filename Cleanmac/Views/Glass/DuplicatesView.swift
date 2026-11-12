import CleanmacCore
import QuickLook
import SwiftUI

/// Écran des doublons, une fois la recherche terminée.
/// On choisit l'exemplaire à garder, on coche les copies, puis on vérifie avant la Corbeille.
struct DuplicatesScreen: View {
    let scan: DuplicateScan
    @Environment(AppModel.self) private var app
    @State private var kind: FileKind?
    @State private var preview: URL?
    @State private var showReview = false

    private var groups: [DuplicateGroup] {
        kind.map { wanted in scan.groups.filter { $0.kind == wanted } } ?? scan.groups
    }

    var body: some View {
        let shown = groups
        let model = app.duplicates
        VStack(alignment: .leading, spacing: 18) {
            header
            if scan.groups.isEmpty {
                empty
            } else {
                toolbar(shown, model: model)
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(shown) { group in
                            GroupCard(group: group, model: model) { preview = URL(fileURLWithPath: $0.path) }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .quickLookPreview($preview, in: shown.flatMap(\.files).map { URL(fileURLWithPath: $0.path) })
            }
            Label("Les copies cochées vont à la Corbeille, après vérification que leur contenu est identique à l'exemplaire gardé. Bureau, Documents, Images et dossiers de code restent protégés : passez par le Finder (bouton loupe).",
                  systemImage: "lock.shield")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.top, 44)
        .padding(.horizontal, 32)
        .padding(.bottom, 150)
        .sheet(isPresented: $showReview) {
            let selected = model.selectedCopies
            CleanReviewSheet(
                palette: Module.doublons.palette,
                title: "Vérification avant la Corbeille",
                totalBytes: model.selectedBytes,
                sections: [ReviewSection(title: "Copies mises à la Corbeille", symbol: "trash", lines: selected.map { copy in
                    ReviewLine(id: copy.file.path, name: DisplayPath.short(copy.file.path),
                               detail: "garde : " + DisplayPath.short(model.keeper(of: copy.group) ?? ""),
                               bytes: copy.file.mayShareBlocks ? 0 : copy.file.allocatedBytes, symbol: "checkmark.shield")
                })],
                notes: ["Juste avant, Cleanmac revérifie chaque copie : l'exemplaire gardé doit exister et avoir exactement le même contenu, sinon la copie est conservée. L'espace n'est libéré qu'une fois la Corbeille vidée."],
                confirmTitle: "Mettre " + copies(selected.count) + " à la Corbeille",
                phase: model.cleanState,
                cleaningTitle: "Vérification et mise à la Corbeille…",
                onConfirm: { model.trashSelection() },
                onClose: { model.dismissCleanResult() })
        }
    }

    private func toolbar(_ shown: [DuplicateGroup], model: DuplicatesModel) -> some View {
        let count = model.selectedCopies.count
        let trashable = model.trashableCount(in: shown)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filter
                selectionButton(shown, model: model, trashable: trashable)
                Spacer(minLength: 8)
                trashButton(count: count, bytes: model.selectedBytes)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    filter
                    selectionButton(shown, model: model, trashable: trashable)
                }
                trashButton(count: count, bytes: model.selectedBytes)
            }
        }
    }

    private var filter: some View {
        Picker("Type", selection: $kind) {
            Text("Tous types").tag(FileKind?.none)
            ForEach(FileKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.large)
        .fixedSize()
    }

    @ViewBuilder
    private func selectionButton(_ shown: [DuplicateGroup], model: DuplicatesModel, trashable: Int) -> some View {
        let selectedHere = shown.contains { group in group.files.contains { model.isSelected($0, in: group) } }
        if selectedHere {
            Button("Tout décocher") { model.deselect(in: shown) }
                .controlSize(.large)
        } else {
            Button("Cocher " + copies(trashable)) { model.selectAllCopies(in: shown) }
                .controlSize(.large)
                .disabled(trashable == 0)
                .help("Coche toutes les copies autorisées, en gardant l'exemplaire marqué « à garder » de chaque groupe.")
        }
    }

    private func trashButton(count: Int, bytes: Int64) -> some View {
        Button {
            showReview = true
        } label: {
            Label(count == 0 ? "Aucune copie cochée" : "Vérifier et mettre " + copies(count) + " à la Corbeille (\(Bytes.text(bytes)))",
                  systemImage: "trash")
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 6)
        }
        .controlSize(.extraLarge)
        .buttonStyle(.borderedProminent)
        .tint(Module.doublons.palette.mid)
        .disabled(count == 0)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            GlassIcon(symbol: "doc.on.doc")
            VStack(alignment: .leading, spacing: 2) {
                Text("Doublons").font(.system(size: 34, weight: .semibold))
                Text((scan.groups.isEmpty ? "Aucun doublon" : "\(plural(scan.groups.count, "groupe")), \(Bytes.text(scan.wastedBytes)) en trop") + " — \(plural(scan.filesExamined, "fichier")) comparés en \(scan.duration.formatted(.units(allowed: [.seconds], width: .abbreviated)))"
                     + (scan.unreadableCount > 0 ? ", \(plural(scan.unreadableCount, "illisible"))" : ""))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Aucun doublon trouvé", systemImage: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
            Text("Ont été ignorés : la Bibliothèque, les dossiers cachés, les applis et photothèques, les dépôts de code, et les fichiers iCloud non téléchargés sur ce Mac (ils ne prennent pas de place).")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Un groupe de fichiers identiques.
private struct GroupCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    let preview: (DuplicateFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: group.kind.symbol)
                    .font(.system(size: 20))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.suggestedKeep?.name ?? "")
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.files.count) exemplaires de \(Bytes.text(group.size))")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Bytes.text(group.wastedBytes))
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                    Text(group.wastedBytes > 0 ? "en trop" : "rien à gagner")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            ForEach(group.files) { file in
                FileRow(file: file, group: group, model: model) { preview(file) }
            }
            if group.hasClones {
                Label("Copie APFS : ces exemplaires partagent peut-être le même espace sur le disque. En supprimer un ne libère alors presque rien.",
                      systemImage: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

private struct FileRow: View {
    let file: DuplicateFile
    let group: DuplicateGroup
    let model: DuplicatesModel
    let preview: () -> Void

    var body: some View {
        let isKeeper = model.isKeeper(file, in: group)
        let selected = model.isSelected(file, in: group)
        let blocked = model.blocked[file.path]
        HStack(spacing: 12) {
            checkbox(isKeeper: isKeeper, selected: selected, blocked: blocked)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(DisplayPath.short(file.path))
                        .font(.system(size: 16, weight: isKeeper ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.head)
                    if isKeeper { badge("à garder", color: .green) }
                    if selected { badge("Corbeille", color: Module.doublons.palette.light) }
                    if file.mayShareBlocks { badge("copie APFS", color: .teal) }
                }
                Text("modifié \(file.modified.formatted(date: .abbreviated, time: .shortened))"
                     + (blocked.map { " — \($0)" } ?? ""))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if !isKeeper {
                Button("Garder celui-ci") { model.keep(file, in: group) }
                    .controlSize(.large)
                    .accessibilityLabel("Garder \(DisplayPath.short(file.path))")
                    .help("Garder cet exemplaire à la place de l'autre")
            }
            QuickLookButton(action: preview)
            FinderButton(path: file.path)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(rowFill(isKeeper: isKeeper, selected: selected),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(file.path)
    }

    @ViewBuilder
    private func checkbox(isKeeper: Bool, selected: Bool, blocked: String?) -> some View {
        let symbol = isKeeper ? "checkmark.shield.fill" : blocked != nil ? "lock.fill" : selected ? "checkmark.square.fill" : "square"
        Button {
            model.toggle(file, in: group)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(isKeeper ? Color.green : selected ? Module.doublons.palette.light : .white.opacity(blocked != nil ? 0.4 : 0.8))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isKeeper || blocked != nil)
        .help(isKeeper ? "Exemplaire gardé" : blocked ?? (selected ? "Ne pas mettre à la Corbeille" : "Mettre à la Corbeille"))
        .accessibilityLabel(isKeeper ? "Exemplaire gardé" : selected ? "Copie cochée pour la Corbeille" : "Copie non cochée")
    }

    private func rowFill(isKeeper: Bool, selected: Bool) -> Color {
        if selected { return Module.doublons.palette.light.opacity(0.18) }
        return .white.opacity(isKeeper ? 0.08 : 0)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.35)))
    }
}

/// « 1 copie », « 3 copies ».
private func copies(_ count: Int) -> String {
    count == 1 ? "1 copie" : "\(count) copies"
}
