import Foundation

/// How much the clock says.
enum ClockFormat: String, Codable, CaseIterable, Sendable {
    case time
    case timeAndDay
    case full

    var title: String {
        switch self {
        case .time: String(localized: "Time", comment: "Clock shows the time only")
        case .timeAndDay: String(localized: "Day and Time", comment: "Clock shows the weekday and the time")
        case .full: String(
            localized: "Day, Date and Time", comment: "Clock shows the weekday, the date and the time")
        }
    }
}

/// Digital text or a drawn dial.
enum ClockStyle: String, Codable, CaseIterable, Sendable {
    case digital
    case analog

    var title: String {
        switch self {
        case .digital: String(localized: "Digital", comment: "Clock drawn as numbers")
        case .analog: String(localized: "Dial", comment: "Clock drawn as a face with hands")
        }
    }
}

/// What the clock cell reads.
///
/// Pure and separated from the drawing because the interesting part is not the drawing: it is that
/// the format has to be the *user's* — 24-hour or not, day before month or after — and that a bar
/// one icon wide going down the side of the screen has nowhere to put "Thursday 3 September".
enum ClockContent {
    /// Built from templates rather than fixed patterns, so `HH:mm` becomes `h:mm a` for someone
    /// whose region uses a 12-hour clock, and `d MMM` becomes `MMM d` for someone whose does not.
    /// This is what makes the clock agree with the one in the menu bar.
    static func lines(
        at date: Date,
        format: ClockFormat,
        isVertical: Bool,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [String] {
        let time = string(from: date, template: "jmm", locale: locale, timeZone: timeZone)

        // A side bar is one icon wide. There is nowhere to put a date, so it shows the time on
        // two short lines and nothing else — the alternative is an ellipsis where the clock was.
        guard !isVertical else {
            return time
                .split(separator: ":", maxSplits: 1)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }

        switch format {
        case .time:
            return [time]
        case .timeAndDay:
            return ["\(string(from: date, template: "EEE", locale: locale, timeZone: timeZone))  \(time)"]
        case .full:
            let day = string(from: date, template: "EEEdMMM", locale: locale, timeZone: timeZone)
            return ["\(day)  \(time)"]
        }
    }

    /// One line, for a tooltip or an accessibility label.
    static func description(
        at date: Date, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        let day = string(from: date, template: "EEEEdMMMM", locale: locale, timeZone: timeZone)
        let time = string(from: date, template: "jmm", locale: locale, timeZone: timeZone)
        return "\(day)  \(time)"
    }

    private static func string(
        from date: Date, template: String, locale: Locale, timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    // MARK: - Dial geometry

    /// How far round the face each hand has travelled, as a fraction of a full turn clockwise from
    /// twelve.
    ///
    /// The hour hand moves continuously: at half past three it is halfway between three and four,
    /// not still pointing at three. A dial whose hour hand jumps between the numerals reads as
    /// broken.
    static func handTurns(hour: Int, minute: Int) -> (hour: Double, minute: Double) {
        let minutes = Double(((minute % 60) + 60) % 60)
        let hours = Double(((hour % 12) + 12) % 12) + minutes / 60
        return (hours / 12, minutes / 60)
    }

    /// A unit vector for a hand that far round the face, in view coordinates — x to the right, y
    /// upwards.
    ///
    /// Twelve is up and the hands run clockwise, which is the opposite of both conventions the maths
    /// hands you: radians start at three o'clock and increase anticlockwise. Getting either of those
    /// backwards produces a dial that looks plausible and tells the wrong time, which is why this is
    /// a function with tests rather than three lines inside a `draw`.
    static func handVector(turns: Double) -> CGPoint {
        let radians = .pi / 2 - turns * 2 * .pi
        return CGPoint(x: cos(radians), y: sin(radians))
    }

    /// When the reading next changes. The clock shows minutes, so it has nothing to do until the
    /// next one — a timer ticking every second would redraw the bar sixty times for each change.
    static func nextMinute(after date: Date, calendar: Calendar = .current) -> Date {
        let next = calendar.nextDate(
            after: date,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime)
        // A second past the boundary, so a timer that fires a hair early still reads the new minute.
        return (next ?? date.addingTimeInterval(60)).addingTimeInterval(0.5)
    }
}
