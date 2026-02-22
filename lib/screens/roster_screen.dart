import 'package:flutter/material.dart';
import '../models/player.dart';
import '../services/player_service.dart';
import '../services/auth_service.dart';
import 'add_player_screen.dart';
import 'manage_members_screen.dart';   // CHANGE (v1.5): was manage_coaches_screen
import 'saved_roster_screen.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// roster_screen.dart  (AOD v1.5)
//
// CHANGE (Notes.txt v1.5 — Unified users):
//   • Accepts [currentUserRole] ('owner'|'coach') from TeamSelectionScreen.
//   • Owner-only actions: Delete Roster, Team Settings edit/delete.
//   • Coach actions: Add Player, Change Status, Game Rosters.
//   • ManageCoachesScreen → ManageMembersScreen.
//   • Overflow menu "Coach Settings" → "Manage Members".
//
// All v1.4 pagination, position display, and status features retained.
// ─────────────────────────────────────────────────────────────────────────────

class RosterScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final String? sport;

  /// CHANGE (v1.5): Role of the currently logged-in user on this team.
  /// Determines which UI actions are available.
  final String currentUserRole;

  const RosterScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    this.sport,
    this.currentUserRole = 'coach', // default for backwards safety
  });

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _playerService = PlayerService();
  final _authService = AuthService();

  // ── Pagination state ──────────────────────────────────────────────────────
  static const int _pageSize = 20;

  List<Player> _players = [];
  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isPaginating = false;

  final ScrollController _scrollController = ScrollController();
  static const double _scrollThreshold = 200;

  bool _bulkDeleteMode = false;
  final Set<String> _selectedIds = {};

  // ── Role helpers ──────────────────────────────────────────────────────────

  bool get _isOwner => widget.currentUserRole == 'owner';
  bool get _isCoachOrOwner =>
      widget.currentUserRole == 'owner' || widget.currentUserRole == 'coach';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= (pos.maxScrollExtent - _scrollThreshold) &&
        _hasMore &&
        !_isPaginating) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _players.clear();
      _page = 0;
      _hasMore = true;
      _isLoading = true;
    });
    await _fetchPage();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _isPaginating) return;
    setState(() => _isPaginating = true);
    await _fetchPage();
    if (mounted) setState(() => _isPaginating = false);
  }

  Future<void> _fetchPage() async {
    try {
      final from = _page * _pageSize;
      final to = from + _pageSize - 1;

      final batch = await _playerService.getPlayersPaginated(
        teamId: widget.teamId,
        from: from,
        to: to,
      );

      if (mounted) {
        setState(() {
          _players.addAll(batch);
          _page++;
          _hasMore = batch.length == _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading players: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Local state helpers ───────────────────────────────────────────────────

  void _applyLocalStatusChange(String playerId, String newStatus) {
    final idx = _players.indexWhere((p) => p.id == playerId);
    if (idx != -1) {
      setState(() => _players[idx] = _players[idx].copyWith(status: newStatus));
    }
  }

  void _removeLocalPlayer(String playerId) {
    setState(() => _players.removeWhere((p) => p.id == playerId));
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  Future<void> _updatePlayerStatus(Player player, String newStatus) async {
    try {
      await _playerService.updatePlayerStatus(player.id, newStatus);
      _applyLocalStatusChange(player.id, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${player.name} marked as $newStatus'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating status: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showStatusMenu(Player player) async {
    final newStatus = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${player.name} — Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusOption(
                'present', 'Present', Icons.check_circle, Colors.green),
            _statusOption('absent', 'Absent', Icons.cancel, Colors.red),
            _statusOption('late', 'Late', Icons.access_time, Colors.orange),
            _statusOption('excused', 'Excused', Icons.event_busy,
                Theme.of(context).colorScheme.primary),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (newStatus != null && mounted) {
      await _updatePlayerStatus(player, newStatus);
    }
  }

  Widget _statusOption(
      String status, String label, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      onTap: () => Navigator.pop(context, status),
    );
  }

  // ── Bulk Actions ──────────────────────────────────────────────────────────

  Future<void> _showBulkActions() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Actions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Mark All Present'),
              onTap: () => Navigator.pop(ctx, 'present'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Mark All Absent'),
              onTap: () => Navigator.pop(ctx, 'absent'),
            ),
            // CHANGE (v1.5): Bulk delete only for owners.
            if (_isOwner)
              ListTile(
                leading:
                    const Icon(Icons.delete_sweep, color: Colors.red),
                title: const Text('Bulk Delete',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'bulkDelete'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;

    if (action == 'bulkDelete') {
      setState(() {
        _bulkDeleteMode = true;
        _selectedIds.clear();
      });
    } else {
      try {
        await _playerService.bulkUpdateStatus(widget.teamId, action);
        setState(() {
          _players = _players.map((p) => p.copyWith(status: action)).toList();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('All players marked as $action')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _confirmBulkDelete() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No players selected')));
      return;
    }

    bool acknowledged = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete Players'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permanently delete ${_selectedIds.length} player(s)? '
                'This cannot be undone.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: acknowledged,
                    activeColor: Colors.red,
                    onChanged: (v) =>
                        setLocal(() => acknowledged = v ?? false),
                  ),
                  const Expanded(
                    child: Text('I understand this is irreversible.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  acknowledged ? () => Navigator.pop(ctx, true) : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && mounted) {
      final ids = _selectedIds.toList();
      try {
        await _playerService.bulkDeletePlayers(ids);
        setState(() {
          _players.removeWhere((p) => ids.contains(p.id));
          _bulkDeleteMode = false;
          _selectedIds.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${ids.length} player(s) deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
        setState(() {
          _bulkDeleteMode = false;
          _selectedIds.clear();
        });
      }
    }
  }

  // ── Overflow menu ─────────────────────────────────────────────────────────

  void _showOverflowMenu() async {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'manageMembers',
        child: Row(children: [
          Icon(Icons.manage_accounts, size: 20),
          SizedBox(width: 12),
          // CHANGE (v1.5): renamed from "Coach Settings"
          Text('Manage Members'),
        ]),
      ),
      const PopupMenuDivider(),
      // CHANGE (v1.5): Delete Roster only shown to owners.
      if (_isOwner)
        const PopupMenuItem(
          value: 'deleteRoster',
          child: Row(children: [
            Icon(Icons.delete_forever, color: Colors.red, size: 20),
            SizedBox(width: 12),
            Text('Delete Roster', style: TextStyle(color: Colors.red)),
          ]),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'logout',
        child: Row(children: [
          Icon(Icons.logout, size: 20),
          SizedBox(width: 12),
          Text('Log Out'),
        ]),
      ),
    ];

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width,
        kToolbarHeight + MediaQuery.of(context).padding.top,
        0,
        0,
      ),
      items: items,
    );

    if (action == null || !mounted) return;

    switch (action) {
      case 'manageMembers':
        // CHANGE (v1.5): Navigate to ManageMembersScreen with role passed in.
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ManageMembersScreen(
              teamId: widget.teamId,
              teamName: widget.teamName,
              currentUserRole: widget.currentUserRole,
            ),
          ),
        );
        break;
      case 'deleteRoster':
        if (_isOwner) await _confirmDeleteRoster();
        break;
      case 'logout':
        await _performLogout();
        break;
    }
  }

  Future<void> _performLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      _playerService.clearCache();
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error logging out: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDeleteRoster() async {
    bool acknowledged = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete Roster'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permanently delete ALL players from '
                '"${widget.teamName}"? This cannot be undone.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: acknowledged,
                    activeColor: Colors.red,
                    onChanged: (v) =>
                        setLocal(() => acknowledged = v ?? false),
                  ),
                  const Expanded(
                    child: Text('I understand all players will be deleted.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  acknowledged ? () => Navigator.pop(ctx, true) : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete All'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && mounted) {
      try {
        final allPlayers = await _playerService.getPlayers(widget.teamId);
        await _playerService
            .bulkDeletePlayers(allPlayers.map((p) => p.id).toList());
        setState(() => _players.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All players deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final present = _players.where((p) => p.status == 'present').length;
    final absent = _players.where((p) => p.status == 'absent').length;
    final late = _players.where((p) => p.status == 'late').length;
    final excused = _players.where((p) => p.status == 'excused').length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.teamName} Roster',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (widget.sport != null && widget.sport!.isNotEmpty)
              Text(widget.sport!, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment),
            tooltip: 'Game Rosters',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SavedRosterScreen(
                  teamId: widget.teamId,
                  teamName: widget.teamName,
                ),
              ),
            ),
          ),
          _bulkDeleteMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel bulk delete',
                  onPressed: () => setState(() {
                    _bulkDeleteMode = false;
                    _selectedIds.clear();
                  }),
                )
              : IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: 'Bulk Actions',
                  onPressed: _showBulkActions,
                ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onPressed: _showOverflowMenu,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Summary card ───────────────────────────────────────────
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _summaryItem('Present', present, Colors.green),
                        _summaryItem('Absent', absent, Colors.red),
                        _summaryItem('Late', late, Colors.orange),
                        _summaryItem(
                            'Excused', excused, colorScheme.primary),
                      ],
                    ),
                  ),
                ),

                if (_bulkDeleteMode)
                  Container(
                    color: Colors.red[50],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_selectedIds.length} of ${_players.length} selected',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            if (_selectedIds.length == _players.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds
                                  .addAll(_players.map((p) => p.id));
                            }
                          }),
                          child: Text(
                            _selectedIds.length == _players.length
                                ? 'Deselect All'
                                : 'Select All',
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Player list ────────────────────────────────────────────
                Expanded(
                  child: _players.isEmpty && !_hasMore
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              const Text('No players yet',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text('Tap + to add your first player!',
                                  style:
                                      TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadFirstPage,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            itemCount: _players.length + 1,
                            itemBuilder: (ctx, i) {
                              if (i == _players.length) {
                                if (_isPaginating) {
                                  return const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  );
                                }
                                if (!_hasMore && _players.isNotEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Center(
                                      child: Text(
                                        'All ${_players.length} players loaded',
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12),
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              }

                              final player = _players[i];
                              final isChecked =
                                  _selectedIds.contains(player.id);

                              if (_bulkDeleteMode) {
                                return Card(
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: _playerAvatar(
                                        player, colorScheme),
                                    title: Text(player.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: _buildSubtitle(player),
                                    trailing: Checkbox(
                                      value: isChecked,
                                      activeColor: Colors.red,
                                      onChanged: (v) => setState(() {
                                        if (v == true) {
                                          _selectedIds.add(player.id);
                                        } else {
                                          _selectedIds
                                              .remove(player.id);
                                        }
                                      }),
                                    ),
                                    onTap: () => setState(() {
                                      if (isChecked) {
                                        _selectedIds.remove(player.id);
                                      } else {
                                        _selectedIds.add(player.id);
                                      }
                                    }),
                                  ),
                                );
                              }

                              return Dismissible(
                                key: Key(player.id),
                                // CHANGE (v1.5): only coaches/owners can swipe-delete
                                direction: _isCoachOrOwner
                                    ? DismissDirection.endToStart
                                    : DismissDirection.none,
                                confirmDismiss: (_) async =>
                                    showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Player'),
                                    content: Text(
                                        'Remove ${player.name} from the roster?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ),
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white, size: 32),
                                ),
                                onDismissed: (_) async {
                                  try {
                                    await _playerService
                                        .deletePlayer(player.id);
                                    _removeLocalPlayer(player.id);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            '${player.name} removed'),
                                      ));
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content:
                                            Text('Error removing: $e'),
                                        backgroundColor: Colors.red,
                                      ));
                                    }
                                    setState(
                                        () => _players.insert(i, player));
                                  }
                                },
                                child: Card(
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: _playerAvatar(
                                        player, colorScheme),
                                    title: Text(player.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: _buildSubtitle(player),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Status toggle — all coaches/owners
                                        if (_isCoachOrOwner)
                                          IconButton(
                                            icon: Icon(
                                              player.status == 'present'
                                                  ? Icons.check_circle
                                                  : Icons.circle_outlined,
                                              color: player.status ==
                                                      'present'
                                                  ? Colors.green
                                                  : Colors.grey,
                                              size: 28,
                                            ),
                                            onPressed: () async {
                                              final ns =
                                                  player.status == 'present'
                                                      ? 'absent'
                                                      : 'present';
                                              await _updatePlayerStatus(
                                                  player, ns);
                                            },
                                          ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(
                                              Icons.more_vert),
                                          onSelected: (v) async {
                                            if (v == 'status' &&
                                                _isCoachOrOwner) {
                                              await _showStatusMenu(
                                                  player);
                                            } else if (v == 'edit' &&
                                                _isCoachOrOwner) {
                                              final result =
                                                  await Navigator.push<
                                                      bool>(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      AddPlayerScreen(
                                                    teamId:
                                                        widget.teamId,
                                                    playerToEdit:
                                                        player,
                                                  ),
                                                ),
                                              );
                                              if (result == true &&
                                                  mounted) {
                                                _loadFirstPage();
                                              }
                                            } else if (v == 'delete' &&
                                                _isCoachOrOwner) {
                                              final ok =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) =>
                                                    AlertDialog(
                                                  title: const Text(
                                                      'Delete Player'),
                                                  content: Text(
                                                      'Remove ${player.name}?'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx,
                                                              false),
                                                      child: const Text(
                                                          'Cancel'),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                      style: FilledButton
                                                          .styleFrom(
                                                              backgroundColor:
                                                                  Colors
                                                                      .red),
                                                      child: const Text(
                                                          'Delete'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok == true && mounted) {
                                                await _playerService
                                                    .deletePlayer(
                                                        player.id);
                                                _removeLocalPlayer(
                                                    player.id);
                                              }
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            if (_isCoachOrOwner) ...[
                                              const PopupMenuItem(
                                                value: 'status',
                                                child: Row(children: [
                                                  Icon(
                                                      Icons
                                                          .event_available,
                                                      size: 20),
                                                  SizedBox(width: 12),
                                                  Text('Change Status'),
                                                ]),
                                              ),
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(children: [
                                                  Icon(Icons.edit,
                                                      size: 20),
                                                  SizedBox(width: 12),
                                                  Text('Edit Player'),
                                                ]),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(children: [
                                                  Icon(Icons.delete,
                                                      color: Colors.red,
                                                      size: 20),
                                                  SizedBox(width: 12),
                                                  Text('Delete',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.red)),
                                                ]),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    onTap: () =>
                                        _showPlayerDetails(player),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: _bulkDeleteMode
          ? (_isOwner
              ? FloatingActionButton.extended(
                  onPressed: _confirmBulkDelete,
                  backgroundColor: Colors.red,
                  icon: const Icon(Icons.delete),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Delete'
                        : 'Delete (${_selectedIds.length})',
                  ),
                )
              : null)
          : (_isCoachOrOwner
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddPlayerScreen(teamId: widget.teamId),
                      ),
                    );
                    if (result == true && mounted) _loadFirstPage();
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Player'),
                )
              : null),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _playerAvatar(Player player, ColorScheme cs) {
    return Stack(
      children: [
        CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(
            player.displayJersey,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: player.statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(count.toString(),
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildSubtitle(Player player) {
    final parts = <String>[];
    if (player.position != null && player.position!.isNotEmpty) {
      parts.add(player.position!);
    }
    if (player.nickname != null && player.nickname!.isNotEmpty) {
      parts.add('"${player.nickname}"');
    }
    if (player.studentId != null && player.studentId!.isNotEmpty) {
      parts.add('ID: ${player.studentId}');
    }
    // CHANGE (v1.5): Show account link indicator
    if (player.hasLinkedAccount) {
      parts.add('✓ Linked');
    }
    if (parts.isEmpty) {
      return Text(player.studentEmail ?? 'No additional info',
          style: TextStyle(color: Colors.grey[600]));
    }
    return Text(parts.join(' • '),
        style: TextStyle(color: Colors.grey[600]));
  }

  void _showPlayerDetails(Player player) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(player.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (player.jerseyNumber != null)
              _detailRow('Jersey', player.jerseyNumber!),
            if (player.position != null && player.position!.isNotEmpty)
              _detailRow('Position', player.position!),
            if (player.nickname != null && player.nickname!.isNotEmpty)
              _detailRow('Nickname', player.nickname!),
            if (player.studentId != null && player.studentId!.isNotEmpty)
              _detailRow('Student ID', player.studentId!),
            if (player.studentEmail != null &&
                player.studentEmail!.isNotEmpty)
              _detailRow('Email', player.studentEmail!),
            _detailRow('Status', player.statusLabel),
            // CHANGE (v1.5): Show account link status in detail dialog.
            _detailRow('Account',
                player.hasLinkedAccount ? 'Linked ✓' : 'Not linked'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
          if (_isCoachOrOwner) ...[
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showStatusMenu(player);
              },
              icon: Icon(player.statusIcon, size: 16),
              label: const Text('Status'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddPlayerScreen(
                      teamId: widget.teamId,
                      playerToEdit: player,
                    ),
                  ),
                );
                if (result == true && mounted) _loadFirstPage();
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 100,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}