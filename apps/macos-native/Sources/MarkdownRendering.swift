import SwiftUI

struct MarkdownBody: View {
    let content: String
    var baseFontSize: CGFloat = 12
    var fillsWidth = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownRenderCache.shared.blocks(from: content).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, baseFontSize: baseFontSize)
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class MarkdownRenderCache {
    static let shared = MarkdownRenderCache()
    private let cache = NSCache<NSString, MarkdownBlockBox>()

    private init() {
        cache.countLimit = 360
    }

    func blocks(from content: String) -> [MarkdownBlock] {
        let key = content as NSString
        if let cached = cache.object(forKey: key) {
            return cached.blocks
        }
        let blocks = MarkdownParser.blocks(from: content)
        cache.setObject(MarkdownBlockBox(blocks), forKey: key)
        return blocks
    }
}

final class MarkdownBlockBox {
    let blocks: [MarkdownBlock]

    init(_ blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let baseFontSize: CGFloat

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(.system(size: baseFontSize + (level == 1 ? 4 : 2), weight: .semibold))
                .foregroundStyle(DeckColor.text)
                .padding(.top, level == 1 ? 4 : 2)
                .textSelection(.enabled)
        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.system(size: baseFontSize, weight: .regular))
                .foregroundStyle(DeckColor.text)
                .lineSpacing(4)
                .textSelection(.enabled)
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(DeckColor.border)
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: baseFontSize, weight: .regular))
                    .foregroundStyle(DeckColor.muted)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        case let .list(items, ordered, checked):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker(index: index, ordered: ordered, checked: checked[index]))
                            .font(.system(size: baseFontSize, weight: .regular))
                            .foregroundStyle(DeckColor.muted)
                            .frame(width: ordered ? 24 : 16, alignment: .trailing)
                        Text(inlineMarkdown(item))
                            .font(.system(size: baseFontSize, weight: .regular))
                            .foregroundStyle(DeckColor.text)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
            }
        case let .code(language, code):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if !language.isEmpty {
                        Text(language)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DeckColor.muted)
                    }
                    Spacer()
                    CopyMessageButton(content: code)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(DeckColor.codeHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(highlightedCode(code, language: language))
                        .font(.system(size: baseFontSize, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .background(DeckColor.codeBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DeckColor.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case let .table(rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(normalizedRows(rows).enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                tableCell(cell, isHeader: rowIndex == 0)
                            }
                        }
                    }
                }
                .background(DeckColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DeckColor.border, lineWidth: 1)
                }
            }
        case .separator:
            Rectangle()
                .fill(DeckColor.border)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func tableCell(_ cell: String, isHeader: Bool) -> some View {
        ZStack(alignment: .leading) {
            (isHeader ? DeckColor.tableHeader : Color.clear)
            Text(inlineMarkdown(cell))
                .font(.system(size: baseFontSize, weight: isHeader ? .semibold : .regular))
                .foregroundStyle(isHeader ? DeckColor.headerText : DeckColor.text)
                .lineLimit(nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 120, maxWidth: 260, alignment: .leading)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DeckColor.border)
                .frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DeckColor.border)
                .frame(height: 0.5)
        }
    }

    private func normalizedRows(_ rows: [[String]]) -> [[String]] {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { row in
            if row.count >= width { return row }
            return row + Array(repeating: "", count: width - row.count)
        }
    }

    private func highlightedCode(_ code: String, language: String) -> AttributedString {
        var result = AttributedString()
        let keywords = syntaxKeywords(language: language)
        let lines = code.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            result += highlightedLine(line, keywords: keywords)
            if lineIndex < lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private func highlightedLine(_ line: String, keywords: Set<String>) -> AttributedString {
        let commentStart = findCommentStart(in: line)
        let codePart = commentStart.map { String(line[..<$0]) } ?? line
        let commentPart = commentStart.map { String(line[$0...]) }
        var output = highlightCodePart(codePart, keywords: keywords)
        if let commentPart {
            var comment = AttributedString(commentPart)
            comment.foregroundColor = DeckColor.codeComment
            output += comment
        }
        return output
    }

    private func highlightCodePart(_ line: String, keywords: Set<String>) -> AttributedString {
        var output = AttributedString()
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if char == "\"" || char == "'" {
                let end = scanStringEnd(in: line, from: index, quote: char)
                var token = AttributedString(String(line[index...end]))
                token.foregroundColor = DeckColor.codeString
                output += token
                index = line.index(after: end)
            } else if char.isNumber {
                let end = line[index...].firstIndex { !$0.isNumber && $0 != "." } ?? line.endIndex
                var token = AttributedString(String(line[index..<end]))
                token.foregroundColor = DeckColor.codeNumber
                output += token
                index = end
            } else if char.isLetter || char == "_" {
                let end = line[index...].firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? line.endIndex
                let word = String(line[index..<end])
                var token = AttributedString(word)
                token.foregroundColor = keywords.contains(word) ? DeckColor.codeKeyword : DeckColor.text
                output += token
                index = end
            } else {
                var token = AttributedString(String(char))
                token.foregroundColor = DeckColor.text
                output += token
                index = line.index(after: index)
            }
        }
        return output
    }

    private func findCommentStart(in line: String) -> String.Index? {
        if let swift = line.range(of: "//")?.lowerBound {
            return swift
        }
        return line.range(of: "#")?.lowerBound
    }

    private func scanStringEnd(in line: String, from start: String.Index, quote: Character) -> String.Index {
        var index = line.index(after: start)
        var escaped = false
        while index < line.endIndex {
            let char = line[index]
            if char == quote && !escaped {
                return index
            }
            escaped = char == "\\" && !escaped
            if char != "\\" { escaped = false }
            index = line.index(after: index)
        }
        return line.index(before: line.endIndex)
    }

    private func syntaxKeywords(language: String) -> Set<String> {
        let common: Set<String> = [
            "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "default", "do", "else", "enum", "export", "false", "for", "from", "func",
            "function", "guard", "if", "import", "in", "let", "nil", "null", "private",
            "public", "return", "static", "struct", "switch", "throw", "throws", "true",
            "try", "type", "var", "while"
        ]
        if language.lowercased().contains("sql") {
            return common.union(["select", "from", "where", "insert", "update", "delete", "join", "left", "right", "group", "order", "by", "limit"])
        }
        return common
    }

    private func marker(index: Int, ordered: Bool, checked: Bool?) -> String {
        if let checked {
            return checked ? "☑" : "☐"
        }
        return ordered ? "\(index + 1)." : "•"
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case list(items: [String], ordered: Bool, checked: [Bool?])
    case code(language: String, code: String)
    case table([[String]])
    case separator
}

