# Anonymous auth & claim — backend contract

What the Header **skill** needs the backend to add so a fresh device can get a working,
write-capable account with **zero user friction**, and convert it to a real account later without
losing its API key or data. Client design: [`anonymous-onboarding-design.md`](anonymous-onboarding-design.md).

The skill already knows how to create topics, generate briefings, and sync experiments against an
API key. The missing piece is **how the key comes into existence on a new machine.** Today that's a
manual hill (sign up → mint a read+write key → paste). This contract removes it: the skill mints an
anonymous trial account silently, keyed on a device UUID it already has (`installation_id`).

> **One-row model (important).** An "anonymous account" and a "full account" are the **same row**.
> Registration creates it with no email and a trial; claiming *attaches* email/auth and flips a
> flag. Nothing migrates, and **the API key never changes on claim** — so the CLI keeps working
> across the conversion. Build accounts to be auth-optional, not anonymous-vs-real as two types.

---

## Endpoints

### 1. `POST /api/v2/auth/anonymous` — register a device (NEW)

No auth header. Idempotent on `installation_id`.

**Request**

```json
{
  "v": 1,
  "installation_id": "8f3c…-uuid",
  "client": { "os": "linux", "arch": "x86_64", "skill_version": "0.38.0", "hostname": "optional" }
}
```

| Field | Type | Notes |
|---|---|---|
| `v` | int | Payload version (`1`). |
| `installation_id` | string (uuid) | **Idempotency key.** The skill's per-device id (`~/.header/installation-id`); already used as the `client_key` prefix for experiment sync. |
| `client` | object | Diagnostics only. `hostname` optional; never required. |

**Behavior**

- **First call for an `installation_id`:** create an account with **no email**, `claimed=false`;
  **auto-start the existing 15-day Pro trial** — reuse the `POST /billing/trial/start` machinery,
  keyed **per installation/account** (there's no email, so the usual one-per-email rule becomes
  one-per-account) — so the immediate `POST /topics/` below doesn't bounce on `TOPIC_LIMIT_FREE`;
  mint a **`full`-scope** API key (`hdr_sk_…`; the existing `/api-keys` model — `full` = all methods);
  generate a single-use-ish `claim_code`. Return all of it.
