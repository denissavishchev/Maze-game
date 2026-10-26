import 'package:flutter/material.dart';

import '../game/ball.dart';
import '../game/ball_collection.dart';
import '../l10n/strings.dart';
import '../monetization/store.dart';
import 'balls.dart';
import 'kit.dart';
import 'palette.dart';

/// The ball cabinet: which balls the player owns, how to earn the others and
/// the buttons to buy them, one by one or all at once.
Future<void> showBallShop(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _BallShop(),
    );

class _BallShop extends StatelessWidget {
  const _BallShop();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([BallCollection.instance, AppLanguage.instance, Store.instance]),
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final owned = BallCollection.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
          child: MossPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('ball.shop.title'), style: cartoon(22, spacing: 2)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [for (final b in BallKind.values) _row(b)],
                  ),
                ),
                const SizedBox(height: 10),
                if (owned.locked.isNotEmpty)
                  ChunkyButton(
                    key: const Key('buy-all-balls'),
                    label: tr('ball.buy_all', {'price': Store.instance.allBallsPrice ?? '…'}),
                    icon: Icons.shopping_bag_rounded,
                    look: ButtonLook.gold,
                    fontSize: 16,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    onTap: Store.instance.canBuy(Store.allBallsId) ? Store.buyAllBalls : null,
                  ),
                TextButton(
                  key: const Key('restore-purchases'),
                  onPressed: () async {
                    await Store.restore();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('ball.restored'))));
                    }
                  },
                  child: Text(tr('ball.restore'),
                      style: const TextStyle(color: Palette.sand)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BallKind b) {
    final has = BallCollection.instance.owns(b);
    final source = BallCollection.sourceOf(b);
    final how = switch (source) {
      BallSource.starter => tr('ball.starter'),
      BallSource.chapter => tr('ball.reward_chapter', {'n': BallCollection.chapterOf(b)!}),
      BallSource.stars => tr('ball.reward_stars', {'n': BallCollection.starsNeeded}),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Opacity(opacity: has ? 1 : 0.45, child: BallBubble(kind: b, size: 42)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(infoOf(b).name, style: cartoon(16, outline: 1.4)),
                Text(has ? tr('ball.owned') : how,
                    style: TextStyle(
                        color: has ? const Color(0xFFA6F55B) : Palette.cream,
                        fontSize: 12)),
              ],
            ),
          ),
          if (has)
            const Icon(Icons.check_circle_rounded, color: Color(0xFFA6F55B))
          else
            FilledButton(
              key: Key('buy-ball-${b.name}'),
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(Palette.gold),
                foregroundColor: WidgetStatePropertyAll(Palette.woodDark),
              ),
              onPressed:
                  Store.instance.canBuy(Store.ballId(b)) ? () => Store.buyBall(b) : null,
              child: Text(Store.instance.ballPrice(b) ?? '…'),
            ),
        ],
      ),
    );
  }
}
