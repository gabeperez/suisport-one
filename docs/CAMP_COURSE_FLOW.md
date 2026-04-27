# Camp Course Flow — implementation spec

> **Status:** scoped, not built. Pick this up when ready.
>
> **Goal:** turn `ChallengeDetailView`'s training-plan list from a static
> preview into a sequential course — "Day 1 ✓ → Day 2 (next up) → Day 3 →
> Day 14." Tap a day, run that session in LiveRecorderView, return to the
> camp with that day marked complete and the next day promoted to "next up."

---

## Why we're not doing this yet

The MVP camp page is a *planner* — it shows what's in Yuya's pressure
camp without driving the user through it one session at a time. For
the hackathon demo it's a fine surface (it tells the story of "train
like the fighter"). But it's not a *course*, and the fighter-camp
narrative is much stronger when it is.

This doc captures what to build so we don't re-figure the design
later.

---

## What "implemented" looks like (from the user's perspective)

### Camp detail today

```
[Hero]                                — fighter, dates, stake, "ONE Samurai 1"
[Stake / Progress]                    — joined? camp progress %
[Training plan]
  14 sessions

  [Day 1] 🥊 Pad rounds · 60 min       ← read-only row
          6 × 3 min on pads…
  [Day 2] 🤼 Live rolling · 75 min     ← read-only row
  ...
[Rewards / Trophy]
[Leaderboard]
[Bottom CTA: Join / Open camp]
```

### Camp detail after course flow

```
[Hero]
[Stake / Progress]
[Training plan]
  Day 1 of 14 · Pad rounds                  ← progress headline
  ━━━━━━━━━━░░░░░░░░░░  1/14

  [▶ NEXT UP · Day 2] 🥊 Pad rounds · 60 min   ← accent border, primary CTA
                       6 × 3 min on pads…
                       [   Start Day 2   ]    ← inline button
  [✓ Day 1] 🥊 Pad rounds · 60 min           ← muted, checkmark
  [   Day 3] 🤼 Live rolling · 75 min         ← future, greyed-but-tappable
  [   Day 4] 🥊 Pad rounds · 60 min
  ...
[Bottom CTA: Continue camp →]                ← jumps to next-up session
```

### What "Start Day N" does

1. Tap → confirm haptic
2. Opens `LiveRecorderView(type: .striking)` with the camp's preset type
3. User records the session as normal
4. On successful submit (the existing `MintSuccessSheet` fires)
5. After "Done" on the success sheet, return to ChallengeDetailView
6. **That session is now marked ✓ complete**, the next session takes the
   "NEXT UP" slot, the headline progress bar ticks
7. If the user just completed Day 14 — show a finisher overlay:
   *"Camp complete. Yuya's trophy will land in your wallet."* with the
   trophy preview + a Suiscan link to the trophy mint (deferred trophy
   minting is a separate strand — see *Trophy mint* below)

---

## Data model

### New on `AppState`

```swift
/// Per-session completion state for camps in progress.
/// Keyed by `CampSession.id`. In-memory only for now —
/// refetched from server when we wire camp progress to D1.
/// Persisting locally would re-introduce the polish-PR pattern
/// we deliberately don't do.
var completedCampSessions: Set<UUID> = []

/// The `CampSession.id` the user just started — set when they
/// tap "Start Day N", read by LiveRecorderView's submit flow to
/// know which session to mark complete on success.
var activeCampSessionID: UUID? = nil
```

### Helpers

```swift
extension AppState {
    /// Mark a session complete and return the next session in the
    /// camp (if any). Caller decides whether to auto-show the next
    /// session as "NEXT UP" or just show a "well done" state.
    @MainActor
    func completeCampSession(_ sessionId: UUID, in plan: [CampSession])
        -> CampSession?
    {
        completedCampSessions.insert(sessionId)
        guard let idx = plan.firstIndex(where: { $0.id == sessionId }) else {
            return nil
        }
        return plan[(idx + 1)...].first { !completedCampSessions.contains($0.id) }
    }

    /// First session in the plan that hasn't been completed.
    /// Drives the "NEXT UP" badge + the bottom CTA.
    func nextSession(in plan: [CampSession]) -> CampSession? {
        plan.first { !completedCampSessions.contains($0.id) }
    }
}
```

