import Foundation

/// Classement des services pour le sélecteur rapide (⌘K).
///
/// Sans tenir compte des majuscules ni des accents, du plus au moins pertinent : nom exact,
/// début du nom, début d'un mot du nom, initiales (« ha » → Home Assistant), nom qui contient
/// le texte, adresse qui le contient, lettres du texte présentes dans l'ordre dans le nom (« pmx »).
enum QuickSearch {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ text: String) -> [Substring] {
        text.split { !$0.isLetter && !$0.isNumber }
    }

    /// Score d'un élément, ou `nil` s'il ne correspond pas. Un texte vide correspond à tout.
    static func score(_ query: String, name: String, detail: String = "") -> Int? {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }
        let n = normalize(name)
        let compactQuery = q.replacingOccurrences(of: " ", with: "")

        if n == q { return 1000 }
        if n.hasPrefix(q) { return 800 }
        let nameWords = words(n)
        if nameWords.contains(where: { $0.hasPrefix(q) }) { return 600 }
        let initials = String(nameWords.compactMap(\.first))
        if compactQuery.count >= 2, initials.hasPrefix(compactQuery) { return 500 }
        if n.contains(q) { return 400 }
        if normalize(detail).contains(q) { return 200 }
        if isSubsequence(compactQuery, of: n) { return 100 }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var index = needle.startIndex
        for character in haystack where character == needle[index] {
            index = needle.index(after: index)
            if index == needle.endIndex { return true }
        }
        return false
    }

    /// Éléments qui correspondent, les plus pertinents d'abord ; à égalité, l'ordre d'origine.
    static func rank<Item>(_ items: [Item], query: String,
                           name: (Item) -> String, detail: (Item) -> String = { _ in "" }) -> [Item] {
        items.enumerated()
            .compactMap { offset, item in
                score(query, name: name(item), detail: detail(item)).map { (offset, $0, item) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .map(\.2)
    }
}
