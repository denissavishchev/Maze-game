# Obrazki do scenariusza — prompty

Jest 27 obrazków. Każdy ma swoją nazwę pliku, a kod będzie szukał dokładnie tych nazw.

**Gdzie zapisać:** `assets/images/story/`, format `.webp`.

**Rozmiary:**
- Plansze pełnoekranowe: pion 1080 × 1920.
- Puzzle: kwadrat 2048 × 2048.
- Środki puzzli: kwadrat 1024 × 1024.

**Jak używać:**
1. Dołącz `assets/images/main_bg.webp` jako obraz referencyjny stylu.
2. Na początek każdego promptu wklej blok „Styl wspólny”.
3. Dodaj prompt konkretnego obrazka.
4. Pierwszy gotowy obrazek z kulką dołączaj jako referencję do kolejnych, żeby kulka wyglądała tak samo.

Obrazki nie mogą zawierać tekstu, bo napisy nakłada gra w trzech językach.

## Styl wspólny

```text
Bright hand-drawn cartoon mobile game art, same style as the reference image: bold dark outlines, saturated friendly colours, soft cel shading, cosy storybook mood, suitable for children and adults. Main character: a small round wooden ball with visible wood grain and a simple friendly look, no face, no arms, no legs. Keep the lower third of the image calm and simple, because text will be placed there. Absolutely no text, letters, numbers, logos or watermarks.
```

## Wprowadzenie

| Plik | Tekst |
| --- | --- |
| `intro_1.webp` | `intro.1` |
| `intro_2.webp` | `intro.2` |
| `intro_3.webp` | `intro.3` |
| `intro_4.webp` | `intro.4` |

**intro_1**
```text
Almost completely black scene. In the very centre, a small wooden ball is softly lit by a faint warm glow, as if just waking up. Quiet, mysterious, gentle, not scary.
```

**intro_2**
```text
The small wooden ball seen from behind, tiny, in front of an enormous closed ancient round gate made of stone and wood. Behind the top of the gate the walls of a vast circular labyrinth are visible. Dawn light, sense of scale and wonder.
```

**intro_3**
```text
Close-up on the ground of a stone path. The small wooden ball has stopped next to a small curved glowing puzzle piece lying on the ground, warm golden light shining from the piece onto the ball. Curious, hopeful mood.
```

**intro_4**
```text
Top view of an empty round puzzle board carved from stone, divided into concentric rings and wedge segments, all segments dark and empty, with a dark round hole in the centre. The small wooden ball rests at the outer edge of the board. Mysterious and inviting.
```

## Karty rozdziałów

| Plik | Tekst |
| --- | --- |
| `chapter_1.webp` | `chapter.1.card` |
| `chapter_2.webp` | `chapter.2.card` |
| `chapter_3.webp` | `chapter.3.card` |
| `chapter_4.webp` | `chapter.4.card` |
| `chapter_5.webp` | `chapter.5.card` |

**chapter_1 (Wiosna)**
```text
Spring. The small wooden ball among fresh green buds and pink blossoms on a winding path, bright light green and pink palette, morning light, everything new and young.
```

**chapter_2 (Lato)**
```text
Summer. The small wooden ball on a wide sunny road through golden fields under a deep blue sky, warm gold and blue palette, energetic and open, the road stretching far ahead.
```

**chapter_3 (Jesień)**
```text
Autumn. The small wooden ball on a forest path among falling leaves, rust, brown and amber palette, low warm evening sun, calm and slightly thoughtful.
```

**chapter_4 (Zima)**
```text
Winter. The small wooden ball alone on a wide white snowy plain, a single line of tracks behind it, pale blue, white and grey palette, soft falling snow, quiet and lonely but beautiful.
```

**chapter_5 (Cisza)**
```text
A magical fifth season. The small wooden ball in soft golden mist, surrounded at the same time by spring buds, summer leaves, autumn leaves and snowflakes floating in the air, off-white and gold palette, deep calm.
```

## Notatki

| Plik | Tekst |
| --- | --- |
| `note_1.webp` | `chapter.1.note` |
| `note_2.webp` | `chapter.2.note` |
| `note_3.webp` | `chapter.3.note` |
| `note_4.webp` | `chapter.4.note` |
| `note_5.webp` | `chapter.5.note` |

**note_1**
```text
An old sheet of paper lying on the ground in front of a big gate with a round handle. On the handle there is a worn round mark, as if a ball had pressed against it many times. The paper is blank. Spring light.
```

**note_2**
```text
An old blank sheet of paper resting against a mossy stone at the edge of a sunny meadow. In the distance a few friendly creatures, a wolf, a frog and a small ghost, look towards the viewer as if waiting for someone. Summer light.
```

**note_3**
```text
An old blank sheet of paper pinned to a huge closed gate with heavy bars across it. Autumn leaves are piled at its foot. A small gentle glow shines through a crack in the gate.
```

**note_4**
```text
An old blank sheet of paper stuck to a snow-covered gate. Beside it on the gate, a clear round print exactly the size of the small wooden ball, which stands in front of it. Pale winter light, moment of recognition.
```

**note_5**
```text
An old sheet of paper floating in golden mist. On it, a simple child-like pencil drawing of a small round ball and nothing else. Soft, still, peaceful.
```