### `CampSession` already has what we need

`CampSession.id` is already a stable `UUID` from `CampPlanner.plan(for:)` —
no changes needed to the model itself.

---

## File-by-file change list

### 1. `iHealth/AppState.swift`
- Add `completedCampSessions: Set<UUID>`
- Add `activeCampSessionID: UUID?`
- Add `completeCampSession(_:in:)` and `nextSession(in:)` helpers

### 2. `iHealth/Features/Explore/ChallengeDetailView.swift`
- Compute `let plan = CampPlanner.plan(for: challenge)` once at body
  entry (already happens; keep)
- Replace static `sessionRow(_:accent:)` with three states:
  - `sessionRowDone(_:)` — muted, checkmark, no tap action
  - `sessionRowNext(_:plan:)` — accent border, "NEXT UP" eyebrow,
    inline `Start Day N` button. Tap → set `app.activeCampSessionID =
    s.id`, present `LiveRecorderView(type: s.type)`
  - `sessionRowFuture(_:)` — same as today's read-only row but tappable
    (lets the user start out of order if they want)
- Add a headline `progressStrip(plan:)` above the list:
  - "Day N of M · *current session title*"
  - thin progress bar showing `completedCount / plan.count`
- Replace bottom CTA: when joined and not finished, show
  "Continue camp →" → presents `LiveRecorderView` for `nextSession`
- When `nextSession == nil` (camp finished), show `campCompleteCard`:
  - Trophy preview, fighter handle, date completed
  - Suiscan link to the trophy mint *if* we wire that (else just
    confetti + "Yuya's trophy is yours")

### 3. `iHealth/Features/Home/LiveRecorderView.swift`
- After a successful submit (when `mintReceipt` is set), check
  `app.activeCampSessionID`. If non-nil:
  - Pass through to `MintSuccessSheet` so the receipt's "Done" button
    triggers `app.completeCampSession(...)` before dismissing
  - Or simpler: call `app.completeCampSession(...)` inline in
    `submit(_:)` right where we set `mintReceipt`. Then clear
    `activeCampSessionID`.
- Edge case: if the user dismisses the LiveRecorderView mid-session
  (Discard), do NOT mark the camp session complete. Clear
  `activeCampSessionID` on dismiss.

### 4. `iHealth/Features/Home/MintSuccessSheet.swift`
- Add an optional `campSessionTitle: String?` property to `MintReceipt`
- When present, the success sheet shows a small
  "Day N of M · Pad rounds" eyebrow above "+X Sweat / Earned"
- "Done" callback can include "Continue camp" as a primary action when
  there's a next session, "View camp" as secondary

### 5. `iHealth/Features/Home/RecordSheet.swift`
- No change needed. The existing entry points (Record new / Upload
  past workouts) still work. Camp sessions are a third path that
  routes through ChallengeDetailView.

---

## State flow

```
ChallengeDetailView
  user taps "Start Day 2 · Pad rounds"
    ↓
  app.activeCampSessionID = day2.id
    ↓
  present LiveRecorderView(type: .striking)
    ↓
  user records → taps End + save
    ↓
  LiveRecorderView.submit() succeeds
    ↓
  app.completeCampSession(day2.id, in: plan)
    → completedCampSessions.insert(day2.id)
    → returns day3 (next incomplete session)
    ↓
  app.activeCampSessionID = nil
    ↓
  MintSuccessSheet shows with optional "Continue camp" CTA
    ↓
  user taps "Done" or "Continue camp"
    ↓
  ChallengeDetailView reappears with day2 ✓ done, day3 = NEXT UP
```

