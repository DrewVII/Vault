import SwiftUI

/// Rendu Markdown bloc par bloc :
/// — titres `#`, `##`, `###`
/// — listes à puces `- item` ou `* item`
/// — listes numérotées `1. item`
/// — paragraphes séparés par lignes vides
/// — formatage inline (gras, italique, code) via AttributedString
struct MarkdownText: View {
    let text: String
    var baseSize: CGFloat = 13
    var spacing: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(inline(content))
                .font(.system(size: headingSize(level), weight: .semibold, design: .default))
                .padding(.top, level == 1 ? 4 : 2)

        case .paragraph(let content):
            Text(inline(content))
                .font(.system(size: baseSize))
                .fixedSize(horizontal: false, vertical: true)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: baseSize, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 8, alignment: .leading)
                        Text(inline(item))
                            .font(.system(size: baseSize))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).")
                            .font(.system(size: baseSize, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .leading)
                        Text(inline(item))
                            .font(.system(size: baseSize))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .code(let content):
            Text(content)
                .font(.system(size: baseSize - 1, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))

        case .rule:
            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 2)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseSize + 5
        case 2: return baseSize + 3
        case 3: return baseSize + 1
        default: return baseSize
        }
    }

    private func inline(_ raw: String) -> AttributedString {
        // Préserve les retours-ligne simples comme vrais sauts de ligne (Markdown les efface sinon)
        let processed = raw.replacingOccurrences(of: "\n", with: "  \n")
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attr = try? AttributedString(markdown: processed, options: opts) {
            return attr
        }
        return AttributedString(raw)
    }
}

// MARK: - Modèle de blocs

enum MarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case code(String)
    case rule
}

// MARK: - Parser

enum MarkdownParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []

        var paragraphLines: [String] = []
        var ulItems: [String] = []
        var olItems: [String] = []
        var codeBuffer: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let joined = paragraphLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraphLines.removeAll()
        }
        func flushUL() {
            guard !ulItems.isEmpty else { return }
            blocks.append(.unorderedList(ulItems))
            ulItems.removeAll()
        }
        func flushOL() {
            guard !olItems.isEmpty else { return }
            blocks.append(.orderedList(olItems))
            olItems.removeAll()
        }
        func flushAll() {
            flushParagraph(); flushUL(); flushOL()
        }

        for raw in lines {
            // Bloc code
            if raw.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuffer.append(raw)
                continue
            }

            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Ligne vide = sépare les blocs
            if trimmed.isEmpty {
                flushAll()
                continue
            }

            // Règle horizontale
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAll()
                blocks.append(.rule)
                continue
            }

            // Titres
            if let heading = parseHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.0, content: heading.1))
                continue
            }

            // Item de liste à puces
            if let item = parseUnorderedItem(trimmed) {
                flushParagraph(); flushOL()
                ulItems.append(item)
                continue
            }

            // Item de liste numérotée
            if let item = parseOrderedItem(trimmed) {
                flushParagraph(); flushUL()
                olItems.append(item)
                continue
            }

            // Ligne ordinaire : continuation du paragraphe (ou nouvelle liste)
            flushUL(); flushOL()
            paragraphLines.append(trimmed)
        }

        if inCode && !codeBuffer.isEmpty {
            blocks.append(.code(codeBuffer.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        var i = line.startIndex
        while i < line.endIndex, line[i] == "#" {
            level += 1
            i = line.index(after: i)
        }
        guard level >= 1, level <= 6, i < line.endIndex, line[i] == " " else { return nil }
        let content = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
        return (level, content)
    }

    private static func parseUnorderedItem(_ line: String) -> String? {
        let bullets = ["- ", "* ", "+ "]
        for b in bullets where line.hasPrefix(b) {
            return String(line.dropFirst(b.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseOrderedItem(_ line: String) -> String? {
        // Détecte "1. ", "10. ", etc.
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber {
            idx = line.index(after: idx)
            digits += 1
        }
        guard digits >= 1, idx < line.endIndex, line[idx] == "." else { return nil }
        let after = line.index(after: idx)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return String(line[line.index(after: after)...]).trimmingCharacters(in: .whitespaces)
    }
}
