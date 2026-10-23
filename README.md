# VibeShort

Short-video app (TikTok/SnackVideo style) — Phase 1 MVP: signup/login with persistent sessions, creator profiles, video upload (Cloudinary), vertical feed, likes, comments, share and basic follow.

- Flutter 3.27.4, package `com.vibeshort.app`
- Backend: Firebase project `quizistan-academy` (explicit FirebaseOptions in Dart; collections are namespaced `vibeshort_users` / `vibeshort_videos`)
- Builds run on GitHub Actions; every push to `main` publishes a downloadable APK under Releases.
- APK is arm64-v8a only (small download size).

Later phases (per blueprint): Discover/search and Inbox/notifications shipped in Phase 2; Wallet/monetization (ledger, withdrawal requests, referral codes — test mode, no real payouts until payment-provider setup) shipped in Phase 3; Admin panel + safety layer shipped in Phase 4. The Editing phase adds an in-app camera with LIVE filter/effect preview, an edit screen (live-look preview, trim, 20 FFmpeg-baked filters, 25 frame effects, device music mix, text overlay) — every chosen edit is baked into the posted video. Still to come: website.
