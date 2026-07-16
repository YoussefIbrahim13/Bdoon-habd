import 'package:flutter_test/flutter_test.dart';

import 'package:el_hakem/models/country.dart';
import 'package:el_hakem/state/game_state.dart';

Country _c(String code) =>
    Country(code: code, nameEn: code, nameAr: code);

void main() {
  test('tier classification: famous=easy, moderate=medium, obscure=hard', () {
    for (final code in ['EG', 'SA', 'BR', 'FR', 'JP', 'US']) {
      expect(CountryDifficulty.of(code), CountryDifficulty.easy, reason: code);
    }
    for (final code in ['PE', 'SN', 'PL', 'VN', 'TH']) {
      expect(CountryDifficulty.of(code), CountryDifficulty.medium,
          reason: code);
    }
    for (final code in ['SR', 'KG', 'LS', 'VU', 'CV']) {
      expect(CountryDifficulty.of(code), CountryDifficulty.hard, reason: code);
    }
    // Unknown/future codes default to hard.
    expect(CountryDifficulty.of('zz'), CountryDifficulty.hard);
  });

  test('startGame filters the deck to the chosen difficulty', () {
    // 8 easy (meets minDeckSize) + obscure noise that must be excluded.
    final easyCodes = ['EG', 'SA', 'FR', 'JP', 'US', 'BR', 'DE', 'IT'];
    final countries = [
      for (final c in easyCodes) _c(c),
      _c('SR'), _c('VU'), _c('LS'),
    ];
    final g = GameState()
      ..startGame(
        names: ['A', 'B'],
        target: 3,
        countries: countries,
        difficulty: CountryDifficulty.easy,
      );
    addTearDown(g.dispose);

    // Walk the whole deck: every drawn country must be from the easy tier.
    for (var i = 0; i < countries.length * 2; i++) {
      expect(easyCodes, contains(g.currentCountry!.code));
      g.skipCountry();
    }
    expect(g.difficulty, CountryDifficulty.easy);
    g.backToSetup();
  });

  test('too-thin filtered deck falls back to the full list', () {
    // Only 2 hard countries — below minDeckSize, so everyone plays.
    final countries = [
      _c('SR'), _c('VU'),
      for (final c in ['EG', 'SA', 'FR', 'JP', 'US', 'BR']) _c(c),
    ];
    final g = GameState()
      ..startGame(
        names: ['A', 'B'],
        target: 3,
        countries: countries,
        difficulty: CountryDifficulty.hard,
      );
    addTearDown(g.dispose);

    // Deck must contain more than just the 2 hard countries: skim it and
    // record what comes up.
    final seen = <String>{};
    for (var i = 0; i < countries.length; i++) {
      seen.add(g.currentCountry!.code);
      g.skipCountry();
    }
    expect(seen.length, countries.length); // full pool in play
    g.backToSetup();
  });

  test('no difficulty (tests/legacy callers) leaves the deck unfiltered', () {
    final countries = [_c('C0'), _c('C1'), _c('C2')];
    final g = GameState()
      ..startGame(names: ['A', 'B'], target: 3, countries: countries);
    addTearDown(g.dispose);

    expect(g.difficulty, isNull);
    expect(g.currentCountry, isNotNull);
    g.backToSetup();
  });
}
