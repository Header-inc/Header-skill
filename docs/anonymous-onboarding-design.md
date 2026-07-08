# Anonymous onboarding — custom topic by default — design spec

Status: **drafting (2026-06-30)**. Target: skill **v0.38.0** (phased — see §7).
Backend contract: [`anonymous-auth-backend-spec.md`](anonymous-auth-backend-spec.md).

The header skill already does the hard half of custom briefings — it detects the stack,
creates a topic, binds it to the repo, polls the async briefing, and enriches future audits
from it (`reference/topics.md`, `reference/custom-briefings.md`). But today that whole motion
is a **post-audit upsell** gated behind a manual hill: *audit lands → far down the flow, "want a
custom topic? go to joinheader.com, start a trial, mint a read+write key, paste it."* Almost no
one climbs it, so the default enrichment stays the two generic public topics forever.

This spec **flips the upsell into a first-run choice**: instead of defaulting to the generic feed
and hiding "custom" behind a signup wall, the skill asks once — *generic agentic recommendations, or
ones tuned to this codebase?* On **custom**, it silently mints an anonymous trial account, creates a
topic tuned to the repo, and from then on enriches every audit from *that* briefing. The account is
convertible to a real one at any time via a claim link, with the API key and all topics/briefings
preserved. On **generic**, nothing leaves the machine beyond the public-topic fetch, exactly as today.

It is **mostly client-side re-sequencing** — the topic/bind/poll/enrich plumbing already ships.
The one genuinely new backend surface is **anonymous registration + the claim link** (§ backend spec).

## Decisions locked

Resolved in design discussion (do not relitigate during build):

1. **One upfront choice, then silent.** *(supersedes the earlier "fully silent" framing.)* On the
   first run for a repo the skill asks one value-framed question — **generic** agentic
   recommendations (public topics, nothing project-derived leaves the machine) **or custom**, tuned
   to this codebase. This single choice *is* the consent: picking custom authorizes the one-line
   stack-summary egress, after which account creation + topic creation proceed **silently** (no
   "we're making an account" prompt). The choice is the disclosure point and is fully reversible
   (`/header account`, `auto_register false`, re-ask per repo). See §2, §3, §6.
2. **Claimable anytime.** The anonymous account converts to a full account by visiting
   `https://joinheader.com/signup?code=<claim_code>`. **Claim = link, not migrate**: the anonymous
   account and the full account are the *same row* — claiming attaches email/auth and flips
   `claimed`, so the existing `hdr_sk_…` keeps working and no data moves. Surface the CTA at
   onboarding and as a soft nudge thereafter (§5).
3. **Run 1 defers only the briefing section.** The audit/coach/config/waste/rails recommendations
   render immediately; the **briefing-derived** recommendations are produced by a background agent
   when the freshly-created briefing finishes (~3–5 min) and surfaced as a follow-up pass (block as
   fallback). No generic-public enrichment on the onboarding run — public is the *fallback only* if
   register fails. See §4.
4. **Upgrade is UI-only.** When the trial ends, the skill never tries to charge; it points to the
   web UI (`/signup?code=…` to claim+upgrade, or the billing portal if already claimed) and falls
   back to public-topic enrichment so audits keep working (§5).
5. **Machine-scoped identity.** One anonymous account per device, keyed on the existing
   `~/.header/installation-id`. Many repos/topics live under it. Trial and tier caps are per account.

---

## 0. Why this exists, why now

The relevance gap is the whole product. A briefing from "Agentic Coding" + "Self Improving Agent"
is a good newsletter that *happens* to mention your stack; a briefing built from *your repo's*
detected stack is the thing that makes a recommendation land. The skill can already produce the
second kind — it just hides it behind a signup wall that filters out ~everyone. Anonymous
registration removes the wall: the first `/header` on a new machine ends with a repo-specific topic
already created and generating, not a pitch to go make an account.

This is also the on-ramp for everything downstream: goal auto-tuning, the experiment-sync dashboard,
and scheduled briefings all require a key + a custom goal. Silent anonymous register is the one move
that makes all of them reachable by default.

## 1. Scope of the change

**New backend** (one endpoint family — see the backend spec):

