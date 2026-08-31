import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../common/page_parts.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return PageFrame(
      title: 'PASSAGETR',
      subtitle:
          'Kelime dağarcığını ve okuma pratiğini kendi hızında güçlendir.',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) => Container(
                width: double.infinity,
                padding: EdgeInsets.all(constraints.maxWidth < 620 ? 20 : 28),
                decoration: BoxDecoration(
                    gradient: tokens.accentGradient,
                    borderRadius: BorderRadius.circular(tokens.cardRadius)),
                child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('KELİME + OKUMA + SÖZLÜK',
                          style: TextStyle(
                              color: Colors.white70,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 10),
                      Text('Gerçek içerikle, kendi hızında ilerle.',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 26,
                              height: 1.15)),
                      SizedBox(height: 10),
                      Text('5.314 kelime · 678 okuma · geniş sözlük içeriği',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
                builder: (context, constraints) =>
                    Wrap(spacing: 16, runSpacing: 16, children: <Widget>[
                      SizedBox(
                          width: _moduleWidth(constraints.maxWidth),
                          child: _ModuleCard(
                              icon: Icons.style_rounded,
                              title: 'Kelime',
                              description:
                                  '5.314 gerçek kelime, kartlar ve mini test.',
                              color: tokens.hero,
                              onTap: () => context.go('/words'))),
                      SizedBox(
                          width: _moduleWidth(constraints.maxWidth),
                          child: _ModuleCard(
                              icon: Icons.menu_book_rounded,
                              title: 'Okuma',
                              description:
                                  '678 okuma ve kaynak cümleleriyle pratik.',
                              color: tokens.purple,
                              onTap: () => context.go('/readings'))),
                      SizedBox(
                          width: _moduleWidth(constraints.maxWidth),
                          child: _ModuleCard(
                              icon: Icons.translate_rounded,
                              title: 'Sözlük',
                              description:
                                  'Geniş sözlük, tüm anlamlar ve sesli dinleme.',
                              color: tokens.accentBlue,
                              onTap: () => context.go('/dictionary'))),
                    ])),
          ]),
    );
  }
}

double _moduleWidth(double maxWidth) {
  if (maxWidth >= 980) return (maxWidth - 32) / 3;
  if (maxWidth >= 680) return (maxWidth - 16) / 2;
  return maxWidth;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard(
      {required this.icon,
      required this.title,
      required this.description,
      required this.color,
      required this.onTap});
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: color)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(description,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ])),
            ]),
      );
}
