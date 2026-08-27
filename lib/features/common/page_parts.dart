import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_breakpoints.dart';
import '../../core/app_theme_tokens.dart';

enum PassagetrDestination { home, words, readings }

class PassagetrShell extends StatelessWidget {
  const PassagetrShell(
      {super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final destination = location.startsWith('/words')
        ? PassagetrDestination.words
        : location.startsWith('/readings')
            ? PassagetrDestination.readings
            : PassagetrDestination.home;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= AppBreakpoints.shellWide;
      final tokens = AppThemeTokens.of(context);
      return Scaffold(
        backgroundColor: tokens.appBackground,
        body: SafeArea(
          bottom: !wide,
          child: wide
              ? Row(children: <Widget>[
                  _DesktopRail(destination: destination),
                  Expanded(child: child),
                ])
              : child,
        ),
        bottomNavigationBar: wide || destination == PassagetrDestination.home
            ? null
            : NavigationBar(
                selectedIndex:
                    destination == PassagetrDestination.words ? 0 : 1,
                onDestinationSelected: (index) => context.go(switch (index) {
                  0 => '/words',
                  _ => '/readings',
                }),
                destinations: const <NavigationDestination>[
                  NavigationDestination(
                      icon: Icon(Icons.style_outlined),
                      selectedIcon: Icon(Icons.style_rounded),
                      label: 'Kelime'),
                  NavigationDestination(
                      icon: Icon(Icons.menu_book_outlined),
                      selectedIcon: Icon(Icons.menu_book_rounded),
                      label: 'Okuma'),
                ],
              ),
      );
    });
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions,
    this.maxWidth,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget>? actions;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Title(
      title: 'PASSAGETR | $title',
      color: tokens.accent,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppBreakpoints.shellWide;
        final compact = constraints.maxWidth < AppBreakpoints.small;
        return SafeArea(
          bottom: !wide,
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  wide ? 36 : 18,
                  wide ? 24 : (compact ? 16 : 20),
                  wide ? 36 : 18,
                  wide ? 36 : 104),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: maxWidth ?? tokens.contentMaxWidth),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (actions != null && actions!.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                              spacing: 10, runSpacing: 10, children: actions!),
                        ),
                      if (actions != null && actions!.isNotEmpty)
                        SizedBox(height: compact ? 14 : 18),
                      Text(title,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: tokens.secondaryText)),
                      SizedBox(height: compact ? 18 : 24),
                      child,
                    ]),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20),
      this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final card = Container(
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.surfaceBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: tokens.surfaceShadow,
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -4)
        ],
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return Material(
        color: Colors.transparent,
        child: InkWell(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            onTap: onTap,
            child: card));
  }
}

class DataLoadErrorPage extends StatelessWidget {
  const DataLoadErrorPage({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'İçerik yüklenemedi',
        subtitle: 'DATA_LOAD_ERROR',
        child: SurfaceCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
              const Icon(Icons.error_outline_rounded, size: 42),
              const SizedBox(height: 16),
              Text(message),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tekrar dene')),
              ],
            ])),
      );
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({required this.destination});

  final PassagetrDestination destination;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      width: tokens.railWidth,
      decoration: BoxDecoration(
          color: tokens.railBackground,
          border: Border(right: BorderSide(color: tokens.surfaceBorder))),
      child: Column(children: <Widget>[
        const SizedBox(height: 24),
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: tokens.accent, borderRadius: BorderRadius.circular(14)),
          child: const Text('PT',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22)),
        ),
        const SizedBox(height: 24),
        _RailButton(
            icon: Icons.home_rounded,
            label: 'Ana Sayfa',
            selected: destination == PassagetrDestination.home,
            onTap: () => context.go('/')),
        _RailButton(
            icon: Icons.style_rounded,
            label: 'Kelime',
            selected: destination == PassagetrDestination.words,
            onTap: () => context.go('/words')),
        _RailButton(
            icon: Icons.menu_book_rounded,
            label: 'Okuma',
            selected: destination == PassagetrDestination.readings,
            onTap: () => context.go('/readings')),
      ]),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final foreground = selected ? Colors.white : tokens.secondaryText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
              color: selected ? tokens.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(18)),
          child: Column(children: <Widget>[
            Icon(icon, color: foreground),
            const SizedBox(height: 5),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: foreground))
          ]),
        ),
      ),
    );
  }
}
