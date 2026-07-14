import 'package:flutter/material.dart';

import '../models/country.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';

/// Hero country display: glowing gradient-bordered flag + Arabic/English name.
///
/// Pure presentational — takes the [Country] as a plain value (no provider
/// lookup), so it only rebuilds when the parent hands it a new country.
class CountryCard extends StatelessWidget {
  final Country country;

  const CountryCard({super.key, required this.country});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Heroic flag: gradient border + colored outer glow.
        GradientBorderCard(
          gradient: AppGradients.turn,
          radius: AppRadii.card,
          borderWidth: 2,
          padding: const EdgeInsets.all(10),
          shadows: AppShadows.glow(
            AppColors.electricBlue,
            alpha: .28,
            blur: 40,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card - 12),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: country.flagPng != null
                  ? Image.network(
                      country.flagPng!,
                      fit: BoxFit.cover,
                      width: 300,
                      loadingBuilder: (c, child, progress) => progress == null
                          ? child
                          : Container(
                              color: AppColors.surfaceActive,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surfaceActive,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.flag_outlined,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : Container(color: AppColors.surfaceActive),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          country.nameAr,
          textAlign: TextAlign.center,
          style: AppText.ui(size: 34, weight: FontWeight.w800, height: 1.1),
        ),
        const SizedBox(height: 2),
        Text(
          country.nameEn.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppText.number(
            size: 14,
            weight: FontWeight.w600,
            color: AppColors.textSecondary,
            spacing: 3,
          ),
        ),
      ],
    );
  }
}
