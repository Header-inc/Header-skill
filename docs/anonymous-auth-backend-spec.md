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
  **auto-start the free trial** (so the immediate `POST /topics/` below doesn't bounce on
  `TOPIC_LIMIT_FREE`); mint a **read+write** API key (`hdr_sk_…`); generate a single-use-ish
  `claim_code`. Return all of it.
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
  "tier": "trial",
  "trial_ends_at": "2026-07-14T00:00:00Z",
  "claimed": false,
  "claim_code": "clm_…",
  "claim_url": "https://joinheader.com/signup?code=clm_…",
  "installation_id": "8f3c…-uuid"
}
```

| Field | Type | Notes |
|---|---|---|
| `account_id` | string | Stable account id. |
| `api_key` | string | Read+write `hdr_sk_…`. The skill saves it to `~/.header/credentials` under umask 077. |
| `tier` | string enum | `trial` on success. Later: `pro` \| `free` \| `expired`. |
| `trial_ends_at` | string (ISO-8601 UTC) \| null | When the trial lapses. Drives the skill's claim/upgrade nudges. |
| `claimed` | bool | `false` for a fresh anonymous account. |
| `claim_code` | string | Unguessable token the `/signup` UI consumes to claim this account. |
| `claim_url` | string | `https://joinheader.com/signup?code=<claim_code>` — surfaced verbatim by the CLI. |

### 2. `GET /api/v2/auth/me` — account status (NEW)

`Authorization: Bearer hdr_sk_…`. Lets the skill nudge to claim "anytime" and detect trial expiry.

**Response** `200`

```json
{
  "account_id": "acct_…",
  "anonymous": true,
  "claimed": false,
  "tier": "trial",
  "trial_ends_at": "2026-07-14T00:00:00Z",
  "claim_url": "https://joinheader.com/signup?code=clm_…",
  "upgrade_url": "https://joinheader.com/billing"
}
```

- `claim_url` is **always current** for an unclaimed account (the skill re-fetches it here rather
  than caching a code that may rotate). Omit/empty once `claimed=true`.
- `upgrade_url` points at the UI billing flow (upgrade is UI-only — the CLI never charges).

### 3. `GET /signup?code=<claim_code>` — claim consumption (UI, NEW)

Web flow, not called by the CLI. Resolve `code` → the **unclaimed** account; collect email/password
(or OAuth); **attach auth to that same account**, set `claimed=true`, keep the trial running, and
**leave every `hdr_sk_…` key valid.** After claim:

- the code is spent (re-visiting it is a no-op / "already claimed"),
- the CLI keeps working with the key it already has,
- the user can now browse their topics/briefings in the UI (the conversion pitch).

Invalid / already-claimed / expired code → a clear UI error, not a 500.

### 4. Trial expiry on write endpoints (CHANGE to existing)

When `tier` has lapsed, **write** operations the trial unlocked return:

```
HTTP 403
{ "error": { "code": "TRIAL_EXPIRED", "message": "…", "upgrade_url": "https://joinheader.com/billing" } }
```

Applies to at least `POST /api/v2/topics/`, `POST /api/v2/goals/{id}/briefings`, and other
Pro-gated writes. **Reads of already-generated briefings should keep working** (recommend) so a
lapsed user still sees their last briefing; only *fresh generation* is blocked. The skill catches
`TRIAL_EXPIRED`, surfaces the upgrade line, and falls back to public-topic enrichment.

This sits alongside the existing `*_FREE` (Pro-only on free tier) and `*_QUOTA` (paid cap) codes
documented in `reference/custom-briefings.md`; `TRIAL_EXPIRED` is specifically "trial lapsed,
no longer unlocked."

---

## Idempotency & data model

- One `installation_id` ⇒ at most one account. Re-register is a lookup, not a create.
- `claim_code`: random, unguessable, single account, invalidated on claim. A new `claim_code` may
  be minted on demand (returned by `/auth/me`); don't depend on the original surviving forever.
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
- **Per-account caps independent of "Pro".** A trial should unlock *enough* (e.g. ~3 topics, a small
  number of manual briefings/day) but not be a free Pro firehose. Reuse the existing
  `TOPIC_LIMIT_QUOTA` / `MANUAL_BRIEFING_QUOTA` shapes with anonymous-tier limits.
- **Unclaimed-account GC.** Decide a TTL for unclaimed accounts past `trial_ends_at` + grace (keep
  inert vs. delete). If deleted, the device's `claim_url` stops resolving — fine, the next
  `/header` re-registers a fresh one.
