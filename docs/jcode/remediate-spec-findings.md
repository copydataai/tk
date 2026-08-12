# J-Code remediation packet — tk specification findings

You are the managed J-Code remediator in `/Users/josesanchez/Developer/public/tk-jcode-challenges-2026-08-12`. Do not launch nested agents. Read the original packet, reviewer findings summarized below, and all current production paths/tests. Resolve every finding through production workflows, test-first. No unrelated cleanup.

Create exactly these six commits in order:

1. `fix: wire transactional insertion into production`
   - Integrate `TextInsertionCoordinator` into live `AppModel`/`MacTextService` insertion and retry/undo paths.
   - Persist candidate text before mutation; stable fingerprint recheck; refuse secure/read-only/disabled/changed targets; direct AX range first; fallback separately classified; readable post-state verification; Unicode-safe surrounding text/selection; nonverified text retained.
   - Add production-wiring workflow tests, not isolated module-only tests.

2. `fix: wire durable operation recovery into production`
   - Integrate `OperationJournal` into capture, inference, pending text, target choice, insertion, verification, retry/copy/discard/commit and launch recovery.
   - Atomic version/predecessor transitions, corrupt/future evidence preservation, targetless capture, idempotent recovery, and no duplicate verified insertion.
   - Add relaunch/process-death tests through production workflows.

3. `fix: enforce inference admission in production`
   - Integrate `InferenceAdmissionPolicy` and content-free performance receipts into `WhisperRuntime`/dictation execution.
   - Enforce preflight and no silent profile/device fallback; measure startup/inference/peak memory when observable/termination/cleanup.
   - Spawn helper in a guaranteed dedicated process group/session and fail if group creation cannot be established; test a forking descendant is killed on timeout/cancellation.
   - Make `benchmark_inference.sh` execute deterministic audio with bundled helper for cold/warm trials, emit receipts, apply exact hardware/profile threshold, and fail missing/exceeded thresholds.

4. `fix: enforce speech capabilities in production`
   - Integrate `SpeechCapabilityPolicy` into live operation dispatch. Copy Mode must cause zero AX/focus/selection/synthetic-event calls. Insertion and Read Selection request only operation-time capabilities. Secure fields fail recoverably. Clipboard ownership restoration and content-free diagnostics remain enforced.
   - Add instrumented live workflow tests proving forbidden-call counts are zero.

5. `fix: validate physical qualification evidence`
   - Define/share strict versioned schema between evidence writer, Swift validator, and compatibility gate.
   - Hash immutable DMG and derive app version/build from bundle; use exact `sw_vers -buildVersion`, `sysctl -n hw.model`, route/device UID, observations, outcome, timestamps/freshness, app/OS/hardware context.
   - Require matrix Record cell to link exactly one matching record. Reject stale, malformed, future-schema, mismatched, duplicate, generalized, and unlinked evidence.
   - Fix normal `.app` bundle handling and add realistic CLI tests.

6. `fix: exercise installed artifact qualification`
   - `qualify_installed_app.sh` must mount the supplied DMG, install into isolated destination/context, inspect Gatekeeper/signature/notarization, launch and probe readiness hooks, enforce offline/no-download/network declarations, verify no resident listener after operation hooks, validate SBOM/provenance/licenses/rollback/uninstall schemas, clean up, and fail closed when a predicate cannot be exercised.
   - Preserve explicit external boundaries: no signing/notarization credentials and no physical matrix records means release remains blocked.
   - Reproduce and resolve deterministic Babylon acquisition/package build if possible; never report a DMG pass if it does not finish.

After each commit run focused tests and `git diff --check`. Final gates: `swift test`, warnings-as-errors build, shell/Python syntax, capability audit, compatibility fail-closed check, benchmark opt-in behavior, development app/DMG attempt, and installed qualification if an artifact exists. Leave a clean worktree. Report exact SHAs/results/skips and every external qualification boundary honestly.