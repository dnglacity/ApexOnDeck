import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sweatdex/models/player.dart';
import '../services/player_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// game_roster_screen.dart  (AOD v1.3)
//
// Builds a Starting Lineup and Substitutes bench by tapping or dragging
// players from the full roster.
//
// CHANGE (Notes.txt v1.3): TabBar labelColor and unselectedLabelColor set to
//   Colors.white so that tab text/icons always appear white regardless of the
//   AppBar's default Material-3 surface-tint colour calculation.
//   Both the selected-label colour AND the unselected-label colour are set to
//   white; a reduced opacity is applied to unselected labels via
//   unselectedLabelColor so the active tab still looks distinct.
//
// CHANGE (Notes.txt v1.3): When [rosterId] is provided, _loadPlayers() now
//   also fetches the previously saved starters/substitutes from Supabase via
//   PlayerService.getGameRosterById() and pre-populates the lists.  This means
//   positions that were saved on another device will be restored when the
//   coach reopens a roster.
//
// CHANGE (Notes.txt): Clipboard icon (Icons.assignment) replaces
//   Icons.sports_score throughout.
//
// BUG FIX (Bug 7): _showSlotDialog() defers TextEditingController.dispose()
//   to the next frame via addPostFrameCallback to avoid use-after-dispose
//   errors when the dialog is dismissed via barrier tap.
// ─────────────────────────────────────────────────────────────────────────────

class GameRosterScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final String? rosterTitle;
  final String? gameDate;
  final int starterSlots;
  final String? rosterId; // Supabase game_rosters.id — null = unsaved

  /// Optional cancel callback shown as a bottom button.
  /// null = hidden; user uses the AppBar back arrow.
  final VoidCallback? onCancel;

  const GameRosterScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    this.rosterTitle,
    this.gameDate,
    this.starterSlots = 5,
    this.rosterId,
    this.onCancel,
  });

  @override
  State<GameRosterScreen> createState() => _GameRosterScreenState();
}

