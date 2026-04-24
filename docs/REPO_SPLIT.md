# Repo split — SuiSport ONE (this repo) vs. SuiSport canonical

## What this is

This repo is a **hackathon fork** of SuiSport, created on 2026-04-25 for the **Sui × ONE Samurai Tokyo Builders Arena** (April 2026). It started as a verbatim duplicate of the canonical SuiSport codebase and is being aggressively reskinned around martial arts / ONE Championship fan engagement.

A mirror of this document lives in the canonical repo with the same explanation from the other side.

## The two repos

| | Hackathon fork (this repo) | Canonical |
|---|---|---|
| Local folder | `~/Documents/main/WIP/SuiSport ONE/` | `~/Documents/main/WIP/SuiSport App/` |
| GitHub | [`gabeperez/suisport-one`](https://github.com/gabeperez/suisport-one) (private) | [`gabeperez/suisport`](https://github.com/gabeperez/suisport) (private) |
| Pitch | "Train like a fighter" — ONE Championship fan engagement | Strava-on-Sui — generic verified fitness with on-chain rewards |
| Hackathon | **Sui × ONE Samurai (Tokyo, Apr 2026)** — submission deadline Apr 25 noon JST, demo day Apr 29 at Ariake Arena | n/a |
| Bundle id | will be re-keyed during the rebrand | `gimme.coffee.iHealth` |
| URL scheme | will be re-keyed during the rebrand | `suisport://` |

## Where this repo started

This fork branched at the tag **`v0.1-pre-hackathon`** (commit `d73205e` from the canonical repo, "feat(profile): bio, pronouns, location, website, avatar upload"). That tag exists in both repos so you can always diff against the shared baseline.

```bash
git log v0.1-pre-hackathon..HEAD --oneline   # what's been added on this fork
```

## What's expected to change in this fork

In rough priority order during the hackathon sprint:

1. **Narrative & copy.** Hero "Train like a fighter," martial-arts-first onboarding, fan-engagement framing throughout.
2. **Workout types.** Add `mma`, `muaythai`, `bjj`, `kickboxing`, `striking` etc. — both iOS enum and the Move contract's `workoutTypeCode` mapping.
3. **Seed data.** ONE-themed Challenges (e.g. "ONE Samurai Week training camp"), 2–3 ONE Fighter athlete profiles.
4. **Branding.** App name, icon, accent colors. Bundle id + URL scheme renamed once branding settles.
5. **Demo content.** A "Featured Fighter" card on Feed pointing at the hackathon-week challenge.
6. **Japanese localization** (light): a handful of `Localizable.strings` ja entries on the hero/landing copy, signaling JP-audience awareness.

## What stays shared with the canonical (initially)

For speed, this fork starts out pointing at the same backend the canonical uses:

- Cloudflare Worker `suisport-api.perez-jg22.workers.dev`
- D1 database `suisport-db`, R2 bucket `suisport-media`, Cloudflare Pages `suisport-wallet`
- Sui testnet Move package `0x966699ee60fdb9e1a308d5d3c0da28fe10ed90ce870fa43a97ff74544b3b452b`
- Operator + oracle Ed25519 keys
- Apple App Attest config
- Apple + Google OAuth client ids

That's fine for a demo because both apps will write to the same testnet backend; the data partitions naturally by athlete id and demo-data flags.

If the hackathon needs schema changes that would break the canonical (e.g. a martial-arts-specific column), spin up a new Worker + new D1 by changing `cloudflare/wrangler.toml`'s `name` + `database_name`. Until then, share.

## Cherry-picking between the two

When a real bug fix lands on either side, copy it across:

```bash
# Inside whichever repo wants the fix:
git remote add other ../<other folder name>          # local path remote
git fetch other
git log other/main --oneline                          # find the commit
git cherry-pick <sha>
```

A path-based remote works offline and is faster than going through GitHub.

**Worth cherry-picking either direction:**
- Real bug fixes that aren't theme-specific
- Backend / infra fixes (APNs, D1 query performance, Sui RPC handling)
- New shared dependencies or auth-flow refinements

**Don't cherry-pick:**
- Branding, copy, icons, seed data
- Bundle-id / scheme renames
- Hackathon-only demo wiring

## Forward path

After the hackathon (Apr 29 demo at Ariake Arena), this repo either:
1. **Gets archived** as the demo-day artifact, no further commits
2. **Gets merged back** into canonical if the "train like a fighter" framing becomes the actual product direction
3. **Gets developed independently** if it warrants its own product line

Decision deferred until after the hackathon.

## Quick reference

| You want | Where to look |
|---|---|
| The shared backend / on-chain / Walrus / Seal docs | `docs/ON_CHAIN_STRATEGY.md`, `docs/SEAL_INTEGRATION.md` |
| The exact code state at the fork point | `git checkout v0.1-pre-hackathon` (read-only, then `git checkout main` to come back) |
| What the canonical has done since | `cd ../SuiSport\ App && git log v0.1-pre-hackathon..main --oneline` |
| Hackathon handbook | https://mystenlabs.notion.site/sui-one-samurai-apr-2026-tokyo-builders-arena |
