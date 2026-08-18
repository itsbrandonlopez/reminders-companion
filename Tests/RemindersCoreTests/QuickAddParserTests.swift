import XCTest
@testable import RemindersCore

final class QuickAddParserTests: XCTestCase {

    /// Tuesday 18 August 2026, matching the dates used across the other suites.
    private let today = Day(year: 2026, month: 8, day: 18)

    private func parse(_ s: String) -> QuickAddParse {
        QuickAddParser.parse(s, today: today)
    }

    // MARK: - Plain text

    func testPlainTitleIsUntouched() {
        let r = parse("Call the venue back")
        XCTAssertEqual(r.title, "Call the venue back")
        XCTAssertNil(r.priority)
        XCTAssertNil(r.day)
        XCTAssertNil(r.listToken)
    }

    // MARK: - Priority

    func testPriorityTokens() {
        XCTAssertEqual(parse("Pay invoice !").priority, .low)
        XCTAssertEqual(parse("Pay invoice !!").priority, .medium)
        XCTAssertEqual(parse("Pay invoice !!!").priority, .high)
        XCTAssertEqual(parse("Pay invoice !!!").title, "Pay invoice")
    }

    func testPriorityAnywhereInTheLine() {
        let r = parse("!! Pay the invoice")
        XCTAssertEqual(r.priority, .medium)
        XCTAssertEqual(r.title, "Pay the invoice")
    }

    /// The case that matters: an exclamation attached to a word is punctuation, not a
    /// token, and must survive into the title.
    func testTrailingBangOnAWordIsNotAPriority() {
        let r = parse("Ship it!")
        XCTAssertNil(r.priority)
        XCTAssertEqual(r.title, "Ship it!")
    }

    func testEmphaticWordIsNotAPriority() {
        let r = parse("Wow!!! that deadline")
        XCTAssertNil(r.priority)
        XCTAssertEqual(r.title, "Wow!!! that deadline")
    }

    func testOnlyTheFirstPriorityTokenCounts() {
        // A second standalone token is unusual enough that keeping it visible in the title
        // is more honest than silently picking one.
        let r = parse("Do it !! !!!")
        XCTAssertEqual(r.priority, .medium)
        // The unconsumed second token stays visible rather than being silently discarded.
        XCTAssertEqual(r.title, "Do it !!!")
    }

    // MARK: - List tokens

    func testListToken() {
        let r = parse("Send the quote #Freelance")
        XCTAssertEqual(r.listToken, "Freelance")
        XCTAssertEqual(r.title, "Send the quote")
    }

    func testBareHashIsNotAListToken() {
        let r = parse("Track issue # 42")
        XCTAssertNil(r.listToken)
        XCTAssertEqual(r.title, "Track issue # 42")
    }

    func testListMatchingIgnoresCaseSpacesAndDiacritics() {
        let lists = [
            TaskList(id: "1", title: "Café Lopez", color: .neutral, isEditable: true, isDefault: false),
            TaskList(id: "2", title: "Freelance", color: .neutral, isEditable: true, isDefault: false),
        ]
        XCTAssertEqual(QuickAddParser.matchList("cafelopez", in: lists)?.id, "1")
        XCTAssertEqual(QuickAddParser.matchList("CAFELOPEZ", in: lists)?.id, "1")
        XCTAssertEqual(QuickAddParser.matchList("free", in: lists)?.id, "2")
        XCTAssertNil(QuickAddParser.matchList("nothing", in: lists))
    }

    func testExactListMatchBeatsAPrefixMatch() {
        let lists = [
            TaskList(id: "long", title: "Work Archive", color: .neutral, isEditable: true, isDefault: false),
            TaskList(id: "short", title: "Work", color: .neutral, isEditable: true, isDefault: false),
        ]
        XCTAssertEqual(QuickAddParser.matchList("work", in: lists)?.id, "short")
    }

    // MARK: - Dates

    func testTodayAndTomorrow() {
        XCTAssertEqual(parse("Call Bob today").day, today)
        XCTAssertEqual(parse("Call Bob tonight").day, today)
        XCTAssertEqual(parse("Call Bob tomorrow").day, today.adding(days: 1))
        XCTAssertEqual(parse("Call Bob tmw").day, today.adding(days: 1))
    }

