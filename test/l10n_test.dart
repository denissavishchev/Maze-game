import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';

Set<String> placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  tearDown(() => AppLanguage.instance.lang = AppLang.pl);

  test('every language has exactly the same keys, placeholders and list lengths', () {
    final tables = translationTables;
    final base = tables[AppLang.pl]!;
    for (final lang in AppLang.values) {
      final t = tables[lang]!;
      expect(t.keys.toSet(), base.keys.toSet(), reason: '${lang.name}: keys differ from Polish');
      for (final key in base.keys) {
        expect(t[key]!.trim(), isNotEmpty, reason: '${lang.name}: $key is empty');
        expect(placeholders(t[key]!), placeholders(base[key]!),
            reason: '${lang.name}: placeholders of $key differ');
        expect(t[key]!.split('|').length, base[key]!.split('|').length,
            reason: '${lang.name}: list length of $key differs');
      }
    }
  });

  test('texts follow the selected language', () {
    AppLanguage.instance.lang = AppLang.pl;
    expect(tr('play'), 'GRAJ');
    expect(tr('end.rank', {'n': 3}), 'Miejsce w rekordach: 3');
    AppLanguage.instance.lang = AppLang.en;
    expect(tr('play'), 'PLAY');
    expect(tr('end.rank', {'n': 3}), 'Record rank: 3');
    AppLanguage.instance.lang = AppLang.ru;
    expect(tr('play'), 'ИГРАТЬ');
    expect(tr('end.rank', {'n': 3}), 'Место в рекордах: 3');
    expect(tr('no.such.key'), 'no.such.key', reason: 'unknown keys show themselves');
  });

  test('worlds, balls, sizes and bonuses all have names in every language', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      for (final w in WorldKind.values) {
        expect(tr('world.${w.name}.name'), isNot(startsWith('world.')));
        expect(tr('world.${w.name}.blurb'), isNot(startsWith('world.')));
        expect(tr('bonus.${w.name}'), isNot(startsWith('bonus.')));
      }
      for (final b in BallKind.values) {
        expect(tr('ball.${b.name}.name'), isNot(startsWith('ball.')));
      }
      for (var l = GameConfig.minLevel; l <= GameConfig.maxLevel; l++) {
        expect(GameConfig(WorldKind.forest, l).sizeName, isNot(startsWith('size.')));
      }
    }
  });
}
