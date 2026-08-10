import 'package:flutter_test/flutter_test.dart';

import 'package:el_hakem/models/ranking.dart';

void main() {
  test('orders players high→low and numbers the places 1..n', () {
    final s = standingsFrom(
      ['أ', 'ب', 'ج', 'د'],
      [2, 5, 0, 3],
    );

    expect([for (final e in s) e.name], ['ب', 'د', 'أ', 'ج']);
    expect([for (final e in s) e.rank], [0, 1, 2, 3]);
    expect([for (final e in s) e.place], [1, 2, 3, 4]);
    // The original seat index survives the sort — screens use it to look up
    // avatars / player ids.
    expect([for (final e in s) e.index], [1, 3, 0, 2]);
    expect(s.first.isChampion, isTrue);
  });

  test('equal scores share a place and consume the ones below (1224)', () {
    final s = standingsFrom(
      ['أ', 'ب', 'ج', 'د'],
      [4, 4, 2, 1],
    );

    expect([for (final e in s) e.rank], [0, 0, 2, 3]);
    // Both leaders show "1"; nobody takes an unearned 2nd.
    expect([for (final e in s) e.place], [1, 1, 3, 4]);
    expect(isDraw(s), isTrue);
  });

  test('a tie below first still leaves a single champion', () {
    final s = standingsFrom(['أ', 'ب', 'ج'], [7, 3, 3]);

    expect([for (final e in s) e.rank], [0, 1, 1]);
    expect(isDraw(s), isFalse);
    expect(resultFor(s, 0), MatchResult.champion);
  });

  test('ties keep seat order so counting-up scores do not reshuffle rows', () {
    final s = standingsFrom(['أ', 'ب', 'ج'], [1, 1, 1]);
    expect([for (final e in s) e.index], [0, 1, 2]);
  });

  test('result is read from the viewer\'s own place', () {
    final s = standingsFrom(['أ', 'ب', 'ج', 'د'], [9, 6, 3, 1]);

    expect(resultFor(s, 0), MatchResult.champion);
    expect(resultFor(s, 1), MatchResult.runnerUp);
    expect(resultFor(s, 2), MatchResult.third);
    expect(resultFor(s, 3), MatchResult.alsoRan);
    // Shared-device (offline) view has no "me" and celebrates the winner.
    expect(resultFor(s, null), MatchResult.champion);
  });

  test('a draw overrides the viewer place for everyone', () {
    final s = standingsFrom(['أ', 'ب'], [4, 4]);
    expect(resultFor(s, 0), MatchResult.draw);
    expect(resultFor(s, 1), MatchResult.draw);
    expect(faceFor(resultFor(s, 1)), '🤝');
  });

  test('the winner gets the trophy and no face is a medal', () {
    expect(faceFor(MatchResult.champion), '🏆');
    for (final r in MatchResult.values) {
      expect(['🥇', '🥈', '🥉'], isNot(contains(faceFor(r))), reason: '$r');
    }
  });

  test('empty standings read as abandoned', () {
    expect(resultFor(const [], null), MatchResult.abandoned);
    expect(faceFor(MatchResult.abandoned), '🤷');
  });

  test('every result has its own face and caption', () {
    final faces = {for (final r in MatchResult.values) faceFor(r)};
    expect(faces.length, MatchResult.values.length);
    for (final r in MatchResult.values) {
      expect(captionFor(r), isNotEmpty, reason: '$r');
    }
  });

  test('mismatched name/score lengths are truncated, not thrown', () {
    expect(standingsFrom(['أ', 'ب'], [1]).length, 1);
    expect(standingsFrom(['أ'], [1, 2]).length, 1);
  });
}
