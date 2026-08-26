import 'package:flutter/material.dart';

import '../../models/content_models.dart';

/// Public-only artwork: local assets are used when supplied by the static
/// source; otherwise this preserves the original PASSAGETR illustration style
/// without inventing a cover image or making a network request.
class ReadingArtwork extends StatelessWidget {
  const ReadingArtwork({
    super.key,
    required this.passage,
    required this.height,
    required this.borderRadius,
  });

  final ReadingPassage passage;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: borderRadius,
        child:
            SizedBox(height: height, width: double.infinity, child: _content()),
      );

  Widget _content() {
    final asset = passage.coverAsset?.trim();
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(asset,
          fit: BoxFit.cover,
          semanticLabel: passage.coverAltText ?? passage.title,
          errorBuilder: (_, __, ___) => _fallback());
    }
    return _fallback();
  }

  Widget _fallback() {
    final palette =
        _paletteFor(passage.category ?? passage.level ?? passage.id);
    final icon = _iconFor(passage.category);
    return DecoratedBox(
      decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: palette,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: Stack(fit: StackFit.expand, children: <Widget>[
        Positioned(
            right: 18,
            top: 18,
            child: Icon(icon,
                size: 48, color: Colors.white.withValues(alpha: .88))),
        Positioned(
            left: 20,
            bottom: 18,
            child: Icon(icon,
                size: 72, color: Colors.white.withValues(alpha: .20))),
      ]),
    );
  }
}

List<Color> _paletteFor(String value) {
  const palettes = <List<Color>>[
    <Color>[Color(0xFF1D4ED8), Color(0xFF0F172A), Color(0xFF38BDF8)],
    <Color>[Color(0xFF059669), Color(0xFF064E3B), Color(0xFFFDE68A)],
    <Color>[Color(0xFF7C3AED), Color(0xFF312E81), Color(0xFFF472B6)],
    <Color>[Color(0xFFDC2626), Color(0xFF7F1D1D), Color(0xFFF97316)],
  ];
  return palettes[value.hashCode.abs() % palettes.length];
}

IconData _iconFor(String? category) {
  final value = (category ?? '').toLowerCase();
  if (value.contains('science') || value.contains('bilim')) {
    return Icons.biotech_outlined;
  }
  if (value.contains('history') || value.contains('tarih')) {
    return Icons.account_balance_outlined;
  }
  if (value.contains('travel') || value.contains('seyahat')) {
    return Icons.travel_explore_outlined;
  }
  if (value.contains('business') || value.contains('iş')) {
    return Icons.business_center_outlined;
  }
  return Icons.auto_stories_outlined;
}
