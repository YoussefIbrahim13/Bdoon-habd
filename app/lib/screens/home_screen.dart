import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/country.dart';
import '../services/api_service.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _fieldLabels = [
    'اللاعب الأول',
    'اللاعب الثاني',
    'اللاعب الثالث',
    'اللاعب الرابع',
  ];
  static const _defaultNames = ['لاعب ١', 'لاعب ٢', 'لاعب ٣', 'لاعب ٤'];

  /// One controller per possible seat, created eagerly so a player's typed
  /// name survives toggling the count down and back up.
  final List<TextEditingController> _nameControllers = [
    for (final name in _defaultNames) TextEditingController(text: name),
  ];

  int _playerCount = GameState.defaultPlayers;
  int _targetScore = 5;

  List<Country>? _countries;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final countries = await context.read<ApiService>().fetchCountries();
      if (mounted) {
        setState(() {
          _countries = countries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'تعذّر الاتصال بالسيرفر:\n$e';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _start() {
    // Only the visible seats play; blank fields fall back to default names.
    final names = [
      for (var i = 0; i < _playerCount; i++)
        _nameControllers[i].text.trim().isEmpty
            ? _defaultNames[i]
            : _nameControllers[i].text.trim(),
    ];
    context.read<GameState>().startGame(
          names: names,
          target: _targetScore,
          countries: _countries!,
        );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Center(
              // Scrollable so 4 fields + keyboard can never overflow: the
              // scaffold shrinks the viewport above the keyboard and this
              // view scrolls within whatever height remains.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            gradient: AppGradients.turn,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: AppShadows.glow(AppColors.neonPurple,
                                alpha: .5, blur: 34),
                          ),
                          // Brand emblem without its own badge — it sits on
                          // this gradient capsule instead.
                          child: const Center(
                            child: AppLogo(size: 68, showBadge: false),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ShaderMask(
                        shaderCallback: (r) => AppGradients.turn.createShader(r),
                        child: Text(
                          'بدون هبد!',
                          textAlign: TextAlign.center,
                          style: AppText.ui(
                              size: 40, weight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      Text(
                        'لعبة معلومات البلاد — من ٢ إلى ٤ لاعبين وحكم واحد',
                        textAlign: TextAlign.center,
                        style: AppText.ui(size: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 32),
                      GlassContainer(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            _PlayerCountPicker(
                              value: _playerCount,
                              onChanged: (v) => setState(() => _playerCount = v),
                            ),
                            const SizedBox(height: 18),
                            // AnimatedSize glides the card open/closed as
                            // fields appear or disappear with the count.
                            AnimatedSize(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: Column(
                                children: [
                                  for (var i = 0; i < _playerCount; i++) ...[
                                    _LabeledField(
                                      label: _fieldLabels[i],
                                      controller: _nameControllers[i],
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            _TargetPicker(
                              value: _targetScore,
                              onChanged: (v) => setState(() => _targetScore = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppText.ui(size: 13, color: AppColors.ruby),
                        ),
                        const SizedBox(height: 12),
                        GameButton(
                          label: 'إعادة المحاولة',
                          icon: Icons.refresh_rounded,
                          onPressed: _loadCountries,
                        ),
                      ] else
                        GameButton(
                          label: 'ابدأ اللعب',
                          icon: Icons.sports_esports_rounded,
                          height: 62,
                          gradient: AppGradients.turn,
                          glowColor: AppColors.neonPurple,
                          textStyle: AppText.ui(size: 18, weight: FontWeight.w800),
                          onPressed: _start,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "عدد اللاعبين" pill row (٢ / ٣ / ٤) in the same segment style as the
/// target-score picker, so the setup card reads as one system.
class _PlayerCountPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PlayerCountPicker({required this.value, required this.onChanged});

  static const _arabicDigits = {2: '٢', 3: '٣', 4: '٤'};

  @override
  Widget build(BuildContext context) {
    // Fluid pills (like _TargetPicker) so the row can never overflow on
    // narrow phones regardless of the label's rendered width.
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text('عدد اللاعبين',
              style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              for (var count = GameState.minPlayers;
                  count <= GameState.maxPlayers;
                  count++) ...[
                if (count > GameState.minPlayers) const SizedBox(width: 6),
                Expanded(
                  child: _Segment(
                    label: _arabicDigits[count] ?? '$count',
                    width: null, // fluid: fill the Expanded slot
                    selected: count == value,
                    onTap: () => onChanged(count),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _LabeledField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 6),
          child: Text(label,
              style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
        ),
        TextField(
          controller: controller,
          style: AppText.ui(size: 15, weight: FontWeight.w700),
          decoration: const InputDecoration(),
        ),
      ],
    );
  }
}

class _TargetPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _TargetPicker({required this.value, required this.onChanged});

  static const _options = [1, 3, 5, 7, 10];

  @override
  Widget build(BuildContext context) {
    // Five options: fixed 44px pills would overflow narrow phones once the
    // label is added, so the segments share the remaining width fluidly.
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text('الفوز عند',
              style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < _options.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _Segment(
                    label: '${_options[i]}',
                    width: null, // fluid: fill the Expanded slot
                    selected: _options[i] == value,
                    onTap: () => onChanged(_options[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Fixed pill width; pass null to fill the parent (fluid layouts).
  final double? width;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.width = 44,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: width,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? AppGradients.turn : null,
          color: selected ? null : AppColors.glassFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.stroke,
          ),
          boxShadow:
              selected ? AppShadows.glow(AppColors.electricBlue, alpha: .35, blur: 16) : null,
        ),
        child: Text(
          label,
          style: AppText.number(
            size: 18,
            weight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
