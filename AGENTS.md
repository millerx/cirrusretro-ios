# Engineering instructions for agents

## Product and distribution objectives

The primary objective is personal installation and ongoing use on the owner's iPhone and iPad. Limited sharing with a friend through TestFlight is optional. Public App Store release and monetization are out of scope. Prefer a sustainable remote signing and installation workflow; account for provisioning and beta expiration. Public source visibility does not waive dependency licenses; review obligations for any binary sharing, including TestFlight.

## Scope and architecture
- Target native iPhone and iPad only. Use SwiftUI for the application, portable C/C++ for emulation, and a narrow C-compatible API with opaque handles, explicit ownership and documented error handling.
- Prefer proven upstream emulator implementations over rewriting sound chips. Audit actual dependencies and licenses before incorporating code; pin upstream revisions and retain notices.
- Keep the core independent of Apple frameworks, browser APIs and Emscripten. Use reproducible CMake or equivalent portable builds and Linux tests.
- Plan AVAudioEngine integration with bounded buffering; avoid allocations, blocking, locks and file I/O on the real-time audio callback. Define sample format, rate, channels, lifecycle and thread ownership.
- Offline-first; import through Files and store locally. No backend or analytics by default. Plan background audio, interruptions, route changes and Now Playing controls.
- Treat imported files as untrusted; validate bounds and sizes, handle malformed inputs and use sanitizers where available.

## Workflow
- Read ROADMAP.md before implementation. Keep tasks focused on the current milestone. Use feature branches and pull requests; do not merge automatically.
- Document build commands, dependency provenance, decisions, test results and limitations. Never claim an iOS build or device test passed unless actually executed.
- Develop portable code in Codex Cloud; use hosted macOS CI for Xcode compilation and simulator tests. Prefer Xcode Cloud for TestFlight, with GitHub Actions macOS as an alternative. Do not assume signing or Apple enrollment is configured.
- Do not commit secrets, signing assets, copyrighted game music or ROMs without redistribution rights. Use original synthetic or explicitly redistributable fixtures with provenance.
- Preserve upstream copyright notices. Do not select a project license or publish a release before the owner approves licensing. Flag copyleft and App Store compatibility questions.
- Keep independent-project attribution to Multimedia Mike; do not imply endorsement.

## Model selection and reasoning effort

Use the lightest available model and effort that reliably meets the task's quality bar. Model names and availability may change; the following are guidance as of November 2026, not hard dependencies.

| Work | Preferred model | Effort |
| --- | --- | --- |
| Milestone 1 feasibility, dependency and license audit, C ABI design | GPT-6.2 Astra | High |
| Routine implementation, SwiftUI, tests and CI | GPT-6.2 Sol | Medium |
| Native audio integration, concurrency, emulator portability and difficult debugging | GPT-6.2 Astra | High |
| Small mechanical edits and documentation | GPT-6 Luna or economical available equivalent | Low or Medium |
| Independent milestone review, security and audio correctness | GPT-6.2 Astra | High; Extra High only for unresolved difficult issues |

If Astra is unavailable, use Sol at High for demanding work. Use the closest available equivalent if named models are unavailable. Escalate after repeated failed attempts or when evidence reveals a high-risk design issue; do not spend repeated expensive runs on an unchanged hypothesis. De-escalate for bounded follow-up work. Prefer a fresh review session for major changes. Record model/effort if known, tests and remaining risks in milestone PRs. These instructions guide the operator's model selection; agents must not assume they can change their own model or authorize extra spending. Ask the owner to select a stronger model if needed. Revisit guidance as models change: https://developers.openai.com/api/docs/guides/model-selection

## Autonomous milestone workflow

- Owner authorizes major milestones and retains final merge authority. Agents make routine engineering decisions independently; escalate significant blockers, security or licensing risks, material scope/architecture changes, unexpected costs and major opportunities.
- GitHub PRs are the authoritative communication channel. Implementation owns changes; independent reviewer owns findings. Default sequence: implementation and tests, review pass 1, fixes, review pass 2, final fixes and CI. Anchor reviews to commit SHAs, classify findings, record dispositions and defer unrelated improvements. Additional review only for unresolved blockers or material high-risk changes. No automatic merge.
- Keep reports concise and evidence-based. Prefer deterministic CI over redundant agent verification. Reuse implementation context for related fixes and independent review context for the second pass.
- Hard AI budget: owner's existing $100/month ChatGPT subscription. No paid API usage, extra credits, upgrades or new paid services without explicit approval. On quota exhaustion, preserve progress and wait for reset; do not bypass limits. Prefer economical models and bounded attempts.
- Automate handoffs only through supported, verified capabilities; never assume a cloud session can be resumed programmatically. Keep credentials out of public repositories and untrusted PR workflows.

