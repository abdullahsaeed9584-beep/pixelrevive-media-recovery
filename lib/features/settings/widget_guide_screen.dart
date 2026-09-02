import 'package:flutter/material.dart';

class WidgetGuideScreen extends StatelessWidget {
  const WidgetGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Widget Setup Guide'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.widgets_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
          SizedBox(height: 24),
          Text(
            'Add the Quick Scan Widget',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'You can add a Quick Scan widget to your home screen to instantly scan for deleted media with one tap.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          SizedBox(height: 40),
          _GuideStep(
            step: '1',
            title: 'Go to Home Screen',
            description: 'Long press on any empty space on your device home screen.',
          ),
          _GuideStep(
            step: '2',
            title: 'Open Widgets Menu',
            description: 'Tap the "Widgets" button that appears at the bottom of the screen.',
          ),
          _GuideStep(
            step: '3',
            title: 'Find PixelRevive',
            description: 'Scroll down to find PixelRevive, then drag the "Quick Scan" widget to your home screen.',
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final String step;
  final String title;
  final String description;

  const _GuideStep({
    required this.step,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
