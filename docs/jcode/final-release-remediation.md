# Final J-Code remediation — tk release blockers

You are the managed J-Code remediator in `/Users/josesanchez/Developer/public/tk-jcode-challenges-2026-08-12`. Do not launch nested agents. Resolve exactly these independently verified blockers test-first, no unrelated cleanup.

Create three commits in order:

1. `fix: measure live inference admission state`
   - Production `WhisperRuntime` currently passes total memory as available and hard-codes normal pressure, helper availability true, and active operations zero.
   - Add narrow injectable live probes for actual available memory, current memory/thermal pressure, executable/helper availability, and process-wide active-operation ownership/concurrency.
   - Fail recoverably if a probe is unavailable/indeterminate where required; never silently assume healthy state or switch profile/device.
   - Add production wiring tests for low available memory, critical pressure, missing helper, concurrent operation, and probe failure.

2. `fix: record failed inference performance receipts`
   - `LocalInferenceSession` currently sets `lastReceipt` only on success.
   - Emit a content-free receipt for success, timeout, cancellation, signal/nonzero exit, launch failure, process-group establishment failure, malformed/oversize response, and cleanup failure, with measured startup/inference durations and cleanup disposition where observable.
   - Preserve the primary error while making receipt retrieval deterministic. Add fake-helper tests for every termination class, including a forking descendant.

3. `fix: exercise installed offline workflows`
   - `qualify_installed_app.sh` currently validates declarations and an immediate readiness hook only.
   - Add explicit qualification-mode app hooks that exercise bundled offline transcription on deterministic bundled/fixture audio, Copy Mode, automatic insertion against a controlled local editable target, Read Selection against controlled text, model-download/network-attempt instrumentation, and post-operation listener/helper cleanup. Hooks must execute production modules/adapters, be release-build-only guarded, use no user transcript, and emit content-free machine-readable evidence.
   - Runner must enforce offline isolation using a safe supported mechanism or fail closed if isolation cannot be established, mount/install in isolation, run those hooks, prove no model download/network attempt, verify no resident listener/helper afterward, and record each predicate separately.
   - Do not promote the 73 physical/app rows; controlled hooks are installed-artifact evidence only. Signing/notarization absence must remain blocked.

After each commit run focused tests and `git diff --check`. Final: `swift test`, warnings-as-errors build, shell/Python syntax, capability audit, benchmark behavior, development app/DMG build, unsigned installed qualification expected fail at signature/Gatekeeper, compatibility expected fail on 73 Not run rows. Leave a clean worktree and report exact evidence.