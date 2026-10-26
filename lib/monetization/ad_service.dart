import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../l10n/strings.dart';
import 'vip.dart';

/// Decides when an interstitial is due: after every [every] finished levels,
/// and never sooner than [minGap] after the last one. The counters live in
/// memory, so they start from zero with every launch.
class AdGate {
  AdGate({this.every = 3, this.minGap = const Duration(seconds: 90), DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  static final AdGate instance = AdGate();

  final int every;
  final Duration minGap;
  final DateTime Function() _now;

  int _finished = 0;
  DateTime? _last;

  /// A level (or an endless run) ended.
  void levelFinished() => _finished++;

  bool get due =>
      _finished >= every && (_last == null || _now().difference(_last!) >= minGap);

  void shown() {
    _finished = 0;
    _last = _now();
  }
}

/// AdMob ids. Debug builds always use Google's test units, so the real ones
/// can never be clicked by accident while developing.
class AdIds {
  AdIds._();

  /// Builds for testers (`--dart-define=TEST_ADS=true`) keep the test units
  /// even in release mode, so nobody clicks a real ad by mistake.
  static const bool _testAds = bool.fromEnvironment('TEST_ADS');

  static bool get _real => kReleaseMode && !_testAds;

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  static String get interstitial => _real
      ? (_android
          ? 'ca-app-pub-8806137132254301/7634164509'
          : 'ca-app-pub-8806137132254301/2190266133')
      : (_android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910');

  static String get rewarded => _real
      ? (_android
          ? 'ca-app-pub-8806137132254301/9480976527'
          : 'ca-app-pub-8806137132254301/4228649846')
      : (_android
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313');
}

/// The ads. On a phone with [start] called, they are real AdMob ads; anywhere
/// else (tests, desktop, web) an ad is a blank screen with a button that
/// closes it.
class AdService {
  AdService._();

  /// True once AdMob is up and running (phones only, after [start]).
  static bool live = false;

  static InterstitialAd? _interstitial;
  static RewardedAd? _rewarded;
  static bool _loadingInterstitial = false;
  static bool _loadingRewarded = false;

  static bool get _phone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Asks for consent where the law wants it (UMP), then starts AdMob and
  /// loads the first ads. Never throws; without it the game just has no ads.
  static Future<void> start() async {
    if (!_phone) return;
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          } catch (_) {}
          if (!done.isCompleted) done.complete();
        },
        (_) {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      await _askToTrack();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      live = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (_) {}
  }

  /// iOS: the system's "allow tracking?" question, asked once, before any ad
  /// is requested. Declining still shows ads, only less personal ones.
  static Future<void> _askToTrack() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      if (await AppTrackingTransparency.trackingAuthorizationStatus ==
          TrackingStatus.notDetermined) {
        // The question only appears once the app is fully in the foreground.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (_) {}
  }

  static void _loadInterstitial() {
    if (!live || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (_) => _loadingInterstitial = false,
      ),
    );
  }

  static void _loadRewarded() {
    if (!live || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
        },
        onAdFailedToLoad: (_) => _loadingRewarded = false,
      ),
    );
  }

  /// Between levels: only when [AdGate] says so, and never for VIPs.
  static Future<void> interstitialIfDue(BuildContext context) async {
    if (Vip.instance.on || !AdGate.instance.due) return;
    await _interstitialNow(context);
  }

  /// An interstitial every time, whatever the gate says (VIPs still skip it).
  static Future<void> interstitialAlways(BuildContext context) async {
    if (Vip.instance.on) return;
    await _interstitialNow(context);
  }

  static Future<void> _interstitialNow(BuildContext context) async {
    if (!live) {
      AdGate.instance.shown();
      await _show(context, rewarded: false);
      return;
    }
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return; // no ad ready: do not hold the player up
    }
    _interstitial = null;
    AdGate.instance.shown();
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show();
    await closed.future;
    _loadInterstitial();
  }

  /// An ad the player chooses to watch for a reward; true when it is earned.
  /// A VIP gets the reward without watching.
  static Future<bool> rewarded(BuildContext context) async {
    if (Vip.instance.on) return true;
    if (!live) return await _show(context, rewarded: true) ?? false;
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(tr('ad.unavailable'))));
      }
      return false;
    }
    _rewarded = null;
    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    await closed.future;
    _loadRewarded();
    return earned;
  }

  static Future<bool?> _show(BuildContext context, {required bool rewarded}) =>
      Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => AdScreen(rewarded: rewarded),
        ),
      );
}

/// The stand-in ad: blank, with a close button.
class AdScreen extends StatelessWidget {
  const AdScreen({super.key, required this.rewarded});

  final bool rewarded;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Text(tr(rewarded ? 'ad.rewarded' : 'ad.interstitial'),
                      style: const TextStyle(color: Colors.white24, fontSize: 18)),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    key: const Key('ad-close'),
                    tooltip: tr('ad.close'),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 30),
                    onPressed: () => Navigator.of(context).pop(rewarded),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
