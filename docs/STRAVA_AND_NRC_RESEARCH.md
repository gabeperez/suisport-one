# Strava & Nike Run Club — Deep Research Dossier

> Compiled April 2026 for the SuiSport product team. Two parallel deep-dive
> agents were tasked to investigate Strava and Nike Run Club respectively;
> this document captures the full findings for future reference and is the
> authoritative source behind the social features shipped in v0.1 of
> SuiSport. Every claim is cited. Where we already shipped a feature inspired
> by the research, it's noted inline as **`[shipped in v0.1]`**.

---

## Table of Contents

1. [Executive Synthesis](#1-executive-synthesis)
2. [Strava: Deep Dive](#2-strava-deep-dive)
   - 2.1 [Core social features](#21-core-social-features)
   - 2.2 [Segments — the moat](#22-segments--the-moat)
   - 2.3 [Clubs](#23-clubs)
   - 2.4 [Challenges](#24-challenges)
   - 2.5 [Routes & planning](#25-routes--planning)
   - 2.6 [Training tools (Summit)](#26-training-tools-summit)
   - 2.7 [Notifications & retention loops](#27-notifications--retention-loops)
   - 2.8 [Discovery & growth](#28-discovery--growth)
   - 2.9 [Subscription gating](#29-subscription-gating-2026)
   - 2.10 [What users love](#210-what-users-love)
   - 2.11 [What users hate / opportunities](#211-what-users-hate--what-suisport-can-exploit)
   - 2.12 [Small-but-loved details](#212-small-but-loved-details)
   - 2.13 [Intentional anti-patterns](#213-the-dark-side--what-strava-does-badly-on-purpose)
3. [Nike Run Club: Deep Dive](#3-nike-run-club-deep-dive)
   - 3.1 [Audio / coaching layer](#31-audio--coaching-layer-the-crown-jewel)
   - 3.2 [Tracking / record experience](#32-tracking--record-experience)
   - 3.3 [Social graph](#33-social-graph--cheers)
   - 3.4 [Gamification](#34-gamification)
   - 3.5 [Training plans](#35-training-plans)
   - 3.6 [Commerce / brand](#36-commerce--brand-integration)
   - 3.7 [Integrations & platform](#37-integrations--platform)
   - 3.8 [What users love](#38-what-users-love-quote-worthy)
   - 3.9 [What users hate / controversies](#39-what-users-hate--the-2023-24-cull)
   - 3.10 [Small-but-loved details](#310-small-but-loved-details)
4. [Feature Scoring Matrix](#4-feature-scoring-matrix)
5. [Top-Ranked Features To Build](#5-top-ranked-features-to-steal-for-suisport)
6. [Copy / Audio Patterns Worth Stealing](#6-copy--audio-patterns-worth-stealing-from-nrc)
7. [DO NOT Copy](#7-do-not-copy--explicit-anti-patterns-from-both)
8. [Strava vs. NRC Side-by-Side](#8-strava-vs-nrc-honest-comparison)
9. [SuiSport v0.1 Implementation Status](#9-suisport-v01-implementation-status)
10. [Future Roadmap Derived From This Research](#10-future-roadmap-derived-from-this-research)
11. [Sources](#11-sources)

---

## 1. Executive Synthesis

**Strava's moat** is a reflexive competitive loop — **record → get kudos →
chase segments → see a progress bar → renew subscription**. 180M+ registered
users, 14B kudos given in 2025, 1M clubs (quadrupled YoY), $79.99/yr
subscription. The product is ruthlessly monetized and the company has
paywalled features users consider their own data (the 2025 Year-in-Sport
paywall caused a public backlash). Every paywall mis-step is an opening for
a crypto-native competitor. ([Strava Year in Sport report](https://press.strava.com/articles/strava-releases-12th-annual-year-in-sport-trend-report-2025),
[World Today Journal backlash coverage](https://www.world-today-journal.com/strava-year-in-sport-80-paywall-sparks-backlash/))

**NRC's moat** is the polar opposite — an **emotional, parasocial audio
experience** that makes you feel like you're running with a friend. Coach
Chris Bennett, Eliud Kipchoge, Shalane Flanagan, Kevin Hart, and an
official Headspace partnership power ~300 guided runs. Users consistently
describe learning to run, returning after long absences, or finishing a
marathon "because Coach Bennett's voice was in my ear." But Nike has eroded
this trust: in March 2024 they locked down the public API (killing RunGap
and third-party tools), dropped Apple Watch Series 3, and visibly
downgraded adaptive coaching. The r/nrcapp narrative is "Nike abandoned
us." ([NPR profile of Coach Bennett](https://www.npr.org/2023/11/04/1210678199/nike-run-clubs-oddly-mindful-coach),
[RunGap on API lockdown](https://rungap.zendesk.com/hc/en-us/articles/115000368794),
[The New Consumer on NRC decline](https://newconsumer.com/2023/11/nike-run-club/))

**The SuiSport wedge** is the union of their strengths with none of their
weaknesses:

- **From Strava**: segment leaderboards, clubs, challenges, kudos — but
  verifiable on-chain (kills cheating), soulbound (portable across apps),
  and stake-backable with $SWEAT (real prize pools, not virtual badges).
- **From NRC**: warm coach voice, guided audio, emotional streak rituals,
  iconic share cards — with signed audio NFTs, tipped cheers that survive
  the run, and an open API they can never take from you.
- **Neither**: the open primitive that Strava's Year-in-Sport paywall
  proved people need — **your own data, back, free, forever**.

---

## 2. Strava: Deep Dive

### 2.1 Core social features

#### Feed (Following vs. Discover)

Strava's home feed can be toggled between strictly chronological ("Latest
Activities") and a personalized ordering that surfaces activities "you tend
to interact with and great efforts you may have missed." A **Favorites**
feature lets users pin specific athletes so their activities always float
to the top, optionally push-notifying on upload. There is no algorithmic
"Discover" feed separate from following — discovery happens via Clubs,
Segment leaderboards, Suggested Athletes, and (for cyclists) Flyby. ([Feed
Ordering docs](https://support.strava.com/hc/en-us/articles/115001183630-Feed-Ordering))

Push notifications fire on: new follower, kudos, comments, mentions, new
activity from favorited athletes, **dethroned KOM/QOM to the loser**, Local
Legend changes, challenge progress milestones, and friend joining a
challenge you're in. ([Strava Notifications
docs](https://support.strava.com/hc/en-us/articles/216918367-Strava-Notifications))

**Retention impact: 5/5** · **Crypto leverage: 2/5** (feed itself isn't
crypto-native, but provenance stamps on each activity are)

#### Kudos

Strava's one-tap like — **14 billion given in 2025 alone**
([Strava Year in Sport](https://press.strava.com/articles/strava-releases-12th-annual-year-in-sport-trend-report-2025)).
Academic research ([ScienceDirect: Kudos make you
run!](https://www.sciencedirect.com/science/article/pii/S0378873322000909))
finds that **receiving kudos causally increases subsequent running
behavior**, and users mimic the behavior of their "kudos-friends." Strava
actively teaches users "10 Ways to Get More Kudos" ([Community
Hub](https://communityhub.strava.com/insider-journal-9/10-ways-to-get-more-kudos-1573)).
The emotional weight is real: a Substack investigation ([Triple Threat
Life](https://triplethreatlife.substack.com/p/running-for-kudos-the-double-edged))
documents users extending runs, skipping runs, or hiding runs based on how
they'll "read" in the feed. "Kudos-bombing" (kudos-ing every activity in
someone's history) is a known tactic.

**Retention impact: 5/5** · **Crypto leverage: 4/5** — kudos as on-chain
micro-reputation, backed by tiny $SWEAT tips, is the single most obvious
Strava-to-crypto upgrade. **`[shipped in v0.1 — kudos animate a $SWEAT
coin on tap; tip badges persist on feed cards]`**

#### Comments, emojis, photos

Emoji support was added late ([Cycling
Weekly](https://www.cyclingweekly.com/news/latest-news/you-can-now-use-emojis-in-strava-310183))
and is still rough on web ([Community
Hub](https://communityhub.strava.com/strava-features-chat-5/where-are-emoji-s-on-strava-browser-version-10230)).
There are **no emoji reactions on comments** — a top-voted community idea
([Community
Hub](https://communityhub.strava.com/t5/ideas/emoji-reacts-on-comments/idi-p/9873)).
Photo uploads work on activities; photos *inside* comments do not. No GIFs.

**Retention impact: 3/5** · **Crypto leverage: 1/5**. **`[shipped in v0.1
— emoji reaction chips on comments, something Strava conspicuously
lacks]`**

#### Group activities (auto-grouping)

Strava auto-groups athletes whose activities are "more than 50% similar"
in route and overlap in time ([Group Activities
docs](https://support.strava.com/hc/en-us/articles/216919497-Group-Activities)).
**Flyby** ([labs.strava.com/flyby](https://labs.strava.com/flyby/)) lets
you rewatch minute-by-minute playback with athletes who crossed your path.
Since July 2025, Strava also auto-matches activities to Events and Clubs
([Activity Event
Match](https://support.strava.com/hc/en-us/articles/38820095583629-Activity-Event-Match)).
Strava's own engineering blog calls Activity Grouping "the heart of a
social network for athletes" ([Strava Engineering
Medium](https://medium.com/strava-engineering/activity-grouping-the-heart-of-a-social-network-for-athletes-865751f7dca)).

**Retention impact: 4/5** · **Crypto leverage: 4/5** — group runs as
verifiable co-signed sessions on Sui is a strong on-chain primitive and
enables $SWEAT-split rewards automatically.

#### Athlete profiles, following, privacy

Profiles show recent activities, weekly mileage, goals, **trophy case**
(challenge-finisher badges, most-recent-4 visible), **verified athlete
badges** ([docs](https://support.strava.com/hc/en-us/articles/115000160850-Verified-Athlete-Badges-on-Strava)),
follower/following counts, clubs, and gear. Follower model is asymmetric
(like Twitter) with optional approval. Default activity privacy is
"Everyone" but configurable per-activity. The first/last 200m of every
activity map is hidden by default. Users can define additional **privacy
zones** by address and radius. In 2025, Strava added the ability to hide
only running or only cycling starts, and to hide segments within specific
events ([The Runners
Digest](https://therunnersdigest.com/strava-privacy-settings-for-runners-2025/)).

Muting and blocking exist but are famously weak — mute-from-feed is a
newer addition.

**Retention impact: 4/5** · **Crypto leverage: 5/5** — profiles as Sui
objects owned by the user, portable across apps, with verifiable activity
provenance, is a genuine 10x improvement. **`[shipped in v0.1 —
AthleteProfileView with tier ring, verified badge, tip-athlete button;
SuiSport ID visible in Advanced settings]`**

#### Mentions / friend finding

@mentions work in comments. Find Friends uses contact import (phone),
Facebook connection, and mutual-follow graph inference ("If A and B both
follow C but don't follow each other, suggest B to A") ([Finding
Friends](https://support.strava.com/hc/en-us/articles/216917377-Finding-Friends-and-Managing-Contacts-on-Strava)).
Users have vocally asked Strava not to become Facebook ([Community
Hub](https://communityhub.strava.com/strava-features-chat-5/please-don-t-be-facebook-928)).

**Retention impact: 3/5** · **Crypto leverage: 3/5**

### 2.2 Segments — the moat

A **segment** is a user-created stretch of road/trail with a leaderboard
([docs](https://support.strava.com/hc/en-us/articles/216917137-What-s-a-segment)).
Anyone can create one. **KOM/QOM/CR** goes to the fastest-ever time.

**Local Legend** ([docs](https://support.strava.com/hc/en-us/articles/360043099552-Local-Legends))
goes to whoever completes the segment *most often* in a rolling 90-day
window, regardless of speed — a consistency-based alternative leaderboard
explicitly designed to reward non-elite athletes
([BikeRadar](https://www.bikeradar.com/news/strava-local-legend)).

Starred segments get **Live Segment** treatment
([docs](https://support.strava.com/hc/en-us/articles/207343830-Live-Segments))
with real-time pacing, but it's partly gated: free users see if they're
ahead/behind PR, subscribers get exact time deltas, distance countdown,
**Carrot/Wolf pacing avatars**, and post-segment results. This is the
cleanest example of Strava paywalling the *emotional climax* of its own
loop.

**Dethroning asymmetry**: when someone beats your KOM, you are notified;
no notification goes to the *new* KOM holder ([Community
idea](https://communityhub.strava.com/t5/ideas/new-kom-notification/idi-p/18042)).
The literature on losing a QOM ([Deep Water
Happy](https://www.deepwaterhappy.com/2020/12/31/when-you-lose-your-qom-on-strava-the-1-app-for-runners-cyclists-swimmers/))
describes it as motivation to train and reclaim. Segments are the single
feature that turns "any random hill into a public test of identity"
([Agate Level
Up](https://agatelevelup.com/stravas-secret-how-gamification-is-redefining-fitness-and-user-engagement-in-2025/)).

**Retention impact: 5/5** · **Crypto leverage: 5/5** — segments as NFT
objects; KOM/QOM/Local Legend as soulbound tokens; segment creators
earning royalties when their segment generates activity; leaderboard
entries as verifiable on-chain attestations. **The single biggest
crypto-native upgrade possibility.** **`[shipped in v0.1 — SegmentsView
with KOM/QOM/Local Legend chips, SegmentDetailView with All/Women/Local
Legends leaderboard tabs, Tip-KOM button, star segments]`**

### 2.3 Clubs

Types:

- **Local** (geographic running/cycling groups)
- **Virtual** (global hobbyist groups)
- **Brand-sponsored** — top 9 by size: Le Col, Rapha, lululemon, ROKA,
  Zwift, New Balance, Shimano, HOKA, GCN ([Strava
  Business](https://business.strava.com/resources/strava-clubs-vs-traditional-social-media)).
  Brand clubs grew audience +279% Q4'18→Q4'21 vs. ~140% for brands' other
  socials.

Club feeds are chronological-only, with posts, events, and leaderboards.
Club creation is now available on mobile as of 2025 ([February 2025
What's New](https://communityhub.strava.com/what-s-new-10/check-it-out-what-s-new-on-strava-from-february-2025-9099)).

**The single biggest missing feature**: native Club Challenges. Users have
been begging ([community
idea](https://communityhub.strava.com/t5/ideas/create-club-challenges/idi-p/4987))
since 2021. The workaround is a private Group Challenge capped at 199
members, which every large club blows past.

What makes an active club: regular events, a charismatic admin, monthly
challenges, brand sponsorship, local meetups. Dead clubs stay dead because
there's no built-in re-engagement mechanism.

**Retention impact: 4/5** · **Crypto leverage: 5/5** — clubs as on-chain
DAOs with treasury in $SWEAT, club challenges with staked prize pools,
brand-sponsored clubs paying token to acquire members, verifiable club
leaderboards. **`[shipped in v0.1 — Clubs list with For You/Joined/Brands
filter, featured brand card, ClubDetailView with Activity/Members/Treasury
tabs, treasury card explaining auto-fund + vote-spend DAO mechanics]`**

### 2.4 Challenges

Three tiers ([Strava Challenges
docs](https://support.strava.com/hc/en-us/articles/216919177-Strava-Challenges)):

1. **Monthly distance/elevation** — universal; badge goes in Trophy Case.
2. **Brand-sponsored** — often with physical prize entries (shoes, gift
   cards).
3. **Group Challenges** ([docs](https://support.strava.com/hc/en-us/articles/360061360791-Group-Challenges))
   — private, 199-athlete cap, creator-run, **subscriber-only**.

The psychology is the **Endowed Progress Effect** ([StriveCloud
analysis](https://www.strivecloud.io/blog/app-engagement-strava)): a
progress bar at 40% toward a monthly goal is emotionally different from
"you've run 20 miles." Users describe monthly badges as the primary reason
they maintain subscriptions during the off-season.

Sponsored Challenges ([business.strava.com/challenges](https://business.strava.com/challenges))
are a major revenue line — brands pay to put their challenge in front of
every active user.

**Retention impact: 5/5** · **Crypto leverage: 5/5** — **stake-to-join
challenges** with smart-contract escrow, trustless brand sponsorships via
on-chain prize pool, verifiable completion. **`[shipped in v0.1 —
ChallengesView with filter chips, ChallengeDetailView with stake banner +
progress + rewards (finisher trophy NFT, Sweat pool, sponsor drop) +
leaderboard + stake-to-join alert]`**

### 2.5 Routes & planning

Strava has a paid **Route Builder** with AI-driven suggestions and
Heatmap-informed routing ([GearJunkie
2025](https://gearjunkie.com/technology/strava-updates-2025-ai-routes)).
June 2025 added point-to-point with POI discovery; November 2024 added
Night and Weekly heatmaps ([press
release](https://press.strava.com/articles/strava-expands-mapping-tools-with-night-and-weekly-heatmaps)).
Users can save/star routes, export GPX, and follow with turn-by-turn on
subscriber tier. The [Global
Heatmap](https://www.strava.com/maps/global-heatmap) is free but lower
fidelity. 2025 added route search by keyword / sport / elevation / surface.

**Retention impact: 3/5** (high for cyclists, lower for runners) · **Crypto
leverage: 3/5** — routes as tradeable/tippable NFT objects, route creators
earning micro-royalties.

### 2.6 Training tools (Summit)

- **Training Log** — weekly calendar colored by Relative Effort.
- **Fitness & Freshness** ([docs](https://support.strava.com/hc/en-us/articles/216918477-Fitness-Freshness))
  — CTL/ATL/TSB using a Banister-model impulse-response. Fitness =
  42-day weighted load; Fatigue = 7-day; Form = difference.
- **Relative Effort** — heart-rate-driven effort score with target range.
- **Best Efforts / All-Time PRs** ([docs](https://support.strava.com/hc/en-us/articles/216918487-All-Time-PRs))
  — lifetime PRs at benchmark distances.
- **Matched Activities** ([docs](https://support.strava.com/hc/en-us/articles/216918597-Matched-Activities))
  — same route compared across efforts.
- **Athlete Intelligence** ([docs](https://support.strava.com/hc/en-us/articles/26786795557005-Athlete-Intelligence-on-Strava))
  — generative-AI workout summaries, out of beta Feb 2025, 80%+ helpful
  rating; now includes power insights and segment analysis.
- **Runna acquisition** ([press](https://press.strava.com/articles/strava-to-acquire-runna-a-leading-running-training-app))
  April 2025; **The Breakaway** acquisition May 2025
  ([TechCrunch](https://techcrunch.com/2025/05/22/strava-is-buying-up-athletic-training-apps-first-runna-and-now-the-breakaway/)).
  Operates as a separate app. Strava + Runna Plan costs $149.99/yr.

**Retention impact: 4/5** · **Crypto leverage: 2/5** — training data works
better as aggregated heatmaps than individual on-chain objects; but
Fitness Score as a verifiable DID attribute is interesting.

### 2.7 Notifications & retention loops

Pings fire on: kudos, comments, new followers, dethroned KOM, favorite
athlete activity, challenge milestones, Local Legend changes, activity
memories ("1 year ago today"), birthday, PR, weekly recap.

**The Year in Sport** ([press](https://press.strava.com/articles/strava-releases-12th-annual-year-in-sport-trend-report-2025))
is the single most-shared content Strava produces — until 2025, when it
moved **behind the subscriber paywall** at $80
([Slashdot](https://news.slashdot.org/story/25/12/19/2158235/strava-puts-popular-year-in-sport-recap-behind-an-80-paywall),
[World Today Journal](https://www.world-today-journal.com/strava-year-in-sport-80-paywall-sparks-backlash/)).
The backlash was severe: users accused Strava of "charging users to view
data they generated" ([T3
opinion](https://www.t3.com/tech/dear-strava-we-have-a-paywall-problem-thats-gone-a-step-too-far),
[Road.cc](https://road.cc/content/news/strava-year-sport-now-only-subscribers-317425)).

**Retention impact: 5/5** · **Crypto leverage: 4/5** — user data
ownership story writes itself here. **This is the single clearest example
of Strava handing SuiSport a marketing moment on a silver platter.**

### 2.8 Discovery & growth

**Instagram Stories share** is the classic viral loop: the Stats Stickers
overlay distance/pace on a photo, the shared story contains a deep link
that opens Strava and prompts follow
([community](https://communityhub.strava.com/what-s-new-10/how-to-share-your-strava-activity-to-instagram-stories-9426)).
There is a "viral running TikTok" overlay aesthetic
([RunFlick](https://runflick.com/blog/share-strava-on-instagram)) using
CapCut templates to replicate Strava's stat overlay.

Find Friends uses contacts, Facebook, and mutual-follow graph inference.

**Retention impact: 4/5** · **Crypto leverage: 3/5** — social graphs as
portable Sui objects; share cards with on-chain proof watermark. **`[shipped
in v0.1 — ShareCardSheet with "Verified on Sui" watermark, IG Stories
button]`**

### 2.9 Subscription gating (2026)

Prices: **$79.99/yr** base, **$11.99/mo**, **$139.99 Family**, **$149.99
Runna bundle** ([Strava Pricing](https://www.strava.com/pricing), [Subscriber
Perks](https://www.strava.com/subscription/perks),
[Wareable](https://www.wareable.com/sport/is-strava-premium-worth-it)).

Behind the paywall:

- Segment leaderboards (full)
- Route Builder + export
- Matched Runs / Matched Activities
- Fitness & Freshness / Training Log
- Relative Effort with range targeting
- Live Segments full UI (time delta, Carrot/Wolf)
- Night / Weekly / Personal Heatmaps
- Athlete Intelligence
- Create Group Challenges
- **Participate in Group Challenges** (yes — even joining requires sub or trial)
- **Year in Sport (new 2025)**
- Race finish prediction
- All achievement / leaderboard deep views

**What users most subscribe for**: segment leaderboards, Fitness &
Freshness, Route Builder.

**What users rage-quit over**: Year in Sport paywalling, being blocked from
joining a friend's Group Challenge, Live Segments time-hiding, and
GPS/segment flags with no support
([Trustpilot](https://www.trustpilot.com/review/strava.com)).

### 2.10 What users love

1. **Kudos-giving ritual** — low-friction way to signal belonging.
2. **Segment-chasing** — "any hill becomes a game."
3. **Local Legends** — recognition for consistency, not speed.
4. **The Year in Sport annual unveil** — before paywalling.
5. **Strava Stats Stickers** for Instagram Stories.
6. **Flyby** — "I didn't know that was you!" path-crossing discovery.
7. **Trophy Case / achievement badges** — small dopamine wins.
8. **Global Heatmap** for trip planning.
9. **Club-level brand content** from Rapha, Le Col, GCN.
10. **Monthly distance badge collecting** — sustains off-season
    subscriptions. ([Trophy.so
    case study](https://trophy.so/blog/strava-gamification-case-study))

### 2.11 What users hate / what SuiSport can exploit

1. **Year-in-Sport paywall** — perceived as charging users for their own
   data.
2. **Segment leaderboards paywalled**.
3. **No club challenges** — most-requested feature since 2021.
4. **Weak DMs** — shipped reluctantly in 2024; bots / harassment concerns
   ([Escape
   Collective](https://escapecollective.com/will-messaging-help-strava-lead-the-pack/),
   [Marathon
   Handbook](https://marathonhandbook.com/strava-direct-messaging/)).
5. **Apple Watch sync bugs** with no recovery path ([Apple
   Discussions](https://discussions.apple.com/thread/255787180),
   [Community
   Hub](https://communityhub.strava.com/devices-and-connections-6/apple-watch-not-syncing-with-strava-app-tried-everythjng-10655)).
6. **Segments arbitrarily excluded** with no appeal.
7. **No emoji reactions on comments**.
8. **Aggressive in-app subscription modals** ([BarBend
   review](https://barbend.com/strava-app-review/)).
9. **No data export on cancel** — loss aversion forces retention.
10. **No stake/prize-backed challenges** — only brand-sponsored prize
    entries.
11. **No verifiable anti-cheat** — GPS spoofers top leaderboards; Strava
    is non-transparent about its Zero-Day Suspensions.
12. **No group training plans** — Runna is individual-only.
13. **FOMO and unhealthy social comparison** ([Canadian Cycling
    Magazine](https://cyclingmagazine.ca/sections/feature/why-i-should-quit-strava/),
    [BikeRadar
    opinion](https://www.bikeradar.com/features/opinion/why-ive-got-a-big-problem-with-strava)).
14. **No in-app goal tracking beyond distance** — no process goals, no
    pace goals, no strength-block goals.
15. **Privacy zones limited to address radius** — no true per-activity
    geofencing.

### 2.12 Small-but-loved details

- Kudos animation (subtle haptic + emoji puff).
- Trophy case on profile — most-recent-4 display.
- Streak / consistency counters in weekly summary.
- "1 year ago today" memory cards.
- Stats Stickers brand recognizable even cropped.
- Orange "+" logo as identity marker.
- Verified Athlete blue check.
- Relative Effort color coding on Training Log.
- Carrot/Wolf/PR avatars in Live Segments.

### 2.13 The dark side — what Strava does badly on purpose

1. **Weak DMs.** Strava keeps messaging thin because deep chat would
   cannibalize the public-feed engagement engine that drives kudos and
   thus retention.
2. **No goal tracking beyond distance.** Richer goals would reduce the
   need for the monthly-badge dopamine loop.
3. **Awkward Apple Watch app.** Strava wants you on the phone where the
   social feed lives.
4. **No data export that preserves social context.** Social graph is
   locked in.
5. **Opaque segment / flag moderation.** Opaque process is cheaper than
   fair process.

---

## 3. Nike Run Club: Deep Dive

Current status: 4.8/5 stars on the App Store with **412,000 ratings** and
Editors' Choice badge ([App Store
page](https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637)).
SGX Studio rates it **77/100** — "emotionally elite but functionally
capped" ([SGX Studio
report](https://sgx.studio/product-intelligence/report-nike-run-club/)).
Users have been vocally upset since a 2023 redesign-era update sent
ratings crashing from 4.5 to 1.5 before Nike patched back ([Refinery29
coverage](https://www.refinery29.com/en-us/2016/08/121457/nike-running-app-redesign-critique),
[Cult of Mac: "Why did Nike ruin its beautiful running
app?"](https://www.cultofmac.com/news/why-did-nike-ruin-its-beautiful-running-app)).

### 3.1 Audio / coaching layer (the crown jewel)

- **Guided Runs library** — ~300 runs across eight categories: Speed,
  Distance, Recovery, Long, First Run, Next Run, Headspace / Mindful,
  Specialty (trail, treadmill), celebrity-led.
- **Coach Bennett voice** — wrote the first guided-run scripts (First Run,
  Next Run, First Speedrun, Comeback Run).
- **Celebrity voices**: Eliud Kipchoge, Mo Farah, Shalane Flanagan, Kevin
  Hart (#RunWithHart), Bill Nye, Sally McRae (trail), English Gardner.
- **Headspace partnership** — 15 mindful runs, 25–60 min, hosted by
  Bennett + Andy Puddicombe. Titles like "Stress Free Run," "Morning Run
  with Headspace," "Don't Wanna Run Run," "Big Day Run," "Mindful
  Meters." ([Headspace partnership
  page](https://www.headspace.com/partners/nike-partnerships), [Nike
  Newsroom](https://news.nike.com/news/nike-headspace-partnership)).
- **Music ducking** — coach's voice fades your music down, then back up.
- **Audio pace/distance cues** at each mile or km.

### 3.2 Tracking / record experience

- GPS + pace + distance + elevation + HR + mile splits.
- Apple Watch + Garmin + Coros compatibility; standalone Apple Watch app
  since 2019 ([9to5Mac](https://9to5mac.com/2019/10/29/nike-run-club-apple-watch/)).
- Indoor / outdoor detection, manual entry.
- **Share Your Run Live** (Dec 2024) — generate a link, friends track
  real-time location without needing the app; safety confirmation on
  completion ([Nike
  Press](https://about.nike.com/en/newsroom/releases/nike-run-club-app-new-features)).
- **Know-Before-You-Go** weather / sunrise / sunset.
- **Race Finder** (v7.72, Oct 2024) — global event discovery.

### 3.3 Social graph + cheers

- Friends, activity feed, comments, likes.
- **Audio Cheers** — push-notifies friends when you start; they send
  pre-set or custom audio cheers that play mid-run ([9to5Mac on Custom
  Cheers](https://9to5mac.com/2018/05/10/custom-audio-cheers-nike/)).
- **Clubs** — user-formed groups. Members in Clubs are **2× more likely to
  retain at 90 days** vs. solo runners
  ([social.plus](https://www.social.plus/blog/community-story-nike-run-club)).
- Leaderboards (friends / weekly distance).
- **Instagram Stories share cards** with Nike-branded map + pace +
  distance overlay — iconic in running Twitter/IG culture.

### 3.4 Gamification

- **Trophies / Achievements**: 5K, 10K, half, full marathon; 100mi /
  500mi / 1,000mi lifetime; first speedrun; longest run; streak
  milestones; challenge completions.
- **Streaks** — **weekly, not daily** (at least one run every calendar
  week). This is much more forgiving than Strava's daily-run expectation
  and is cited as key to retention for beginners.
- **Pigment Progression** — UI color shifts with lifetime distance
  (Yellow → Volt), creating permanent status and switching costs.
- **Personal Bests** surfaced post-run — "competition with your past
  self."
- **Challenges** — weekly 3mi/9mi, monthly 100K, streak challenges,
  branded / seasonal challenges with limited-time modals and sometimes
  Nike gear prizes / early access ([Nike
  Help](https://www.nike.com/help/a/nrc-challenges)).

### 3.5 Training plans

- 4-week **Getting Started**, **5K**, **10K**, **half marathon**
  (12-week), **marathon** (16-week), plus a **next-level 5K** plan.
  ~6 plans total.
- Plans adapt (lightly) based on logged runs; Bennett narrates key
  workouts.
- **2023–24 rollback**: Adaptive coaching personalization that once
  retuned plans based on real performance became a thinner, "checklist-
  style" flow per reviewers. Long-time users lament loss of personalized
  workouts. Dennis Crowley (quoted in The New Consumer) said it feels
  like "no one is maintaining it anymore"
  ([TNC](https://newconsumer.com/2023/11/nike-run-club/)).

### 3.6 Commerce / brand integration

- **Shoe tagging** — log mileage per pair; prompts replacement ~500km
  ("Gear Mortality Ledger").
- Personalized gear recommendations tied to profile and run style.
- Deep link to Nike.com / Nike App for checkout.
- Member-exclusive product drops surfaced in-app; early access as
  challenge rewards.
- Physical Nike Run Clubs — NYC, global "Community Shakeout" run before
  NYC Marathon drew 1,200+ ([IDEKO
  case study](https://www.ideko.com/nike-nyc-community-shakeout-run)).

Nike uses NRC as **top-of-funnel for Nike.com running gear**: shoe
mileage → replace-prompt → upsell in-app → DTC growth from 28% to 44% of
Nike revenue 2017–2023 ([The New
Consumer](https://newconsumer.com/2023/11/nike-run-club/)).

### 3.7 Integrations & platform

- Apple Health (summary + HR + distance + calories; **GPS maps are NOT
  exported** — cult-of-mac flagged this as indefensible
  ([Cult of Mac](https://www.cultofmac.com/news/why-did-nike-ruin-its-beautiful-running-app))).
- Strava sync (activity export).
- Spotify + Apple Music.
- **Lost / restricted**:
  - Google Fit integration (killed).
  - Nike public API (locked down March 2024, breaking RunGap and
    third-party tools) ([RunGap
    explainer](https://rungap.zendesk.com/hc/en-us/articles/115000368794)).
  - Apple Watch Series 3 GPS (dropped late 2023).

### 3.8 What users love (quote-worthy)

1. **"Coach Bennett's instructions enabled me to run for twenty straight
   minutes without a break."** (App Store review) — he makes running feel
   possible.
2. **"It feels like running with a friend who always shows up."**
3. **"I went from hating running to loving it because of NRC."**
4. **Audio Cheers** — people describe tearing up mid-run when a friend's
   voice interrupts. "My dad cheered me on at mile 4. I cried through the
   rest of it."
5. **Instagram share card** — "posting my NRC map is the reward."
6. **Completely free** — repeated praise vs. Strava paywall.
7. **Headspace mindful runs** — "finally a way to run without
   self-criticism."
8. **Trophy / milestone unlocks** — "the marathon trophy was the
   proudest screenshot of my year."
9. **Celebrity guided runs** — Kipchoge telling you to slow down hits
   different.
10. **Streaks** — "I wouldn't have run three weeks in a row without the
    streak."

### 3.9 What users hate / the 2023–24 cull

- **App instability** — crashes mid-guided-run, sync failures, deleted
  runs, streaks lost to bugs. Reported on Apple Community, MacRumors,
  JustUseApp.
- **Apple Health export gap** — only summary + HR + distance + calories;
  GPS maps never exported.
- **API lockdown March 2024** — killed RunGap and third-party tools.
  Users can't fetch historic data. Major trust breach.
- **Apple Watch Series 3 GPS dropped late 2023** — users with 10-year-old
  Nike loyalty forced to buy new hardware.
- **Coach repetitiveness** — "coaches talk too much, not enough silent
  space."
- **Training plan regression** — 2023-era adaptive coaching became
  checklist-lite.
- **China shutdown** (June 2022,
  [CNN](https://www.cnn.com/2022/06/08/business/nike-run-club-app-china-shutting-intl-hnk/index.html))
  — full market exit destroyed goodwill.
- **4.5 → 1.5 App Store crash** after the redesign that removed
  run-data sharing in favor of photo-share-only cards ([Refinery29
  coverage](https://www.refinery29.com/en-us/2016/08/121457/nike-running-app-redesign-critique)).

### 3.10 Small-but-loved details

- The **Volt / Nike orange splash** on launch — brand identity cemented
  in half a second.
- **"Every Run Has A Purpose"** repeated as Bennett's catchphrase across
  app + podcast ([Spotify
  podcast](https://open.spotify.com/show/4zMl73Ot2pSrJFnwjS9dQD)).
- Coach's voice **exhaling with you** during warmups — parasympathetic cue.
- Haptic taps at mile markers on Apple Watch.
- Post-run **colorful map reveal** like a polaroid developing.
- **First-run trophy animation** — "you just did something you never did
  before."
- The Nike-branded corner watermark on the Instagram share — a tiny act of
  swoosh advertising that ~10M runners do for free each year.

---

## 4. Feature Scoring Matrix

All features rated on two axes: **Retention Impact (1–5)** — does this
feature measurably change user-return rates? — and **Crypto-Native
Leverage (1–5)** — does SuiSport gain a real advantage by rebuilding this
on Sui/Walrus (verifiability, tokenization, escrow, composability)?

| Source | Feature | Retention | Crypto | Score |
|---|---|---|---|---|
| Strava | Segments / KOM / QOM / Local Legend | 5 | 5 | **25** |
| Either | Stake-to-join challenges | 5 | 5 | **25** |
| Strava | Club DAOs with treasury | 4 | 5 | **20** |
| Strava | Kudos as on-chain micro-reputation / tip | 5 | 4 | **20** |
| Strava | Year-in-Sport as ownable NFT (free forever) | 5 | 4 | **20** |
| NRC | Weekly streaks with $SWEAT stake | 5 | 4 | **20** |
| NRC | Audio cheers with attached tip | 5 | 4 | **20** |
| NRC | Guided audio runs (named coach) | 5 | 2 | **10** |
| NRC | Achievement NFTs (First 5K, First Marathon) | 4 | 5 | **20** |
| Either | Sponsored-challenge escrow contracts | 4 | 5 | **20** |
| Strava | Verifiable anti-cheat (HealthKit + ZK) | 4 | 5 | **20** |
| Strava | Segment NFTs with creator royalties | 4 | 5 | **20** |
| NRC | Pigment / tier progression | 4 | 4 | **16** |
| Strava | Group-activity co-signed sessions | 4 | 4 | **16** |
| NRC | Shoe mileage NFTs | 4 | 5 | **20** |
| Strava | Monthly distance badges (on-chain) | 5 | 3 | **15** |
| NRC | Instagram share with "verified on Sui" watermark | 4 | 3 | **12** |
| Strava | Trophy case as soulbound SBT collection | 4 | 3 | **12** |
| NRC | Training plan with completion NFT | 4 | 4 | **16** |
| NRC | Live run sharing + tipped cheers | 4 | 5 | **20** |
| Strava | Flyby / path-crossing as on-chain event | 3 | 4 | **12** |
| Strava | Portable athlete profile as Sui object | 4 | 5 | **20** |
| Strava | Fitness/Freshness as verifiable DID attr | 3 | 3 | **9** |
| Strava | Route NFTs with usage royalties | 3 | 4 | **12** |
| NRC | Physical run-club events as attendance POAPs | 3 | 4 | **12** |
| NRC | Celebrity parasocial voice NFTs | 5 | 3 | **15** |
| NRC | Provable Personal Bests | 4 | 4 | **16** |

---

## 5. Top-Ranked Features To Steal For SuiSport

*(Ordered by overall impact × feasibility × crypto advantage — the
recommended build order.)*

1. **Verifiable segments + KOM/QOM/Local Legend leaderboards** on Sui.
   **`[shipped in v0.1]`**
2. **Stake-to-join challenges** with smart-contract escrow. **`[shipped in
   v0.1]`**
3. **Kudos-as-tip** in $SWEAT (even fractional cents — make the emotional
   act transactional). **`[shipped in v0.1]`**
4. **Club DAOs** with on-chain treasury + native club challenges.
   **`[shipped in v0.1 as UI + treasury story; on-chain DAO logic TBD]`**
5. **Year-in-Sport NFT** — free, beautiful, collectible, annual drop —
   directly weaponizing Strava's #1 unforced error.
6. **Soulbound Trophy Case** — portable across fitness apps. **`[shipped in
   v0.1]`**
7. **Weekly streaks + stake-to-commit** (NRC's most-loved feature,
   upgraded). **`[shipped in v0.1]`**
8. **Live-run audio cheers + attached $SWEAT tip** — fuses NRC's Dec-2024
   "Share Your Run Live" with tippable micro-interactions. *(Requires live
   recording UI first — v0.2.)*
9. **Sponsored challenges with on-chain prize escrow** — brands prove the
   prize exists. **`[shipped in v0.1 for UI; chain escrow TBD]`**
10. **Guided audio runs with a named SuiSport coach** — Nike's #1 moat; no
    Web3 competitor has this. *(v0.2+ — needs audio assets.)*
11. **Segment NFTs with creator royalties** — rewards the person who
    first mapped a segment every time it's run.
12. **Group-activity co-signed sessions** splitting shared $SWEAT reward.
13. **Shoe NFTs with depreciating mileage** — merges Nike shoe-tagging
    with tokenized gear.
14. **Portable profile as Sui object** — export/import across fitness
    apps. **`[architecturally shipped — Sui address is the profile
    primary key]`**
15. **Instagram share with on-chain proof deep link** — converts shares
    into referrals and proves the run isn't fabricated. **`[shipped in
    v0.1 as ShareCardSheet]`**

---

## 6. Copy / Audio Patterns Worth Stealing From NRC

From Coach Bennett and the NRC voice, consistently praised phrasing:

- **Opening**: *"Thanks for showing up today. That's the hardest part."*
- **Permission to go slow**: *"We've been taught that running is supposed
  to be hard. We've been told that easy running is not 'real' running."*
- **Reframe**: *"Start easy. Run the right way now, so you can run the
  right way later and finish strong."*
- **Validation during struggle**: *"If you feel like quitting, that just
  means you're trying."*
- **End-of-run**: *"I'll meet you at the next starting line."*
- **Purpose framing**: *"Every run has a purpose."* (Bennett's signature
  podcast title)
- **PR ritual**: *"You just did something today you've never done
  before."*
- **Philosophy**: *"Your best runs aren't measured by distance or time
  but by how they make you feel."*

**Audio pattern rules NRC follows — copy these:**

- Music ducks under coach, doesn't stop.
- Coach speaks ~20–25% of the run, not more.
- First 90 seconds: thank the runner, set intention.
- Every mile/km: pace + distance + one encouragement line.
- Last minute: cooldown cue, self-congratulation prompt.
- Post-run: *"Great run. You showed up. That matters."*

---

## 7. DO NOT Copy — Explicit Anti-Patterns From Both

1. **Paywalling user-generated summaries** (Strava's Year in Sport).
   Giving users their own data back is table stakes; SuiSport should make
   this explicitly free forever and enshrine it in the Move contracts.
2. **Asymmetric "dethroned" notifications** (Strava). Strava notifies the
   loser but not the winner. Celebrate both sides — the ascent AND the
   legacy.
3. **Aggressive modal upsells** (Strava). Reviews repeatedly cite these
   as the #1 UX offense.
4. **Opaque segment / flag moderation** (Strava). Sui gives us publicly
   auditable moderation logs — use them.
5. **Intentionally weak messaging** (Strava). Strava keeps DMs thin to
   protect the feed. SuiSport should ship real group chat tied to clubs
   and group activities, since our retention loop is tokens +
   verifiability, not attention-farming.
6. **API lockdown / walled garden** (NRC, March 2024). Don't betray
   developers. Make all workout data exportable, ideally Walrus-backed
   and portable. Verifiability is the structural advantage — don't
   waste it.
7. **Dropping old devices cynically** (NRC, Apple Watch Series 3).
   Aggressively support old HealthKit sources.
8. **Chatty coaches** (NRC complaint). Users *love* the voices but hate
   over-talk. Budget silence as a feature.

---

## 8. Strava vs. NRC Honest Comparison

| Dimension | NRC wins | Strava wins |
|---|---|---|
| Guided audio coaching | ✅ crown jewel | ❌ none |
| Free training plans | ✅ 6 free plans | ❌ paywall |
| Community / social graph | ❌ shallow friend lists | ✅ network-effect moat |
| Segments / leaderboards | ❌ | ✅ definitive |
| Data analytics | ❌ basic | ✅ HR zones, cadence, elevation, power |
| Gear database | ❌ Nike-only | ✅ every shoe model |
| Elapsed vs. moving time | ❌ elapsed only | ✅ both |
| Multi-sport | ❌ running only | ✅ all activities |
| Emotional hook | ✅ parasocial coach | ❌ competitive pressure |
| Beginner onboarding | ✅ best-in-class | ❌ intimidating |

**SuiSport lesson**: Steal NRC's warmth + onboarding. Steal Strava's
social graph + analytics. Add crypto-verifiable PRs (anti-Strava's rampant
cheating problem) as the differentiator.

---

## 9. SuiSport v0.1 Implementation Status

*(As of April 23, 2026. Items marked ✅ are built and building clean;
items marked ○ are scaffolded / placeholder; items marked ✗ are not yet
started.)*

### Social & feed
- ✅ Feed with kudos, comments, tip-kudos animation, comment peek, filter
  row (Following / Discover), share button
- ✅ Full `WorkoutDetailView` — hero map, stats grid, verified-on-Sui
  strip, kudos strip with tip buttons, comment list, composer
- ✅ `AthleteProfileView` — avatar with tier ring, verified badge,
  follow/message/tip buttons, trophy preview, recent activities
- ✅ Deterministic gradient avatars (`AthleteAvatar`) with tier ring
- ✅ Seeded realistic mock feed via `SocialDataService`

### Segments
- ✅ `SegmentsView` list with KOM/QOM/Local Legend chips
- ✅ `SegmentDetailView` with map hero, stat strip, KOM card, board tabs,
  top-10 leaderboard
- ○ Actual segment creation / detection from GPS traces (needs live
  recording)
- ✗ Segment creator royalties on-chain
- ✗ Live Segments (real-time pace-ahead/behind during recording)

### Clubs
- ✅ `ClubsView` — For You / Joined / Brands filter, featured brand card
- ✅ `ClubDetailView` — Activity / Members / Treasury tabs, join flow
- ○ Treasury card explains DAO mechanics; real on-chain DAO logic TBD
- ✗ Club challenges
- ✗ Club messaging / group chat

### Challenges
- ✅ `ChallengesView` — All / Joined / Sponsored filter
- ✅ `ChallengeDetailView` — stake banner, progress, rewards list, leader
  list, stake-to-join confirmation alert
- ○ Sponsored challenge UI complete; real on-chain escrow Move contract
  written but not yet deployed
- ✗ Private group challenges

### Trophies
- ✅ `TrophyCaseView` with category filter, rarity chips, lock overlays
- ✅ `TrophyDetailSheet` with "Soulbound to your Sui address" framing
- ○ Trophy mint logic: UI mock only; real mint on-chain TBD
- ✗ Year-in-Sport annual trophy drop

### Streaks
- ✅ Streak card in feed + profile, streak row with multiplier
- ✅ `StreakSheet` with stake-to-commit UI (10/25/50/100 Sweat presets)
- ○ Stake-to-commit UI; real on-chain stake TBD

### Share & identity
- ✅ `ShareCardSheet` with on-chain-verified watermark
- ✅ Tier progression visualization (Starter → Legend ring colors)
- ✗ Instagram Stories actual integration (share button is a stub)

### NRC-style audio / coaching
- ✗ Guided audio runs
- ✗ Coach voice pack
- ✗ Mid-run audio cheers
- ✗ Music ducking
- ✗ Mindful-run / Headspace-style partnership

### Recording
- ✓ `WorkoutRecorder` plumbing (iOS 26 `HKWorkoutSession` +
  `CLLocationUpdate.liveUpdates(.fitness)`)
- ✗ Live recording UI (record button currently opens a sheet picker only)

### On-chain / backend
- ✅ Move 2024 Edition package (sweat, admin, version, rewards_engine,
  workout_registry, user_profile, challenges) — compile target, not yet
  mainnet-deployed
- ✅ Backend Fastify scaffold with endpoint signatures and service stubs
- ✗ Enoki zkLogin real integration (currently mocked with deterministic
  fake Sui address)
- ✗ Walrus upload path
- ✗ App Attest verification
- ✗ Sui sponsored-transaction wiring

---

## 10. Future Roadmap Derived From This Research

### v0.2 — "The Coach" (next 8–12 weeks of work)
- Live recording UI with real-time map, pace, HR, splits, audio cues.
- **First guided audio run**: 20-minute "First Run" with a SuiSport
  coach voice. License or generate voice talent.
- **Mid-run audio cheers + $SWEAT tip** — friends see your run as a
  notification; tap to cheer with a tip; audio plays over your music,
  tip lands in your wallet post-run.
- Streak stake goes live on Sui testnet.

### v0.3 — "The Verification" (real chain integration)
- Enoki zkLogin replaces the mock.
- Walrus uploads encrypted GPS traces with `send_object_to = user_address`.
- App Attest verifies every submission.
- Move contracts deployed to Sui testnet; `submit_workout` mints real
  Sweat.
- Trophies mint as real soulbound NFTs.

### v0.4 — "The Network" (social depth)
- Real follower graph; push notifications on kudos / dethrones / club
  activity.
- Messaging (clubs-first, then 1:1) — the Strava gap.
- Group activities auto-grouped from overlapping GPS traces.
- Flyby-style path-crossing card.

### v0.5 — "The Brands" (revenue)
- Sponsored challenges with real brand escrow.
- Segment creator royalties.
- Sponsor drops gated on trophy ownership.
- First Year-in-Sport NFT drop — free, beautiful, collectible, annual,
  permanently exportable.

### v1.0 — "The Platform"
- Public API — no lockdown, ever (contract-level guarantee).
- Shoe NFTs with mileage tracking.
- Race finisher credentials (timing-chip oracle partnerships).
- Club DAOs with real governance.

---

## 11. Sources

### Strava

**Official**

- [Strava Support — What is Kudos?](https://support.strava.com/hc/en-us/articles/216918397-What-is-Kudos)
- [Strava Support — What's a segment?](https://support.strava.com/hc/en-us/articles/216917137-What-s-a-segment)
- [Strava Support — Local Legends](https://support.strava.com/hc/en-us/articles/360043099552-Local-Legends)
- [Strava Support — Live Segments](https://support.strava.com/hc/en-us/articles/207343830-Live-Segments)
- [Strava Support — Group Activities](https://support.strava.com/hc/en-us/articles/216919497-Group-Activities)
- [Strava Support — Activity Event Match](https://support.strava.com/hc/en-us/articles/38820095583629-Activity-Event-Match)
- [Strava Support — Matched Activities](https://support.strava.com/hc/en-us/articles/216918597-Matched-Activities)
- [Strava Support — Strava Challenges](https://support.strava.com/hc/en-us/articles/216919177-Strava-Challenges)
- [Strava Support — Group Challenges](https://support.strava.com/hc/en-us/articles/360061360791-Group-Challenges)
- [Strava Support — Feed Ordering](https://support.strava.com/hc/en-us/articles/115001183630-Feed-Ordering)
- [Strava Support — Strava Notifications](https://support.strava.com/hc/en-us/articles/216918367-Strava-Notifications)
- [Strava Support — Following Athletes](https://support.strava.com/hc/en-us/articles/115000173484-Following-Athletes-on-Strava)
- [Strava Support — Finding Friends and Managing Contacts](https://support.strava.com/hc/en-us/articles/216917377-Finding-Friends-and-Managing-Contacts-on-Strava)
- [Strava Support — Privacy Controls FAQ](https://support.strava.com/hc/en-us/articles/360025920332-Strava-s-Privacy-Controls-FAQ)
- [Strava Support — Edit Map Visibility](https://support.strava.com/hc/en-us/articles/115000173384-Edit-Map-Visibility)
- [Strava Support — Messaging on Strava](https://support.strava.com/hc/en-us/articles/19255163090573-Messaging-on-Strava)
- [Strava Support — Fitness & Freshness](https://support.strava.com/hc/en-us/articles/216918477-Fitness-Freshness)
- [Strava Support — All-Time PRs](https://support.strava.com/hc/en-us/articles/216918487-All-Time-PRs)
- [Strava Support — Best Efforts Overview](https://support.strava.com/hc/en-us/articles/19685360245005-Best-Efforts-Overview)
- [Strava Support — Athlete Intelligence](https://support.strava.com/hc/en-us/articles/26786795557005-Athlete-Intelligence-on-Strava)
- [Strava Support — Trophy Case](https://support.strava.com/hc/en-us/articles/216918557-The-Strava-Trophy-Case)
- [Strava Support — Verified Athlete Badges](https://support.strava.com/hc/en-us/articles/115000160850-Verified-Athlete-Badges-on-Strava)
- [Strava Support — Your Year in Sport](https://support.strava.com/hc/en-us/articles/22067973274509-Your-Year-in-Sport)
- [Strava Pricing](https://www.strava.com/pricing)
- [Strava Subscriber Perks](https://www.strava.com/subscription/perks)
- [Strava Global Heatmap](https://www.strava.com/maps/global-heatmap)
- [Strava Flyby Labs](https://labs.strava.com/flyby/)
- [Strava Press — 12th Annual Year in Sport Trend Report 2025](https://press.strava.com/articles/strava-releases-12th-annual-year-in-sport-trend-report-2025)
- [Strava Press — Nike Partnership](https://press.strava.com/articles/strava-and-nike-partner-to-serve-athletes)
- [Strava Press — Runna Acquisition](https://press.strava.com/articles/strava-to-acquire-runna-a-leading-running-training-app)
- [Strava Press — Night and Weekly Heatmaps](https://press.strava.com/articles/strava-expands-mapping-tools-with-night-and-weekly-heatmaps)
- [Strava Press — New Subscriber Features](https://press.strava.com/articles/strava-unveils-suite-of-new-subscriber-features)
- [Strava Business — Clubs vs. Traditional Social Media](https://business.strava.com/resources/strava-clubs-vs-traditional-social-media)
- [Strava Business — Sponsored Challenges](https://business.strava.com/challenges)
- [Strava Engineering — Activity Grouping](https://medium.com/strava-engineering/activity-grouping-the-heart-of-a-social-network-for-athletes-865751f7dca)
- [Strava Community — 10 Ways to Get More Kudos](https://communityhub.strava.com/insider-journal-9/10-ways-to-get-more-kudos-1573)
- [Strava Community — Create Club Challenges Idea](https://communityhub.strava.com/t5/ideas/create-club-challenges/idi-p/4987)
- [Strava Community — New KOM Notification Idea](https://communityhub.strava.com/t5/ideas/new-kom-notification/idi-p/18042)
- [Strava Community — Emoji Reacts on Comments Idea](https://communityhub.strava.com/t5/ideas/emoji-reacts-on-comments/idi-p/9873)
- [Strava Community — February 2025 What's New](https://communityhub.strava.com/what-s-new-10/check-it-out-what-s-new-on-strava-from-february-2025-9099)
- [Strava Community — Please Don't Be Facebook](https://communityhub.strava.com/strava-features-chat-5/please-don-t-be-facebook-928)
- [Strava Community — Apple Watch Not Syncing](https://communityhub.strava.com/devices-and-connections-6/apple-watch-not-syncing-with-strava-app-tried-everythjng-10655)

**Independent research / press / reviews**

- [ScienceDirect — Kudos make you run!](https://www.sciencedirect.com/science/article/pii/S0378873322000909)
- [ResearchGate — Reflections from the Strava-sphere](https://www.researchgate.net/publication/346678505_Reflections_from_the_'Strava-sphere'_Kudos_community_and_self-surveillance_on_a_social_network_for_athletes)
- [Marathons.com — Strava: the race for Kudos](https://www.marathons.com/en/featured-stories/strava-chasing-kudos-and-social-recognition/)
- [Triple Threat Life — Running for Kudos: Double-Edged Sword](https://triplethreatlife.substack.com/p/running-for-kudos-the-double-edged)
- [BikeRadar — Strava Local Legend launch](https://www.bikeradar.com/news/strava-local-legend)
- [BikeRadar — Year in Sport 2025 / cycling out of fashion](https://www.bikeradar.com/news/strava-year-in-sport-2025)
- [BikeRadar — Strava 2025 Updates](https://www.bikeradar.com/news/strava-updates)
- [BikeRadar — Why I'll Never Use Strava Again](https://www.bikeradar.com/features/opinion/why-ive-got-a-big-problem-with-strava)
- [BikeRadar — Free Alternatives to Strava](https://www.bikeradar.com/advice/fitness-and-training/free-alternatives-to-strava)
- [DC Rainmaker — Local Legends Rollout](https://www.dcrainmaker.com/2020/06/strava-legends-feature.html)
- [DC Rainmaker — Strava Acquires Runna](https://www.dcrainmaker.com/2025/04/strava-acquires-runna-thoughts-forward.html)
- [TechCrunch — Strava buys Runna and The Breakaway](https://techcrunch.com/2025/05/22/strava-is-buying-up-athletic-training-apps-first-runna-and-now-the-breakaway/)
- [GearJunkie — Strava 2025 AI Routes Update](https://gearjunkie.com/technology/strava-updates-2025-ai-routes)
- [Wareable — Is Strava Premium Worth It](https://www.wareable.com/sport/is-strava-premium-worth-it)
- [Cycling Magazine — Why I Should Quit Strava](https://cyclingmagazine.ca/sections/feature/why-i-should-quit-strava/)
- [Marathon Handbook — Direct Messaging Safety Concerns](https://marathonhandbook.com/strava-direct-messaging/)
- [Escape Collective — Will Messaging Help Strava Lead the Pack](https://escapecollective.com/will-messaging-help-strava-lead-the-pack/)
- [Triathlon Magazine Canada — Can Finally Use Emojis](https://triathlonmagazine.ca/feature/can-finally-use-emojis-strava/)
- [Cycling Weekly — Emojis on Strava](https://www.cyclingweekly.com/news/latest-news/you-can-now-use-emojis-in-strava-310183)
- [Deep Water Happy — When You Lose Your QOM](https://www.deepwaterhappy.com/2020/12/31/when-you-lose-your-qom-on-strava-the-1-app-for-runners-cyclists-swimmers/)
- [LetsRun — Strava Should Seriously Consider DMs](https://www.letsrun.com/forum/flat_read.php?thread=11180069)
- [Trustpilot — Strava Reviews](https://www.trustpilot.com/review/strava.com)
- [Product Hunt — Strava Reviews](https://www.producthunt.com/products/strava/reviews)
- [BarBend — Strava App Review 2026](https://barbend.com/strava-app-review/)
- [StriveCloud — How Strava Drives App Engagement](https://www.strivecloud.io/blog/app-engagement-strava)
- [Trophy.so — Strava Gamification Case Study](https://trophy.so/blog/strava-gamification-case-study)
- [Agate Level Up — Strava's Gamification Secret](https://agatelevelup.com/stravas-secret-how-gamification-is-redefining-fitness-and-user-engagement-in-2025/)
- [Slashdot — Strava Puts Year in Sport Behind $80 Paywall](https://news.slashdot.org/story/25/12/19/2158235/strava-puts-popular-year-in-sport-recap-behind-an-80-paywall)
- [World Today Journal — Year in Sport $80 Paywall Backlash](https://www.world-today-journal.com/strava-year-in-sport-80-paywall-sparks-backlash/)
- [T3 — Strava Paywall Problem](https://www.t3.com/tech/dear-strava-we-have-a-paywall-problem-thats-gone-a-step-too-far)
- [Road.cc — Year in Sport Only for Subscribers](https://road.cc/content/news/strava-year-sport-now-only-subscribers-317425)
- [The Runners Digest — Privacy Settings for Runners 2025](https://therunnersdigest.com/strava-privacy-settings-for-runners-2025/)
- [RunFlick — Share Strava on Instagram 2026](https://runflick.com/blog/share-strava-on-instagram)
- [Athletech News — Strava Year in Sport Report](https://athletechnews.com/running-walking-strength-training-strava-year-in-sport-report/)
- [The5KRunner — Strava 2025 Year in Sport Report](https://the5krunner.com/2025/12/04/strava-2025-year-in-sport-report-apple-watch-coros-gen-z/)

### Nike Run Club

**Official**

- [Nike Run Club App Store page](https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637)
- [Nike Run Club on Google Play](https://play.google.com/store/apps/details?id=com.nike.plusgps)
- [Nike.com NRC App](https://www.nike.com/nrc-app)
- [Nike Press Release — NRC new features (Share Your Run Live, Know-Before-You-Go)](https://about.nike.com/en/newsroom/releases/nike-run-club-app-new-features)
- [NRC Guided Runs: Speed](https://www.nike.com/au/running/guided-runs/speed)
- [NRC Guided Runs: Mindful](https://www.nike.com/au/running/guided-runs/mindful)
- [Nike Run Club Marathon Training Plan PDF](https://www.nike.com/pdf/Nike-Run-Club-Marathon-Training-Plan-Audio-Guided-Runs.pdf)
- [Nike Help — Challenges in NRC](https://www.nike.com/help/a/nrc-challenges)
- [Nike Help — What Features Can I Use During My NRC Run?](https://www.nike.com/help/a/nrc-run-features)
- [Nike Help — Share My NRC Run on Social Media](https://www.nike.com/help/a/nrc-share)
- [Headspace — Nike Partnership page](https://www.headspace.com/partners/nike-partnerships)
- [Nike Newsroom — Nike + Headspace](https://news.nike.com/news/nike-headspace-partnership)
- [Coach Bennett's Podcast on Spotify](https://open.spotify.com/show/4zMl73Ot2pSrJFnwjS9dQD)
- [Defy the Distance: Nike Running Challenge on Strava](https://www.strava.com/challenges/defy-the-distance-nike-running-challenge)

**Independent press / reviews**

- [NPR — Nike Run Club's oddly mindful coach](https://www.npr.org/2023/11/04/1210678199/nike-run-clubs-oddly-mindful-coach)
- [VPM/NPR — Nike Run Club's oddly mindful coach](https://www.vpm.org/npr-news/npr-news/2023-11-04/nike-run-clubs-oddly-mindful-coach)
- [Cult of Mac — Why did Nike ruin its beautiful running app?](https://www.cultofmac.com/news/why-did-nike-ruin-its-beautiful-running-app)
- [The New Consumer — Is Nike actually good at digital?](https://newconsumer.com/2023/11/nike-run-club/)
- [SGX Studio — Product Intelligence: Nike Run Club](https://sgx.studio/product-intelligence/report-nike-run-club/)
- [Trophy.so — NRC gamification case study](https://trophy.so/blog/nike-run-club-gamification-case-study)
- [StriveCloud — NRC Gamification examples](https://www.strivecloud.io/blog/gamification-examples-nike-run-club)
- [GoodUX — NRC's gamified approach](https://goodux.appcues.com/blog/nike-run-club-gamification)
- [Gear Patrol — Nike's Run Club App Made Me Fall in Love with Running Again](https://www.gearpatrol.com/fitness/a43976920/nike-run-club-app-review/)
- [Tom's Guide — NRC review](https://www.tomsguide.com/reviews/nike-run-club-review)
- [Mostly Media — NRC Review 2025](https://mostly.media/nike-run-club-full-app-review/)
- [Coach Web — Is NRC Better Than Strava?](https://www.coachweb.com/gear/fitness-apps/is-nike-run-club-better-than-strava)
- [Medium — Lessons from NRC's Guided Runs](https://medium.com/tan-kit-yung/lessons-from-nike-running-clubs-guided-runs-74b8b297500d)
- [Zero to Ultra — NRC Guided Runs](https://zerotoultra.home.blog/2019/10/08/nrc-guided-runs/)
- [Wareable — NRC mindful runs with Headspace](https://www.wareable.com/running/nike-run-club-mindful-runs-headspace-221)
- [TechRadar — Nike partners with Headspace for mindful run coaching](https://www.techradar.com/news/meditation-while-you-jog-nike-partners-with-headspace-for-mindful-run-coaching)
- [9to5Mac — Custom Audio Cheers launch](https://9to5mac.com/2018/05/10/custom-audio-cheers-nike/)
- [9to5Mac — NRC standalone Apple Watch app](https://9to5mac.com/2019/10/29/nike-run-club-apple-watch/)
- [9to5Mac — NRC with Apple Watch Nike+ review](https://9to5mac.com/2017/04/05/apple-watch-nike-review/)
- [9to5Mac — Audio Guided Runs + elevation support](https://9to5mac.com/2017/10/02/nike-run-update-apple-watch/)
- [DC Rainmaker — Apple Watch Series 2 Nike Edition review](https://www.dcrainmaker.com/2017/02/apple-watch-series2-nike-edition-review.html)
- [Marketing Dive — NRC adaptive coaching launch](https://www.marketingdive.com/ex/mobilemarketer/cms/sectors/sports/23490.html)
- [RunGap Support — Why Nike is no longer supported](https://rungap.zendesk.com/hc/en-us/articles/115000368794-Why-Nike-is-no-longer-supported-by-RunGap-and-how-to-get-your-data-anyway)
- [CNN Business — Nike shutting NRC in China](https://www.cnn.com/2022/06/08/business/nike-run-club-app-china-shutting-intl-hnk/index.html)
- [Refinery29 — NRC redesign critique](https://www.refinery29.com/en-us/2016/08/121457/nike-running-app-redesign-critique)
- [JustUseApp — Nike Run Club problems (2026)](https://justuseapp.com/en/app/387771637/nike-run-club/problems)
- [JustUseApp — Nike Run Club reviews (2025)](https://justuseapp.com/en/app/387771637/nike-run-club/reviews)
- [Apple Community — NRC app on Apple Watch suddenly not working](https://discussions.apple.com/thread/255276834)
- [Apple Community — NRC won't display / Series 3 drop](https://discussions.apple.com/thread/255267842)
- [Nike Help — NRC run not showing / GPS](https://www.nike.com/help/a/nrc-gps)
- [Nike Help — Why didn't my run sync](https://www.nike.com/help/a/nrc-upload)
- [Media Structures — #RunWithHart (Kevin Hart + Nike)](https://www.mediastructures.co.uk/run-with-hart/)
- [social.plus — NRC community-driven fitness](https://www.social.plus/blog/community-story-nike-run-club)
- [Collins — Nike Run Club design work](https://www.wearecollins.com/work/nikerunclub/)
- [PRINT Magazine — NRC UX work with Collins](https://www.printmag.com/branding-identity-design/nike-run-club-app-improves-user-experience-with-help-from-collins/)
- [Nike Experiences — Run Club events](https://www.nike.com/experiences/events)
- [IDEKO — Nike NYC Community Shakeout Run](https://www.ideko.com/nike-nyc-community-shakeout-run)
- [Strength Running — Chris Bennett on Good Coaching](https://strengthrunning.com/2024/06/chris-bennett/)

---

*Document maintained by the SuiSport product team. Update as we learn
more and as competitor feature sets change. Last research passes: two
parallel agents, April 23, 2026.*