## Puzzle

Dołącz `docs/puzzle-szablon.png` jako układ, a kolory i linie szablonu nie mogą być widoczne w wyniku. Zgodność z układem jest tu ważniejsza od szczegółów, bo gra tnie obraz dokładnie po tych liniach.

Geometria szablonu:
- Wielkość 2048 × 2048, środek w punkcie (1024, 1024).
- Promień zewnętrzny to 1000, a pustego środka 240.
- 5 pierścieni i 14 wycinków. Pierwszy wycinek zaczyna się na godzinie 12, a kolejne idą zgodnie z ruchem wskazówek zegara.

**puzzle.webp**
```text
Top-down painted map of a huge circular labyrinth, following the layout of the attached template exactly: 5 concentric rings and 14 equal wedges, empty dark circle in the centre. No visible template lines, no white gaps; the painting is continuous from wedge to wedge.

Rings show the seasons, from outside to inside: outer ring spring, second ring summer, third ring autumn, fourth ring winter, innermost ring a calm golden season.

Wedges show the worlds, clockwise from 12 o'clock: 1 forest with wolves, 2 mud swamp, 3 candy land, 4 mountains, 5 snow with a yeti, 6 city with drones, 7 ocean with jellyfish, 8 dark underground tunnels, 9 graveyard with small friendly ghosts, 10 glass halls, 11 spaceship with stars, 12 volcano, 13 factory with gears, 14 moving maze walls.

Each cell is that world in that season. Friendly, not scary. Transparent or plain background outside the circle.
```

Dokładne motywy 70 pól są w scenariuszu, w kolumnie „Obrazek na kawałku”. Jeśli generator nie utrzyma układu, napisz mi. Zmienię wtedy podejście na 70 osobnych kwadratowych kafelków, które gra sama wygnie w wycinki.

**puzzle_center_a.webp** (środek po zakończeniu A, 1024 × 1024)
```text
Round image on a transparent background: a tall open gate seen from above with bright spring light pouring through it, a small path leading out to a green meadow. Bright and hopeful.
```

**ending_b_3.webp** (środek po zakończeniu B, 1024 × 1024)
```text
Round image on a transparent background: a small sleeping golden light in the centre, the small wooden ball resting beside it, soft snowflakes around them. Calm and warm.
```

## Finał

| Plik | Tekst |
| --- | --- |
| `final_1.webp` | `final.1` |
| `final_2.webp` | `final.2` |
| `final_3.webp` | `final.3` |
| `final_4.webp` | `final.4` |
| `final_5.webp` | `final.choice.open`, `final.choice.stay` |

**final_1**
```text
The small wooden ball rolling into a quiet round stone chamber at the very centre of the labyrinth. Soft shafts of light from above, dust in the air, complete stillness.
```

**final_2**
```text
Inside the round chamber: a small sleeping golden light floating above the floor, and in front of it a tall old standing mirror with a simple dark frame. The small wooden ball looks up at them from a distance.
```

**final_3**
```text
The small wooden ball in front of the tall mirror. In the mirror its reflection appears as a row of overlapping versions of itself: wood, steel, green slime, glass, paper and a soap bubble, blending into each other.
```

**final_4**
```text
The tall mirror close up. The reflection is one single ball shimmering with all the colours of a chameleon, calm and glowing softly. The small wooden ball in front of the mirror stands still.
```

**final_5**
```text
Wide view of the round chamber. On the left, the tall mirror with the small golden light. On the right, a tall gate standing slightly open with bright daylight behind it. The small wooden ball is exactly in the middle. Keep the lower third empty for two buttons.
```

## Zakończenie A: Otwórz bramy

| Plik | Tekst |
| --- | --- |
| `ending_a_1.webp` | `ending.a.1` |
| `ending_a_2.webp` | `ending.a.2` |
| `ending_a_3.webp` | `ending.a.3` |

**ending_a_1**
```text
The great gates of the labyrinth swinging wide open, warm daylight flooding in along the stone corridors. The small wooden ball is silhouetted in the light.
```

**ending_a_2**
```text
The small wooden ball rolling out onto a wide spring meadow full of flowers, the labyrinth walls behind it, bright sky, feeling of freedom and relief.
```

**ending_a_3**
```text
Early morning at the open gate of the labyrinth, seen from outside. A different, new, very small wooden ball rolls in through the gate, while the first ball watches from the meadow far away. The story begins again.
```

## Zakończenie B: Zostań Strażnikiem

| Plik | Tekst |
| --- | --- |
| `ending_b_1.webp` | `ending.b.1` |
| `ending_b_2.webp` | brak, ekran bez tekstu |

`ending_b_3.webp` jest opisany w części o puzzlach. Na tym ekranie gra pokazuje całą planszę z tym obrazkiem w środku.

**ending_b_1**
```text
The small wooden ball rolling slowly towards the small sleeping golden light in the round chamber, warm glow on the stone floor, tender and quiet.
```

**ending_b_2**
```text
The small wooden ball at complete rest beside the small golden light. Gentle snow falls from an opening above. Nothing else happens. Very calm, very still. This image has no text, so use the whole frame.
```
