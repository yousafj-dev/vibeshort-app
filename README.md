# VibeShort

Short-video app (TikTok/SnackVideo style) — Phase 1 MVP: signup/login with persistent sessions, creator profiles, video upload (Cloudinary), vertical feed, likes, comments, share and basic follow.

- Flutter 3.27.4, package `com.vibeshort.app`
- Backend: Firebase project `quizistan-academy` (explicit FirebaseOptions in Dart; collections are namespaced `vibeshort_users` / `vibeshort_videos`)
- Builds run on GitHub Actions; every push to `main` publishes a downloadable APK under Releases.
- APK is arm64-v8a only (small download size).

Later phases (per blueprint): Discover/search and Inbox/notifications shipped in Phase 2; Wallet/monetization (ledger, withdrawal requests, referral codes — test mode, no real payouts until payment-provider setup) shipped in Phase 3. Still to come: Admin panel, website.
