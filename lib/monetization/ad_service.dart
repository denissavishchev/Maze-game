import 'package:flutter/material.dart';

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

/// The ads. Until a real ad network is plugged in, an ad is a blank screen
/// with a button that closes it.
class AdService {
  AdService._();

  /// Between levels: only when [AdGate] says so, and never for VIPs.
  static Future<void> interstitialIfDue(BuildContext context) async {
    if (Vip.instance.on || !AdGate.instance.due) return;
    AdGate.instance.shown();
    await _show(context, rewarded: false);
  }

  /// An interstitial every time, whatever the gate says (VIPs still skip it).
  static Future<void> interstitialAlways(BuildContext context) async {
    if (Vip.instance.on) return;
    AdGate.instance.shown();
    await _show(context, rewarded: false);
  }

  /// An ad the player chooses to watch for a reward; true when it is earned.
  /// A VIP gets the reward without watching.
  static Future<bool> rewarded(BuildContext context) async {
    if (Vip.instance.on) return true;
    return await _show(context, rewarded: true) ?? false;
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
