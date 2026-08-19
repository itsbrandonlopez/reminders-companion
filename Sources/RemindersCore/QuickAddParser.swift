import Foundation

/// What a line of quick-add text resolved to.
public struct QuickAddParse: Equatable, Sendable {
    /// The text left after removing anything that was interpreted. Never empty unless the
    /// whole input was tokens.
    public var title: String
    public var priority: Priority?
    /// The raw text after `#`, unresolved — the parser deliberately knows nothing about
    /// which lists exist. Resolve with `QuickAddParser.matchList(_:in:)`.
    public var listToken: String?
    public var day: Day?

    public init(
        title: String, priority: Priority? = nil, listToken: String? = nil, day: Day? = nil
    ) {
        self.title = title
        self.priority = priority
        self.listToken = listToken
        self.day = day
    }
}

/// Interprets `!` priority, `#list`, and natural-language dates in quick-add text.
///
/// The governing principle is that a wrong guess is worse than no guess. Silently eating a
/// real word out of someone's task title — turning "Prep Tuesday's invoice" into "Prep
/// invoice" — is a worse failure than simply not parsing it, because the damage is
/// invisible until they go looking for the task later. So:
///
/// - **Sigil tokens (`!`, `#`) may appear anywhere**, since nothing else in a task title
///   plausibly looks like a standalone `!!!` or a `#word`.
/// - **Date phrases are only recognised at the very start or end of the input.** A date
///   word in the middle of a sentence is part of the sentence. This is the rule that keeps
///   "Prep Tuesday's invoice" and "Move the Friday meeting" intact.
public enum QuickAddParser {

    public static func parse(
        _ input: String, today: Day = .today(), calendar: Calendar = .current
    ) -> QuickAddParse {
        var words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var result = QuickAddParse(title: "")

        // Sigils first — they're unambiguous and can be lifted from anywhere.
        var kept: [String] = []
        for word in words {
            if let priority = priorityToken(word), result.priority == nil {
                result.priority = priority
            } else if let list = listToken(word), result.listToken == nil {
                result.listToken = list
            } else {
                kept.append(word)
            }
        }
        words = kept

        // Then dates, edge-anchored only.
        if let (day, range) = dateAtEdges(of: words, today: today, calendar: calendar) {
            result.day = day
            words.removeSubrange(range)
        }

        result.title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result
    }

    /// Resolves a `#token` against real list names, ignoring case, spaces and diacritics,
    /// so `#cafelopez` finds "Café Lopez". Exact match wins over a prefix match, so a
    /// token that fully names one list is never stolen by a longer one.
    public static func matchList(_ token: String, in lists: [TaskList]) -> TaskList? {
        let needle = normalize(token)
        guard !needle.isEmpty else { return nil }
        if let exact = lists.first(where: { normalize($0.title) == needle }) { return exact }
        return lists.first { normalize($0.title).hasPrefix(needle) }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { !$0.isWhitespace }
    }

    // MARK: - Priority

    /// `!` low, `!!` medium, `!!!` high — but only as a standalone word. "Wow!" is one
    /// word ending in a bang, not a priority token, and stays in the title.
    private static func priorityToken(_ word: String) -> Priority? {
        guard !word.isEmpty, word.allSatisfy({ $0 == "!" }) else { return nil }
        switch word.count {
        case 1: return .low
        case 2: return .medium
        default: return .high
        }
    }

    // MARK: - List

    /// `#freelance` names a list. `#423` does not.
    ///
    /// A list token must contain a letter. Issue numbers, invoice numbers and order numbers
    /// are written exactly like this — "Fix login bug #423", "Chase invoice #7" — and
    /// treating them as list names silently ate them out of the title, leaving a token that
    /// matches nothing and a task filed in the default list anyway. That is the same damage
    /// the edge-anchoring rule exists to prevent for date words: a wrong guess is worse than
    /// no guess, because it is invisible until you go looking for the task.
    private static func listToken(_ word: String) -> String? {
        guard word.hasPrefix("#") else { return nil }
        let token = String(word.dropFirst())
        guard token.contains(where: \.isLetter) else { return nil }
        return token
    }

    // MARK: - Dates

    /// Looks for a date phrase anchored to the start or the end of the words, longest
    /// first so "next monday" wins over a bare "monday".
    private static func dateAtEdges(
        of words: [String], today: Day, calendar: Calendar
    ) -> (Day, Range<Int>)? {
        guard !words.isEmpty else { return nil }
        let maxPhrase = 3

        // Trailing first: "call bob tomorrow" is the far more common shape than
        // "tomorrow call bob".
        for length in stride(from: min(maxPhrase, words.count), through: 1, by: -1) {
            let range = (words.count - length)..<words.count
            if let day = day(from: Array(words[range]), today: today, calendar: calendar) {
                return (day, range)
            }
        }
        for length in stride(from: min(maxPhrase, words.count), through: 1, by: -1) {
            let range = 0..<length
            // A phrase that is the entire input is still worth honouring — the resulting
            // empty title is the caller's problem to reject, not a reason to misparse.
            if let day = day(from: Array(words[range]), today: today, calendar: calendar) {
                return (day, range)
            }
        }
        return nil
    }

    private static func day(from phrase: [String], today: Day, calendar: Calendar) -> Day? {
        let text = phrase.joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            // Trailing punctuation shouldn't defeat a match: "...tomorrow," still parses.
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))

        switch text {
        case "today", "tonight": return today
        case "tomorrow", "tmw", "tmrw": return today.adding(days: 1)
        case "yesterday": return today.adding(days: -1)
        case "next week": return today.adding(days: 7)
        case "in a week", "in one week": return today.adding(days: 7)
        default: break
        }

        // "next monday" — the named weekday in the week after the coming one.
        if text.hasPrefix("next "), let weekday = weekdayIndex(String(text.dropFirst(5))) {
            return nextOccurrence(of: weekday, after: today, calendar: calendar, skippingAWeek: true)
        }
        // Bare "monday" — the next time that weekday comes round, always in the future, so
        // typing "monday" on a Monday means the one coming up rather than today.
        if let weekday = weekdayIndex(text) {
            return nextOccurrence(of: weekday, after: today, calendar: calendar, skippingAWeek: false)
        }
        // "in 3 days"
        if text.hasPrefix("in "), text.hasSuffix(" days") || text.hasSuffix(" day") {
            let middle = text.dropFirst(3).split(separator: " ").first.map(String.init) ?? ""
            if let n = Int(middle), n > 0, n < 3650 { return today.adding(days: n) }
        }
        return nil
    }

    /// 1 = Sunday, matching `Calendar`'s own weekday numbering.
    private static func weekdayIndex(_ text: String) -> Int? {
        switch text {
        case "sunday", "sun": return 1
        case "monday", "mon": return 2
        case "tuesday", "tue", "tues": return 3
        case "wednesday", "wed": return 4
        case "thursday", "thu", "thur", "thurs": return 5
        case "friday", "fri": return 6
        case "saturday", "sat": return 7
        default: return nil
        }
    }

    private static func nextOccurrence(
        of weekday: Int, after today: Day, calendar: Calendar, skippingAWeek: Bool
    ) -> Day {
        var cal = calendar
        cal.timeZone = .current
        let current = cal.component(.weekday, from: today.startOfDay())
        var delta = (weekday - current + 7) % 7
        if delta == 0 { delta = 7 }          // never "today"
        if skippingAWeek { delta += 7 }
        return today.adding(days: delta)
    }
}
