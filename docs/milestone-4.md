# Personal TestFlight maintenance

## Update and verify on iPhone

1. Before updating, note your library count and a distinctive recording, filename and track. Keep the original Files copies. In TestFlight, **Update** over the installed app, check version 0.4.0 and the build number from the PR, then reopen offline. Check the count, search, tracks and duplicate import.
2. Play both NSF pitches, an SPC and a finite VGM. Queue another recording behind the VGM, lock the phone through the transition, and check sound, title, Play/Pause and Next/Previous. Try Siri while playing and paused, then disconnect and reconnect headphones.
3. Use VoiceOver and a large accessibility text size. Find Import, open a recording, distinguish Play from Add to queue for the same track, hear the playing state and reach the transport controls.
4. For a sustained run, use an unplugged iPhone, a fixed route/volume and a locked screen. Queue enough music for an hour. Record device model, iOS, route, elapsed time, start/end battery %, heat, dropouts and any termination. Compare with the previous build or repeat under the same conditions if drain looks unusual. If a Mac with Instruments is available, compare process memory after warm-up and at the end. Report unavailable measurements as such.

Post results on the delivery PR. The owner approves merge separately after acceptance.

## Renewal

TestFlight expires each build 90 days from upload. The subscription-backed **Renew owner TestFlight build** check runs weekly, starting January 18, 2027. When the newest build available to **Owner** has 36 days or less left, begin renewal (normally day 54–60). Use Apple's expiration date on that build. Record the version, build, source SHA, upload/expiration dates and Owner availability on its PR. A successfully uploaded build may still be processing or waiting for compliance.

1. Look for an in-flight delivery first. When a reviewed, tested feature PR is still open at its original head, recheck eligibility and use a fresh owner delivery tag. After merge, create a small maintenance PR from current main recording the previous accepted build and renewal date in this record. Follow the normal two native review passes and current-head CI. This keeps the open-PR gate usable through successive renewals. A maintenance build keeps its marketing version.
2. Use the existing protected tag, unsigned archive, isolated signer and internal-only export. The Owner TestFlight run number supplies the new build number. Keep the main-only environment, restricted tags and receiving-group checks. If the environment requires approval, approve the verified SHA. Install the new build over the previous installation.
3. If the scheduled check is unavailable, use the same steps manually at day 60. Set a private fallback reminder for 30 days before Apple's displayed expiration. At 14 days remaining without an available replacement, escalate immediately. A failed or ambiguous upload calls for checking the exact build in App Store Connect before creating a fresh tag. Processing, Missing Compliance and group assignment can be resolved on the uploaded build. Assign only to **Owner**. An expired beta can be updated in place when the replacement is available. Keep the installed app and its container.

## Credentials and recovery

On uploads after this change reaches main, the signer reports the profile's actual expiration and its matched distribution certificate's expiry. Warnings at 75 days leave time to rotate before the following upload. Record both dates in the owner's private calendar with a 75-day reminder. In Apple Developer Membership details, verify annual renewal, payment method and expiration. Set a private reminder before renewal and optionally set the protected environment variable `APPLE_MEMBERSHIP_EXPIRY` to the displayed YYYY-MM-DD. Refresh it after renewal. Apple remains authoritative for membership status.

- **Profile expired or revoked.** Generate an App Store Connect profile for the existing explicit app ID and valid distribution identity. Replace `APP_STORE_PROFILE_BASE64` in **owner-testflight**.
- **Certificate or private key unavailable.** Restore the password-protected identity from the owner's encrypted backup, or issue a new distribution certificate and regenerate its matching profile. Pause deployments during rotation, replace both P12 secrets and the profile together, and verify the next protected upload before retiring an old usable identity.
- **Upload authentication failed.** Check the team key in App Store Connect. Restore the private backup or generate a Developer-role replacement. Update the protected key ID, issuer if needed, and P8. Revoke a compromised key promptly and resolve pending deployments before resuming.
- **Account or audience failure.** The owner renews membership or accepts required agreements in the Apple account. Inspect the Owner group and automatic internal groups and fix unexpected recipients before retrying. Use the existing protected setup and leave credentials out of PRs, Actions inputs and chat. [Signing and group setup](milestone-2.md#deliver-the-authorized-owner-only-testflight-build)
- **Library recovery.** Search offline and re-import an original from Files if the media is missing or changed. The content hash restores the same recording ID. A valid catalog keeps its original filename during repair. Avoid deleting the app during recovery. Restore from the owner's device backup if both the app container and originals are lost.

## Hosted playback baseline

On x86-64 Linux with GCC 14.2, Release and pinned GME, all 14 baseline CTest cases passed. After CTest, run `python3 tests/playback_soak.py build` with about 606 MiB of temporary space. On the baseline core it rendered 158,760,000 stereo frames (one hour of synthetic NSF) in 1.16 s. Sampled process RSS after the first rendered minute was 2,044–2,044 KiB across 22 samples. The first, middle and final one-second windows had 443, 440 and 440 positive crossings per channel, with matching left/right samples. Existing tests also cover the deterministic short reference, SPC/VGM output and ring conversion/underrun silence.

This accelerated measurement covers the Linux converter and emulator. Wall-clock audio scheduling, AVAudioEngine memory, device energy and the physical output route require the iPhone checks above. Use the PR for the final hosted simulator, device archive and physical results.

## Screen-off tone regression

The owner heard Pulse Pair and BRR pulse break up with the screen off and recover as soon as the Lock Screen lit up. In a Linux ring test with 32 requests of 4,096 frames and one producer wake per request, the build 7 refill policy supplied 16,384 of 131,072 frames. The callback zero-filled the rest. This models a delayed producer and large render slices. The iPhone's actual slice size and wake interval were not measured.

The producer now primes 8,192 stereo frames (32 KiB, about 186 ms) and replenishes the space available at the start of each wake in blocks of at most 512 frames. The callback still reads only committed samples. Stop discards the buffer and pause retains it. The simulator regression uses both reported fixtures and pulls one or two 4,096-frame slices between refills.

On the replacement build, play each tone using the same output route as before. Lock with the side button for at least 30 seconds, wake the screen without unlocking, and repeat twice. Listen for a continuous pitch throughout. Record the build, iPhone model, iOS and output route if it still breaks up.
