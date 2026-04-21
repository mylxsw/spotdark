import Foundation

enum SearchHighlight {
    /// Returns an attributed string with matched ranges highlighted.
    ///
    /// This is intentionally simple: case-insensitive substring matching.
    static func highlight(text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attributed }

        let lowerText = text.lowercased()
        let lowerQuery = q.lowercased()

        var searchRange = lowerText.startIndex..<lowerText.endIndex
        while let range = lowerText.range(of: lowerQuery, options: [], range: searchRange) {
            let start = range.lowerBound
            let end = range.upperBound

            if let attrStart = AttributedString.Index(start, within: attributed),
               let attrEnd = AttributedString.Index(end, within: attributed) {
                var container = AttributeContainer()
                container.foregroundColor = .accentColor
                container.font = .system(size: 14, weight: .bold)
                attributed[attrStart..<attrEnd].mergeAttributes(container)
            }

            searchRange = end..<lowerText.endIndex
        }

        return attributed
    }
}
