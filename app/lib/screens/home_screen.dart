import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/country.dart';
import '../services/api_service.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/game_button.dart';
import '../widgets/fx.dart';
import '../widgets/glass_container.dart';
import '../widgets/nova_components.dart';
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

  // Per-player neon identity comes from the shared theme token so the same
  // color follows each player onto the in-game scoreboard.

  /// One controller per possible seat, created eagerly so a player's typed
  /// name survives toggling the count down and back up. Empty by default —
  /// the seat's default name shows as hint text, and _start() falls back to
  /// it if the field is left blank.
  final List<TextEditingController> _nameControllers = [
    for (var i = 0; i < 4; i++) TextEditingController(),
  ];

  int _playerCount = GameState.defaultPlayers;
  int _targetScore = 5;
  CountryDifficulty _difficulty = CountryDifficulty.easy;

  /// Neon vibe per difficulty tier: easy=green, medium=amber, hard=crimson.
  static const _difficultyAccents = [
    AppColors.emerald,
    AppColors.amber,
    AppColors.ruby,
  ];

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
          difficulty: _difficulty,
        );
    Navigator.of(context).push(
      NovaPageRoute(builder: (_) => const GameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Explicit rather than inherited from the theme: during a route
      // transition this screen must be opaque dark violet on frame zero,
      // with nothing showing through from the route underneath.
      backgroundColor: AppColors.bg,
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
                          // this gradient capsule and idles with its own
                          // breathing pulse.
                          child: const Center(
                            child:
                                AppLogo(size: 68, showBadge: false, animate: true),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const DisplayHeadline(
                        'بدون هبد!',
                        size: 44,
                        gradient: true,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'لعبة معلومات البلاد — من ٢ إلى ٤ لاعبين وحكم واحد',
                        textAlign: TextAlign.center,
                        style: AppText.ui(size: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 30),
                      _SetupCard(
                        child: Column(
                          children: [
                            _PickerRow(
                              label: 'عدد اللاعبين',
                              child: _SlidingSegments(
                                labels: const ['2', '3', '4'],
                                selectedIndex:
                                    _playerCount - GameState.minPlayers,
                                onSelected: (i) => setState(() =>
                                    _playerCount = GameState.minPlayers + i),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // fastOutSlowIn: settles without the overshoot
                            // clipping that easeOutBack causes inside a
                            // clipping AnimatedSize.
                            AnimatedSize(
                              duration: const Duration(milliseconds: 340),
                              curve: Curves.fastOutSlowIn,
                              alignment: Alignment.topCenter,
                              // AnimatedSwitcher cross-fades the field block
                              // as seats 3/4 appear/disappear, while the
                              // outer AnimatedSize glides the height.
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOutCubic,
                                child: Column(
                                  key: ValueKey(_playerCount),
                                  children: [
                                    for (var i = 0; i < _playerCount; i++) ...[
                                      _PlayerField(
                                        label: _fieldLabels[i],
                                        hint: _defaultNames[i],
                                        controller: _nameControllers[i],
                                        accent: AppColors.playerAccents[i],
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            // Generous breathing room before the target row.
                            const SizedBox(height: 12),
                            _PickerRow(
                              label: 'الفوز عند',
                              child: _SlidingSegments(
                                labels: const ['1', '3', '5', '7', '10'],
                                selectedIndex:
                                    _targetOptions.indexOf(_targetScore),
                                onSelected: (i) => setState(
                                    () => _targetScore = _targetOptions[i]),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _PickerRow(
                              label: 'درجة الصعوبة',
                              child: _SlidingSegments(
                                labels: const ['سهل', 'متوسط', 'صعب'],
                                arabicLabels: true,
                                accents: _difficultyAccents,
                                selectedIndex: _difficulty.index,
                                onSelected: (i) => setState(() => _difficulty =
                                    CountryDifficulty.values[i]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
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
                        // Prominent fully-rounded CTA with the violet glow.
                        PillButton(
                          label: 'ابدأ اللعبة',
                          icon: Icons.sports_esports_rounded,
                          height: 60,
                          mediumHaptic: true,
                          onPressed: _start,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Glass back button to the mode-selection gateway. Last in the
          // Stack so it paints (and hit-tests) above the scroll layer;
          // directional positioning keeps it in the correct corner under RTL.
          const PositionedDirectional(
            top: 0,
            start: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: GlassBackButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _targetOptions = [1, 3, 5, 7, 10];
}

/// The setup card: a solid dark-violet glass surface wrapped in a fine
/// blue→purple gradient ring, floated on soft black + faint neon shadows so
/// it lifts cleanly off the ambient background.
///
/// This is the largest surface on the screen and it mounts on the same frame
/// as the [NovaPageRoute] transition, so it is deliberately cheap: no
/// backdrop blur, no entrance sheen, and a [RepaintBoundary] so its two soft
/// shadows rasterize once instead of on every frame of the push animation.
class _SetupCard extends StatelessWidget {
  final Widget child;

  const _SetupCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card + 1.4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.electricBlue.withValues(alpha: .45),
              AppColors.stroke,
              AppColors.neonPurple.withValues(alpha: .45),
            ],
          ),
          boxShadow: [
            ...AppShadows.soft,
            BoxShadow(
              color: AppColors.neonPurple.withValues(alpha: .10),
              blurRadius: 44,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.4),
        // GlassCard on its fast path: opaque dark base + a static violet tint
        // gradient. No BackdropFilter — over this near-uniform background the
        // blur was visually a no-op that cost a saveLayer every frame.
        child: GlassCard(
          radius: AppRadii.card,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: child,
        ),
      ),
    );
  }
}

/// Label + fluid control on one line ("عدد اللاعبين", "الفوز عند").
class _PickerRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _PickerRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(label,
              style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }
}

/// Segmented control with a gradient pill that GLIDES behind the selected
/// option (AnimatedPositionedDirectional) instead of each segment swapping
/// its own background. Slots share the track width fluidly, so any count of
/// options fits any screen width without overflowing.
class _SlidingSegments extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Optional per-option accent (same length as [labels]): the glider's fill
  /// and glow take the selected option's color instead of the brand
  /// blue→purple. Used by the difficulty picker (green/amber/crimson).
  final List<Color>? accents;

  /// Arabic labels render in Cairo ([AppText.ui]) — Outfit has no Arabic
  /// glyphs. Digits keep the default Outfit ([AppText.number]).
  final bool arabicLabels;

  const _SlidingSegments({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.accents,
    this.arabicLabels = false,
  });

  static const _gap = 5.0;
  static const _inset = 4.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = labels.length;
          final slotWidth =
              (constraints.maxWidth - _gap * (n - 1)) / n;
          return Stack(
            children: [
              // The glider. Directional start: in this RTL app it measures
              // from the right edge, matching the RTL row order below.
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 300),
                curve: Curves.fastOutSlowIn,
                start: selectedIndex * (slotWidth + _gap),
                top: 0,
                bottom: 0,
                width: slotWidth,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    gradient: accents == null
                        ? AppGradients.turn
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accents![selectedIndex],
                              Color.lerp(accents![selectedIndex],
                                  Colors.black, .30)!,
                            ],
                          ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppShadows.glow(
                        accents?[selectedIndex] ?? AppColors.electricBlue,
                        alpha: .35,
                        blur: 14),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact(); // toggle tick
                          onSelected(i);
                        },
                        child: Center(
                          // Springy pop on the newly-selected label.
                          child: AnimatedScale(
                            scale: i == selectedIndex ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutBack,
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: arabicLabels
                                  ? AppText.ui(
                                      size: 13,
                                      weight: FontWeight.w800,
                                      color: i == selectedIndex
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    )
                                  : AppText.number(
                                      size: 17,
                                      weight: FontWeight.w700,
                                      color: i == selectedIndex
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    ),
                              child: Text(labels[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Player name field with a neon identity: a 4px accent strip on the
/// physical left edge, an accent-tinted border, and a soft animated glow
/// that blooms while the field is focused.
class _PlayerField extends StatefulWidget {
  final String label;

  /// Watermark shown while the field is empty (the seat's default name).
  final String hint;
  final TextEditingController controller;
  final Color accent;

  const _PlayerField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.accent,
  });

  @override
  State<_PlayerField> createState() => _PlayerFieldState();
}

class _PlayerFieldState extends State<_PlayerField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final focused = _focus.hasFocus;
    final radius = BorderRadius.circular(AppRadii.field);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label,
                  style:
                      AppText.ui(size: 12.5, color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              // Tiny identity swatch beside the label.
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: accent),
              ),
            ],
          ),
        ),
        // Outer layer carries the focus glow (shadows can't be clipped).
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: .34),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          // Clip so the accent strip follows the field's rounded silhouette.
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  style: AppText.ui(size: 15, weight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: AppText.ui(
                      size: 15,
                      weight: FontWeight.w600,
                      color: AppColors.textSecondary.withValues(alpha: .45),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide:
                          BorderSide(color: accent.withValues(alpha: .30)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: BorderSide(color: accent, width: 1.6),
                    ),
                  ),
                ),
                // 4px neon identity strip on the physical left edge,
                // brightening with focus.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    color: accent.withValues(alpha: focused ? 1 : .55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
