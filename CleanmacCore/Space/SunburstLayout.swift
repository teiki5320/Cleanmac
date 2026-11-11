import Foundation

/// Un secteur de la vue en anneaux.
public struct SunburstSegment: Sendable, Identifiable {
    public let node: DiskNode
    /// Début et fin, en fraction du tour (0…1, sens horaire depuis midi).
    public let start: Double
    public let end: Double
    /// Anneau : 1 pour le contenu direct du dossier affiché.
    public let depth: Int
    /// Indice de couleur, hérité de l'ancêtre du premier anneau.
    public let colorIndex: Int

    public var id: String { node.id }
    public var span: Double { end - start }
}

/// Calcul des secteurs de la vue en anneaux autour d'un dossier.
public enum SunburstLayout {
    /// - Parameters:
    ///   - levels: nombre d'anneaux affichés.
    ///   - minSpan: secteurs plus petits ignorés (fraction du tour).
    public static func segments(for focus: DiskNode, levels: Int = 3, minSpan: Double = 0.004) -> [SunburstSegment] {
        var result: [SunburstSegment] = []

        func walk(_ node: DiskNode, start: Double, span: Double, depth: Int, color: Int?) {
            guard depth <= levels, node.allocatedBytes > 0 else { return }
            var cursor = start
            for (index, child) in node.children.enumerated() {
                let childSpan = span * Double(child.allocatedBytes) / Double(node.allocatedBytes)
                if childSpan >= minSpan {
                    let colorIndex = color ?? index
                    result.append(SunburstSegment(node: child, start: cursor, end: cursor + childSpan,
                                                  depth: depth, colorIndex: colorIndex))
                    if child.isDirectory {
                        walk(child, start: cursor, span: childSpan, depth: depth + 1, color: colorIndex)
                    }
                }
                cursor += childSpan
            }
        }

        walk(focus, start: 0, span: 1, depth: 1, color: nil)
        return result
    }
}
