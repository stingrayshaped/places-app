//
//  ParsedReview.swift
//  Places
//
//  Created by Raymond Yang on 9/30/26.
//


import Foundation

struct ParsedReview {
    var name: String
    var address: String
    var statements: [String]
}

/// Reads the readable text made by "Share as Text" (or similar) into a review.
enum ReviewTextImport {

    static func parse(_ text: String) -> ParsedReview? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let first = lines.first else { return nil }

        // The first line is the name, possibly with a Markdown "#" in front.
        let name = String(first.drop(while: { $0 == "#" || $0 == " " }))
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let rest = Array(lines.dropFirst())
        let hasNumbered = rest.contains { numberedText($0) != nil }

        var address = ""
        var statements: [String] = []

        if hasNumbered {
            // A line before the first numbered one is the address.
            var seenStatement = false
            for line in rest {
                if let text = numberedText(line) {
                    statements.append(text)
                    seenStatement = true
                } else if !seenStatement && address.isEmpty {
                    address = line
                }
            }
        } else {
            // No numbering: every remaining line is a statement.
            statements = rest
        }

        guard !statements.isEmpty else { return nil }
        return ParsedReview(name: name, address: address, statements: statements)
    }

    /// "12. text" or "12) text" gives "text". Anything else gives nil.
    private static func numberedText(_ line: String) -> String? {
        var index = line.startIndex
        var digits = 0
        while index < line.endIndex, line[index].isWholeNumber {
            index = line.index(after: index)
            digits += 1
        }
        guard digits > 0,
              index < line.endIndex,
              line[index] == "." || line[index] == ")" else { return nil }

        let text = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}