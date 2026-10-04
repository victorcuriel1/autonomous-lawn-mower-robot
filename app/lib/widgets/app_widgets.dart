import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
//----------------------------------------------------------------
// - Tarjeta blanca con bordes redondeados, usada en toda la app -
// - Receptora de cualquier widget como hijo                     -
// ---------------------------------------------------------------
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double radius;
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }
}

// Label de sección — el título gris pequeño que aparece antes de cada grupo
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsets? padding;

  const SectionLabel(this.text, {super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.text3,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// Fila dentro de una AppCard — label a la izquierda, valor a la derecha
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool showDivider;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                  color: AppColors.text)),
              Text(value,
                style: TextStyle(fontSize: 14,
                  color: valueColor ?? AppColors.text3)),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: AppColors.gray),
      ],
    );
  }
}