- `POST /api/v2/auth/anonymous` — idempotent on `installation_id`; creates an anonymous account,
  **auto-starts the existing 15-day Pro trial** (reusing `/billing/trial/start`, keyed per
  installation since there's no email — so `POST /topics/` doesn't bounce on `TOPIC_LIMIT_FREE`),
  mints a `full`-scope `hdr_sk_…` (existing `/api-keys` model), returns it + trial fields + `claim_url`.
- `/signup?code=<claim_code>` — UI consumes the code, attaches a Clerk identity to the same account.
- Abuse controls on `POST /auth/anonymous` (the spam magnet is account *creation*; the trial itself
  stays standard).

**Everything else reuses the existing API** — no new surface: `GET /billing/subscription` for tier/trial
state (`trial_active` / `trial_ends_at` / `can_start_trial` / `tier_flip_kind`); the `*_FREE` /
`*_QUOTA` tier-gate codes (flat `{"error_code","message"}`); `/billing/create-checkout` for upgrade.
**No `/auth/me`, no `TRIAL_EXPIRED`.**

**New client** (mostly re-sequencing existing pieces):

- `header-auth` bin — `register` (curl → save credentials → write `~/.header/.account`),
  `save-key` (the existing-user paste path, same hardened save), `state`, `status`, `claim-url`.
  Encapsulates the API + local-state writes so SKILL prose stays thin and the path is unit-tested
  (consistent with every other bin having a `.test.sh`).
- Preamble signals: `ACCOUNT:` and `AUTO_REGISTER:` (§6).
- Re-sequence: silent register + default topic creation move **out of** the post-audit upsell
  (`reference/topics.md`) **into** the default flow; the upsell wording is retired.
- Deferred-briefing pass on the onboarding run (§4).
- `/header account` subcommand + claim/trial messaging + doc/privacy updates (§5, §6).

**Reused unchanged:** `installation_id`; topic create → `first_briefing_id`; `header-repo bind`
/ `get` / `seen` / `flag`; the bound-repo freshness check; the polling cadence; `header-cost`,
`header-audit`, the ledger.

## 2. The first run (new device, new repo, interactive)

Ordering, after the existing preamble → update-check → welcome/language:

1. **Audit (Step 3 scans)** — local, read-only. Detects the stack. *Unchanged; always runs.*
2. **The enrichment choice** *(NEW)* — fires once per repo when `INTERACTIVE: yes` **and**
   `ENRICH_MODE: unset` for this repo **and** `HAS_KEY: no` **and** `AUTO_REGISTER` ≠ `false`
   **and** not CI/`HEADER_NONINTERACTIVE` **and** no legacy `public-only` marker. Posed *after* the
   scans so the custom option can name the detected stack:

   > I can enrich these recommendations two ways. **Generic** — the public agentic-coding briefing
   > (nothing about your code leaves the machine). **Custom — tuned to this codebase** (I detected
   > *\<stack\>*): I set up a free Header trial and build a briefing for *your* stack; a one-line
   > stack summary leaves the machine, no code or file contents. You can switch or delete anytime.
   >
   > 1. **Custom — tuned to this codebase** (recommended)  2. Generic  3. Always custom  4. Always generic

   Persist the answer as the per-repo `ENRICH_MODE` (`custom`/`generic`); options 3/4 also set the
   global default so new repos don't re-ask. **Generic** → skip steps 2a/3, enrich from public
   topics as today, done. **Custom** → continue.
   - **2a. New or existing Header user?** *(only when `HAS_KEY: no` and `ACCOUNT: none`.)* An
     existing user shouldn't get a redundant anonymous account — they should use their own:

     > Quick one: are you already a Header user?
     >
     > 1. **New to Header** (recommended — I'll set up a free trial, no signup) 2. I have an account — I'll paste my API key

     - **New** → **silent anonymous register**: `header-auth register` → `POST /auth/anonymous` →
       saves the key to `~/.header/credentials` (umask 077) + writes `~/.header/.account`.
     - **Existing** → **paste path**: point them at joinheader.com ▸ Settings ▸ API Keys for a
       read+write `hdr_sk_…`, then `header-auth save-key "<pasted>"` (same hardened save; no
       `.account` → `state` reads `full`). Their account may be Pro (topic creation just works) or
       free-tier (`TOPIC_LIMIT_FREE` → the existing trial/upgrade recovery in
       `reference/custom-briefings.md`). **No new backend** — reuses today's key + topic endpoints.
     - On register **failure** (offline, 5xx, rate-limited) or a declined/blank paste: tell the user
       once that custom setup didn't go through, fall back to generic-public enrichment for this run,
       leave `ENRICH_MODE` unset so it re-offers. Never block the audit.
3. **Create the repo's topic** *(NEW default)* — fires when `ENRICH_MODE: custom`, a key is now
   available, **and** `REPO_TOPIC` empty **and** `TEAM_TOPIC` empty.
   - `POST /topics/` with the **default source group** + a `goal_description` drafted from the
     detected stack. *(Skip `sources/recommend` on run 1 for latency — offer source tailoring later.)*
   - `header-repo bind <topic_id> "<name>"`. Future runs here resolve it as `REPO_TOPIC`.
4. **Present now, defer the briefing** *(NEW)* — render the coach lead + scorecard + non-briefing
   recommendations immediately; the briefing subsection shows a placeholder and a background agent
   takes over (§4).
5. **Post-audit chain** — schedule offer, team-config offer, telemetry consent — as today, except
   the topic already exists (created in step 3, not the upsell).
6. **Claim CTA** *(NEW, custom only)* — one line: the trial + `claim_url` + how to see/delete the
   account (`/header account`). The upfront choice already disclosed the setup, so this is the
   conversion nudge, not a consent line (§5).

**Subsequent runs** (key + `REPO_TOPIC` bound): exactly today's bound-repo path — fetch the bound
topic, freshness-check, enrich the audit inline from the custom briefing (no deferral; it already
exists), single combined output + one apply menu. This steady state is where the relevance win pays
off; run 1 is the cold-start.

## 3. Privacy posture & the "nothing leaves your machine" rewrite

The choice in §2.2 is the consent surface — it states the egress *before* asking, and the egress only
happens if the user picks custom. But the marketing/docs lingo still over-promises and must change.

**Today's claim** ("nothing about your project leaves the machine") is true only on the generic
path. The precise replacement, used everywhere the old line appears (README, SKILL.md, `llms.txt`,
and the choice prompt itself):

> **The audit is always 100% local** — no code, no file contents, no diffs ever leave the machine,
> on either path. If you choose **custom** enrichment, one thing leaves: a **one-line stack summary**
> (e.g. *"Python/FastAPI + React; focus on MCP and agent memory"*) so Header can build a briefing
> tuned to your stack. Nothing else. Choose **generic** and not even that leaves — you get the public
> briefing. Switch or delete anytime: `header-config set auto_register false`, or `/header account`.

The shift in framing: stop saying *"nothing leaves your machine"* (a blanket promise the custom path
breaks) and start saying *"your **code** never leaves; on custom, a one-line **stack summary** does,
by your choice."* The local-and-read-only audit is still the headline — it's just no longer conflated
with the enrichment source.

Required guardrails so the custom path stays defensible:

- **Opt-out flag** `auto_register` (default `true`) — `false` removes the custom option entirely and
  forces generic. Egress-related → **not** team-config-shareable (the committed `.header/config`
  allow-list already ignores egress keys), personal/env only.
- **Never register unattended** — CI / `HEADER_NONINTERACTIVE` skip the choice and register entirely
  (scheduled runs shouldn't mint accounts). They keep working on public topics.
- **`/header account`** gives full visibility + a delete path (§5).
- README + SKILL.md + `llms.txt` rewritten to the wording above.

## 4. Run-1 deferred briefing

The briefing can't enrich the run that *creates* it (built from the audit, generated async). So on
the onboarding run:

- Render everything non-briefing now. The briefing subsection reads:
  `📰 Building this repo's briefing (~3–5 min) — stack-specific recommendations will follow as soon
  as it's ready.`
- **Background wait** on `first_briefing_id` using the patterns already in
  `reference/custom-briefings.md` ("Polling IN_PROGRESS briefings"):
  - **Claude Code:** `run_in_background` poll loop *or* `ScheduleWakeup` at `remaining + buffer`.
    On completion: fetch the briefing (`Accept: text/markdown`), run the Step 4 cross-reference for
    **briefing-derived items only**, surface them as a follow-up — `🔁 Your repo's briefing is ready`
    — with their own small apply prompt; `header-repo seen <generated_at>`.
  - **Other harnesses** (no background timer): the briefing-derived recs land on the **next** run
    (the topic is already bound, so it's just the normal bound-repo path). Say so in one line.
- **Apply menu fires twice** on the onboarding run: once now for audit/config/waste/rails recs,
  once when the briefing lands for the briefing-derived recs. Steady-state runs keep the single
  combined menu.
- **Block fallback:** if the user prefers to wait (or a harness can't background), block on the
  polling loop and present the full combined output once — at the cost of a multi-minute stall.

## 5. Claim, trial, upgrade

**Claim (anytime).** The `claim_url` (`/signup?code=<claim_code>`) is cached in `~/.header/.account`
at register and re-fetchable from the idempotent `POST /auth/anonymous` — `header-auth claim-url`
surfaces it. Show it:

- once at onboarding (disclosure line, §2.6),
- as a **soft nudge** after the user has applied **N≥3** recommendations (reuse the
  `header-ledger list --action applied` signal that already gates the auto-tune offer) — gated by a
  `~/.header/.claim-nudged` marker so it's not every run,
- and at **trial expiry** (must-act).

Wording: *"Your topics live in a free Header trial. Create a full account — keeps your API key and
this repo's topic, and you can browse your briefings in the web UI: `<claim_url>`. Optional; works
fine from the CLI without it."*

**Trial expiry (existing model — no new code).** Detected off existing signals: a Pro-gated write
(`POST /topics/`, `POST /goals/{id}/briefings`) returns an existing `*_FREE` code with
`can_start_trial: false`, and `GET /billing/subscription` reports `tier_flip_kind: "trial_expired"`. Behavior:

- Surface once: *"Your Header trial ended. Upgrade in the web UI to keep this repo's briefing
  fresh: `<claim_url>` (claim + upgrade) or the billing portal if already claimed."*
- **Fall back to public-topic enrichment** so the audit still runs enriched. Custom-topic schedules
  auto-pause server-side on lapse and auto-resume on upgrade (existing behavior).
- The skill **never** initiates payment — upgrade is UI-only (`/billing/create-checkout`).

**`/header account`** *(mode routing → `header-auth status`)* — prints: account type
(anonymous-unclaimed / anonymous-claimed / full), trial status, the `claim_url`, and the controls:
`header-config set auto_register false` (stop creating), and an account delete (link to the UI, or a
small `DELETE /api/v2/account` if the backend ships one). The user's console for the silently-created
account — what makes silent setup defensible.

## 6. State & preamble signals

New `~/.header/` state (all read as data — never sourced):

| File | Contents |
|---|---|
| `credentials` | `HEADER_API_KEY=hdr_sk_…` (existing; the key now arrives from the API, not the clipboard). |
| `.account` | JSON: `account_id`, `anonymous`, `claimed`, `tier`, `trial_ends_at`, `claim_url`. Written by `header-auth register`/`status`. |
| `.claim-nudged` | Marker + last-nudge cadence for the soft claim nudge. |

New config keys (`header-config`): `auto_register` (bool, default `true`; not team-shareable) and
`enrich_mode` (global default `custom`/`generic`/unset, set by the "always" options in §2.2).

New per-repo flag (`header-repo flag`): `enrich-mode` (`custom`/`generic`/unset) — the answer to the
§2.2 choice for *this* repo. Resolves: per-repo flag › global `enrich_mode` default › unset (ask).

New preamble lines:

| Echoed line | Use |
|---|---|
| `ENRICH_MODE` | `custom` / `generic` / `unset` for this repo (per-repo flag › global default). `unset` (+ interactive, no key, `auto_register` ≠ false) → ask the §2.2 choice. `generic` → public topics, never register. `custom` → register + custom topic. |
| `ACCOUNT` | `none` / `anonymous-unclaimed` / `anonymous-claimed` / `full` — from `.account`. Gates register (only on `none`) and the claim nudge. |
| `AUTO_REGISTER` | `true` / `false` — the opt-out. `false` → never register, never offer custom; public-topic behavior. |

`HAS_KEY` keeps its meaning; after a successful register it is effectively `yes` for the rest of
the session.

## 7. Phased plan

- **Phase 0 — backend (blocking).** Only **two** new endpoints: `POST /auth/anonymous` (auto-starts
  the existing 15-day trial, mints a `full` key, returns a claim code) + the `/signup?code=` Clerk
  claim flow. Everything else reuses the existing API (`GET /billing/subscription`, `*_FREE` /
  `can_start_trial` / `tier_flip_kind`, `/billing/create-checkout`). Per the backend spec. Nothing
  client-side ships until this is live.
- **Phase 1a — tested foundation. ✅ DONE.** `header-auth` bin (`register`/`save-key`/`state`/
  `status`/`claim-url`, hermetically testable via `HEADER_AUTH_STUB`) + `test/auth.test.sh`;
  `header-config` keys `auto_register` (default `true`, egress → not team-shareable) + `enrich_mode`;
  `header-repo enrich-mode` per-repo value; tests extended (config, repo, binexit). No `SKILL.md`/flow
  change yet — the bins are dormant infra, fully unit-tested. `VERSION` unchanged (not a release).
- **Phase 1b — preamble signals. ✅ DONE.** `SKILL.md` preamble emits `ENRICH_MODE`/`ACCOUNT`/
  `AUTO_REGISTER` + table rows; +7 preamble assertions. Inert until the flow consumes them.
- **Phase 2 — the choice flow. ✅ DONE + dogfooded against prod (2026-07-07).** `SKILL.md` "First-run
  enrichment choice" entry hook + reconciled the old upsell to the existing-key path + telemetry-gate
  fold-in; `reference/topics.md` choice flow (§2.2 generic-vs-custom, §2.2a new-or-existing →
  `header-auth register` / `save-key`, topic-from-stack create + bind); lingo rewrite (SKILL.md +
  README). A live `/header` first-run ran end-to-end on prod: choice → new-user → register → topic
  create + bind → `ENRICH_MODE:custom` + `REPO_TOPIC` bound. **Hardened:** the topic create/bind dance
  is now the `header-topic` bin (not prose-parsed JSON) after a nested-id bug.
- **Phase 3 — deferred briefing. ✅ DONE + dogfooded.** present-now / background-wait (`header-topic
  status`) / surface-when-ready / claim CTA. Validated live: the background poll ran; a fresh briefing
  can exceed its ETA, so the designed fallback (topic bound → recs land next run) is confirmed.
- **Phase 4 — claim & lifecycle. ✅ DONE.** `/header account` ✅; privacy rewrite (README + SKILL.md +
  `llms.txt`) ✅; **claim UI tested by the user — works** (re-register shows `claimed:true`, key
  preserved); **claim-nudge cadence** ✅ (`CLAIM_NUDGED` preamble signal + `.claim-nudged` marker,
  fires once after ≥3 applied recs on an `anonymous-unclaimed` account); **trial-expiry** ✅
  (`header-auth subscription` → `EXPIRED yes` off `tier_flip_kind`/`can_start_trial`; prose messages +
  falls back to public enrichment). All read off the existing `GET /billing/subscription` — no new backend.
- **Extra — scripted the deterministic API surface.** `header-topic` (create/latest/get/generate/
  status/add-source/dashboard) + `header-auth` (trial/checkout) own every endpoint + response shape;
  prose orchestrates only. All validated against prod.

## 8. Open questions / follow-ups

- **Key recovery on re-register.** A device that loses `~/.header/credentials` re-calls
  `/auth/anonymous` with the same `installation_id`. Return the **same** key (treats
  `installation_id` as the device credential — recovery is smooth) vs. rotate (more secure, but
  orphans nothing since it's one device). Recommend **same key**; backend decides (see spec §abuse).
- **Source tailoring on run 1.** `sources/recommend` → `commit` gives a sharper group but adds
  latency before the briefing even starts. Deferred to a later run / explicit `add-source` for v1.
- **Shared repos.** A repo with a committed `TEAM_TOPIC` suppresses per-dev topic creation (already
  handled by the resolution order). A shared repo *without* a team topic still gets a per-dev
  personal topic — fine; the team-config offer can promote one. No special-casing for v1.
- **Existing users.** Don't auto-register when a key already exists or a legacy `public-only`
  marker is set — back-compat with 0.10.x opt-outs.
- **Account GC.** Backend's call: unclaimed accounts past trial + grace — keep inert vs. delete.
  Affects whether a long-idle device's `claim_url` still resolves.