---

## Trophy mint on camp completion

Currently when you finish a camp the iOS UI shows a "Camp complete"
state but **no trophy is actually minted on chain.** Today's
`rewards_engine::submit_workout` mints SWEAT + a soulbound `Workout`
NFT per session — there's no "and-also-mint-a-camp-trophy" path.

Two options for trophy mints:

| Option | What | Effort |
|---|---|---|
| **A. Server-side post-completion** | Worker detects "this submit_workout completes a camp" by counting completed sessions for the athlete. Mints a separate Trophy NFT via a new `trophy_registry::mint_trophy` Move entry. | Half day on the contract + indexer + iOS. |
| **B. Move-level on the last submit** | `submit_workout` takes an optional `is_camp_finish` flag from the oracle. If true, mints SWEAT + Workout + Trophy in one tx. | Couple hours of Move + redeploy. |
| **C. Off-chain only for now** | Camp complete = just the in-app trophy fixture in `app.trophies`. No real on-chain trophy NFT. | Already the case today — zero change. |

For the course flow itself, **C is fine** — the course is the value;
the trophy is a separate deliverable. Don't block on it.

---

## Edge cases to handle

- **User has already done Day 3 outside the camp flow** (e.g. submitted
  a striking workout via RecordSheet → Record New). Today nothing
  detects that. Either ignore (the user explicitly tapped "Start Day
  3" if they used the camp flow) or do a fuzzy-match — same workout
  type within ±24h of "starting" the session. Recommend: ignore for
  v1, only count sessions started from inside the camp.

- **Switching devices / re-opening a partially-finished camp.**
  `completedCampSessions` is in-memory. After a relaunch, the camp
  shows as fresh until we wire server-side persistence. For the v1
  scope this is acceptable; document it.

- **Designer changes the camp plan after a user has progressed.**
  `CampSession.id` is generated fresh by `CampPlanner.plan(for:)` on
  every call, so the IDs aren't stable across runs. **This needs a
  fix.** Options:
  - Make the plan deterministic by hashing `(camp.id, dayIndex)` into
    the session id. Then `completedCampSessions` survives a re-plan.
  - Persist the full plan with the camp at first-join and keep it
    even if the planner logic changes.
  Recommend deterministic hashing — minimal code, no persistence
  needed. **Required before shipping the course flow.**

- **Camps you haven't joined.** Course UI should only show on joined
  camps. Pre-join state stays the same as today (preview-only).

---

## Implementation order (when we pick this up)

1. **CampPlanner: deterministic session IDs** — derive UUID from
   `(camp.id, dayIndex)` so completion tracking survives re-plans.
   *~15 min.*
2. **AppState additions** — `completedCampSessions`, `activeCampSessionID`,
   helpers. *~10 min.*
3. **ChallengeDetailView refactor** — three row states + progress strip
   + new bottom CTA. *~30 min.*
4. **LiveRecorderView + MintSuccessSheet** — wire camp completion
   on successful submit; add optional eyebrow + "Continue camp" CTA.
   *~20 min.*
5. **Smoke test on device** — run a 3-day mini-camp end to end.
   *~15 min.*

**Total: ~90 minutes.** Add another hour if we want server-side
persistence of `completedCampSessions` (D1 row keyed on
`(athlete_id, camp_id, day_index)`).

---

## What we explicitly punt

- Real trophy NFT mint on completion (option C above)
- Per-session leaderboards (camp-level leaderboard already exists)
- "Skip a day" / "Reschedule day" UX
- Streak protection if a day is missed
- Push notification "your fighter just dropped Day 5 of their camp"
- Sharing a session-completion to the feed automatically (today the
  user shares from the workout detail; that's enough)

---

## Suggested branch name

`feat/camp-course-flow`

Branch off `main` after the current `polish/sweat-onchain-ux` is
merged. Don't stack it on top — this is a meaningful enough scope
that it deserves its own PR.
