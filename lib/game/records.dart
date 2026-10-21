import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'world.dart';

class RecordEntry {
  const RecordEntry({
    required this.world,
    required this.level,
    required this.millis,
    required this.playedAt,
  });

  final WorldKind world;
  final int level;
  final int millis;
  final DateTime playedAt;

  String get board => '${world.index}_$level';

  Map<String, Object> toJson() => {
        'w': world.index,
        'l': level,
        't': millis,
        'd': playedAt.millisecondsSinceEpoch,
      };

  static RecordEntry fromJson(Map<String, dynamic> j) => RecordEntry(
        world: WorldKind.values[j['w'] as int],
        level: j['l'] as int,
        millis: j['t'] as int,
        playedAt: DateTime.fromMillisecondsSinceEpoch(j['d'] as int),
      );
}

/// Best results per world + difficulty: the fastest time wins.
class RecordStore {
  static const _key = 'records_v3';
  static const _keepPerBoard = 20;

  static Future<List<RecordEntry>> _all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return [
        for (final j in jsonDecode(raw) as List)
          RecordEntry.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  static int _byTime(RecordEntry a, RecordEntry b) =>
      a.millis.compareTo(b.millis);

  static Future<List<RecordEntry>> load(WorldKind world, int level) async {
    final board = '${world.index}_$level';
    final all = await _all();
    return all.where((e) => e.board == board).toList()..sort(_byTime);
  }

  /// Saves [entry] and returns its 1-based rank on its board.
  static Future<int> add(RecordEntry entry) async {
    final all = await _all();
    all.add(entry);
    final board = all.where((e) => e.board == entry.board).toList()
      ..sort(_byTime);
    final kept = board.take(_keepPerBoard).toSet();
    final rest = all.where((e) => e.board != entry.board);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final e in [...rest, ...kept]) e.toJson()]),
      );
    } catch (_) {}
    return board.indexOf(entry) + 1;
  }
}
