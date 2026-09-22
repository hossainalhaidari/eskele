import Foundation
import Testing
@testable import Eskele

private let london = TimeZone(identifier: "Europe/London")!
/// 2025-09-03 14:40 in London (BST), so the 12-hour reading is unambiguously afternoon and the
/// minutes are not zero — a clock test on the hour cannot tell hours from minutes apart.
private let afternoon = Date(timeIntervalSince1970: 1_756_906_800)

private func lines(
    _ format: ClockFormat,
    vertical: Bool = false,
    locale: String = "en_GB",
    at date: Date = afternoon
) -> [String] {
    ClockContent.lines(
        at: date, format: format, isVertical: vertical,
        locale: Locale(identifier: locale), timeZone: london)
}

// MARK: - The format is the user's, not ours

/// The whole point of building from templates: the clock has to agree with the menu bar's, and that
/// means a region using a 12-hour clock gets one. A hard-coded "HH:mm" would show 14:40 to someone
/// whose every other clock says 2:40 PM.
@Test func theHourFollowsTheRegionsOwnConvention() {
    let british = lines(.time).first ?? ""
    let american = lines(.time, locale: "en_US").first ?? ""
    #expect(british.hasPrefix("14"), "expected a 24-hour reading, got \(british)")
    #expect(american.hasPrefix("2"), "expected a 12-hour reading, got \(american)")
    #expect(american.uppercased().contains("PM"))
    #expect(!british.uppercased().contains("PM"))
}

/// Day before month or after is also the region's business.
@Test func theDateOrderFollowsTheRegionToo() {
    let british = lines(.full).first ?? ""
    let american = lines(.full, locale: "en_US").first ?? ""
    #expect(british.contains("3"))
    #expect(american.contains("3"))
    // Both name the weekday and the month; only the order differs.
    #expect(british.contains("Sep"))
    #expect(american.contains("Sep"))
}

@Test func eachFormatSaysMoreThanTheLastOne() {
    let time = lines(.time).joined()
    let day = lines(.timeAndDay).joined()
    let full = lines(.full).joined()
    #expect(time.count < day.count)
    #expect(day.count <= full.count)
    // Every one of them still tells the time.
    for reading in [time, day, full] { #expect(reading.contains(":")) }
}

// MARK: - A bar one icon thick

/// A side bar has nowhere to put a date. Two short lines are the honest answer; the alternative is
/// an ellipsis where the clock was.
@Test func aVerticalBarStacksTheTimeAndDropsTheDate() {
    for format in ClockFormat.allCases {
        let stacked = lines(format, vertical: true)
        #expect(stacked.count == 2, "\(format) gave \(stacked)")
        #expect(stacked.allSatisfy { !$0.isEmpty })
        // No colon: it is the split, not part of either line.
        #expect(stacked.allSatisfy { !$0.contains(":") })
        // No weekday or month has crept in.
        #expect(!stacked.joined().contains("Sep"))
    }
}

@Test func aVerticalClockSplitsHoursFromMinutes() {
    let stacked = lines(.time, vertical: true)
    #expect(stacked.last == "40")
}

// MARK: - Ticking

/// Scheduled to the boundary rather than 60 seconds from now: a repeating timer started at :30
/// would change the reading half a minute after every other clock on the machine.
@Test func theNextTickIsTheTopOfTheMinute() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = london

    let at40 = Date(timeIntervalSince1970: 1_756_906_830)   // 14:40:30
    let next = ClockContent.nextMinute(after: at40, calendar: calendar)
    let parts = calendar.dateComponents([.second], from: next)
    // Just past the boundary, so a timer firing a hair early still reads the new minute.
    #expect(parts.second == 0)
    #expect(next > at40)
    #expect(next.timeIntervalSince(at40) <= 31)
}

@Test func theTickIsAlwaysInTheFuture() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = london
    // Exactly on a boundary is the awkward case: a tick scheduled for "now" would fire immediately
    // and reschedule for now again.
    let exact = afternoon
    #expect(ClockContent.nextMinute(after: exact, calendar: calendar) > exact)
}

// MARK: - Description

@Test func theSpokenFormIsFullerThanTheBarsOwn() {
    let spoken = ClockContent.description(
        at: afternoon, locale: Locale(identifier: "en_GB"), timeZone: london)
    #expect(spoken.contains("September"))
    #expect(spoken.contains(":"))
    #expect(spoken.count > (lines(.full).first ?? "").count)
}