- **Repeat call (same `installation_id`):** return the **existing** account — same `account_id`,
  and **return the same `api_key`** so a device that lost its `credentials` file recovers without a
  reset. (This treats `installation_id` as the device credential — see Abuse.) If you prefer
  rotation, the skill will overwrite `credentials` with whatever you return; just don't invalidate
  other devices (there's only ever one per id).

**Response** `200`/`201`

```json
{
  "account_id": "acct_…",
  "api_key": "hdr_sk_…",
  "key_scope": "full",
  "claimed": false,
  "claim_code": "clm_…",
  "claim_url": "https://joinheader.com/signup?code=clm_…",
  "trial_active": true,
  "trial_ends_at": "2026-07-15T19:00:00Z",
  "can_start_trial": false,
  "tier": "trial",
  "installation_id": "8f3c…-uuid"
}
```

| Field | Type | Notes |
|---|---|---|
| `account_id` | string | Stable account id. |
| `api_key` | string | `full`-scope `hdr_sk_…`. The skill saves it to `~/.header/credentials` under umask 077. |
| `key_scope` | string | `full` (all methods) — needed to create topics. The existing `/api-keys` scope model. |
| `claimed` | bool | `false` for a fresh anonymous account. |
| `claim_code` | string | Unguessable token the `/signup` UI consumes to claim this account. |
| `claim_url` | string | `https://joinheader.com/signup?code=<claim_code>` — surfaced verbatim by the CLI. |
| `trial_active` / `trial_ends_at` / `can_start_trial` | — | The **same fields `GET /subscription` returns** — mirror them here so the skill has them inline at register. Authoritative trial state stays `/subscription`. |
| `tier` | string | Optional coarse summary (`trial` \| `free` \| `pro`) for CLI display; derive from subscription state. Not authoritative. |

### 2. Account / trial status — REUSE the existing `GET /api/v2/subscription`

**No new status endpoint.** The live API already exposes everything the skill needs to nudge and
to detect expiry — don't add `/auth/me`. `GET /api/v2/subscription` (auth `Bearer hdr_sk_…`) returns:

```json
{
  "trial_started_at": "2026-06-30T19:00:00Z",
  "trial_ends_at":   "2026-07-15T19:00:00Z",
  "trial_used":      true,
  "trial_active":    true,                  // true while inside the 15-day window
  "can_start_trial": false,
  "tier_flip_kind":  null                   // "trial_expired" | "pro_lapsed" | null
}
```

The only anonymous-specific datum not in `/subscription` is the **claim URL**. Rather than a new
status endpoint, **`POST /auth/anonymous` is idempotent and returns the current `claim_url` on every
call** (see §1), so the skill re-fetches it there. Keep `/subscription` unchanged; just make sure an
anonymous account answers it like any other account.

### 3. `GET /signup?code=<claim_code>` — claim consumption (UI, NEW)

Web flow, not called by the CLI. Resolve `code` → the **unclaimed** account; collect email/password
(or OAuth); **attach auth to that same account**, set `claimed=true`, keep the trial running, and
**leave every `hdr_sk_…` key valid.** After claim:

- the code is spent (re-visiting it is a no-op / "already claimed"),
- the CLI keeps working with the key it already has,
- the user can now browse their topics/briefings in the UI (the conversion pitch).

Invalid / already-claimed / expired code → a clear UI error, not a 500.

### 4. Trial expiry — REUSE the existing model. NO new error code.

There is **no `TRIAL_EXPIRED`** — don't invent one. When an anonymous account's 15-day trial lapses
it reverts to free tier, and the existing behavior already covers it:

- Pro-gated writes (`POST /api/v2/topics/`, `POST /api/v2/goals/{id}/briefings`) return the existing
  **`*_FREE`** code (e.g. `TOPIC_LIMIT_FREE`) — now with **`can_start_trial: false`** (the lifetime
  trial is used), so the recovery is **upgrade-only** (`POST /api/v2/billing/create-checkout`, UI).
- `GET /api/v2/subscription` reports **`tier_flip_kind: "trial_expired"`** (the post-trial state).
- Schedules on the account's custom topics **auto-pause server-side** on lapse and **auto-resume on
  upgrade** — already implemented; no client action.

So the skill detects expiry off the **existing** `*_FREE` + `can_start_trial` + `tier_flip_kind`
signals (documented in `reference/custom-briefings.md` "Tier limits and error handling") and falls
back to public-topic enrichment. **Error envelope is flat** — `{"error_code": "...", "message": "..."}`
per joinheader.com/docs — not nested. Nothing new to build here.

---

## Idempotency & data model

- One `installation_id` ⇒ at most one account. Re-register is a lookup, not a create.
- `claim_code`: random, unguessable, single account, invalidated on claim. A new `claim_code` may
  be minted on demand (returned by the idempotent `POST /auth/anonymous`); don't depend on the
  original surviving forever.
- Keys are **stable across claim.** Claiming must not rotate or revoke existing `hdr_sk_…`.
- Tier transitions: `trial → (claim, optional) → trial → expired → pro (after UI upgrade)`. Claiming
  and upgrading are independent — a user can claim without paying, and the trial keeps counting down.

## Abuse controls (do not skip)

Anonymous + write-capable + auto-trial is a spam magnet: free Pro for anyone, and `POST
/sources/recommend` + briefing generation burn backend LLM spend. At minimum:

- **Rate-limit `POST /auth/anonymous`** per IP (e.g. a few/min, low daily cap per IP). New-account
  creation is the expensive event — repeat calls for an existing `installation_id` are cheap lookups
  and can be limited more loosely.
- **`installation_id` is a bearer-ish secret.** Returning the same key on re-register means anyone
  who can present an `installation_id` gets that device's key. The id is a random UUID stored
  locally (`~/.header/installation-id`), never transmitted except to register — acceptable for an
  anonymous trial, but treat it as a credential: don't log it in the clear, and consider binding
  first-registration to the originating IP/ASN for the trial window if abuse appears.
- **The trial itself stays standard.** An anonymous account gets the *normal* 15-day Pro trial and
  its normal limits (`*_QUOTA` shapes already enforce them) — don't build a bespoke anonymous tier.
  The abuse lever is **how many anonymous accounts can be created**, not nerfing each trial. If
  large-scale abuse appears, an anonymous trial *may* be given tighter caps than an email trial, but
  that's a later dial, not day-one.
- **Unclaimed-account GC.** Decide a TTL for unclaimed accounts past `trial_ends_at` + grace (keep
  inert vs. delete). If deleted, the device's `claim_url` stops resolving — fine, the next
  `/header` re-registers a fresh one.
- **Account delete** so `/header account` can offer a real delete (what makes silent creation
  defensible) — reuse an existing account-delete if the API has one; otherwise a small
  `DELETE /api/v2/account` is fine. Optional for v1.

## What the client does with each piece (for context)

- Saves `api_key` → `~/.header/credentials` (umask 077), caches `account_id` / `tier` /
  `trial_ends_at` / `claim_url` → `~/.header/.account` (read as data, never sourced).
- Immediately `POST /api/v2/topics/` with the default source group + a stack-summary
  `goal_description`, then `header-repo bind` it to the repo.
- Polls `first_briefing_id` and enriches the audit when it completes.
- Re-checks `GET /subscription` (existing) to nudge claim (after ≥3 applied recs) and to detect a
  lapsed trial (`tier_flip_kind: "trial_expired"` / `*_FREE` + `can_start_trial:false`); re-fetches
  `claim_url` from an idempotent `POST /auth/anonymous`.
- Never initiates payment.

---

## Prompt for the backend agent

> Copy-paste this to brief the backend implementation agent. It references the contract above.

```
Implement anonymous device registration + account claim for the Header API (the
backend behind joinheader.com). Build it so the Header CLI can give a brand-new
machine a working, write-capable trial account with no user signup, and convert it to
a real account later without changing the API key.

Core model — one row, auth-optional:
- An account can exist with NO email (anonymous) and be claimed later by attaching
  auth. Anonymous and full are the SAME account row; claiming flips claimed=false→true
  and attaches email/auth. The API key MUST stay valid across claim. Nothing migrates.

Build:

SCOPE: only TWO new things are needed — (1) POST /auth/anonymous and (2) the
/signup?code= claim flow. Everything else REUSES the existing API: the 15-day
trial (/billing/trial/start machinery), GET /subscription for trial/tier state,
the *_FREE / *_QUOTA tier-gate codes, /billing/create-checkout for upgrade, and
the /api-keys scope model (read|full). Do NOT add /auth/me or a TRIAL_EXPIRED code.

1) POST /api/v2/auth/anonymous (no auth). Body: {v:1, installation_id (uuid),
   client:{os,arch,skill_version,hostname?}}. Idempotent on installation_id.
   - First call: create account with NO email (claimed=false); auto-start the EXISTING
     15-day Pro trial (reuse /billing/trial/start, keyed per-installation since there's no
     email); mint a FULL-scope hdr_sk_ key (existing /api-keys model); mint an unguessable
     single-use claim_code.
   - Repeat call (same installation_id): return the SAME account_id AND the SAME api_key
     (device key recovery). Do not invalidate keys. Return the current claim_url.
   - Return: {account_id, api_key, key_scope:"full", claimed:false, claim_code,
     claim_url:"https://joinheader.com/signup?code=<claim_code>", trial_active,
     trial_ends_at, can_start_trial, installation_id}. (trial_* mirror GET /subscription;
     optional coarse tier:"trial" for display.)

2) Account/trial status: REUSE GET /api/v2/subscription (trial_active, trial_ends_at,
   can_start_trial, tier_flip_kind). An anonymous account must answer it like any account.
   No new status endpoint — the skill gets claim_url from the idempotent register call.

3) Signup claim flow: GET https://joinheader.com/signup?code=<claim_code> resolves the
   code to the UNCLAIMED account, runs the existing Clerk sign-up, ATTACHES that Clerk
   identity to the SAME account row, sets claimed=true, keeps the trial running, keeps all
   hdr_sk_ keys valid (no rotation, no data migration). Spend the code on claim;
   invalid/already-claimed/expired → clean UI error, not a 500.

4) Trial expiry: NO new code. When the 15-day trial lapses the account reverts to free —
   Pro-gated writes already return the existing *_FREE codes (e.g. TOPIC_LIMIT_FREE) with
   can_start_trial=false (upgrade-only), GET /subscription reports tier_flip_kind:
   "trial_expired", and topic schedules auto-pause server-side (auto-resume on upgrade).
   Keep the error envelope FLAT: {"error_code","message"}. Upgrade is UI-only.

5) Abuse controls: the trial stays STANDARD (anonymous accounts get the normal 15-day
   Pro trial + normal *_QUOTA limits — don't build a bespoke tier). The lever is account
   CREATION: rate-limit POST /auth/anonymous per IP with a low daily new-account cap
   (repeat-lookups for an existing installation_id are cheap, limit looser); treat
   installation_id as a bearer-ish credential (don't log in clear; consider IP/ASN binding
   for the trial window). GC unclaimed accounts past trial+grace.

6) (Optional) An account-delete the CLI's `/header account` can link to — reuse an
   existing one if present, else a small DELETE /api/v2/account.

TESTING HOOKS (so the CLI author can integrate against this while building):
- The CLI points at the API via env HEADER_API_BASE (default https://joinheader.com).
  Expose the new endpoints under a reachable base (staging or local) and tell me that
  base URL + any access requirement. Everything must work when HEADER_API_BASE is
  overridden — no hardcoded joinheader.com in the new paths.
- A way to run repeated registers without tripping rate limits in staging — e.g. honor
  a header `X-Header-Test: <shared-secret>` that bypasses the per-IP cap, or exempt a
  known test installation_id prefix.
- A non-UI way to claim in staging so claimed-state + key-preservation can be tested
  headless — e.g. POST /api/v2/auth/claim {"code":"clm_…","email":"t@e.st"} gated to
  staging or behind the test secret.
- A way to force trial expiry in staging — e.g. POST /api/v2/test/expire-trial (Bearer
  key), or honoring a past trial_ends_at — so the trial-expired path (tier_flip_kind +
  *_FREE with can_start_trial:false) is testable without waiting out a real trial.

ACCEPTANCE (these should pass; share BASE so I can run them too):
  A=$(curl -sS -X POST $BASE/api/v2/auth/anonymous -H 'Content-Type: application/json' \
    -d '{"v":1,"installation_id":"test-1111","client":{"os":"linux","arch":"x86_64","skill_version":"0.38.0"}}')
  KEY=$(printf '%s' "$A" | sed -n 's/.*"api_key":"\([^"]*\)".*/\1/p')
  # same installation_id → same key (idempotent recovery)
  B=$(curl -sS -X POST $BASE/api/v2/auth/anonymous -H 'Content-Type: application/json' \
    -d '{"v":1,"installation_id":"test-1111","client":{"os":"linux","arch":"x86_64"}}')
  [ "$KEY" = "$(printf '%s' "$B" | sed -n 's/.*"api_key":"\([^"]*\)".*/\1/p')" ] && echo IDEMPOTENT-OK
  # key authenticates against the EXISTING subscription endpoint (trial state)
  curl -sS $BASE/api/v2/subscription -H "Authorization: Bearer $KEY"
  # trial unlocks topic creation immediately (no TOPIC_LIMIT_FREE)
  curl -sS -X POST $BASE/api/v2/topics/ -H "Authorization: Bearer $KEY" \
    -H 'Content-Type: application/json' \
    -d '{"name":"smoke","source_group_ids":["64981a34-3b8b-4064-a391-22f4534c229b"],"goal_description":"smoke test"}'

Keep response shapes byte-compatible with the tables in the spec doc, and the error
envelope FLAT ({"error_code","message"}). Update joinheader.com/docs and the OpenAPI spec
(/api/v2/openapi.json) with the two new endpoints (POST /auth/anonymous + the /signup?code=
claim flow) so the CLI's "fetch the live contract" fallback stays accurate. No new error
codes — trial expiry reuses the existing *_FREE / can_start_trial / tier_flip_kind model.
```
