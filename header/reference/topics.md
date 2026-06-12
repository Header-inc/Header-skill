# Header reference — topics

*Loaded on demand by the Header skill; not part of the always-loaded SKILL.md.*

## After the audit: customize your topic

Once the audit + recommendations are delivered **and the apply menu has resolved**, in interactive mode, offer to **tailor the enrichment topic to this repo**. This is its own separate question — never bundled as a second question inside the apply-menu `AskUserQuestion` call. It is the upsell — the briefing that enriched the audit came from a generic topic; a custom topic targets sources about *your* stack.

**Conditions to fire** (all must hold):

- `INTERACTIVE: yes`
- `TOPIC_OFFERED: no` for this repo
- `SIGNUP_STATE` is **not** `public-only` (back-compat — honors older opt-out markers from 0.10.0/0.10.1; this skill no longer writes new ones)
- `REPO_TOPIC` is empty (this repo isn't already bound to a custom topic)

If any of those fails, skip this section and go straight to "Telemetry consent".

Ask (`AskUserQuestion` on Claude Code; numbered plain text elsewhere):

> The recommendations above were enriched by Header's **general** agentic-coding briefing — the same source feed for everyone. A **custom topic** would tune the enrichment to *this* repo: sources and focus tailored to your stack, so every future audit pulls in items directly relevant to your code.
>
> Want one for this repo?
>
> 1. **Yes — customize for this repo** (recommended for repos you'll work in repeatedly)
> 2. Remind me next session
> 3. Not for this repo — don't ask again

There is **no global "never ask anywhere" opt-out** — declines are per-repo only. Each repo is its own decision; "not for this repo" silences only here. (`<REPO>` is `header-repo`, next to the preamble's `HEADER_BIN`.)

### 1 — Yes, customize

If `HAS_KEY: no`, walk through signup first:

> Custom topics need a Header account. About 30 seconds, no card.
>
> Sign up at https://joinheader.com/ — start the free trial → open **Settings ▸ API Keys** → create a key with **read + write** access (`hdr_sk_...`; write is required to create custom topics) → paste it here.

Offer to open the URL:

```bash
URL="https://joinheader.com/"
if   command -v open     >/dev/null 2>&1; then open "$URL"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
elif command -v start    >/dev/null 2>&1; then start "$URL"
else echo "Open $URL in your browser."
fi
```

When the user pastes a key, offer to save it under a tight umask:

> Save it to `~/.header/credentials` (readable only by you) so you don't re-enter it each session?

Replace `PASTED_KEY` with the key the user pasted:

```bash
_HH="${HEADER_HOME:-$HOME/.header}"; mkdir -p "$_HH"
( umask 077; printf 'HEADER_API_KEY=%s\n' "PASTED_KEY" > "$_HH/credentials" )
chmod 600 "$_HH/credentials" 2>/dev/null
case "$(ls -l "$_HH/credentials" 2>/dev/null)" in
  -rw-------*) printf 'done\n' > "$_HH/.signup-state"; echo "Saved — custom briefings are ready." ;;
  *) rm -f "$_HH/credentials"
     echo "Could not secure the file — not saving the key. Add this to your shell profile instead:"
     echo "  export HEADER_API_KEY=PASTED_KEY" ;;
esac
```

If the user defers (won't paste a key right now), record `pending` and skip the rest — next run will re-offer once:

```bash
printf 'pending\n' > "${HEADER_HOME:-$HOME/.header}/.signup-state"
```

The credentials file is **only ever read as data** (parsed via `grep`/`sed`); nothing sources or executes it.

**With a key now available**, build the custom topic — the Step 3 audit already inferred the stack, so draft the goal for them. For a sharper fit, first let Header propose sources: `POST /api/v2/sources/recommend` → `POST /api/v2/sources/recommend/commit` returns a `group_id`. Then create the topic (see "Create a custom topic"); the response includes `first_briefing_id` — generation runs **asynchronously**, typically a few minutes.

> Creating a topic focused on <one-line summary of the detected stack and priorities>. The first briefing is generating in the background (~3-5 min); while we wait, let me get a couple of things set up.

**During the server-side generation**, run the chained per-repo offers — fill the dead air with the questions that depend on the new topic existing. Order:

1. **Bind the topic to this repo.** `"<REPO>" bind <new_topic_id> "<topic name>"` — future runs here use it automatically as `REPO_TOPIC`.

2. **Offer a schedule** (if `SCHEDULE_OFFERED: no`):

   > Keep this repo's briefing fresh automatically? Header regenerates it server-side on cadence, so a new one is waiting next session.
   >
   > 1. Every 3 days  2. Every 7 days (recommended)  3. Every 14 days  4. Every 30 days  5. No thanks

   On a cadence → `PUT /api/v2/goals/{default_goal_id}` with `schedule_enabled: true`, `schedule_frequency_days: N` (see "Bound repos — freshness & schedule"). Confirm and `"<REPO>" flag schedule-offered set` regardless.

3. **Offer team config** (if `TEAM_CONFIG: none`, `TEAM_CONFIG_OFFERED: no`, and a `git remote` is configured — i.e., shared repo):

   > Share this topic with your team? I can drop a `.header/config` in the repo pinning this topic — commit it, and every teammate's `/header` uses it automatically with no setup. (Recommended for shared repos.)

   On yes → `"<HEADER_BIN>" team-init <new_topic_id>` writes `./.header/config`; surface the `git add` hint so the file reaches teammates. Always `"<REPO>" flag team-config-offered set`. See "Team config" for what keys are allowed.

4. **Poll for the first briefing.** When all offers are resolved, check briefing status (see "Polling IN_PROGRESS briefings"). When `COMPLETED`, surface one line — "✓ Your custom briefing is ready; next session here will use it" — and continue to "Telemetry consent". Don't re-deliver the audit; the next run picks up the new topic.

If briefing creation hits `TOPIC_LIMIT_FREE` or any other `*_FREE` code, run the trial/upgrade flow (see "Tier limits and error handling"). On `*_QUOTA`, surface it and continue (the existing audit still landed).

**Flip the per-repo flag** once the topic is created (or once the user finishes signup + topic creation in this flow). Do **not** flip it if the user picked option 2 or option 3 — those branches handle the flag themselves.

```bash
"<REPO>" flag topic-offered set
```

### 2 — Remind me next session

Don't flip the per-repo flag. Don't touch `SIGNUP_STATE`. The next session in this repo will re-ask with the same wording. Acknowledge briefly ("ok, I'll bring it up next time") and continue to "Telemetry consent".

### 3 — Not for this repo, don't ask again

Flip the per-repo flag — this repo never gets re-offered:

```bash
"<REPO>" flag topic-offered set
```

Other repos still get asked. Tell the user they can re-enable this repo with `header-repo flag topic-offered clear` if they change their mind. Public-default audits keep working unchanged.

### Resumption (deferred signup)

On a later run where `SIGNUP_STATE: pending` and `TOPIC_OFFERED: no`, re-offer with a softer pitch ("you started signup earlier — still want a custom topic for this repo?"). Same three options, same gating. The user can keep deferring as long as they want — option 3 ("not for this repo") is how they silence it.


