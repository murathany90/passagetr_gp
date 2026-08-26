import 'package:flutter/material.dart';

class StudentTtsIconButton extends StatelessWidget {
  const StudentTtsIconButton({
    super.key,
    required this.isSpeaking,
    required this.isInitializing,
    required this.isUnavailable,
    required this.onPlay,
    required this.onStop,
    this.tooltip,
    this.iconSize = 20,
    this.visualDensity,
  });

  final bool isSpeaking;
  final bool isInitializing;
  final bool isUnavailable;
  final Future<void> Function() onPlay;
  final Future<void> Function() onStop;
  final String? tooltip;
  final double iconSize;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    final resolvedTooltip = tooltip ??
        (isUnavailable
            ? 'English TTS kullanilamiyor'
            : isSpeaking
                ? 'Durdur'
                : 'Dinle');

    return Tooltip(
      message: resolvedTooltip,
      child: IconButton(
        visualDensity: visualDensity,
        onPressed: isUnavailable
            ? null
            : () async {
                if (isSpeaking) {
                  await onStop();
                  return;
                }
                await onPlay();
              },
        icon: isInitializing
            ? SizedBox(
                width: iconSize,
                height: iconSize,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                size: iconSize,
              ),
      ),
    );
  }
}
