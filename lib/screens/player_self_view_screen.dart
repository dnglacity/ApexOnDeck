import 'package:flutter/material.dart';
import 'package:sweatdex/models/player.dart';
import '../services/player_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// player_self_view_screen.dart  (AOD v1.3 — NEW)
//
// A read-only screen shown to players when they tap a team that they are
// linked to via player_accounts.  It displays:
//
//   1. Their own player card (name, jersey, nickname, current status).
//   2. Their attendance summary (present / absent / late / excused counts
//      derived from the current status — a full history table would require
//      a separate attendance_log table, which is a future enhancement).
//   3. A scrollable list of teammates (other players on the same team)
//      showing jersey number and name only — no status details exposed.
//
// This screen is intentionally read-only: no status-change buttons, no
// edit controls, no FAB.  Players can pull-to-refresh the list if needed.
//
// NAVIGATION: TeamSelectionScreen routes here when is_player == true (v1.3).
// ─────────────────────────────────────────────────────────────────────────────

class PlayerSelfViewScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const PlayerSelfViewScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<PlayerSelfViewScreen> createState() => _PlayerSelfViewScreenState();
}

class _PlayerSelfViewScreenState extends State<PlayerSelfViewScreen> {
  final _playerService = PlayerService();

  /// The player row linked to the current auth account on this team.
  Player? _myPlayer;

  /// All players on the team (including self) — used for the teammates list.
  List<Player> _allPlayers = [];

  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  /// Fetches the current user's linked player record and all teammates.
  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // Step 1: Get the player row linked to the current auth account.
      final myPlayerData =
          await _playerService.getMyPlayerOnTeam(widget.teamId);

      // Step 2: Fetch all players on the team for the teammates list.
      final allPlayers = await _playerService.getPlayers(widget.teamId);

      setState(() {
        _myPlayer = myPlayerData;
        _allPlayers = allPlayers;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.teamName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('My Team View',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildContent(theme, cs),
                ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _buildContent(ThemeData theme, ColorScheme cs) {
    // Separate self from teammates list.
    final teammates = _myPlayer != null
        ? _allPlayers.where((p) => p.id != _myPlayer!.id).toList()
        : _allPlayers;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── My Player Card ────────────────────────────────────────────────
        if (_myPlayer != null) ...[
          Text(
            'My Profile',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _MyPlayerCard(player: _myPlayer!, cs: cs),
          const SizedBox(height: 24),

          // ── Attendance Summary ─────────────────────────────────────────
          Text(
            'Current Status',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _AttendanceSummaryCard(player: _myPlayer!, cs: cs),
          const SizedBox(height: 24),
        ] else ...[
          // Not yet linked to a player row on this team.
          Card(
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: cs.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your account is not yet linked to a player on this '
                      'team. Ask your coach to link you.',
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── Teammates List ────────────────────────────────────────────────
        Row(
          children: [
            Text(
              'Teammates',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            // Count badge.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${teammates.length}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (teammates.isEmpty)
          const Center(
              child: Text('No teammates yet.',
                  style: TextStyle(fontStyle: FontStyle.italic)))
        else
          ...teammates.map((p) => _TeammateRow(player: p, cs: cs)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MyPlayerCard — displays the player's own info prominently
// ─────────────────────────────────────────────────────────────────────────────
class _MyPlayerCard extends StatelessWidget {
  final Player player;
  final ColorScheme cs;

  const _MyPlayerCard({required this.player, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Jersey avatar.
            CircleAvatar(
              radius: 36,
              backgroundColor: cs.primary,
              child: Text(
                player.displayJersey,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (player.nickname != null &&
                      player.nickname!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '"${player.nickname}"',
                      style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[600]),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Status chip.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: player.statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: player.statusColor, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(player.statusIcon,
                            size: 14, color: player.statusColor),
                        const SizedBox(width: 4),
                        Text(
                          player.statusLabel,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: player.statusColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AttendanceSummaryCard — read-only status display
// ─────────────────────────────────────────────────────────────────────────────
class _AttendanceSummaryCard extends StatelessWidget {
  final Player player;
  final ColorScheme cs;

  const _AttendanceSummaryCard({required this.player, required this.cs});

  @override
  Widget build(BuildContext context) {
    // [Inference] Currently only the live status is available per the existing
    // data model (no attendance_log table).  The card displays a note
    // explaining this.  A future enhancement can add historical tracking.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(player.statusIcon, color: player.statusColor),
                const SizedBox(width: 8),
                Text(
                  'Today\'s Status: ${player.statusLabel}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: player.statusColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Full attendance history will be available in a future update. '
              'Your coach sets your status during each practice or game.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TeammateRow — a single read-only teammate entry
// Names and jersey numbers only — no status details shared with players
// ─────────────────────────────────────────────────────────────────────────────
class _TeammateRow extends StatelessWidget {
  final Player player;
  final ColorScheme cs;

  const _TeammateRow({required this.player, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(
            player.displayJersey,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
                fontSize: 12),
          ),
        ),
        title: Text(player.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: player.nickname != null
            ? Text('"${player.nickname}"',
                style: const TextStyle(fontStyle: FontStyle.italic))
            : null,
        // Intentionally no trailing actions — read-only view.
      ),
    );
  }
}