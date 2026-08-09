import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/country.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'game_button.dart';
import 'nova_components.dart';

/// "Ask the Smart Judge" panel: the human judge types the disputed claim,
/// the backend checks it, and the verdict is shown as ADVISORY input only.
///
/// Presented as a glassmorphic bottom sheet with a spring entrance: the modal
/// controller slides it up while a bottom-anchored scale-overshoot (the
/// [_spring] curve below) adds the bounce.
class SmartJudgeSheet extends StatefulWidget {
  final Country country;
  const SmartJudgeSheet({super.key, required this.country});

  @override
  State<SmartJudgeSheet> createState() => _SmartJudgeSheetState();
}

class _SmartJudgeSheetState extends State<SmartJudgeSheet> {
  final _claimController = TextEditingController();
  bool _loading = false;
  Verdict? _verdict;
  String? _error;

  @override
  void dispose() {
    _claimController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final claim = _claimController.text.trim();
    if (claim.length < 2 || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _verdict = null;
      _error = null;
    });
    try {
      final verdict = await context.read<ApiService>().verifyFact(
        countryCode: widget.country.code,
        claim: claim,
      );
      if (mounted) setState(() => _verdict = verdict);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The modal controller already slides the sheet up from the bottom; we
    // layer a bottom-anchored scale-overshoot + fade on top for the "bounce"
    // (a second translate would fight the built-in slide).
    final anim = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final spring = CurvedAnimation(
      parent: anim,
      curve: _spring,
      reverseCurve: Curves.easeIn,
    );

    return Column(
      // Full-height sheet so the transparent area above the glass card is an
      // explicit tap-to-dismiss target — dismissal never depends on the modal
      // barrier (which the custom transition controller can leave unresponsive).
      // The route's dim scrim still shows through the transparent area.
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(spring),
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.sheet),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: .82),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadii.sheet),
                      ),
                      border: const Border(
                        top: BorderSide(color: AppColors.stroke),
                        left: BorderSide(color: AppColors.stroke),
                        right: BorderSide(color: AppColors.stroke),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: AppColors.stroke,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Header(country: widget.country),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _claimController,
                            maxLines: 2,
                            minLines: 1,
                            style: AppText.ui(
                              size: 15,
                              weight: FontWeight.w600,
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText:
                                  'مثال: عاصمة ${widget.country.nameAr} هي ...',
                            ),
                          ),
                          const SizedBox(height: 14),
                          GameButton(
                            label: _loading
                                ? 'جاري التحقق...'
                                : 'تحقّق من المعلومة',
                            icon: _loading ? null : Icons.gavel_rounded,
                            leading: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                            gradient: AppGradients.turn,
                            glowColor: AppColors.neonPurple,
                            onPressed: _loading ? null : _submit,
                          ),
                          // Animated reveal for the result / error card.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: _buildResult(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _ResultCard(
          gradient: AppGradients.falsehood,
          icon: Icons.wifi_off_rounded,
          title: 'تعذّر التحقق',
          body: _error!,
        ),
      );
    }
    if (_verdict != null) {
      final v = _verdict!;
      final (gradient, icon, title) = switch (v.verdict) {
        'true' => (AppGradients.truth, Icons.verified_rounded, 'صح ✓'),
        'false' => (AppGradients.falsehood, Icons.gpp_bad_rounded, 'غلط ✗'),
        _ => (AppGradients.uncertain, Icons.help_rounded, 'غير مؤكد'),
      };
      final source = v.sourceType == 'objective_data'
          ? 'المصدر: بيانات رسمية عن الدولة'
          : 'المصدر: بحث على الإنترنت';
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _ResultCard(
          gradient: gradient,
          icon: icon,
          title: title,
          body: v.explanation,
          footer: '$source • رأي استشاري — الحكم البشري يقرّر',
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Header extends StatelessWidget {
  final Country country;
  const _Header({required this.country});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: AppGradients.turn,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppShadows.glow(
              AppColors.neonPurple,
              alpha: .4,
              blur: 18,
            ),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الحكم الذكي',
                style: AppText.ui(size: 18, weight: FontWeight.w800),
              ),
              Text(
                'اكتب المعلومة والذكاء الاصطناعي يتحقق — القرار النهائي لك',
                style: AppText.ui(
                  size: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Gradient gradient;
  final IconData icon;
  final String title;
  final String body;
  final String? footer;

  const _ResultCard({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final accent = (gradient as LinearGradient).colors.first;
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.glow(accent, alpha: .3, blur: 26),
      ),
      padding: const EdgeInsets.all(1.6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card - 1.6),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                GradientText(
                  title,
                  // Verdict gradient (truth / falsehood / uncertain) — the
                  // semantic gameplay colors, not the brand violet.
                  gradient: gradient,
                  style: AppText.ui(size: 22, weight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: AppText.ui(
                size: 14.5,
                height: 1.5,
                weight: FontWeight.w500,
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.stroke, height: 1),
              const SizedBox(height: 10),
              Text(
                footer!,
                style: AppText.ui(size: 11, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Overshoot curve for the spring/bounce entrance.
const _spring = Cubic(0.34, 1.56, 0.64, 1.0);