class _GameRosterScreenState extends State<GameRosterScreen>
    with SingleTickerProviderStateMixin {
  final PlayerService _playerService = PlayerService();

  List<Player> _allPlayers = [];
  List<Player> _starters = [];
  List<Player> _substitutes = [];
  bool _loading = true;

  late TabController _tabController;
  late int _starterSlots;

  @override
  void initState() {
    super.initState();
    _starterSlots = widget.starterSlots;
    _tabController = TabController(length: 2, vsync: this);
    _loadPlayers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  /// Loads the full player list for this team, then — if a [rosterId] was
  /// provided — restores previously saved starter/sub positions from Supabase.
  Future<void> _loadPlayers() async {
    try {
      // Step 1: Fetch all players for this team.
      final players = await _playerService.getPlayers(widget.teamId);

      // Step 2: If we have a saved roster, restore its lineup.
      if (widget.rosterId != null) {
        final rosterData =
            await _playerService.getGameRosterById(widget.rosterId!);
        if (rosterData != null) {
          // rosterData['starters'] and ['substitutes'] are List<Map> with
          // {player_id, slot_number}.  Map them back to Player objects,
          // preserving slot_number ordering.
          final starterIds = _extractOrderedIds(rosterData['starters']);
          final subIds = _extractOrderedIds(rosterData['substitutes']);

          final playerMap = {for (final p in players) p.id: p};

          final savedStarters = starterIds
              .where((id) => playerMap.containsKey(id))
              .map((id) => playerMap[id]!)
              .toList();

          final savedSubs = subIds
              .where((id) => playerMap.containsKey(id))
              .map((id) => playerMap[id]!)
              .toList();

          setState(() {
            _allPlayers = players;
            _starters = savedStarters;
            _substitutes = savedSubs;
            _loading = false;
          });
          return;
        }
      }

      // No saved roster — start with empty starters/subs.
      setState(() {
        _allPlayers = players;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading players: $e')),
        );
      }
    }
  }

  /// Extracts player IDs in slot_number order from a JSON list.
  /// Handles both List<Map> (JSONB from Supabase) and null gracefully.
  List<String> _extractOrderedIds(dynamic raw) {
    if (raw == null) return [];
    final list = raw as List;
    final sorted = List<Map<String, dynamic>>.from(list)
      ..sort((a, b) =>
          ((a['slot_number'] ?? 0) as int).compareTo((b['slot_number'] ?? 0) as int));
    return sorted
        .map((m) => (m['player_id'] ?? '') as String)
        .where((id) => id.isNotEmpty)
        .toList();
  }

  // ── Available players ─────────────────────────────────────────────────────

  List<Player> get _availablePlayers {
    final assigned = {
      ..._starters.map((p) => p.id),
      ..._substitutes.map((p) => p.id),
    };
    return _allPlayers.where((p) => !assigned.contains(p.id)).toList();
  }

  // ── Assignment ────────────────────────────────────────────────────────────

  void _addToStarters(Player player) {
    if (_starters.length >= _starterSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Lineup full ($_starterSlots spots). Adjust or bench a starter.'),
          action: SnackBarAction(label: 'Adjust', onPressed: _showSlotDialog),
        ),
      );
      return;
    }
    setState(() => _starters.add(player));
  }

  void _addToSubs(Player player) => setState(() => _substitutes.add(player));
  void _removeFromStarters(Player p) => setState(() => _starters.remove(p));
  void _removeFromSubs(Player p) => setState(() => _substitutes.remove(p));

  void _promoteSubToStarter(Player player) {
    if (_starters.length >= _starterSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Starting lineup is full.')));
      return;
    }
    setState(() {
      _substitutes.remove(player);
      _starters.add(player);
    });
  }

  void _demoteStarterToSub(Player player) {
    setState(() {
      _starters.remove(player);
      _substitutes.add(player);
    });
  }

  void _clearAll() => setState(() {
        _starters.clear();
        _substitutes.clear();
      });

  // ── Slot-count dialog ─────────────────────────────────────────────────────

  /// BUG FIX (Bug 7): Dispose deferred to next frame to avoid
  /// use-after-dispose when dialog is dismissed via barrier tap.
  Future<void> _showSlotDialog() async {
    int temp = _starterSlots;
    final controller = TextEditingController(text: '$temp');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void onTextChanged(String value) {
            final parsed = int.tryParse(value);
            if (parsed != null && parsed >= 1 && parsed <= 50) {
              setLocal(() => temp = parsed);
            }
          }

          return AlertDialog(
            title: const Text('Starting Lineup Size'),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: temp > 1
                      ? () => setLocal(() {
                            temp--;
                            controller.text = '$temp';
                          })
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onChanged: onTextChanged,
                  ),
                ),
                IconButton(
                  onPressed: temp < 50
                      ? () => setLocal(() {
                            temp++;
                            controller.text = '$temp';
                          })
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final parsed = int.tryParse(controller.text);
                  if (parsed != null && parsed >= 1 && parsed <= 50) {
                    setState(() => _starterSlots = parsed);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    // BUG FIX (Bug 7): Defer disposal so the animation frame that runs
    // immediately after dialog close doesn't fire on a disposed controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  // ── Save roster ───────────────────────────────────────────────────────────

  /// Persists starters and subs to the Supabase game_rosters table.
  /// If [rosterId] is provided, updates the existing row; otherwise shows
  /// a summary dialog (no Supabase ID means the roster was never persisted).
  Future<void> _saveRoster() async {
    if (widget.rosterId != null) {
      try {
        // Build JSONB payload: [{player_id, slot_number}]
        final starterData = [
          for (int i = 0; i < _starters.length; i++)
            {'player_id': _starters[i].id, 'slot_number': i + 1},
        ];
        final subData = [
          for (int i = 0; i < _substitutes.length; i++)
            {'player_id': _substitutes[i].id, 'slot_number': i + 1},
        ];

        await _playerService.updateGameRosterLineup(
          rosterId: widget.rosterId!,
          starters: starterData,
          substitutes: subData,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Roster saved!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error saving: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    } else {
      // No DB ID — show a summary instead.
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Roster Summary'),
          content: Text(
            'Starters (${_starters.length}): '
            '${_starters.map((p) => p.name).join(', ')}\n\n'
            'Subs (${_substitutes.length}): '
            '${_substitutes.map((p) => p.name).join(', ')}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTitle = widget.rosterTitle ?? widget.teamName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.gameDate != null && widget.gameDate!.isNotEmpty)
              Text(widget.gameDate!,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.normal))
            else
              const Text('Game Roster Builder',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Set starter slots',
            onPressed: _showSlotDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear all',
            onPressed: _starters.isEmpty && _substitutes.isEmpty
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear Roster'),
                        content: const Text(
                            'Remove all players from starters and subs?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) _clearAll();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save roster',
            onPressed: _starters.isEmpty ? null : _saveRoster,
          ),
        ],
        // ── CHANGE (Notes.txt v1.3): White tab font colors ─────────────────
        // The AppBar background is deep blue (_brandBlue). Without explicit
        // labelColor, Material 3 picks ColorScheme.primary (#1A3A6B) for the
        // selected label — invisible on blue.  Setting both to white ensures
        // readability.  Unselected tabs use 70% opacity white so they still
        // feel visually distinct from the active tab.
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people, size: 16),
                  const SizedBox(width: 6),
                  Text('Available (${_availablePlayers.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // CHANGE: clipboard icon in the Roster tab.
                  const Icon(Icons.assignment, size: 16),
                  const SizedBox(width: 6),
                  Text('Roster (${_starters.length}/$_starterSlots)'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAvailableTab(theme),
                _buildRosterTab(theme),
              ],
            ),
      bottomNavigationBar: widget.onCancel != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel Roster'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  // ── Available tab ─────────────────────────────────────────────────────────

  Widget _buildAvailableTab(ThemeData theme) {
    final available = _availablePlayers;

    if (_allPlayers.isEmpty) {
      return const Center(
        child: Text(
          'No players on this team yet.\nAdd players from the Roster screen.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (available.isEmpty) {
      return const Center(
        child: Text(
          'All players have been assigned.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Tap a player to add them to the starting lineup or bench. '
            'Long-press and drag to the Roster tab.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: available.length,
            itemBuilder: (_, i) {
              final p = available[i];
              return _DraggablePlayerCard(
                player: p,
                onAddStarter: () => _addToStarters(p),
                onAddSub: () => _addToSubs(p),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Roster tab ────────────────────────────────────────────────────────────

  Widget _buildRosterTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context: context,
            label: 'Starting Lineup',
            count: _starters.length,
            max: _starterSlots,
            color: theme.colorScheme.primary,
            icon: Icons.star,
          ),
          const SizedBox(height: 8),
          _StarterDropZone(
            starters: _starters,
            starterSlots: _starterSlots,
            onDropPlayer: _addToStarters,
            onRemove: _removeFromStarters,
            onSendToBench: _demoteStarterToSub,
            onReorder: (oldIdx, newIdx) {
              setState(() {
                final p = _starters.removeAt(oldIdx);
                _starters.insert(newIdx, p);
              });
            },
          ),
          const SizedBox(height: 24),
          _sectionHeader(
            context: context,
            label: 'Substitutes Bench',
            count: _substitutes.length,
            max: null,
            color: theme.colorScheme.secondary,
            icon: Icons.airline_seat_recline_normal,
          ),
          const SizedBox(height: 8),
          _SubsDropZone(
            substitutes: _substitutes,
            onDropPlayer: _addToSubs,
            onRemove: _removeFromSubs,
            onPromote: _promoteSubToStarter,
            onReorder: (oldIdx, newIdx) {
              setState(() {
                final p = _substitutes.removeAt(oldIdx);
                _substitutes.insert(newIdx, p);
              });
            },
          ),
          if (_starters.isEmpty && _substitutes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Column(
                  children: [
                    // CHANGE: clipboard icon in empty state
                    Icon(Icons.assignment, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'Your roster is empty.\n'
                      'Go to the Available tab to add players.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required BuildContext context,
    required String label,
    required int count,
    int? max,
    required Color color,
    required IconData icon,
  }) {
    final countStr = max != null ? '$count / $max' : '$count';
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            countStr,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DraggablePlayerCard — shown in the Available tab
// ─────────────────────────────────────────────────────────────────────────────
class _DraggablePlayerCard extends StatelessWidget {
  final Player player;
  final VoidCallback onAddStarter;
  final VoidCallback onAddSub;

  const _DraggablePlayerCard({
    required this.player,
    required this.onAddStarter,
    required this.onAddSub,
  });

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<Player>(
      data: player,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 240,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  player.jerseyNumber ?? '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(player.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildCard(context)),
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            player.jerseyNumber ?? '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(player.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: player.nickname != null
            ? Text('"${player.nickname}"',
                style: const TextStyle(fontStyle: FontStyle.italic))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Add to starters',
              child: IconButton(
                icon: const Icon(Icons.star_outline, size: 20),
                onPressed: onAddStarter,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Tooltip(
              message: 'Add to bench',
              child: IconButton(
                icon: const Icon(Icons.airline_seat_recline_normal, size: 20),
                onPressed: onAddSub,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StarterDropZone — reorderable starters list with drag-target overlay
// ─────────────────────────────────────────────────────────────────────────────
class _StarterDropZone extends StatelessWidget {
  final List<Player> starters;
  final int starterSlots;
  final ValueChanged<Player> onDropPlayer;
  final ValueChanged<Player> onRemove;
  final ValueChanged<Player> onSendToBench;
  final void Function(int, int) onReorder;

  const _StarterDropZone({
    required this.starters,
    required this.starterSlots,
    required this.onDropPlayer,
    required this.onRemove,
    required this.onSendToBench,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFull = starters.length >= starterSlots;

    return DragTarget<Player>(
      onWillAcceptWithDetails: (d) => !starters.contains(d.data) && !isFull,
      onAcceptWithDetails: (d) => onDropPlayer(d.data),
      builder: (_, candidateData, __) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : theme.colorScheme.surface,
            border: Border.all(
              color: isHovering
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.03),
              width: isHovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: starters.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      isFull
                          ? 'Lineup full'
                          : 'Drag players here or tap ★ on the Available tab',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: starters.length,
                  onReorder: onReorder,
                  itemBuilder: (_, i) {
                    final p = starters[i];
                    return _RosterRowTile(
                      key: ValueKey(p.id),
                      player: p,
                      slotNumber: i + 1,
                      accentColor: theme.colorScheme.primary,
                      trailingActions: [
                        Tooltip(
                          message: 'Move to bench',
                          child: IconButton(
                            icon: const Icon(
                                Icons.airline_seat_recline_normal,
                                size: 18),
                            onPressed: () => onSendToBench(p),
                          ),
                        ),
                        Tooltip(
                          message: 'Remove',
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: Colors.red,
                            onPressed: () => onRemove(p),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SubsDropZone — reorderable bench list with drag-target overlay
// ─────────────────────────────────────────────────────────────────────────────
class _SubsDropZone extends StatelessWidget {
  final List<Player> substitutes;
  final ValueChanged<Player> onDropPlayer;
  final ValueChanged<Player> onRemove;
  final ValueChanged<Player> onPromote;
  final void Function(int, int) onReorder;

  const _SubsDropZone({
    required this.substitutes,
    required this.onDropPlayer,
    required this.onRemove,
    required this.onPromote,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DragTarget<Player>(
      onWillAcceptWithDetails: (d) => !substitutes.contains(d.data),
      onAcceptWithDetails: (d) => onDropPlayer(d.data),
      builder: (_, candidateData, __) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.secondary.withValues(alpha: 0.08)
                : theme.colorScheme.surface,
            border: Border.all(
              color: isHovering
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.outline.withValues(alpha: 0.03),
              width: isHovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: substitutes.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Drag players here or tap the bench icon on the Available tab',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: substitutes.length,
                  onReorder: onReorder,
                  itemBuilder: (_, i) {
                    final p = substitutes[i];
                    return _RosterRowTile(
                      key: ValueKey(p.id),
                      player: p,
                      slotNumber: i + 1,
                      accentColor: theme.colorScheme.secondary,
                      trailingActions: [
                        Tooltip(
                          message: 'Promote to starter',
                          child: IconButton(
                            icon: const Icon(Icons.star_outline, size: 18),
                            onPressed: () => onPromote(p),
                          ),
                        ),
                        Tooltip(
                          message: 'Remove from bench',
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: Colors.red,
                            onPressed: () => onRemove(p),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RosterRowTile — shared tile inside both reorderable lists
// ─────────────────────────────────────────────────────────────────────────────
class _RosterRowTile extends StatelessWidget {
  final Player player;
  final int slotNumber;
  final Color accentColor;
  final List<Widget> trailingActions;

  const _RosterRowTile({
    super.key,
    required this.player,
    required this.slotNumber,
    required this.accentColor,
    required this.trailingActions,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 16,
            backgroundColor: accentColor.withValues(alpha: 0.15),
            child: Text(
              player.jerseyNumber ?? '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
      title:
          Text(player.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: player.nickname != null
          ? Text('"${player.nickname}"',
              style:
                  const TextStyle(fontStyle: FontStyle.italic, fontSize: 12))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: trailingActions,
      ),
    );
  }
}