# SuiSport ONE — 90-second demo speed-run

A faster cut of `DEMO.md`. Use this when you have ~30 minutes total to record + render + upload before deadline. Total runtime target: **90 seconds.**

If you have more time, fall back to `DEMO.md` (3-minute polished version).

## Setup (5 min)

1. Open Xcode, build to **iPhone 17 Pro** simulator (largest screen, cleanest crop).
2. Set the simulator to **light mode** (Sim menu → Features → Toggle Appearance) — the ONE-red gradient pops more on light mode chrome.
3. Sign in once so you're past Hero/AgeGate. Land on the Feed with the Samurai card visible.
4. **QuickTime Player → New Movie Recording → click the dropdown next to record → choose your Simulator** (iOS device shows up). Or use `xcrun simctl io booted recordVideo --codec=h264 demo.mp4` from terminal.
5. Hit record.

## Shot list (90 seconds)

### 0:00 → 0:08 — Brand opener
**Visual:** Static frame on the SuiSport ONE Hero — "Train like a fighter."
**Voiceover:**
> "ONE Championship has a problem every league has. Fans watch. They don't *do*. SuiSport ONE makes the gap from watching a fighter to training like one a single tap."

### 0:08 → 0:18 — The hook
**Visual:** Quick scroll over the Feed — show the Samurai 1 hero card, points card, then a fighter's training session in the feed.
**Voiceover:**
> "Live countdown to ONE Samurai 1 at Ariake Arena. Every workout below is a real fighter logging real fight-camp work."

### 0:18 → 0:35 — Tap a fighter → see his camps
**Visual:** Tap an athlete avatar → land on Yuya Wakamatsu's profile. Linger on the photo + bio. Scroll to **"Train with Yuya"** carousel. Tap **Wakamatsu Pressure Camp**.
**Voiceover:**
> "Yuya Wakamatsu — ONE Flyweight World Champion, real photo from ONE Championship's CDN, real bio, real gym. Right under his stats: his designed camps. Tap one — *Pressure Camp* — and you're in his program."

### 0:35 → 0:55 — The on-chain story
**Visual:** Camp screen scroll: hero with sponsor → designer strip ("Designed by Yuya Wakamatsu") → progress → **"What you'll mint" trophy preview** in ember-orange — "Yuya Pressure Camp Trophy · Signed by @yuya_wakamatsu on completion · SOULBOUND."
**Voiceover:**
> "Designed by Yuya. Sponsored by ONE. Complete it and a soulbound trophy NFT signed by Yuya mints to your Sui wallet. Eighty-eight thousand SWEAT pool, split among finishers."

### 0:55 → 1:15 — The proof
**Visual:** Scroll to **"Stack up"** — show "Top 15%" pill, your rank tile (#312 of 2.1K), top-5 leaderboard. Then jump to: tap any workout in the feed → workout detail → tap "View on Sui" → Suiscan opens with the real testnet tx digest. (Or: open `suisport-api.perez-jg22.workers.dev` to show the live worker.)
**Voiceover:**
> "Every session is verified by Apple's App Attest, blob-stored on Walrus, minted by our Move contract on Sui testnet. Here's the live transaction. Real chain, real proof, real now."

### 1:15 → 1:30 — Close
**Visual:** Cut back to the Feed. Hold for a beat. Cut to a final card with the cover.html screenshot.
**Voiceover:**
> "SuiSport ONE. Built for ONE Championship's Japanese fans. Code on GitHub, demo running on testnet. Train like a fighter."

## Production shortcuts

- **Don't worry about background music for the speedrun cut** — clean voiceover beats overproduced silence.
- **If voiceover record is slow**, narrate live during the screen-record. iOS Sim screen recordings capture system audio + your mic if you check the mic in QuickTime's record dropdown.
- **Burn captions in** at the end via QuickTime → Show Subtitles is unreliable; use the Mac's built-in **Live Captions** during recording, or use the auto-captions on YouTube after upload.
- **Upload to YouTube unlisted** for the submission — DeepSurge accepts URLs and YouTube's CDN will deliver during demo day. Save the local `.mp4` as backup.

## Final delivery

- **Format:** mp4, H.264, ≤ 100 MB, 1080p portrait or 1080p landscape (judges' call). The simulator's native 1290×2796 will downscale fine.
- **Filename:** `suisport-one-demo.mp4`
- **Submission fields:** GitHub URL → `github.com/gabeperez/suisport-one` · Video URL → YouTube unlisted link · Cover → screenshot of `cover.html` (1200×630)

## If you run over time

Drop the **0:55 → 1:15 "proof" segment** if it would push you past 1:30. The demo lives or dies on the *fighter → camp → trophy* loop in the middle. The on-chain proof is reassurance, not the headline.
