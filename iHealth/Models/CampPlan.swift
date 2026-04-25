import Foundation

/// One prescribed session inside a fight-camp `Challenge`. The camp's
/// `goal.target` decides how many sessions are generated; the
/// designer's specialty (or lack of one — league-level camps use a
/// balanced split) decides the type mix.
struct CampSession: Identifiable, Hashable {
    var id: UUID = UUID()
    var dayIndex: Int            // 1...N — display as "Day 3"
    var type: WorkoutType
    var title: String            // "Pad rounds", "Live rolling", etc.
    var minutes: Int
    var detail: String           // "6 × 3 min on pads, 1 min rest"
}

enum CampPlanner {
    /// Build a session plan for a camp. Returns up to `goal.target`
    /// sessions for `.workouts` camps; falls back to a 7-day default
    /// for streak / distance / elevation camps so the UI always has
    /// something concrete to show.
    static func plan(for camp: Challenge) -> [CampSession] {
        let count: Int
        switch camp.kind {
        case .workouts: count = max(1, Int(camp.goal.target))
        case .streak:   count = max(1, Int(camp.goal.target))
        default:        count = 7
        }
        let mix = sessionTypes(for: camp.designerHandle, count: count)
        return mix.enumerated().map { i, type in
            let template = template(for: type, weekIndex: i / 7)
            return CampSession(
                dayIndex: i + 1,
                type: type,
                title: template.title,
                minutes: template.minutes,
                detail: template.detail
            )
        }
    }

    // MARK: - Type mix per designer
    //
    // Order matters — we cycle through it with `i % mix.count`, so
    // putting the highest-volume type first means it lands on day 1.

    private static func sessionTypes(for designerHandle: String?, count: Int) -> [WorkoutType] {
        let pattern: [WorkoutType]
        switch designerHandle {
        // Striking specialists — Wakamatsu (pressure), Takeru (K-1),
        // Nadaka (Muay Thai), Akimoto (kickboxing).
        case "yuya_wakamatsu", "k1takeru", "nadaka", "hiro_a_16":
            pattern = [.striking, .conditioning, .striking, .grappling,
                       .striking, .recovery, .striking]
        // Grappling specialists — Ayaka, Itsuki, Aoki, Wada.
        case "ayaka_zombie", "_itsuki_h_", "shinya050983", "tatsumitsu_wada":
            pattern = [.grappling, .conditioning, .grappling, .striking,
                       .grappling, .recovery, .grappling]
        // League-level camp (no designer) or unknown designer:
        // balanced fight-week split.
        default:
            pattern = [.striking, .grappling, .conditioning, .striking,
                       .grappling, .recovery, .conditioning]
        }
        return (0..<count).map { pattern[$0 % pattern.count] }
    }

    // MARK: - Per-session copy
    //
    // Returns a small bundle of (title, minutes, detail) per session
    // type. Week index lets us escalate intensity slightly on later
    // weeks without needing a per-camp custom plan.

    private struct SessionTemplate {
        let title: String
        let minutes: Int
        let detail: String
    }

    private static func template(for type: WorkoutType, weekIndex: Int) -> SessionTemplate {
        let bump = weekIndex          // 0, 1, 2 …
        switch type {
        case .striking:
            return SessionTemplate(
                title: "Pad rounds",
                minutes: 60 + bump * 10,
                detail: "\(6 + bump) × 3 min on pads · 1 min rest · finish on the bag"
            )
        case .grappling:
            return SessionTemplate(
                title: "Live rolling",
                minutes: 75,
                detail: "Drill of the day, then \(5 + bump) × 5 min rounds from feet"
            )
        case .conditioning:
            return SessionTemplate(
                title: "Roadwork + circuits",
                minutes: 50,
                detail: "5 km easy run + 4 × 400 m fast · finishers: burpees, sprawls"
            )
        case .recovery:
            return SessionTemplate(
                title: "Mobility + sauna",
                minutes: 45,
                detail: "20 min mobility flow · 15 min easy bike · 10 min sauna"
            )
        case .mma:
            return SessionTemplate(
                title: "MMA sparring",
                minutes: 90,
                detail: "Technical rounds, all ranges. Light contact, 5 × 5 min."
            )
        case .lift:
            return SessionTemplate(
                title: "Strength block",
                minutes: 60,
                detail: "Squat / press / pull · 4 × 5 at fight-camp loads"
            )
        case .run:
            return SessionTemplate(
                title: "Roadwork",
                minutes: 45,
                detail: "8 km steady · last km hard"
            )
        case .yoga:
            return SessionTemplate(
                title: "Yoga + breath",
                minutes: 45,
                detail: "Hip openers · breath ladder · cooldown"
            )
        case .hiit:
            return SessionTemplate(
                title: "HIIT circuit",
                minutes: 35,
                detail: "8 rounds · 30 s on / 30 s off · 4 stations"
            )
        case .walk, .ride, .swim, .hike, .other:
            return SessionTemplate(
                title: type.title,
                minutes: 45,
                detail: "Easy aerobic flush — keep heart rate Zone 2."
            )
        }
    }
}
