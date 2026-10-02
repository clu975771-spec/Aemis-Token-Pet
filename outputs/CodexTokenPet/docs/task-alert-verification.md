# Task alert repair — 2026-10-01

## Source
Read-only `~/.codex/thread_history_1.sqlite`, `thread_turns.error_json`, on a failed latest turn. The local database contains the exact message `Selected model is at capacity. Please try a different model.` and `codexErrorInfo: serverOverloaded`. The record supplies `thread_id`, `turn_id`, start/completion times. No screen text or chat quotations are scanned for this error.

Bubble: 所选模型暂时繁忙，换个模型再试. Audio uses the existing problem.wav / boosted variant.

## Event behavior
- One problem alert per thread/turn; persistent delivered state retained, historical repeat setting migrated to zero.
- Only events after monitor launch and within 90 seconds are eligible. Poll gaps over 90 seconds silently baseline accumulated records.
- Disabled events are consumed; enabling does not replay them.
- A newer user reply, turn, resumed/paused/completed goal invalidates the old problem. Pending bubbles and delayed audio are revalidated.
- Missing timestamps cannot become alerts; latest-turn selection handles legacy duplicate/null timestamps deterministically.
- Completion accepts either an explicit goal completion (including rollout after the goal row is removed) or a completed ordinary turn whose final_agent_item_id references a nonempty final_answer without questions. Active/blocked goals, commentary, empty answers and unfinished turns are excluded. The bubble says 本轮回复完成啦 for an ordinary final reply.

## Verification
`zsh pet/tests/run.sh`: temporary SQLite files and a unique UserDefaults suite, no live callbacks, notifications, bubbles, or audio. Tests cover capacity attribution, generic failure, unanswered questions, reply/retry/resume/completion cancellation, old blocked states, disabled/restart/sleep behavior, migration, null timestamps, quoted error text without a task, explicit rollout completion, 200% volume, and simulated idle polling beyond 15 minutes. Existing placement/audio-asset checks also pass.

Installed via pet/deploy.sh. Both taskCompletionAlertEnabled and taskProblemAlertEnabled are now true. Installed process startup confirms both values. Existing distributed preview entry was invoked once for each kind; the actual installed process logged complete.wav and problem.wav with started=true at volume 1.0. No fabricated task records or English/long test bubbles were injected into the live app. This verifies real process/audio routing; event classification and async monitor callbacks were exercised in isolated SQLite fixtures. The installed process is also observed for idle alerts and crashes.


## Follow-up hardening
All Dictionary(uniqueKeysWithValues:) constructors in pet sources were replaced with duplicate-tolerant merges. The historical crash in the pet stderr log was a deployed process crash before the prior fix, not merely observer output. Current regression fixtures include duplicate metadata IDs, duplicate goal IDs, and null-time turns. Completion identity is shared between explicit goal and final reply for the same turn, remains stable after a newer turn, and does not suppress separate turns within 60 seconds. The three recorded completions for thread 01a05d4b on October 1 correspond to three distinct explicit goal completion timestamps (11:27, 11:46, 12:13 UTC), not evidence of one completion replaying three times.


## Night silence regression fixed (2026-10-01 23:37 Asia/Shanghai)
The process was healthy, both alert switches true and task volume 1.591433. Real completed-turn events continued to reach `present`, followed by `muted by settings`. The old default 23:00–08:00 quiet schedule was the cause. Added explicit `taskQuietHoursEnabled`, default false, a visible settings switch, persistence, and detailed mute-reason logs. Existing hour values remain configurable but have no effect until the switch is enabled. Night/morning opt-in and persistence tests run in isolated UserDefaults. Original Chinese voice files and 200% slider are preserved.

Default output observed: OpenFit 2+ by Shokz, system volume 13%, not muted. Output routing/system volume were not changed. The two installed-process preview calls exercise the actual audio player with the user's existing ~159% setting. No synthetic records were written into live task databases.
