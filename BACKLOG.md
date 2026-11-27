# Backlog

Reconcile at each milestone boundary. ROADMAP.md defines active scope; do not implement deferred items without authorization or an established maintenance need.

| Item | Status / target |
| --- | --- |
| ITMS-90725 SDK requirement | Xcode 27.1 migration landed in PR #4. Archive verifies the built app’s iPhoneOS SDK and iOS 16.0 minimum. Check the processed 0.4.0 build’s Apple delivery messages for ITMS-90725 and record the result on its PR. Apple confirmation remains open until observed. Recheck by February 2027 ahead of April enforcement. |
| Hosted Xcode 27 runner | Keep the working xcode-27 runner. Revisit on a verified stable replacement or a reproducible build failure. Earlier simulator audio startup RPC timeout passed on retry/final head. |
| Sustainable TestFlight renewal and signing | Weekly subscription-backed check targets days 54–60. Inspect the protected signing dates on upload and update in place. See [renewal and recovery](docs/milestone-4.md). |
| External TestFlight sharing | Optional; review LGPL/GPL obligations, notices, corresponding source and recipient rights before inviting friends. |
| Battery, memory, audio fidelity and accessibility | Portable hour-render baseline recorded. Physical battery, sustained playback, route fidelity and VoiceOver acceptance are tracked per build in the milestone PR. |
| Additional formats and broader VGM compatibility | Post-MVP; audit and test individually. |
| Playlists, channel controls, visualizations | Post-MVP. |
| iPad-specific development | Indefinitely deferred; iPhone only. |
| Fully automated cloud session handoffs | Deferred unless supported subscription-only capability becomes available; use established fallback. |
