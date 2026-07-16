/// How recognizable a country/flag is — the more famous, the easier.
/// Tiers are keyed by ISO-3166 alpha-2 code in [CountryDifficulty.of]:
/// anything not explicitly listed as easy or medium is hard, so newly added
/// obscure countries land in the right bucket by default.
enum CountryDifficulty {
  easy,
  medium,
  hard;

  /// Highly famous, globally (and regionally — Arabic-first audience, so all
  /// Arab countries count) recognized.
  static const Set<String> _easy = {
    // Arab world
    'EG', 'SA', 'AE', 'QA', 'KW', 'BH', 'OM', 'YE', 'JO', 'LB', 'SY', 'IQ',
    'PS', 'LY', 'SD', 'TN', 'DZ', 'MA', 'MR', 'SO', 
    // Global heavyweights
    'US', 'GB', 'FR', 'DE', 'IT', 'ES', 'PT', 'NL', 'BE', 'CH', 'SE', 'NO',
    'DK', 'GR', 'RU', 'UA', 'TR', 'IR', 'CN', 'JP', 'KR', 'IN', 'PK', 'ID',
    'BR', 'AR', 'MX', 'CA', 'AU', 'ZA', 'NG', 'ET',
  };

  /// Moderately recognizable.
  static const Set<String> _medium = {
    // Europe
    'IE', 'IS', 'FI', 'PL', 'AT', 'CZ', 'HU', 'RO', 'BG', 'RS', 'HR', 'SK',
    'SI', 'LT', 'LV', 'EE', 'LU', 'MT', 'CY', 'AL', 'MK', 'BA', 'MD', 'BY',
    // Asia & Oceania
    'TH', 'VN', 'PH', 'MY', 'SG', 'NZ', 'AF', 'BD', 'LK', 'NP', 'MM', 'KH',
    'KZ', 'UZ', 'AZ', 'GE', 'AM', 'MN', 'KP', 'IL',
    // Americas
    'CL', 'CO', 'PE', 'VE', 'UY', 'EC', 'CU', 'DO', 'PA', 'CR', 'GT', 'BO',
    'PY', 'JM', 'HT', 'HN', 'NI', 'SV','DJ', 'KM',
    // Africa
    'KE', 'GH', 'SN', 'CM', 'CI', 'TZ', 'UG', 'ZW', 'AO', 'MZ', 'ML', 'NE',
    'TD', 'RW', 'ZM', 'BW', 'GA',
  };

  static CountryDifficulty of(String code) {
    final c = code.toUpperCase();
    if (_easy.contains(c)) return easy;
    if (_medium.contains(c)) return medium;
    return hard;
  }
}

class Country {
  final String code;
  final String nameEn;
  final String nameAr;
  final String? flagPng;
  final String? flagSvg;

  /// Derived from [code] — see [CountryDifficulty.of].
  final CountryDifficulty difficulty;

  Country({
    required this.code,
    required this.nameEn,
    required this.nameAr,
    this.flagPng,
    this.flagSvg,
    CountryDifficulty? difficulty,
  }) : difficulty = difficulty ?? CountryDifficulty.of(code);

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
