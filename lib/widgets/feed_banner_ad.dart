import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vibeshort/services/ad_service.dart';

/// The shared anchored banner shown as a slim strip at the
/// very bottom of the home feed screen, above the shell's
/// bottom navigation bar.
///
/// Collapse-on-failure is the contract: while no ad has
/// loaded — offline, a load error, or AdMob's limited serving
/// during the app's "Requires review" period — this renders
/// as a zero-height box, so the feed looks and behaves
/// exactly as it did before ads were integrated. Only a
/// successfully loaded ad takes up its 50dp strip.
class FeedBannerAd extends StatefulWidget {
  const FeedBannerAd({super.key});

  @override
  State<FeedBannerAd> createState() => _FeedBannerAdState();
}

class _FeedBannerAdState extends State<FeedBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      adUnitId: AdService.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('VibeShort ads: banner failed to load: $error');
          ad.dispose();
          if (mounted) {
            setState(() {
              _loaded = false;
              _banner = null;
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (!_loaded || banner == null) return const SizedBox.shrink();
    return Container(
      // The feed behind/above is black; keep the strip black
      // too so the banner reads as part of the feed chrome.
      color: Colors.black,
      width: double.infinity,
      height: banner.size.height.toDouble(),
      alignment: Alignment.center,
      child: SizedBox(
        width: banner.size.width.toDouble(),
        height: banner.size.height.toDouble(),
        child: AdWidget(ad: banner),
      ),
    );
  }
}
