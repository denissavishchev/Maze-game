import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../l10n/strings.dart';
import 'kit.dart';
import 'palette.dart';

enum _Filter { all, earned, locked }

/// Every achievement as a tile: in colour once earned, greyed out until then.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([AppLanguage.instance, Achievements.instance]),
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final store = Achievements.instance;
    final shown = [
      for (final a in achievementList)
        if (switch (_filter) {
          _Filter.all => true,
          _Filter.earned => store.has(a.id),
          _Filter.locked => !store.has(a.id),
        })
          a,
    ];
    return Scaffold(
      body: ArtBackdrop(
        dim: 0.5,
        blur: 5,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ChunkyIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(tr('achievements'), style: cartoon(24, spacing: 3)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                for (final f in _Filter.values) ...[
                                  ChoiceChip(
                                    key: Key('ach-filter-${f.name}'),
                                    label: Text(tr('ach.filter.${f.name}')),
                                    selected: _filter == f,
                                    onSelected: (_) => setState(() => _filter = f),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${store.earnedCount}/${achievementList.length}',
                            key: const Key('ach-count'),
                            style: cartoon(20, outline: 1.5)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                              child: Text(tr('ach.empty'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, color: Palette.cream)),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: shown.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _Tile(shown[i]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.a);

  final Achievement a;

  @override
  Widget build(BuildContext context) {
    final got = Achievements.instance.has(a.id);
    final progress = got ? null : Achievements.instance.progress(a.id);
    final tile = MossPanel(
      key: Key('ach-${a.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: got ? Palette.woodDark : Colors.black38,
              border: Border.all(color: got ? Palette.gold : Palette.stoneDark, width: 3),
            ),
            child: Icon(a.icon, size: 28, color: got ? Palette.gold : Palette.stone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('ach.${a.id}'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: Palette.cream)),
                const SizedBox(height: 2),
                Text(tr('ach.${a.id}.desc'),
                    style: const TextStyle(fontSize: 14, color: Palette.cream)),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress.$1 / progress.$2,
                            minHeight: 6,
                            color: Palette.gold,
                            backgroundColor: Colors.black38,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${progress.$1} / ${progress.$2}',
                          style: const TextStyle(fontSize: 12, color: Palette.cream)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (got) const Icon(Icons.check_circle_rounded, color: Palette.gold),
        ],
      ),
    );
    // Not earned yet: the whole tile greyed out.
    return got
        ? tile
        : ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0, 0, 0, 0.7, 0,
            ]),
            child: tile,
          );
  }
}
