import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/country.dart';
import '../services/api_service.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/game_button.dart';
import '../widgets/glass_container.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _player1 = TextEditingController(text: 'لاعب ١');
  final _player2 = TextEditingController(text: 'لاعب ٢');
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
    _player1.dispose();
    _player2.dispose();
    super.dispose();
  }

  void _start() {
    final names = [
      _player1.text.trim().isEmpty ? 'لاعب ١' : _player1.text.trim(),
      _player2.text.trim().isEmpty ? 'لاعب ٢' : _player2.text.trim(),
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
                          child: const Center(
                            child: Text('⚖️', style: TextStyle(fontSize: 44)),
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
                        'لعبة معلومات البلاد — لاعبان وحكم واحد',
                        textAlign: TextAlign.center,
                        style: AppText.ui(size: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 32),
                      GlassContainer(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            _LabeledField(label: 'اللاعب الأول', controller: _player1),
                            const SizedBox(height: 14),
                            _LabeledField(label: 'اللاعب الثاني', controller: _player2),
                            const SizedBox(height: 18),
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

  static const _options = [3, 5, 7, 10];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text('الفوز عند',
              style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
        ),
        const Spacer(),
        Row(
          children: [
            for (final opt in _options)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _Segment(
                  label: '$opt',
                  selected: opt == value,
                  onTap: () => onChanged(opt),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: 44,
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
