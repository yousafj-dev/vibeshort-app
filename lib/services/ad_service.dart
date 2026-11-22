import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob integration (VibeShort's own ad units, created
/// 22 Nov 2026 — separate from Quizistan's).
///
/// Placements:
///  - One anchored banner at the bottom of the home feed
///    (rendered by FeedBannerAd, which uses [bannerUnitId]).
///  - One interstitial, preloaded at startup, shown after
///    every [swipesPerInterstitial]-th video change in the
///    feed and at most once per [minInterstitialInterval].
///
/// Failure safety is the design rule: the app is in AdMob's
/// "Requires review" state, so limited / no ad serving is
/// EXPECTED for now. Every load is fire-and-forget with its
/// failure swallowed (debugPrint only) — a failed ad must
/// leave the app behaving exactly as it did before ads
/// existed: no crashes, no stuck overlays, and the banner
/// area collapses to zero height (see FeedBannerAd).
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  /// VibeShort banner ad unit ("Vibe short", created
  /// 22 Nov 2026).
  static const String bannerUnitId =
      'ca-app-pub-7871232394986284/5585298235';

  /// VibeShort interstitial ad unit (created 22 Nov 2026).
  static const String interstitialUnitId =
      'ca-app-pub-7871232394986284/1646053223';

  /// Show one interstitial per this many feed video changes…
  static const int swipesPerInterstitial = 5;

  /// …but never more often than this, however fast the swipes.
  static const Duration minInterstitialInterval = Duration(minutes: 3);

  bool _initialized = false;

  InterstitialAd? _interstitial;
  bool _interstitialLoading = false;
  bool _interstitialShowing = false;

  int _swipesSinceInterstitial = 0;
  DateTime? _lastInterstitialAt;

  /// Starts the Mobile Ads SDK and preloads the first
  /// interstitial. Non-blocking and safe to call unawaited
  /// from main(): every failure is caught here.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
      loadInterstitial();
    } catch (e) {
      debugPrint('VibeShort ads: SDK init failed: $e');
    }
  }

  /// Loads one interstitial into memory. No-op while one is
  /// already loaded, loading, or on screen.
  void loadInterstitial() {
    if (_interstitial != null ||
        _interstitialLoading ||
        _interstitialShowing) {
      return;
    }
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialLoading = false;
          _interstitial = null;
          // Expected while the app is under AdMob review —
          // stay silent in release, just don't show anything.
          debugPrint('VibeShort ads: interstitial failed to load: $error');
        },
      ),
    );
  }

  /// Called by the home feed's pager on every settled video
  /// change. Counts swipes and shows the interstitial when
  /// both the swipe quota and the minimum interval allow it.
  void onFeedVideoChanged() {
    _swipesSinceInterstitial++;
    if (_swipesSinceInterstitial < swipesPerInterstitial) return;
    final last = _lastInterstitialAt;
    if (last != null &&
        DateTime.now().difference(last) < minInterstitialInterval) {
      // Quota reached but too soon since the last one — keep
      // the count, so the next swipe after the interval can
      // show immediately.
      return;
    }
    _showInterstitial();
  }

  void _showInterstitial() {
    final ad = _interstitial;
    if (ad == null) {
      // Nothing ready (still loading, or serving is limited):
      // kick a load and try again on a later swipe.
      loadInterstitial();
      return;
    }
    if (_interstitialShowing) return;
    _interstitialShowing = true;
    _interstitial = null;
    _swipesSinceInterstitial = 0;
    _lastInterstitialAt = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialShowing = false;
        loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('VibeShort ads: interstitial failed to show: $error');
        ad.dispose();
        _interstitialShowing = false;
        loadInterstitial();
      },
    );
    try {
      ad.show();
    } catch (e) {
      debugPrint('VibeShort ads: interstitial show threw: $e');
      ad.dispose();
      _interstitialShowing = false;
      loadInterstitial();
    }
  }
}
