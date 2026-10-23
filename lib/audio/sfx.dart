import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sound_setting.dart';

/// Every sound of the game. Impacts come in one flavour per ball material.
enum Sound {
  impactWood,
  impactSteel,
  impactRubber,
  impactGlass,
  impactStone,
  impactSlime,
  wolfWake,
  droneWake,
  ghostWake,
}

/// Small synthesised sound effects, so the game needs no audio files.
class Sfx {
  /// Off until the app turns it on (unit tests have no audio plugin).
  static bool enabled = false;

  /// Tests collect (sound, volume) here instead of playing anything.
  @visibleForTesting
  static List<(Sound, double)>? record;

  static const int _rate = 22050;
  static final Map<Sound, Uint8List> _cache = {};
  static final List<AudioPlayer> _players = [];
  static int _next = 0;

  /// Whether sounds would actually be played right now (the app switched
  /// audio on and the player has not turned sound off in the settings).
  static bool get audible => enabled && SoundSetting.instance.on;

  /// The last playback error, if any (for example a missing audio plugin
  /// after a hot reload). The settings screen shows it.
  static final ValueNotifier<String?> lastError = ValueNotifier(null);

  static void _fail(Object error) {
    debugPrint('Sfx: could not play a sound: $error');
    lastError.value = '$error';
  }

  /// Plays [sound] at [volume] (0..1).
  static void play(Sound sound, {double volume = 1}) {
    final v = volume.clamp(0.0, 1.0);
    record?.add((sound, v));
    if (!audible || v <= 0.01) return;
    try {
      if (_players.isEmpty) {
        for (var i = 0; i < 6; i++) {
          _players.add(AudioPlayer()..setReleaseMode(ReleaseMode.stop));
        }
      }
      final bytes = _cache.putIfAbsent(sound, () => _wav(_synth(sound)));
      final p = _players[_next++ % _players.length];
      p.play(BytesSource(bytes, mimeType: 'audio/wav'), volume: v).then(
        (_) {
          if (lastError.value != null) lastError.value = null;
        },
        onError: _fail,
      );
    } catch (e) {
      _fail(e);
    }
  }

  /// The generated WAV file of a sound (tests inspect it).
  @visibleForTesting
  static Uint8List wavFor(Sound sound) => _wav(_synth(sound));

  // ---- synthesis ----------------------------------------------------------

  static List<int> _synth(Sound s) {
    final rnd = Random(s.index + 1);
    double noise() => rnd.nextDouble() * 2 - 1;
    // [fn] gets the time in seconds and returns a sample in -1..1.
    List<int> render(double seconds, double Function(double t) fn) {
      final n = (_rate * seconds).round();
      return [
        for (var i = 0; i < n; i++)
          (fn(i / _rate).clamp(-1.0, 1.0) * 0.8 * 32767).round(),
      ];
    }

    double sine(double f, double t) => sin(2 * pi * f * t);
    double env(double t, double decay) => exp(-t * decay);

    switch (s) {
      case Sound.impactWood:
        // A dull knock: a short low tone with a little noise at the start.
        return render(0.16, (t) {
          final f = 190 - 70 * (t / 0.16);
          return (sine(f, t) * 0.8 + noise() * 0.35 * env(t, 80)) * env(t, 26);
        });
      case Sound.impactSteel:
        // A ringing clang: inharmonic overtones that die away slowly.
        return render(0.5, (t) {
          final ring = sine(1180, t) * 0.6 + sine(1760, t) * 0.4 + sine(2650, t) * 0.25;
          return (ring * env(t, 7) + noise() * 0.5 * env(t, 160)) * 0.9;
        });
      case Sound.impactRubber:
        // A soft boing: a low tone whose pitch drops fast, no sharp edge.
        return render(0.18, (t) {
          final f = 150 - 60 * (t / 0.18);
          return sine(f, t) * (1 - exp(-t * 400)) * env(t, 20);
        });
      case Sound.impactGlass:
        // A bright tink with a high shimmer.
        return render(0.42, (t) {
          final ping = sine(2400, t) * 0.7 + sine(3620, t) * 0.4 + sine(5100, t) * 0.15;
          return (ping * env(t, 10) + noise() * 0.25 * env(t, 220)) * 0.85;
        });
      case Sound.impactStone:
        // A heavy thud: low-passed noise plus a deep tone.
        var low = 0.0;
        return render(0.18, (t) {
          low += (noise() - low) * 0.12;
          return (low * 2.2 * env(t, 24) + sine(95, t) * 0.7 * env(t, 22));
        });
      case Sound.impactSlime:
        // A wet squelch: a low blob whose pitch dips, with a soft smack.
        var wet = 0.0;
        return render(0.22, (t) {
          wet += (noise() - wet) * 0.25;
          final f = 130 - 55 * (t / 0.22) + sin(2 * pi * 30 * t) * 12;
          return (sine(f, t) * 0.8 + wet * 0.9 * env(t, 45)) *
              (1 - exp(-t * 500)) *
              env(t, 18);
        });
      case Sound.wolfWake:
        // A low growl: a rising throaty tone with a fast tremble and rasp.
        return render(1.0, (t) {
          final f = 92 + 40 * (t / 1.0) + sin(2 * pi * 7 * t) * 4;
          final tone = sine(f, t) + 0.55 * sine(2 * f, t) + 0.3 * sine(3 * f, t);
          final tremble = 0.65 + 0.35 * sin(2 * pi * 24 * t);
          final shape = (1 - exp(-t * 14)) * exp(-pow(max(0, t - 0.55), 2) * 14);
          return (tone * 0.45 + noise() * 0.18) * tremble * shape;
        });
      case Sound.ghostWake:
        // A thin wail that rises and falls, with a ripple of breath.
        return render(1.1, (t) {
          final f = 340 + 220 * sin(pi * t / 1.1) + sin(2 * pi * 6 * t) * 14;
          final tone = sine(f, t) + 0.35 * sine(2 * f, t);
          final shape = sin(pi * (t / 1.1).clamp(0.0, 1.0));
          return (tone * 0.5 + noise() * 0.07) * shape * 0.8;
        });
      case Sound.droneWake:
        // Rotors spinning up, then two beeps.
        return render(0.95, (t) {
          if (t < 0.6) {
            final f = 170 + 700 * pow(t / 0.6, 1.6);
            final saw = 2 * ((f * t) % 1.0) - 1;
            return (saw * 0.35 + sine(f * 2, t) * 0.15 + noise() * 0.06) * (t / 0.6);
          }
          final u = t - 0.6;
          final beep = (u % 0.17) < 0.07 && u < 0.34;
          return beep ? sine(1250, t) * 0.55 : 0.0;
        });
    }
  }

  static Uint8List _wav(List<int> samples) {
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
