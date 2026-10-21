import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Languages of the app. To add one, add a value here, a label in
/// [AppLang.label] and a table in [_tables] with the same keys.
enum AppLang {
  pl('PL', 'Polski'),
  en('EN', 'English'),
  ru('RU', 'Русский');

  const AppLang(this.label, this.nativeName);

  /// Short code and the language's own name.
  final String label;
  final String nativeName;
}

/// The language in use. Screens that show text listen to it so they redraw
/// when it changes; the choice is remembered between launches.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();

  static final AppLanguage instance = AppLanguage._();

  AppLang lang = AppLang.pl;

  /// Loads the saved language, or picks one from the device (Polish, Russian or
  /// English).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('lang');
      lang = AppLang.values.firstWhere(
        (l) => l.name == saved,
        orElse: _fromDevice,
      );
    } catch (_) {
      lang = _fromDevice();
    }
    notifyListeners();
  }

  static AppLang _fromDevice() =>
      switch (PlatformDispatcher.instance.locale.languageCode) {
        'pl' => AppLang.pl,
        'ru' => AppLang.ru,
        _ => AppLang.en,
      };

  Future<void> set(AppLang value) async {
    if (value == lang) return;
    lang = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lang', value.name);
    } catch (_) {}
  }
}

/// Translates [key] into the current language. `{name}` placeholders are
/// replaced from [args]. Falls back to Polish, then to the key itself.
String tr(String key, [Map<String, Object> args = const {}]) {
  var s = _tables[AppLanguage.instance.lang]![key] ?? _tables[AppLang.pl]![key] ?? key;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// A translation holding several lines separated by `|`.
List<String> trList(String key) => tr(key).split('|');

/// All translation tables (tests check that they cover the same keys).
@visibleForTesting
Map<AppLang, Map<String, String>> get translationTables => _tables;

const _tables = <AppLang, Map<String, String>>{
  AppLang.pl: {
    'cal.label': 'Kalibruj',
    'tt.calibrate': 'Kalibruj: ustaw obecne trzymanie telefonu jako poziome',
    'tt.restart': 'Restart',
    'set.vibration': 'Wibracje',
    'set.vib_on': 'Włączone (delikatne)',
    'set.vib_off': 'Wyłączone',
    'set.test': 'Sprawdź dźwięk',
    'set.sound_error':
        'Dźwięk nie działa: {e}\nZamknij aplikację całkowicie i uruchom ją od nowa (po dodaniu dźwięku samo odświeżenie nie wystarcza).',
    'settings': 'USTAWIENIA',
    'set.language': 'Język',
    'set.sound': 'Dźwięk',
    'set.sound_on': 'Włączony',
    'set.sound_off': 'Wyłączony',
    'title': 'LABIRYNT',
    'play': 'GRAJ',
    'records': 'REKORDY',
    'sel.world': 'ŚWIAT',
    'sel.ball': 'KULKA',
    'sel.size': 'ROZMIAR LABIRYNTU',
    'sel.bonus': 'Bonus: {name} ({n} użycia)',
    'size.1': 'Mały',
    'size.2': 'Średni',
    'size.3': 'Duży',
    'size.4': 'Wielki',
    'size.5': 'Ogromny',
    'summary.one': '{buttons} przycisków · {note} · 1 bonus',
    'summary.many': '{buttons} przycisków · {note} · {bonuses} bonusy',
    'note.wolf.one': '1 wilk',
    'note.wolf.many': '{n} wilki',
    'note.drone.one': '1 dron',
    'note.drone.many': '{n} drony',
    'note.light': 'widać {x} pola',
    'note.trap.one': '1 pułapka co {s} s',
    'note.trap.many': '{n} pułapki co {s} s',
    'note.boulder.one': '1 głaz co {s} s',
    'note.boulder.many': '{n} głazy co {s} s',
    'world.forest.name': 'Las',
    'world.forest.blurb':
        'Wilk śpi, a budzi go hałas toczącej się kulki. Gdy staniesz, traci zainteresowanie.',
    'world.mud.name': 'Błoto',
    'world.mud.blurb':
        'Bagna wciągają, a kolce wyskakują w korytarzu przed tobą i go blokują.',
    'world.mountains.name': 'Góry',
    'world.mountains.blurb':
        'Głazy spadają tam, dokąd jedziesz, i zostają jako rumowisko. Na największych: wiatr.',
    'world.underground.name': 'Podziemie',
    'world.underground.blurb': 'Ciemno. Widać tylko najbliższe otoczenie kulki.',
    'world.city.name': 'Miasto',
    'world.city.blurb':
        'Drony śpią, ale hałas je budzi. Gdy staniesz, tracą zainteresowanie. Zauważą cię – wracasz na start.',
    'bonus.forest': 'Uśpij wilki',
    'bonus.mud': 'Wyłącz pułapki',
    'bonus.mountains': 'Wyłącz głazy',
    'bonus.underground': 'Więcej światła',
    'bonus.city': 'Wyłącz drony',
    'ball.wood.name': 'Drewno',
    'ball.wood.pros': 'Zbalansowana we wszystkim',
    'ball.wood.cons': 'Bez szczególnych zalet',
    'ball.steel.name': 'Stal',
    'ball.steel.pros': 'Najszybsza, długo się toczy|Wiatr słabiej ją znosi',
    'ball.steel.cons': 'Głośna: słychać ją z daleka|Wolno przyspiesza, trudno ją zatrzymać',
    'ball.rubber.name': 'Guma',
    'ball.rubber.pros': 'Bardzo cicha|Odbija się od ścian',
    'ball.rubber.cons': 'Skacze, trudniej ją opanować|Wiatr zwiewa ją mocniej',
    'ball.glass.name': 'Szkło',
    'ball.glass.pros': 'Mała i zwinna, szybko przyspiesza',
    'ball.glass.cons': 'Pęka przy mocnym uderzeniu w ścianę',
    'ball.stone.name': 'Kamień',
    'ball.stone.pros': 'Wiatr i bagno słabo na nią działają|Dość cicha',
    'ball.stone.cons': 'Wolna i większa',
    'tt.menu': 'Menu',
    'hint.tilt':
        'Przechyl telefon, żeby toczyć kulkę do środka. Mapka odsłania się tam, gdzie byłeś; złote kropki to przyciski bram.',
    'hint.nosensor':
        'Nie wykryto czujnika ruchu. Ta gra jest sterowana wyłącznie przechylaniem telefonu.',
    'meter.noise': 'HAŁAS',
    'meter.quiet': 'cicho',
    'meter.cells': '{x} pola',
    'wind.now': 'WIATR!',
    'wind.coming': 'NADCHODZI WIATR',
    'notice.wind': 'Podmuch wiatru!',
    'notice.drone': 'Dron cię zauważył! Wracasz na start.',
    'notice.bonus': 'Bonus! {n} użycia: {name}',
    'lose.wolf': 'Wilk cię dopadł!',
    'lose.trap': 'Wpadłeś w pułapkę!',
    'lose.rock': 'Zgniótł cię głaz!',
    'lose.bog': 'Utonąłeś w błocie!',
    'lose.glass': 'Szklana kulka pękła!',
    'end.win': 'Wyjście znalezione!',
    'end.time': 'Czas: {t}',
    'end.rank': 'Miejsce w rekordach: {n}',
    'end.next': 'Następny labirynt',
    'end.retry': 'Spróbuj ponownie',
    'end.new_maze': 'Nowy labirynt',
    'end.records': 'Rekordy',
    'records.empty': 'Brak wyników. Przejdź labirynt!',
  },
  AppLang.en: {
    'cal.label': 'Calibrate',
    'tt.calibrate': 'Calibrate: take the way you hold the phone now as level',
    'tt.restart': 'Restart',
    'set.vibration': 'Vibration',
    'set.vib_on': 'On (gentle)',
    'set.vib_off': 'Off',
    'set.test': 'Test sound',
    'set.sound_error':
        'Sound is not working: {e}\nClose the app completely and start it again (a hot reload is not enough after audio was added).',
    'settings': 'SETTINGS',
    'set.language': 'Language',
    'set.sound': 'Sound',
    'set.sound_on': 'On',
    'set.sound_off': 'Off',
    'title': 'MAZE',
    'play': 'PLAY',
    'records': 'RECORDS',
    'sel.world': 'WORLD',
    'sel.ball': 'BALL',
    'sel.size': 'MAZE SIZE',
    'sel.bonus': 'Bonus: {name} ({n} uses)',
    'size.1': 'Small',
    'size.2': 'Medium',
    'size.3': 'Large',
    'size.4': 'Huge',
    'size.5': 'Giant',
    'summary.one': '{buttons} buttons · {note} · 1 bonus',
    'summary.many': '{buttons} buttons · {note} · {bonuses} bonuses',
    'note.wolf.one': '1 wolf',
    'note.wolf.many': '{n} wolves',
    'note.drone.one': '1 drone',
    'note.drone.many': '{n} drones',
    'note.light': 'visibility {x} cells',
    'note.trap.one': '1 trap every {s} s',
    'note.trap.many': '{n} traps every {s} s',
    'note.boulder.one': '1 boulder every {s} s',
    'note.boulder.many': '{n} boulders every {s} s',
    'world.forest.name': 'Forest',
    'world.forest.blurb':
        'The wolf sleeps and is woken by the noise of your rolling ball. Stand still and it loses interest.',
    'world.mud.name': 'Mud',
    'world.mud.blurb':
        'Bogs pull you in, and spikes pop up in the corridor ahead and block it.',
    'world.mountains.name': 'Mountains',
    'world.mountains.blurb':
        'Boulders fall where you are heading and stay behind as rubble. On the biggest sizes: wind.',
    'world.underground.name': 'Underground',
    'world.underground.blurb': 'Dark. You only see the area right around the ball.',
    'world.city.name': 'City',
    'world.city.blurb':
        'Drones sleep, but noise wakes them. Stand still and they lose interest. If they spot you, you go back to the start.',
    'bonus.forest': 'Put wolves to sleep',
    'bonus.mud': 'Disable traps',
    'bonus.mountains': 'Disable boulders',
    'bonus.underground': 'More light',
    'bonus.city': 'Disable drones',
    'ball.wood.name': 'Wood',
    'ball.wood.pros': 'Balanced in everything',
    'ball.wood.cons': 'No special strengths',
    'ball.steel.name': 'Steel',
    'ball.steel.pros': 'Fastest, keeps rolling|Wind pushes it less',
    'ball.steel.cons': 'Loud: heard from afar|Slow to accelerate, hard to stop',
    'ball.rubber.name': 'Rubber',
    'ball.rubber.pros': 'Very quiet|Bounces off walls',
    'ball.rubber.cons': 'Bouncy, harder to control|Wind blows it harder',
    'ball.glass.name': 'Glass',
    'ball.glass.pros': 'Small and agile, accelerates fast',
    'ball.glass.cons': 'Shatters on a hard hit against a wall',
    'ball.stone.name': 'Stone',
    'ball.stone.pros': 'Wind and bogs barely affect it|Fairly quiet',
    'ball.stone.cons': 'Slow and larger',
    'tt.menu': 'Menu',
    'hint.tilt':
        'Tilt your phone to roll the ball to the centre. The minimap shows where you have been; golden dots are gate buttons.',
    'hint.nosensor':
        'No motion sensor detected. This game is controlled only by tilting your phone.',
    'meter.noise': 'NOISE',
    'meter.quiet': 'quiet',
    'meter.cells': '{x} cells',
    'wind.now': 'WIND!',
    'wind.coming': 'WIND INCOMING',
    'notice.wind': 'Gust of wind!',
    'notice.drone': 'A drone spotted you! Back to the start.',
    'notice.bonus': 'Bonus! {n} uses: {name}',
    'lose.wolf': 'The wolf got you!',
    'lose.trap': 'You fell into a trap!',
    'lose.rock': 'A boulder crushed you!',
    'lose.bog': 'You drowned in the mud!',
    'lose.glass': 'The glass ball shattered!',
    'end.win': 'Exit found!',
    'end.time': 'Time: {t}',
    'end.rank': 'Record rank: {n}',
    'end.next': 'Next maze',
    'end.retry': 'Try again',
    'end.new_maze': 'New maze',
    'end.records': 'Records',
    'records.empty': 'No results yet. Solve a maze!',
  },
  AppLang.ru: {
    'cal.label': 'Калибровка',
    'tt.calibrate': 'Калибровка: считать текущее положение телефона ровным',
    'tt.restart': 'Заново',
    'set.vibration': 'Вибрация',
    'set.vib_on': 'Включена (лёгкая)',
    'set.vib_off': 'Выключена',
    'set.test': 'Проверить звук',
    'set.sound_error':
        'Звук не работает: {e}\nПолностью закройте приложение и запустите заново (после добавления звука одного обновления недостаточно).',
    'settings': 'НАСТРОЙКИ',
    'set.language': 'Язык',
    'set.sound': 'Звук',
    'set.sound_on': 'Включён',
    'set.sound_off': 'Выключен',
    'title': 'ЛАБИРИНТ',
    'play': 'ИГРАТЬ',
    'records': 'РЕКОРДЫ',
    'sel.world': 'МИР',
    'sel.ball': 'ШАРИК',
    'sel.size': 'РАЗМЕР ЛАБИРИНТА',
    'sel.bonus': 'Бонус: {name} ({n} использования)',
    'size.1': 'Малый',
    'size.2': 'Средний',
    'size.3': 'Большой',
    'size.4': 'Огромный',
    'size.5': 'Гигантский',
    'summary.one': '{buttons} кнопок · {note} · 1 бонус',
    'summary.many': '{buttons} кнопок · {note} · {bonuses} бонуса',
    'note.wolf.one': '1 волк',
    'note.wolf.many': '{n} волка',
    'note.drone.one': '1 дрон',
    'note.drone.many': '{n} дрона',
    'note.light': 'видно {x} клетки',
    'note.trap.one': '1 ловушка каждые {s} с',
    'note.trap.many': '{n} ловушки каждые {s} с',
    'note.boulder.one': '1 валун каждые {s} с',
    'note.boulder.many': '{n} валуна каждые {s} с',
    'world.forest.name': 'Лес',
    'world.forest.blurb':
        'Волк спит, и его будит шум катящегося шарика. Остановишься — он теряет интерес.',
    'world.mud.name': 'Грязь',
    'world.mud.blurb':
        'Болота затягивают, а шипы выскакивают в коридоре перед тобой и перекрывают его.',
    'world.mountains.name': 'Горы',
    'world.mountains.blurb':
        'Валуны падают туда, куда ты катишься, и остаются как завал. На самых больших — ветер.',
    'world.underground.name': 'Подземелье',
    'world.underground.blurb': 'Темно. Видно только ближайшее окружение шарика.',
    'world.city.name': 'Город',
    'world.city.blurb':
        'Дроны спят, но шум их будит. Остановишься — они теряют интерес. Заметят тебя — вернёшься на старт.',
    'bonus.forest': 'Усыпить волков',
    'bonus.mud': 'Отключить ловушки',
    'bonus.mountains': 'Отключить валуны',
    'bonus.underground': 'Больше света',
    'bonus.city': 'Отключить дроны',
    'ball.wood.name': 'Дерево',
    'ball.wood.pros': 'Сбалансирован во всём',
    'ball.wood.cons': 'Без особых достоинств',
    'ball.steel.name': 'Сталь',
    'ball.steel.pros': 'Самый быстрый, долго катится|Ветер сносит слабее',
    'ball.steel.cons': 'Громкий: слышно издалека|Медленно разгоняется, трудно остановить',
    'ball.rubber.name': 'Резина',
    'ball.rubber.pros': 'Очень тихая|Отскакивает от стен',
    'ball.rubber.cons': 'Прыгает, труднее управлять|Ветер сносит сильнее',
    'ball.glass.name': 'Стекло',
    'ball.glass.pros': 'Маленькое и ловкое, быстро разгоняется',
    'ball.glass.cons': 'Разбивается при сильном ударе о стену',
    'ball.stone.name': 'Камень',
    'ball.stone.pros': 'Ветер и болото почти не действуют|Довольно тихий',
    'ball.stone.cons': 'Медленный и крупнее',
    'tt.menu': 'Меню',
    'hint.tilt':
        'Наклоняй телефон, чтобы катить шарик к центру. Мини-карта открывается там, где ты был; золотые точки — кнопки ворот.',
    'hint.nosensor':
        'Датчик движения не найден. Игра управляется только наклоном телефона.',
    'meter.noise': 'ШУМ',
    'meter.quiet': 'тихо',
    'meter.cells': '{x} клетки',
    'wind.now': 'ВЕТЕР!',
    'wind.coming': 'БЛИЗИТСЯ ВЕТЕР',
    'notice.wind': 'Порыв ветра!',
    'notice.drone': 'Дрон заметил тебя! Возврат на старт.',
    'notice.bonus': 'Бонус! {n} использования: {name}',
    'lose.wolf': 'Волк тебя поймал!',
    'lose.trap': 'Ты попал в ловушку!',
    'lose.rock': 'Тебя раздавил валун!',
    'lose.bog': 'Ты утонул в грязи!',
    'lose.glass': 'Стеклянный шарик разбился!',
    'end.win': 'Выход найден!',
    'end.time': 'Время: {t}',
    'end.rank': 'Место в рекордах: {n}',
    'end.next': 'Следующий лабиринт',
    'end.retry': 'Попробовать снова',
    'end.new_maze': 'Новый лабиринт',
    'end.records': 'Рекорды',
    'records.empty': 'Пока нет результатов. Пройди лабиринт!',
  },
};