enum MarkdownParser {
    static func blocks(from content: String) -> [MarkdownBlock] {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listChecks: [Bool?] = []
        var listOrdered = false
        var inCode = false
        var codeLanguage = ""
        var codeLines: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        func flushList() {
            if !listItems.isEmpty {
                blocks.append(.list(items: listItems, ordered: listOrdered, checked: listChecks))
            }
            listItems.removeAll()
            listChecks.removeAll()
            listOrdered = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inCode {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    inCode = false
                    codeLanguage = ""
                    codeLines.removeAll()
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                inCode = true
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if trimmed == "---" || trimmed == "⸻" {
                flushParagraph()
                flushList()
                blocks.append(.separator)
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if let item = parseListItem(trimmed) {
                flushParagraph()
                if listItems.isEmpty {
                    listOrdered = item.ordered
                } else if listOrdered != item.ordered {
                    flushList()
                    listOrdered = item.ordered
                }
                listItems.append(item.text)
                listChecks.append(item.checked)
                continue
            }

            if isTableLine(trimmed) {
                flushParagraph()
                flushList()
                let row = parseTableRow(trimmed)
                if !row.isEmpty {
                    blocks.append(.table([row]))
                }
                continue
            }

            flushList()
            paragraph.append(line)
        }

        if inCode {
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        flushList()
        return mergeTables(blocks)
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func parseListItem(_ line: String) -> (ordered: Bool, checked: Bool?, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let raw = String(line.dropFirst(marker.count))
            let parsed = parseTask(raw)
            return (false, parsed.checked, parsed.text)
        }
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let after = line[line.index(after: dot)...]
        guard after.first == " " else { return nil }
        return (true, nil, String(after.dropFirst()))
    }

    private static func parseTask(_ value: String) -> (checked: Bool?, text: String) {
        if value.hasPrefix("[x] ") || value.hasPrefix("[X] ") {
            return (true, String(value.dropFirst(4)))
        }
        if value.hasPrefix("[ ] ") {
            return (false, String(value.dropFirst(4)))
        }
        return (nil, value)
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.contains("|")
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ row: [String]) -> Bool {
        !row.isEmpty && row.allSatisfy { cell in
            let clean = cell.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            return clean.trimmingCharacters(in: .whitespaces).isEmpty && cell.contains("-")
        }
    }

    private static func mergeTables(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        var merged: [MarkdownBlock] = []
        var pendingRows: [[String]] = []
        for block in blocks {
            if case let .table(rows) = block {
                pendingRows.append(contentsOf: rows)
                continue
            }
            flushRows(&pendingRows, into: &merged)
            merged.append(block)
        }
        flushRows(&pendingRows, into: &merged)
        return merged
    }

    private static func flushRows(_ rows: inout [[String]], into blocks: inout [MarkdownBlock]) {
        guard !rows.isEmpty else { return }
        let filtered = rows.filter { !isTableSeparator($0) }
        if !filtered.isEmpty {
            blocks.append(.table(filtered))
        }
        rows.removeAll()
    }
}
