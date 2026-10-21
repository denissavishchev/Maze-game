import 'package:flutter/material.dart';

import '../game/records.dart';
import '../game/world.dart';
import '../l10n/strings.dart';
import 'game_screen.dart';
import 'kit.dart';
import 'palette.dart';
import 'worlds.dart';

Future<void> showRecords(BuildContext context, GameConfig config) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF223820),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: Palette.ink, width: 3),
    ),
    builder: (_) => _RecordsSheet(config: config),
  );
}

class _RecordsSheet extends StatefulWidget {
  const _RecordsSheet({required this.config});

  final GameConfig config;

  @override
  State<_RecordsSheet> createState() => _RecordsSheetState();
}

class _RecordsSheetState extends State<_RecordsSheet> {
  late WorldKind world = widget.config.world;
  late int level = widget.config.level;
  late Future<List<RecordEntry>> future = RecordStore.load(world, level);

  void _select({WorldKind? w, int? l}) {
    setState(() {
      world = w ?? world;
      level = l ?? level;
      future = RecordStore.load(world, level);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.emoji_events_rounded, color: Palette.gold),
                  const SizedBox(width: 8),
                  Text(tr('records'), style: cartoon(22, spacing: 2)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  for (final w in WorldKind.values)
                    ChoiceChip(
                      label: Text(themeFor(w).name),
                      selected: w == world,
                      onSelected: (_) => _select(w: w),
                    ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (var l = GameConfig.minLevel; l <= GameConfig.maxLevel; l++)
                    ChoiceChip(
                      label: SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(
                          child: Container(
                            width: 6.0 + l * 3,
                            height: 6.0 + l * 3,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      tooltip: GameConfig(world, l).sizeName,
                      selected: l == level,
                      onSelected: (_) => _select(l: l),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<List<RecordEntry>>(
                  future: future,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(color: Palette.gold),
                      );
                    }
                    final list = snap.data!;
                    if (list.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr('records.empty')),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length > 10 ? 10 : list.length,
                      itemBuilder: (_, i) => _row(i + 1, list[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(int place, RecordEntry e) {
    final d = e.playedAt;
    final date =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: place == 1 ? 0.35 : 0.2),
        borderRadius: BorderRadius.circular(10),
        border: place == 1 ? Border.all(color: Palette.gold) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('$place.',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: place == 1 ? Palette.gold : Colors.white70)),
          ),
          const Icon(Icons.timer_outlined, size: 16, color: Colors.white70),
          const SizedBox(width: 4),
          Expanded(child: Text(formatTime(e.millis / 1000))),
          Text(date, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
