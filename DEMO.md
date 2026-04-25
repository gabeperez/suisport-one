# SuiSport ONE — demo video script

**Target length: 3 minutes.** The hackathon submission requires a demo video; even with a live presentation slot the recorded version is what the reviewers will watch first. Keep it tight.

Recording on iPhone 17 Pro simulator (or a real device if App Attest is available). Screen-record in 60 fps, 1080p portrait.

**Voiceover should be calm, paced, and confident — match ONE Championship's tone-of-voice (heritage, craft, honor) without trying to be a hype reel.**

---

## Shot 0 — Cold open (0:00 → 0:08)

**Visual:** Black screen → fade in to the SuiSport ONE app icon → wipe to the onboarding hero ("Train like a fighter.")

**Voiceover:**
> "ONE Championship has a problem every league has. Fans watch. They don't *do*."

**On-screen text:** `SuiSport ONE — Train like a fighter.`

---

## Shot 1 — Onboarding (0:08 → 0:25)

**Visual:** Tap "Get started" → AgeGate → Apple Sign In sheet → land on the home feed.

**Voiceover:**
> "We sign in with Apple. Behind the scenes Enoki creates a Sui wallet — no seed phrase, no extension. From here, every workout this fan logs is verified on-chain."

**Don't over-narrate the auth UI. Let the speed sell the wallet-less story.**

---

## Shot 2 — The Samurai card (0:25 → 0:40)

**Visual:** Home feed loads. Camera lingers on the ONE Samurai 1 hero card with the live countdown ("X days out · Ariake Arena Tokyo").

**Voiceover:**
> "The morning of ONE Samurai 1, this is what fans see first. Fight night countdown, the official camp, the headline fighters. One tap and you're training with them."

**Tap the card.** Transition to the camp screen.

---

## Shot 3 — Pick a fighter, see their camp (0:40 → 1:05)

**Visual:** ONE Samurai 1 — Fight Week challenge detail. Scroll to "Train with Yuya Wakamatsu." Tap. Yuya's profile screen with his real photo from `cdn.onefc.com`, bio, gym (Tribe Tokyo MMA), and "Photo: ONE Championship" attribution.

**Voiceover:**
> "Yuya Wakamatsu — ONE Flyweight World Champion, Tribe Tokyo MMA. His camp is fourteen sessions over seven days: striking, grappling, conditioning, recovery. Real fighter, real bio, real photo from ONE Championship."

**Don't editorialize. Show the attribution chip, then move on.**

---

## Shot 4 — Log a workout (1:05 → 1:50)

**Visual:** Home feed → tap the + button → "Striking" → live recorder starts → fast-forward simulated 45 minutes (use Xcode time-slip if needed) → hit Finish.

The submit pipeline shows live:
1. "Verifying with App Attest…"
2. "Uploading to Walrus…"
3. "Submitting to Sui…"
4. ✓ Done. Tx digest visible.

**Voiceover:**
> "I do the session. Apple Watch records it. The app signs the canonical hash with App Attest — Apple's hardware-rooted attestation, so a jailbroken device can't lie. Walrus stores the proof. The Sui Move contract verifies the oracle signature and mints SWEAT to my address."

**Tap the tx digest.** Open Suiscan in-app. Show the on-chain `WorkoutSubmitted` event. Close.

---

## Shot 5 — Trophy + push (1:50 → 2:20)

**Visual:** Profile tab → trophy case → the new "Yuya Pressure Camp · session 1/14" trophy is now there. Then a push notification slides in from another fighter ("Hiroki Akimoto gave you kudos"), tap it → deep-link back to the workout detail.

**Voiceover:**
> "The trophy is soulbound — it lives on the user's `UserProfile` Sui object forever. And other fans see your camp in their feed. Hiroki Akimoto just sent kudos. The push notification deep-links me back into the workout."

---

## Shot 6 — Walrus + Suiscan (2:20 → 2:40)

**Visual:** From the workout detail tap "View on Walrus" → Walruscan opens with the blob page. Cut to "View on Sui" → Suiscan with the tx page.

**Voiceover:**
> "Every workout is two artifacts. A Walrus blob with the canonical workout JSON — immutable, content-addressed. And a Sui transaction with the matching digest. The fighter, the chain, and the user all see the same proof."

---

## Shot 7 — Close (2:40 → 3:00)

**Visual:** Cut back to the SuiSport ONE home feed showing camp progress 1/14. Hold for 2 seconds. Fade to a final card.

**Final card:**
```
SuiSport ONE
github.com/gabeperez/suisport-one
Sui × ONE Samurai · Tokyo · April 2026

Train like a fighter.
Photo: ONE Championship.
```

**Voiceover:**
> "SuiSport ONE. Built for ONE Championship's Japanese fans. Built on Sui. Available now on testnet."

---

## Production notes

**Don't:**
- Use stock motion graphics or templated outros. The app's gradients + ONE-red palette is the entire look.
- Rush the on-chain step. The pipeline screen is the most novel thing in the demo — let it breathe.
- Show any "SuiSport" string without " ONE" after it. (If you spot one, message me — see `docs/REPO_SPLIT.md` for what's still on the canonical brand.)

**Do:**
- Record in airplane mode + connect to a local hotspot — gives clean network indicator + full battery in the status bar.
- Time-slip the simulator clock for the workout-duration shot if you don't want to wait 45 minutes.
- Subtitle every voiceover line — judges may watch on mute.
- Add a discreet 1-second hold on every transition so the screen-recording doesn't feel like a TikTok.

**Music:** royalty-free taiko or atmospheric instrumental — nothing too "samurai movie." Tonally we're closer to a Nike Run Club ad than a Kurosawa cold open. Avoid anything copyrighted by ONE Championship's productions team.

**Captions:** burn them in at the end (Final Cut "Captions" → "Burn into video"). Submission platforms sometimes strip soft subs.

**Final delivery:** 1080×1920 portrait, mp4, H.264 + AAC, ≤ 100 MB. Upload to YouTube unlisted as a backup; submit the YouTube URL alongside the mp4 attachment.