    func testDatePhraseIsStrippedFromTheTitle() {
        XCTAssertEqual(parse("Call Bob tomorrow").title, "Call Bob")
        XCTAssertEqual(parse("tomorrow Call Bob").title, "Call Bob")
    }

    func testNextWeekAndRelativeDays() {
        XCTAssertEqual(parse("Invoice next week").day, today.adding(days: 7))
        XCTAssertEqual(parse("Invoice in a week").day, today.adding(days: 7))
        XCTAssertEqual(parse("Invoice in 3 days").day, today.adding(days: 3))
        XCTAssertEqual(parse("Invoice in 1 day").day, today.adding(days: 1))
    }

    /// Today is a Tuesday, so a bare "tuesday" means the one coming up, never today.
    func testBareWeekdayIsAlwaysInTheFuture() {
        XCTAssertEqual(parse("Standup tuesday").day, today.adding(days: 7))
        XCTAssertEqual(parse("Standup thursday").day, today.adding(days: 2))
        XCTAssertEqual(parse("Standup monday").day, today.adding(days: 6))
    }

    func testNextWeekdaySkipsAWeek() {
        XCTAssertEqual(parse("Review next thursday").day, today.adding(days: 9))
        XCTAssertEqual(parse("Review next tuesday").day, today.adding(days: 14))
    }

    func testTrailingPunctuationDoesNotDefeatADate() {
        XCTAssertEqual(parse("Call Bob tomorrow.").day, today.adding(days: 1))
    }

    // MARK: - The rule that protects real titles

    /// A date word in the middle of a sentence is part of the sentence. These are the
    /// cases a naive parser silently corrupts.
    func testMidSentenceDateWordsAreLeftAlone() {
        let r = parse("Prep Tuesday's invoice")
        XCTAssertNil(r.day)
        XCTAssertEqual(r.title, "Prep Tuesday's invoice")
    }

    func testMidSentenceWeekdayIsLeftAlone() {
        let r = parse("Move the Friday meeting to another slot")
        XCTAssertNil(r.day)
        XCTAssertEqual(r.title, "Move the Friday meeting to another slot")
    }

    func testMidSentenceTomorrowIsLeftAlone() {
        let r = parse("Ask about tomorrow plans with Sam")
        XCTAssertNil(r.day)
        XCTAssertEqual(r.title, "Ask about tomorrow plans with Sam")
    }

    // MARK: - Combinations and edges

    func testEverythingAtOnce() {
        let r = parse("!! Send the revised quote #Freelance tomorrow")
        XCTAssertEqual(r.priority, .medium)
        XCTAssertEqual(r.listToken, "Freelance")
        XCTAssertEqual(r.day, today.adding(days: 1))
        XCTAssertEqual(r.title, "Send the revised quote")
    }

    func testTokensOnlyLeavesAnEmptyTitle() {
        // The caller rejects this; the parser's job is only to report it faithfully.
        let r = parse("!!! tomorrow")
        XCTAssertEqual(r.title, "")
        XCTAssertEqual(r.priority, .high)
        XCTAssertEqual(r.day, today.adding(days: 1))
    }

    func testEmptyAndWhitespaceInput() {
        XCTAssertEqual(parse("").title, "")
        XCTAssertEqual(parse("   ").title, "")
        XCTAssertNil(parse("   ").day)
    }

    func testExtraWhitespaceIsCollapsed() {
        XCTAssertEqual(parse("Call    Bob   tomorrow").title, "Call Bob")
    }

    func testCaseInsensitiveDates() {
        XCTAssertEqual(parse("Call Bob TOMORROW").day, today.adding(days: 1))
        XCTAssertEqual(parse("Call Bob Next Week").day, today.adding(days: 7))
    }

    func testImplausibleDayCountIsIgnored() {
        let r = parse("Retro in 99999 days")
        XCTAssertNil(r.day)
        XCTAssertEqual(r.title, "Retro in 99999 days")
    }
}
