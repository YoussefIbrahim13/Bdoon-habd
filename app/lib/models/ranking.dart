/// Pure end-of-match standings helpers, shared by the offline and online
/// podiums so both modes rank and tie-break identically.
library;

/// One row of a final podium, already placed.
class Standing {
  /// 0-based place. Equal scores share a place (see [standingsFrom]).
  final int rank;

  /// Index into the caller's own player list — offline uses the seat index,
  /// online uses the position in `room.players`.
  final int index;

  final String name;
  final int score;

  const Standing({
    required this.rank,
    required this.index,
    required this.name,
    required this.score,
  });

  bool get isChampion => rank == 0;

  /// Place as shown on the podium: 1-based, so [rank] 0 reads "1".
  int get place => rank + 1;
}

/// Ranks [names]/[scores] high→low into podium order.
///
/// Uses standard competition ranking ("1224"): entries on equal points share
/// a place, and the next distinct score skips the places they consumed — so
/// two players tied at the top are both 🥇 and the next player is 🥉, never a
/// silver that nobody outscored.
///
/// Ties are ordered by seat index so the list is stable across rebuilds
/// (a score counting up mustn't reshuffle rows under the user).
List<Standing> standingsFrom(List<String> names, List<int> scores) {
  final n = names.length < scores.length ? names.length : scores.length;
  final rows = [
    for (var i = 0; i < n; i++) (index: i, name: names[i], score: scores[i]),
  ]..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });

  final out = <Standing>[];
  for (var i = 0; i < rows.length; i++) {
    // Share the previous place on equal points, else take this position.
    final rank =
        i > 0 && rows[i].score == rows[i - 1].score ? out[i - 1].rank : i;
    out.add(Standing(
      rank: rank,
      index: rows[i].index,
      name: rows[i].name,
      score: rows[i].score,
    ));
  }
  return out;
}

/// True when more than one player shares the top score, i.e. nobody won
/// outright. Drives the 🤝 face and suppresses the "winner" headline.
bool isDraw(List<Standing> standings) =>
    standings.length > 1 && standings[1].rank == 0;

/// How the match ended, from the perspective of one viewer.
enum MatchResult {
  /// Won outright.
  champion,

  /// Tied for first.
  draw,

  /// Second place.
  runnerUp,

  /// Third place.
  third,

  /// Finished off the podium.
  alsoRan,

  /// Ended without a real result (players left, room abandoned).
  abandoned,
}

/// Classifies [rank] within [standings]. Pass a null [rank] for a spectator
/// or shared-device view that has no "me" to speak of.
MatchResult resultFor(List<Standing> standings, int? rank) {
  if (standings.isEmpty) return MatchResult.abandoned;
  if (isDraw(standings)) return MatchResult.draw;
  return switch (rank) {
    0 => MatchResult.champion,
    1 => MatchResult.runnerUp,
    2 => MatchResult.third,
    null => MatchResult.champion, // shared screen celebrates the winner
    _ => MatchResult.alsoRan,
  };
}

/// The symbol shown at the top of the end-of-match screen. The winner gets
/// the trophy; nothing here uses medals, which the podium deliberately spells
/// out as plain place numbers instead.
String faceFor(MatchResult r) => switch (r) {
      MatchResult.champion => '🏆',
      MatchResult.draw => '🤝',
      MatchResult.runnerUp => '👏',
      MatchResult.third => '🙂',
      MatchResult.alsoRan => '😔',
      MatchResult.abandoned => '🤷',
    };

/// Arabic caption under the winner's name, matched to [faceFor].
String captionFor(MatchResult r) => switch (r) {
      MatchResult.champion => 'الفائز باللعبة',
      MatchResult.draw => 'تعادل — محدش كسب!',
      MatchResult.runnerUp => 'المركز التاني — قربت!',
      MatchResult.third => 'المركز التالت',
      MatchResult.alsoRan => 'حظ أحسن المرة الجاية',
      MatchResult.abandoned => 'اللعبة خلصت من غير نتيجة',
    };