- **`DELETE /api/v2/auth/me`** (optional but recommended) so `/header account` can offer a real
  delete, which is what makes silent creation defensible.

## What the client does with each piece (for context)

- Saves `api_key` → `~/.header/credentials` (umask 077), caches `account_id` / `tier` /
  `trial_ends_at` / `claim_url` → `~/.header/.account` (read as data, never sourced).
- Immediately `POST /api/v2/topics/` with the default source group + a stack-summary
  `goal_description`, then `header-repo bind` it to the repo.
- Polls `first_briefing_id` and enriches the audit when it completes.
- Re-checks `/auth/me` to nudge claim (after ≥3 applied recs) and to detect `expired`.
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

1) POST /api/v2/auth/anonymous (no auth). Body: {v:1, installation_id (uuid),
   client:{os,arch,skill_version,hostname?}}. Idempotent on installation_id.
   - First call: create account (no email, claimed=false), auto-start the free trial,
     mint a read+write hdr_sk_ key, mint an unguessable single-use claim_code.
   - Repeat call (same installation_id): return the SAME account_id AND the SAME api_key
     (device key recovery). Do not invalidate keys.
   - Return: {account_id, api_key, tier:"trial", trial_ends_at, claimed:false,
     claim_code, claim_url:"https://joinheader.com/signup?code=<claim_code>",
     installation_id}.

2) GET /api/v2/auth/me (Bearer key). Return {account_id, anonymous, claimed, tier,
   trial_ends_at, claim_url (current, for unclaimed only), upgrade_url}.

3) Signup claim flow: GET https://joinheader.com/signup?code=<claim_code> resolves the
   code to the UNCLAIMED account, collects email/password (or OAuth), attaches auth to
   that same account, sets claimed=true, keeps the trial running, keeps all hdr_sk_ keys
   valid. Spend the code on claim; invalid/already-claimed/expired → clean UI error.

4) Trial expiry: when the trial lapses, Pro-gated WRITE endpoints (POST /topics/,
   POST /goals/{id}/briefings, etc.) return 403 {error:{code:"TRIAL_EXPIRED",
   message, upgrade_url}}. Reads of already-generated briefings keep working. Upgrade
   happens only in the UI (no CLI billing).

5) Abuse controls: rate-limit POST /auth/anonymous per IP with a low daily new-account
   cap (repeat-lookups for an existing installation_id can be looser); treat
   installation_id as a bearer-ish credential (don't log in clear; consider IP/ASN
   binding for the trial window). Give the trial real but bounded limits (e.g. ~3
   topics, small manual-briefings/day) reusing the existing *_QUOTA shapes — not a free
   Pro firehose. Add a GC policy for unclaimed accounts past trial+grace.

6) (Recommended) DELETE /api/v2/auth/me so the CLI's `/header account` can offer a real
   account delete.

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
  key), or honoring a past trial_ends_at — so the TRIAL_EXPIRED path is testable without
  waiting out a real trial.

ACCEPTANCE (these should pass; share BASE so I can run them too):
  A=$(curl -sS -X POST $BASE/api/v2/auth/anonymous -H 'Content-Type: application/json' \
    -d '{"v":1,"installation_id":"test-1111","client":{"os":"linux","arch":"x86_64","skill_version":"0.38.0"}}')
  KEY=$(printf '%s' "$A" | sed -n 's/.*"api_key":"\([^"]*\)".*/\1/p')
  # same installation_id → same key (idempotent recovery)
  B=$(curl -sS -X POST $BASE/api/v2/auth/anonymous -H 'Content-Type: application/json' \
    -d '{"v":1,"installation_id":"test-1111","client":{"os":"linux","arch":"x86_64"}}')
  [ "$KEY" = "$(printf '%s' "$B" | sed -n 's/.*"api_key":"\([^"]*\)".*/\1/p')" ] && echo IDEMPOTENT-OK
  # key authenticates
  curl -sS $BASE/api/v2/auth/me -H "Authorization: Bearer $KEY"
  # trial unlocks topic creation immediately (no TOPIC_LIMIT_FREE)
  curl -sS -X POST $BASE/api/v2/topics/ -H "Authorization: Bearer $KEY" \
    -H 'Content-Type: application/json' \
    -d '{"name":"smoke","source_group_ids":["64981a34-3b8b-4064-a391-22f4534c229b"],"goal_description":"smoke test"}'

Keep response shapes byte-compatible with the tables in the spec doc. Update
joinheader.com/docs and the OpenAPI spec (/api/v2/openapi.json) with the new endpoints
and the TRIAL_EXPIRED error code so the CLI's "fetch the live contract" fallback stays
accurate.
```
