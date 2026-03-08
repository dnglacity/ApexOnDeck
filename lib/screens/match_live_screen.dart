import 'package:flutter/material.dart';
import '../models/match.dart';
import '../services/player_service.dart';
import 'match_format_screen.dart';

// =============================================================================
// match_live_screen.dart  (AOD v1.23)
//
// Side-by-side roster view opened when the host taps "Start Match" after both
// teams have staged.  Displays match format sections with position slots for
// each team, plus starters and substitutes listed below.
// =============================================================================

class MatchLiveScreen extends StatefulWidget {
  final Match match;
  final String hostTeamName;
  final String opponentTeamName;
  final List<Map<String, dynamic>> hostStarters;
  final List<Map<String, dynamic>> hostSubs;
  final MatchFormatTemplate? hostFormat;
  final Map<String, String> hostFormatSlots;

  const MatchLiveScreen({
    super.key,
    required this.match,
    required this.hostTeamName,
    required this.opponentTeamName,
    required this.hostStarters,
    required this.hostSubs,
    this.hostFormat,
    this.hostFormatSlots = const {},
  });

  @override
  State<MatchLiveScreen> createState() => _MatchLiveScreenState();
}

class _MatchLiveScreenState extends State<MatchLiveScreen> {
  List<Map<String, dynamic>> _opponentStarters = [];
  List<Map<String, dynamic>> _opponentSubs = [];
  MatchFormatTemplate? _opponentFormat;
  // Opponent format slots are already enriched: key → {id, name, position, position_override}
  Map<String, Map<String, dynamic>> _opponentFormatSlots = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOpponentRoster();
  }

  Future<void> _loadOpponentRoster() async {
    try {
      final result =
          await PlayerService().getLinkedMatchRoster(widget.match.id);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _error = 'Opponent roster not available.';
          _loading = false;
        });
        return;
      }
      // Parse format template if present.
      MatchFormatTemplate? format;
      final fName = result['format_name'] as String?;
      final fSections = result['format_sections'] as List<dynamic>?;
      if (fName != null && fSections != null) {
        format = MatchFormatTemplate(
          id: '',
          teamId: '',
          name: fName,
          sections: fSections
              .cast<Map<String, dynamic>>()
              .map(MatchFormatSection.fromMap)
              .toList(),
        );
      }
      // Parse enriched format slots.
      final rawSlots = result['format_slots'] as Map<String, dynamic>? ?? {};
      final enrichedSlots = <String, Map<String, dynamic>>{};
      for (final entry in rawSlots.entries) {
        if (entry.value is Map<String, dynamic>) {
          enrichedSlots[entry.key] = entry.value as Map<String, dynamic>;
        }
      }

      setState(() {
        _opponentStarters =
            (result['starters'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                [];
        _opponentSubs =
            (result['substitutes'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                [];
        _opponentFormat = format;
        _opponentFormatSlots = enrichedSlots;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load opponent roster.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Build host playerById map for format slot lookups.
    final hostPlayerById = <String, Map<String, dynamic>>{};
    for (final p in [...widget.hostStarters, ...widget.hostSubs]) {
      final id = p['id'] as String?;
      if (id != null) hostPlayerById[id] = p;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.hostTeamName} vs. ${widget.opponentTeamName}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: cs.error),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: tt.bodyLarge,
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Host roster column ────────────────────
                        Expanded(
                          child: _RosterColumn(
                            teamName: widget.hostTeamName,
                            starters: widget.hostStarters,
                            subs: widget.hostSubs,
                            format: widget.hostFormat,
                            formatSlots: widget.hostFormatSlots,
                            playerById: hostPlayerById,
                            cs: cs,
                            tt: tt,
                          ),
                        ),
                        // ── Vertical divider ──────────────────────
                        VerticalDivider(
                          width: 24,
                          thickness: 1,
                          color: cs.outlineVariant,
                        ),
                        // ── Opponent roster column ────────────────
                        Expanded(
                          child: _RosterColumn(
                            teamName: widget.opponentTeamName,
                            starters: _opponentStarters,
                            subs: _opponentSubs,
                            format: _opponentFormat,
                            formatSlotsEnriched: _opponentFormatSlots,
                            cs: cs,
                            tt: tt,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

// ── Roster column ─────────────────────────────────────────────────────────────
//
// Renders a single team's roster. If a format template is attached the column
// shows sections with numbered position rows first, then starters/subs below.

class _RosterColumn extends StatelessWidget {
  final String teamName;
  final List<Map<String, dynamic>> starters;
  final List<Map<String, dynamic>> subs;
  final MatchFormatTemplate? format;
  // Host format slots: key → playerId (needs playerById for lookup).
  final Map<String, String> formatSlots;
  // Opponent format slots: key → enriched player map (already has name etc.).
  final Map<String, Map<String, dynamic>> formatSlotsEnriched;
  final Map<String, Map<String, dynamic>> playerById;
  final ColorScheme cs;
  final TextTheme tt;

  const _RosterColumn({
    required this.teamName,
    required this.starters,
    required this.subs,
    this.format,
    this.formatSlots = const {},
    this.formatSlotsEnriched = const {},
    this.playerById = const {},
    required this.cs,
    required this.tt,
  });

  /// Look up the assigned player for a format slot key.
  /// Works for both host (formatSlots + playerById) and opponent (formatSlotsEnriched).
  Map<String, dynamic>? _resolveSlot(String key) {
    // Try enriched first (opponent).
    if (formatSlotsEnriched.containsKey(key)) {
      return formatSlotsEnriched[key];
    }
    // Fall back to host style: formatSlots maps key → playerId.
    final playerId = formatSlots[key];
    if (playerId != null && playerById.containsKey(playerId)) {
      return playerById[playerId];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Team name header ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            teamName,
            textAlign: TextAlign.center,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onPrimaryContainer,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 12),

        // ── Match Format Sections ─────────────────────────────────────────
        if (format != null) ...[
          Text(
            format!.name,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(format!.sections.length, (sIdx) {
            final section = format!.sections[sIdx];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8)),
                    ),
                    child: Text(
                      section.title,
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  // Position rows
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    child: Column(
                      children:
                          List.generate(section.positionCount, (pIdx) {
                        final key = '$sIdx-$pIdx';
                        final assigned = _resolveSlot(key);
                        final posLabel = assigned != null
                            ? ((assigned['position_override'] as String?)
                                        ?.isNotEmpty ==
                                    true
                                ? assigned['position_override'] as String
                                : assigned['position'] as String? ?? '')
                            : '';
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                child: Text(
                                  '${pIdx + 1}',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurface
                                        .withValues(alpha: 0.4),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (assigned != null) ...[
                                Icon(Icons.person,
                                    size: 12, color: cs.primary),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    assigned['name'] as String? ??
                                        '\u2014',
                                    style: tt.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (posLabel.isNotEmpty)
                                  Text(
                                    posLabel,
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                              ] else ...[
                                Icon(Icons.person_outline,
                                    size: 12,
                                    color: cs.onSurface
                                        .withValues(alpha: 0.3)),
                                const SizedBox(width: 3),
                                Text(
                                  '\u2014',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurface
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
        ],

        // ── Starters ──────────────────────────────────────────────────────
        if (starters.isNotEmpty) ...[
          Text(
            'Starters (${starters.length})',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          ...starters.map((p) => _PlayerTile(player: p, cs: cs, tt: tt)),
        ],

        // ── Substitutes ───────────────────────────────────────────────────
        if (subs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Substitutes (${subs.length})',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          ...subs.map((p) => _PlayerTile(player: p, cs: cs, tt: tt)),
        ],

        // ── Empty state ───────────────────────────────────────────────────
        if (format == null && starters.isEmpty && subs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No players assigned.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Single player tile ────────────────────────────────────────────────────────

class _PlayerTile extends StatelessWidget {
  final Map<String, dynamic> player;
  final ColorScheme cs;
  final TextTheme tt;

  const _PlayerTile({
    required this.player,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    final name = player['name'] as String? ?? '\u2014';
    final position =
        (player['position_override'] as String?)?.isNotEmpty == true
            ? player['position_override'] as String
            : player['position'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.person_outline,
              size: 12, color: cs.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              name,
              style: tt.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (position.isNotEmpty)
            Text(
              position,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}
