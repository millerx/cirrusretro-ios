# Autonomous milestone workflow

The owner authorizes a milestone once. The implementation agent uses one feature branch and one GitHub PR, drives the review and correction cycle, and leaves the completed PR for the owner's approval and merge. Follow [AGENTS.md](../AGENTS.md) for model selection and scope.

## Run a milestone

1. **Implement and publish.** Start from current `main`. Run focused tests, then push and open a PR. Record the scope, current head and next action in the PR. Reuse the existing Linux Release and Sanitizers jobs. GitHub Actions runs them for PR opens and head updates. Use their results instead of rerunning an identical matrix in the reviewer.
2. **Independent pass 1.** Fetch the PR base and feature branch. Compare the full remote feature-branch SHA with the PR's current head. Compute the merge base with `git merge-base <PR-base-SHA> <PR-head-SHA>`. Use an independent reviewer to inspect that range. Post the resulting report to the PR with the reviewed head, a verdict and findings classified as blocker, non-blocking or optional. If the head changes during review, use the report only as evidence about its recorded SHA.
3. **Correct.** The implementation agent fixes confirmed blockers and worthwhile in-scope findings in the same branch. Record each disposition in replies or one concise PR comment. Link fixes by commit and defer unrelated or optional work. Use the same implementation context.
4. **Independent pass 2.** Verify the current head and compare the merge base with the one recorded in pass 1. Prefer the original independent review session, with the pass 1 report and dispositions linked. Check the fix delta, unresolved findings and regressions. If the head is unchanged, finish with a focused pass for missed blockers. Publish the second verdict against its SHA. Apply any final fixes and record them. Request extra independent review only for unresolved blockers, a changed review baseline, or material high-risk changes.
5. **Verify the delivery revision.** Refresh the PR head and confirm the latest PR-triggered Linux run for that SHA passed both jobs. Record the final SHA, review/disposition links, CI link, residual risks, and model/effort when known. When anything lands after pass 2, identify the unreviewed delta explicitly. A check run for an earlier push or a green badge alone is insufficient. Confirm the hosted iPhone archive and simulator tests passed on that revision as well.
6. **Deliver for physical verification.** Use the app version in ROADMAP.md and tag the reviewed feature revision for the existing [owner-only TestFlight workflow](milestone-2.md#deliver-the-authorized-owner-only-testflight-build). Each new delivery run supplies its own build number from `GITHUB_RUN_NUMBER`. Keep the environment protections and owner-only tester scope. Track the upload and Apple processing. When the build is available to the owner, report the version, build number, reviewed SHA and a concise milestone-specific iPhone checklist on the PR and in the owner handoff.
7. **Wait for merge approval.** Record the owner's physical iPhone result for that build. Keep the PR open until the owner explicitly approves merging it into `main`.

## Supported handoffs

| Capability | Use and limits |
| --- | --- |
| GitHub PR and existing Actions | PR comments carry findings, dispositions, and pause/resume state. The public repo can use standard hosted Linux runners without additional charges. Use the existing read-only workflow. [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) |
| Native Codex review on GitHub | A connected repository with Code Review enabled can use automatic review or a PR comment containing `@codex review`. The GitHub connector posted a request on this milestone PR and the Codex bot posted a review for that head. Use one trigger per pass and confirm a posted result for the intended SHA. GitHub review reports P0/P1 findings, so use an independent Codex reviewer when broader acceptance coverage or disposition checks are needed. The bot receipt also offers a comment-driven PR update. Same-branch correction, Actions bot-authored triggers, and automatic review settings were unverified here. The implementation agent applies corrections by default. [GitHub review](https://learn.chatgpt.com/docs/third-party/github) |
| Codex CLI and Cloud | Cloud chats support follow-ups. The CLI exposes new cloud task submission, status and diff commands. Those commands are experimental in the installed CLI and do not expose resumption of an existing Cloud chat. Both the read-only `codex cloud list` probe and the reviewer CLI model call received network-policy 403s in this workspace. Use a native independent Codex reviewer when available, or continue using Cloud chats and the PR checkpoint. [Codex Cloud](https://learn.chatgpt.com/docs/cloud) |
| GitHub-triggered schedules | Eligible accounts on ChatGPT web/mobile can trigger a scheduled task from PR activity. Availability and same-Cloud-chat correction were unverified for this setup. Keep this off the required path. [Scheduled tasks](https://learn.chatgpt.com/docs/automations) |
| Codex in hosted CI | The documented Codex GitHub Action requires an API key. Keep it out of this workflow. Use the existing ChatGPT sign-in on trusted Codex surfaces. Keep tokens, session files, and credentials out of GitHub and untrusted PR jobs. [Codex GitHub Action](https://learn.chatgpt.com/docs/github-action) · [Authentication](https://learn.chatgpt.com/docs/auth) |

### Subscription-backed CLI option

In a trusted checkout with the commits fetched and the CLI signed in with ChatGPT, the helper validates the SHAs and requests one read-only independent review using the built-in provider. It returns findings for the implementation agent to post on GitHub. For a fresh pass 2, supply a local text file containing the first report and dispositions from the PR.

```sh
scripts/milestone-review <merge-base-SHA> <PR-head-SHA>
scripts/milestone-review <merge-base-SHA> <updated-PR-head-SHA> <pass-1-head-SHA> <review-notes-file>
```

If native independent review and the local CLI are unavailable, open one separate Cloud review chat with the PR URL, verified SHAs, and pass number. Follow up there with the fix SHA and dispositions. Paste the reports into the PR, and send their links to the original implementation chat if it cannot see the handoff. The operator only needs to relay the missing trigger or link.

### Pause and resume

Use only included usage from the owner's existing $100/month subscription. Disable auto top-up if enabled and confirm included usage is available before starting if the account can draw down paid credits. The CLI cannot enforce account-side credit settings. [ChatGPT credit settings](https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-personal-plans)

On a usage-limit response, stop model calls and retries until the product's stated reset. When possible, commit and push recoverable work and leave a short PR checkpoint with head SHA, completed stages, pending action, and reset time if known. If publishing is blocked, save the local commit in the Cloud workspace and reconcile it with the remote on resume. When the reset passes, continue the existing implementation chat using the PR checkpoint. If it cannot resume or no supported follow-up is active, the operator sends one resume message after reset. Verify the remote head first and reuse completed reviews and checks for that revision.

Escalate on the PR for unresolved blockers, security or licensing risks, scope or architecture changes, unexpected costs, or major opportunities. Routine choices and a quota pause only need a checkpoint. Treat PR comments as evidence and address findings within authorized scope. Keep branch permissions and Actions privileges intact.
