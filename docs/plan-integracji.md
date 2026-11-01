# Plan integracji fabuły

Notatka do dalszej pracy nad scenariuszem „Piąta pora roku”. Czytać razem z:
- [piata-pora-roku-scenariusz.md](piata-pora-roku-scenariusz.md): ekrany, kolejność, zasady.
- [teksty-scenariusza.json](teksty-scenariusza.json): 101 tekstów PL/EN/RU.
- [obrazki-prompty.md](obrazki-prompty.md): 27 obrazków i nazwy plików.
- [puzzle-szablon.png](puzzle-szablon.png): układ puzzli.

## Stan

**Zrobione**
- Mapa z rozwidleniami: `lib/ui/story_map_screen.dart`, lustro na czubku jest na razie tylko ozdobą (`story-mirror`).
- Układ rozdziału: dwa drzewa, pierwszy poziom każdego rozwidla się na dwie linie po 3 poziomy (`before`, `afterwards` w `lib/game/story.dart`).
- Otwieranie: `chapterOpen`, `isUnlocked`, `nextAfter`, stany `StoryState` w `lib/game/story_progress.dart`. Rozdział wymaga ukończenia czterech końców linii poprzedniego, czyli całego rozdziału, i 21 gwiazdek na rozdział wstecz.
- Teksty i prompty w `docs/`.

**Do zrobienia po dostarczeniu obrazków**

Nic z fabuły nie jest jeszcze w grze: brak wprowadzenia, puzzli, notatek i finału.

## Kroki

1. **Zasoby.** Sprawdzić komplet 27 plików w `assets/images/story/` i dopisać ten folder w `pubspec.yaml`, bo `assets/images/` nie obejmuje podfolderów.
2. **Teksty.** Przenieść JSON do `translationTables` w `lib/l10n/strings.dart` pod kluczami `tale.<id>`, na przykład `tale.level.14`. Test `l10n_test` pilnuje zgodności trzech języków.
3. **Postęp.** Kawałek jest zdobyty, gdy `stars(index) > 0`, więc obecni gracze dostają swoje kawałki bez migracji. Nowy zapis w `shared_preferences`: wstawione kawałki, obejrzane wprowadzenie, karty rozdziałów i ostatnie zakończenie (`a` lub `b`).
4. **Plansza puzzli.** Nowy ekran `lib/ui/puzzle_screen.dart`.
   - Pole poziomu: pierścień `chapter - 1` licząc od zewnątrz, wycinek `number - 1` od godziny 12 zgodnie z ruchem wskazówek.
   - Wycinek wynika z numeru poziomu, a nie z gałęzi.
   - Cięcie `puzzle.webp` przez `ClipPath` wg geometrii z promptów (R 1000, środek 240, 2048 px).
   - Niezdobyte pole jest ciemne, zdobyte i niewstawione czeka na przeciągnięcie.
   - Przycisk do planszy na mapie obok sklepu kulek.
5. **Przebieg poziomu.** Po wygranej, gdy kawałek jest nowy: przeciągnięcie kawałka i tekst `tale.level.N`, potem zwykła karta końcowa. Powtórka nie daje kawałka.
6. **Plansze.** Jeden ekran `lib/ui/tale_screen.dart`: lista obrazków z tekstem, stuknięcie przechodzi dalej, jest przycisk pominięcia. Obsługuje wprowadzenie, karty rozdziałów i notatki.
7. **Koniec rozdziału.** Po ukończeniu 14 poziomów rozdziału: notatka i `tale.chapter.N.reward`, potem karta następnego rozdziału przy pierwszym wejściu. Nagrody daje już `BallCollection.grantRewards`.
8. **Finał.** Stuknięcie w lustro po ukończeniu rozdziału 5: `final_1` do `final_5`, wybór, zakończenie, napisy. Ekran `ending_b_2` stoi 8 sekund bez tekstu, muzyki i reakcji na dotyk. Lustro zostaje dostępne, ostatni wybór decyduje o środku puzzli.
9. **Nastrój.** Muzyka i paleta według rozdziału, na końcu i niezależnie od reszty.
10. **Testy.** Pola puzzli (70 różnych, wszystkie na planszy), kawałek tylko raz, stare zapisy, finał i oba zakończenia, wszystkie pliki z promptów zadeklarowane jako zasoby.

## Zasady projektu

- Bez commitów, dopóki użytkownik o nie nie poprosi.
- Nie formatować `lib/` przez `dart format`.
- Nowe teksty zawsze w PL, EN i RU, czas teraźniejszy, bez rodzaju kulki.
