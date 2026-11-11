import CleanmacCore
import QuickLook
import SwiftUI

/// Écran des doublons, une fois la recherche terminée.
/// Lecture seule : on compare, on prévisualise et on ouvre dans le Finder, sans supprimer d'ici.
struct DuplicatesScreen: View {
    let scan: DuplicateScan
    @State private var kind: FileKind?
    @State private var preview: URL?

    private var groups: [DuplicateGroup] {
        kind.map { wanted in scan.groups.filter { $0.kind == wanted } } ?? scan.groups
    }

    var body: some View {
        let shown = groups
        VStack(alignment: .leading, spacing: 18) {
            header
            if scan.groups.isEmpty {
                empty
            } else {
                HStack(spacing: 12) {
                    Picker("Type", selection: $kind) {
                        Text("Tous types").tag(FileKind?.none)
                        ForEach(FileKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.large)
                    .fixedSize()
                    Text("\(shown.count) groupes, \(Bytes.text(shown.reduce(0) { $0 + $1.wastedBytes })) en trop")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.75))
                }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(shown) { group in
                            GroupCard(group: group) { preview = URL(fileURLWithPath: $0.path) }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .quickLookPreview($preview, in: shown.flatMap(\.files).map { URL(fileURLWithPath: $0.path) })
            }
            Label("Lecture seule : rien n'est supprimé ici. Supprimez les exemplaires inutiles depuis le Finder (bouton loupe).",
                  systemImage: "lock")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(.top, 44)
        .padding(.horizontal, 32)
        .padding(.bottom, 150)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            GlassIcon(symbol: "doc.on.doc")
            VStack(alignment: .leading, spacing: 2) {
                Text("Doublons").font(.system(size: 34, weight: .semibold))
                Text((scan.groups.isEmpty ? "Aucun doublon" : "\(Bytes.text(scan.wastedBytes)) en trop") + " — \(scan.filesExamined.formatted()) fichiers comparés en \(scan.duration.formatted(.units(allowed: [.seconds], width: .abbreviated)))"
                     + (scan.unreadableCount > 0 ? ", \(scan.unreadableCount.formatted()) illisibles" : ""))
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
            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                FileRow(file: file, isSuggestedKeep: index == 0) { preview(file) }
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
    let isSuggestedKeep: Bool
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(DisplayPath.short(file.path))
                        .font(.system(size: 16, weight: isSuggestedKeep ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.head)
                    if isSuggestedKeep {
                        badge("à garder", color: .green)
                    }
                    if file.mayShareBlocks {
                        badge("copie APFS", color: .teal)
                    }
                }
                Text("modifié \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            QuickLookButton(action: preview)
            FinderButton(path: file.path)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.white.opacity(isSuggestedKeep ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(file.path)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.35)))
    }
}
