class Country {
  final String code;
  final String nameEn;
  final String nameAr;
  final String? flagPng;
  final String? flagSvg;

  const Country({
    required this.code,
    required this.nameEn,
    required this.nameAr,
    this.flagPng,
    this.flagSvg,
  });

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        code: json['code'] as String,
        nameEn: json['name_en'] as String,
        nameAr: json['name_ar'] as String,
        flagPng: json['flag_png'] as String?,
        flagSvg: json['flag_svg'] as String?,
      );
}

/// Advisory verdict returned by the backend's Smart Judge.
class Verdict {
  /// "true", "false" or "uncertain".
  final String verdict;
  final String explanation;
  final String sourceType;

  const Verdict({
    required this.verdict,
    required this.explanation,
    required this.sourceType,
  });

  factory Verdict.fromJson(Map<String, dynamic> json) => Verdict(
        verdict: json['verdict'] as String,
        explanation: json['explanation'] as String,
        sourceType: json['source_type'] as String,
      );
}
