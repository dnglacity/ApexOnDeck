import 'package:flutter/material.dart';
import '../models/match.dart';

// =============================================================================
// match_play_screen.dart  (AOD v1.13)
//
// Active match play screen. Opened when a coach stages a match from
// MatchViewScreen. Displays match info and will host live scoring / lineup
// management during the game.
// =============================================================================

class MatchPlayScreen extends StatefulWidget {
  final Match match;
  final bool isCoach;

  const MatchPlayScreen({
    super.key,
    required this.match,
    this.isCoach = false,
  });

  @override
  State<MatchPlayScreen> createState() => _MatchPlayScreenState();
}

class _MatchPlayScreenState extends State<MatchPlayScreen> {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.match.title),
        backgroundColor: const Color(0xFF1A3A6B),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sports, size: 64, color: Color(0xFF1A3A6B)),
              const SizedBox(height: 16),
              Text(
                widget.match.title,
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.match.locationLabel,
                style: tt.bodyLarge?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              Text(
                'Match is live',
                style: tt.titleMedium?.copyWith(
                  color: const Color(0xFF1A3A6B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
