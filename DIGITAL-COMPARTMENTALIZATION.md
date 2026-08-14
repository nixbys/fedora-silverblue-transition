# Digital Life Compartmentalization Plan

Companion to TRANSITION-PLAN.md — same underlying principle (compartmentalize
by category, don't let one identity leak into another), applied to accounts
and personas instead of containers and Flatpaks.

## The compartments

| Compartment | Real-identity or pseudonym? | Handle | Why |
|---|---|---|---|
| **Real identity** — financial, legal, government, LinkedIn | Real identity | **josdar** | KYC and professional networking both require real, verifiable identity — no privacy benefit to separating these from each other, only from the pseudonymous compartments below |
| **Real identity** — GitHub specifically | Real identity | **nixbys** | Same "real identity" bucket as above, just a different label on a different platform — normal to use platform-specific handles as long as all of them stay real/findable and none touch the gaming compartment |
| Gaming / content (YouTube, Discord, Reddit) | Pseudonym, zero real-identity links | **new — see below** | The entire point of the faceless-channel strategy. Do not reuse `nixbys` or `josdar`. |
| Security research / CTF (TryHackMe, HackTheBox) | Your call | **c4k3b0i** (checked, appears clean — see note) | Same portfolio-vs-private question as GitHub used to be — TryHackMe/HackTheBox aren't automatically "professional" just because GitHub is, worth deciding explicitly |
| Personal / social (Signal, personal Fediverse, friends & family) | Real-ish (first name or a nickname people already know you by) | Your call | Low stakes — this is for people who already know who you are |
| Privacy / research / anonymous browsing | No persistent identity at all | *(none — that's the point)* | Tor Browser, sensitive lookups. A username here defeats the purpose. |

**The actual boundary that matters in this whole table is just one line: real identity (`josdar`, `nixbys`, real name — doesn't matter which label on which platform) versus the gaming pseudonym, full stop.** Using two different real-identity handles across platforms isn't a problem to fix — that's normal, plenty of people use different specific usernames per professional platform while still being the same identifiable person once you know their name. The thing that would actually break compartmentalization is either of those touching the gaming compartment, not them differing from each other.

## New handle: gaming / content

Needs to work identically across YouTube, Discord, and Reddit (same handle
everywhere in this compartment keeps it simple to manage — see the container
rule below for why that's *safe* to do within the compartment even though
cross-compartment reuse isn't). Went for something that fits the AQW/Artix
aesthetic without touching any actual trademarked terms, and that reads as a
deliberate brand rather than a random string — helps discoverability too,
not just privacy:

- **duskrunner**
- **hollowvale**
- **cindermarch**
- **unseenadept** — leans into the faceless/no-facecam identity as an actual creative angle rather than hiding it
- **hushherald** — same idea, narrator/voiceover-coded

Pick whichever reads best out loud as a channel name, then check actual
availability yourself across YouTube/Discord/Reddit before committing —
that's not something I can verify from here.

## Real identity — `josdar` (LinkedIn, financial, legal) + `nixbys` (GitHub)

Two labels, one compartment. `josdar` covers LinkedIn and everything
financial/legal/government; `nixbys` covers GitHub. Different strings on
different platforms, same underlying rule for both: real, findable,
verifiable — and neither one ever touches or references the gaming
compartment. Nothing to change about either account. The only actual
requirement going forward is discipline: no shared avatar or bio phrasing
between this bucket and the gaming handle, and no cross-linking the two.

**The one thing that did need action: a shelved YouTube project already
using `nixbys`.** Rename it — and because it's shelved with little to no
published content, this is the cheapest possible moment to do it properly.
Two layers, not just one:
1. The channel handle/display name — rename to a gaming-compartment option.
2. The underlying Google account itself — if its actual email or recovery
   info also references "nixbys" (not just the channel's display name),
   renaming the channel alone doesn't fix that, same reasoning as rule #8
   below. Since the channel is unused, starting a genuinely new Google
   account costs almost nothing here and removes the risk instead of just
   relabeling it.

**OWASP membership confirms this is genuinely you, not a coincidence** —
resolves the ambiguity flagged a few turns back about whether `nixbys` the
GitHub account and you were actually the same person. Two things follow
from that, not a change to the plan itself:

1. **This is likely a real-world identity, not just a GitHub bio tag.**
   OWASP chapters commonly meet in person, tied to a specific metro area —
   the "North Las Vegas, NV" signal in that bio probably isn't incidental.
   If there's an in-person component (chapter meetups, networking, possibly
   eventually speaking), that identity is real-name-and-location-tied at a
   level well beyond what a username swap could ever undo. Good reason the
   "never let this touch the gaming compartment" rule matters more here than
   it might for a purely online-only professional handle.
2. **Worth leaning into, not just protecting.** Since `nixbys` and `josdar`
   are confirmed the same real-identity compartment, cross-linking *within*
   it is fine and actually useful for the career-transition goal — listing
   OWASP membership on LinkedIn, linking GitHub from LinkedIn, letting the
   professional identity read as one coherent, credentialed story rather
   than two disconnected profiles. The rule was always "don't cross-link
   *between* compartments," not "don't cross-link at all" — within this one,
   more cohesion helps.

Also relevant to the still-open CTF question below: OWASP membership plus
HackTheBox/TryHackMe achievements is a genuinely strong, coherent
"credentialed security professional" narrative if the portfolio path is
what's wanted there. Not deciding that for you — just flagging that this new
information is relevant context for a choice that was already left open.

## AQWorlds accounts — payment history complicates this one

Different in kind from every other compartment issue in this plan: not
fixable with tooling. Artix Entertainment's ToS means accounts can be
disabled but not deleted once a purchase has been made, and **every
AQWorlds account here — including `mandyr` (primary) and `ethan9056`, the
two actually in active use — has a purchase linking back to the real bank
account.** Disabling/re-enabling doesn't change that; the backend record
persists either way.

**What kind of risk this actually is, precisely:** not the same category as
`nixbys` was. `nixbys` was *active* exposure — searchable by anyone, today.
This is *latent* — it only becomes a real problem if Artix is breached,
receives a legal request targeting the account, or an employee misuses
access. All three are real possibilities, not zero, but it's dormant rather
than live. That distinction affects urgency, not whether the risk is real.

**Structurally the same lesson as the GitHub-rename question, worth naming
explicitly:** featuring `mandyr` on the channel because it's the established,
most-progressed account is the same move renaming `nixbys` for gaming
would have been — reusing something already entangled instead of starting
clean. The only way to fully close this specific gap is a genuinely new
account that never has and never will have a payment method attached, not
picking among the existing ones.

**Two real paths, not resolved here — a genuine trade-off, not a clear fix:**

| | Keep `mandyr`/`ethan9056` as featured | Fresh account, zero payment methods, ever |
|---|---|---|
| Upside | Years of progress/items kept, already feels like "the" account for content | Closes the gap completely |
| Cost | Permanent, un-fixable backend link to real bank account sits behind whatever's shown on camera | Grinding back to where `mandyr` already is; doesn't match the existing "primary account" identity |
| Risk level | Latent, small probability, but genuinely unfixable after the fact if it ever surfaces | None on this specific vector |

Leaning fresh-account given this whole plan is built around maximizing
security — but this one is a real effort-vs-risk-tolerance call, not
something to default into either direction.

**Re-enabling the abandoned/disabled accounts for rare personal use (not
featured on the channel) stays low-risk regardless of which path above gets
chosen** — that risk only activates for whatever actually appears in front
of an audience.

### The rest of the AQWorlds handle list, reviewed individually

Once several accounts are all featured on the same channel, they're already
publicly tied together as "your accounts" — that correlation is intentional,
not a leak. So the useful question per handle isn't "does this link to the
others" (it's supposed to), it's "does this specific string, alone, leak
anything about real identity":

- **`DarkSide1998`** — flagged directly: age is 27 as of mid-2026, putting
  birth year around 1998. A number in a handle matching a birth year is one
  of the most common, easiest-to-miss self-doxxing patterns there is. Worth
  confirming whether that's literal before this one goes anywhere near the
  channel.
- **`Ethan Charge` / `ethan9056`** — checked directly, no existing
  identifiable account found under either string. Open question, not
  resolved: does "Ethan" carry any personal significance (a real name,
  yours or someone else's)? If it's a purely stylistic pick, fine as-is.
- **`Yoshiko` / `Yoshikon`** — no real-name signal in either, low stakes.
- **`mandyr`, `Chiffy`** — nothing that reads as identity-bearing on the
  string itself; `mandyr`'s issue is the payment history above, not the name.

### Refining the "one account per service" plan going forward

The account count isn't actually the load-bearing part of that plan — the
AQWorlds situation shows why. A single account, the moment it ever takes a
payment, permanently carries that financial link for its whole life under
Artix's retention policy. So "one account per game" only prevents this
problem if it's paired with a role decision made *before* the account is
used: is this account going to be personal/private (fine to attach a
payment method, never appears on the channel), or channel-public (never a
payment method attached, ever, full stop)? Trying to have one account serve
both roles is the actual structural problem — not the number of accounts.
Worth setting that rule explicitly for every new game/service going forward,
not just AQWorlds.

## Firefox architecture: profiles + containers, named

Two different Firefox features, worth using both rather than just
containers for everything — they solve different problems:

- **Containers** (Multi-Account Containers, already installed) — separate
  cookie jars/storage within the *same* Firefox process. Fast to switch
  between, good for keeping same-risk-level things from bleeding into each
  other. Everything still shares one extension set, one process.
- **Profiles** (`about:profiles`) — genuinely separate Firefox instances:
  own extensions, own cache, own storage location, can even run
  simultaneously. Heavier to switch between, but real isolation.

Three profiles, not one, because two of these compartments have a concrete
technical reason to be fully separate, not just a privacy one:

| Profile | Compartment | Why a full profile, not just a container |
|---|---|---|
| **Default** (existing, don't rename) | Real identity — financial, LinkedIn, GitHub | Baseline — no change needed |
| **Frontier** | Gaming/content — highest audience exposure of anything in this plan | The one compartment where a shared-process leak would matter most; worth the strongest available isolation |
| **Range** | Security research/CTF | Practical, not just privacy: HackTheBox/TryHackMe work often means proxy settings (Burp/FoxyProxy), custom CA certs, and dev-tools configuration you don't want anywhere near normal browsing — a shared profile means those settings leak into every other tab |

Create them via `about:profiles` in Firefox, or from a terminal (Flatpak
Firefox, matching what's actually installed):
```bash
flatpak run org.mozilla.firefox -P
```
launches the profile picker. Create "Frontier" and "Range" there. Launch a
specific one directly with:
```bash
flatpak run org.mozilla.firefox -P "Frontier" --new-instance
```

### Containers within `Default` (real identity)

| Container | Icon | Color | Covers |
|---|---|---|---|
| **Finance** | dollar | green | Banking, EveryDollar, taxes, bills |
| **Work** | briefcase | blue | Walmart portal, LinkedIn, GitHub (`nixbys`) |
| **Shopping** | cart | orange | Amazon, retail, subscriptions |
| **Personal** | fruit | pink | Signal web companion, personal Fediverse, casual real-name browsing |

### Containers within `Frontier` (gaming/content)

| Container | Icon | Color | Covers |
|---|---|---|---|
| **Channel** | fingerprint | purple | YouTube Studio, creator-facing Discord, the gaming/content brand identity itself |
| **AQW** | tree | turquoise | AQWorlds specifically (`mandyr`/`ethan9056`, or the future clean account) — deliberately its own container, not lumped in with Channel, given the payment-history discussion: if one ever gets compromised, it doesn't trivially expose the other's session |
| **Community** | circle | yellow | Reddit specifically, kept separate from Discord/YouTube per the earlier Reddit compartmentalization discussion |

### Within `Range` (security research)

Already isolated at the profile level, so a container inside it is optional
— add **CTF** (fingerprint, red) only if you end up wanting a second
identity inside this profile later. Not necessary to start.

### What deliberately isn't here

Privacy/anonymous research doesn't get a Firefox container or profile —
that compartment is Tor Browser's job specifically, per the earlier plan.
Giving it a regular-Firefox container would undermine the point: a
container inside Firefox still carries Firefox's own fingerprint and
extension set, which Tor Browser is specifically built to avoid.

## Security research / CTF (TryHackMe, HackTheBox) — `c4k3b0i`

Checked this one directly (same self-audit instinct IntelTechniques teaches —
search your own handles before someone else does): no existing, identifiable
account under this exact string turned up. That's a search-engine check, not
full OSINT, but it's a meaningfully different result than `nixbys` got, where
I had firsthand confirmation it's a real, geolocated, professionally-tied
identity. This one looks unburned.

**Worth deciding explicitly, not by default:** GitHub landed on "professional, findable" because that's what you use it for. TryHackMe/HackTheBox aren't automatically the same just because GitHub resolved that way — CTF practice runs, half-finished rooms, and lower-ranked periods are a different kind of visible than curated repos. If you want recruiters checking your GitHub to also find your HTB/THM rank, keep it under the same professional identity. If you'd rather practice and fail without that being watched, `c4k3b0i` stays exactly as it is. Either is reasonable — just pick one on purpose rather than defaulting into it.

Platform-specific hygiene either way:
- Check each platform's profile visibility settings — HTB and THM both
  default to showing rank/completed content publicly; some activity can be
  set private.
- Don't attach real payment info to either platform under this handle if
  you're keeping it in the private-practice bucket — same virtual-card logic
  as the payment-separation rule below.

## Rules that actually make compartments hold

The usernames are the easy part — these are what actually prevent bleed-through:

1. **A dedicated Proton email alias per compartment**, not per service. One
   alias for gaming/content, one for CTF practice (if kept separate from
   professional), one for financial (or real address, since that's expected
   there). Never the same alias across compartments — an alias leak only
   exposes one compartment, not all of them.
2. **A dedicated Firefox container or profile per compartment** — see the
   "Firefox architecture" section above for the actual names, icons, and
   which compartments get a full profile versus just a container.
3. **No shared avatar or profile photo across compartments.** Reverse image
   search is a real, easy deanonymization path — this is one of
   IntelTechniques' most emphasized points, and it's the single easiest rule
   to accidentally break by reusing a photo you like.
4. **Never cross-reference compartments in content or bios.** No "check out
   my other account," no bio text reused verbatim between the gaming handle
   and anything real-name-linked. Writing-style correlation (stylometry) is
   a real but harder-to-fully-defend-against risk — not worth obsessing
   over, but a reason to genuinely write differently across compartments
   rather than copy-paste bios.
5. **Separate Proton Pass folders/tags per compartment** so nothing in the
   vault itself visually groups them together at a glance.
6. **Strip metadata before publishing anything.** YouTube video files and
   any images carry EXIF/creation metadata by default — check this is
   scrubbed before upload, especially early on before it's habit.
7. **Payment separation where it's worth the friction.** A virtual/single-use
   card for gaming-compartment subscriptions (if you ever monetize or pay
   for anything under that identity) keeps a breach or chargeback dispute
   from ever touching your real financial identity. Not necessary for every
   small purchase — worth it specifically for anything recurring under the
   gaming handle. The AQWorlds section above is what happens when this rule
   comes too late — worth reading if this one feels abstract.
8. **Renaming an existing account is never a substitute for a fresh one when
   the goal is a new compartment.** GitHub's own docs confirm contribution
   graphs, repos, and commit attribution all follow a username change — the
   account's *history* is the actual fingerprint, not the current label on
   top of it. Search engines/web archives may also have already indexed the
   old name together with any bio/location info, which a rename doesn't
   retroactively undo. If an existing account already has history tied to
   one compartment, repurposing it for another compartment doesn't actually
   separate them — only a genuinely new signup (new email, zero shared
   history) does that. See the shelved-YouTube note above for the concrete
   version of this.

## Where your existing accounts from other conversations fit

- **Reddit** (discussed earlier): gaming/content compartment, its own
  container, signed up with the gaming compartment's email alias — not your
  existing personal Reddit account if you have one.
- **Discord**: gaming/content compartment. Given the recent age-verification
  rollout discussed earlier, don't attach payment info or anything
  real-identity-linked to this account regardless of which handle it uses.
- **Element**: personal compartment, unless you end up using it for a
  gaming-adjacent community space, in which case it moves to that
  compartment instead.
- **Mastodon** (you mentioned having an account already): worth deciding
  explicitly which compartment it's actually serving right now — personal,
  or promotional for the channel — since Pixelfed/Lemmy/Friendica from the
  last conversation should follow whichever compartment Mastodon is already
  in, not create a fourth undecided bucket.
