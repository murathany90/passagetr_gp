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
      title: 'İngilizce yolculuğuna başla',
      subtitle:
          'PASSAGETR ile kelime dağarcığını ve okuma pratiğini güçlendir.',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                  gradient: tokens.accentGradient,
                  borderRadius: BorderRadius.circular(tokens.cardRadius)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('KELİME + OKUMA',
                        style: TextStyle(
                            color: Colors.white70,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    const Text('Gerçek içerikle, kendi hızında ilerle.',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 30,
                            height: 1.12)),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: tokens.accent),
                      onPressed: () => context.go('/words'),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Kelime çalışmalarını aç'),
                    ),
                  ]),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
                builder: (context, constraints) =>
                    Wrap(spacing: 16, runSpacing: 16, children: <Widget>[
                      SizedBox(
                          width: constraints.maxWidth >= 680
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          child: _ModuleCard(
                              icon: Icons.style_rounded,
                              title: 'Kelime',
                              description:
                                  '5.314 gerçek kelime, kartlar ve mini test.',
                              color: tokens.hero,
                              onTap: () => context.go('/words'))),
                      SizedBox(
                          width: constraints.maxWidth >= 680
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          child: _ModuleCard(
                              icon: Icons.menu_book_rounded,
                              title: 'Okuma',
                              description:
                                  '678 okuma ve kaynak cümleleriyle pratik.',
                              color: tokens.purple,
                              onTap: () => context.go('/readings'))),
                    ])),
          ]),
    );
  }
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