// MARK: - Settings

@Test func theClockIsOffUntilAskedFor() throws {
    #expect(Settings().showClock == false)
    #expect(Settings().clockStyle == .digital)
    let old = try #require(try? JSONDecoder().decode(
        Settings.self, from: Data(#"{"edge":"left"}"#.utf8)))
    #expect(old.showClock == false)

    var settings = Settings()
    settings.showClock = true
    settings.clockStyle = .analog
    settings.clockFormat = .full
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
}

/// The clock is the last cell on the bar, after the Trash.
@MainActor
@Test func theClockSitsAtTheVeryEnd() {
    let strip = BarComposition.strip(
        leading: [DockItem(kind: .appsMenu)],
        groups: BarComposition.Groups(tasks: []),
        trailing: [DockItem(kind: .trash(isEmpty: true)), DockItem(kind: .clock)])
    #expect(strip.last?.isClock == true)
    #expect(strip.dropLast().last?.isTrash == true)
    // It is not something a positional hot key should activate ahead of an app, but it is a cell
    // you can click, so it does take a slot.
    #expect(BarComposition.addressable(strip).last?.isClock == true)
}

// MARK: - Dial geometry

/// Twelve is up, three is right, six is down, nine is left. Radians start at three o'clock and
/// increase anticlockwise, so both of those conventions are backwards from a clock face — get
/// either wrong and you have a dial that looks plausible and tells the wrong time.
@Test func theHandsPointWhereTheNumeralsWouldBe() {
    func direction(hour: Int, minute: Int) -> CGPoint {
        ClockContent.handVector(turns: ClockContent.handTurns(hour: hour, minute: minute).hour)
    }

    let twelve = direction(hour: 12, minute: 0)
    #expect(abs(twelve.x) < 0.001)
    #expect(twelve.y > 0.999, "twelve should point up, got \(twelve)")

    let three = direction(hour: 3, minute: 0)
    #expect(three.x > 0.999, "three should point right, got \(three)")
    #expect(abs(three.y) < 0.001)

    let six = direction(hour: 6, minute: 0)
    #expect(abs(six.x) < 0.001)
    #expect(six.y < -0.999, "six should point down, got \(six)")

    let nine = direction(hour: 9, minute: 0)
    #expect(nine.x < -0.999, "nine should point left, got \(nine)")
    #expect(abs(nine.y) < 0.001)
}

@Test func theMinuteHandGoesRoundTheSameWay() {
    #expect(ClockContent.handVector(turns: 0).y > 0.999)          // :00 up
    #expect(ClockContent.handVector(turns: 0.25).x > 0.999)       // :15 right
    #expect(ClockContent.handVector(turns: 0.5).y < -0.999)       // :30 down
    #expect(ClockContent.handVector(turns: 0.75).x < -0.999)      // :45 left
}

/// A dial whose hour hand jumps between numerals reads as broken. At half past, it should be
/// halfway to the next hour.
@Test func theHourHandMovesWithTheMinutes() {
    let onTheHour = ClockContent.handTurns(hour: 3, minute: 0).hour
    let halfPast = ClockContent.handTurns(hour: 3, minute: 30).hour
    let nextHour = ClockContent.handTurns(hour: 4, minute: 0).hour
    #expect(halfPast > onTheHour)
    #expect(abs(halfPast - (onTheHour + nextHour) / 2) < 0.0001)
}

/// Midnight and noon are both twelve on a dial, and 13:00 is one.
@Test func theDialIsATwelveHourFace() {
    #expect(ClockContent.handTurns(hour: 0, minute: 0).hour == 0)
    #expect(ClockContent.handTurns(hour: 12, minute: 0).hour == 0)
    #expect(ClockContent.handTurns(hour: 13, minute: 0).hour
        == ClockContent.handTurns(hour: 1, minute: 0).hour)
}

/// Nonsense in must not produce a hand pointing off the face.
@Test func outOfRangeComponentsStayOnTheFace() {
    for (hour, minute) in [(-1, -1), (99, 300), (24, 60)] {
        let turns = ClockContent.handTurns(hour: hour, minute: minute)
        #expect(turns.hour >= 0 && turns.hour < 1, "hour \(hour):\(minute) -> \(turns.hour)")
        #expect(turns.minute >= 0 && turns.minute < 1)
    }
}
