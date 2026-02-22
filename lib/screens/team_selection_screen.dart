import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../services/auth_service.dart';
import 'roster_screen.dart';
import 'login_screen.dart';
import 'player_self_view_screen.dart'; // NEW (Notes.txt v1.3): player self-view

// ─────────────────────────────────────────────────────────────────────────────
// team_selection_screen.dart  (AOD v1.3)
//
// Shows all teams the authenticated coach belongs to.
// Also shows teams where the user is a "player" (via player_accounts),
// distinguished by a player icon instead of the coach shield.
//
// BUG FIX (bugfix.txt Issue 1 / team_selection_screen.dart:534):
//   The original code called nameController.dispose() and sportController.dispose()
//   immediately after showDialog() returned. Flutter's dialog close animation runs
//   one extra frame *after* the Future resolves, meaning the TextField's animation
//   state tries to call addListener on a disposed ChangeNotifier — causing:
//
//     "A TextEditingController was used after being disposed."
//     "A RenderFlex overflowed by 99785 pixels on the bottom."
//     "_dependents.isEmpty: is not true."
//
//   FIX: Move all controller.dispose() calls into WidgetsBinding.instance
//   .addPostFrameCallback((_) { ... }) so disposal happens *after* the frame
//   in which the close-animation finalises.  This pattern matches the fix
//   already applied to game_roster_screen.dart and saved_roster_screen.dart.
//
// CHANGE (Notes.txt): Three-dot menu Logout now executes a full
//   AuthService.signOut() and navigates back to LoginScreen.
//
// CHANGE (Notes.txt): Player-linked teams display with a player icon (person
//   running) rather than the coach shield.
//
// CHANGE (Notes.txt v1.3): Tapping a player-linked team now routes to
//   PlayerSelfViewScreen (read-only) instead of the full coach RosterScreen.
//
// BUG FIX (Bug 1): Local submission guard is a plain `bool submitted` variable
//   rather than a class-member `_submitted`, preventing double-submit.
// ─────────────────────────────────────────────────────────────────────────────

class TeamSelectionScreen extends StatefulWidget {
  const TeamSelectionScreen({super.key});

  @override
  State<TeamSelectionScreen> createState() => _TeamSelectionScreenState();
}

class _TeamSelectionScreenState extends State<TeamSelectionScreen> {
  final _playerService = PlayerService();
  final _authService = AuthService();

  late Future<List<Map<String, dynamic>>> _teamsFuture;

  @override
  void initState() {
    super.initState();
    _refreshTeams();
  }

  /// Re-fetches the team list (coach teams + player-linked teams).
  void _refreshTeams() {
    setState(() {
      _teamsFuture = _loadAllTeams();
    });
  }

  /// Merges coach teams and player-linked teams into one sorted list.
  /// Player-linked entries include `is_player: true` so the UI can
  /// distinguish them and route differently.
  Future<List<Map<String, dynamic>>> _loadAllTeams() async {
    final coachTeams = await _playerService.getTeams();
    final playerTeams = await _playerService.getPlayerLinkedTeams();

    // Deduplicate: prefer the coach entry if the same team_id appears in both.
    final seenIds = <String>{};
    final merged = <Map<String, dynamic>>[];

    for (final t in coachTeams) {
      seenIds.add(t['id'] as String);
      merged.add({...t, 'is_player': false});
    }
    for (final t in playerTeams) {
      if (!seenIds.contains(t['id'] as String)) {
        merged.add({...t, 'is_player': true});
      }
    }

    return merged;
  }

  // ── Full logout ───────────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
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
      // Actually sign out of Supabase — invalidates the session token.
      await _authService.signOut();

      if (mounted) {
        // Remove every route and push LoginScreen as the new root.
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Edit team dialog ──────────────────────────────────────────────────────

  Future<void> _showEditTeamDialog(Map<String, dynamic> team) async {
    final nameController = TextEditingController(text: team['team_name']);
    final sportController =
        TextEditingController(text: team['sport'] ?? 'General');
    final formKey = GlobalKey<FormState>();

    // BUG FIX (Bug 1): plain local variable, no underscore prefix.
    bool submitted = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Team'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Team Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter a team name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: sportController,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!submitted && formKey.currentState!.validate()) {
                    submitted = true;
                    Navigator.pop(ctx, true);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Sport',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!submitted && formKey.currentState!.validate()) {
                submitted = true;
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // BUG FIX (bugfix.txt Issue 1): Deferred disposal prevents
    // "TextEditingController used after being disposed" assertion.
    // The dialog's close animation fires one frame after showDialog() returns.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      sportController.dispose();
    });

    if (result == true && mounted) {
      try {
        await _playerService.updateTeam(
          team['id'],
          nameController.text.trim(),
          sportController.text.trim(),
        );
        _refreshTeams();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Team updated!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  // ── Delete team dialog ────────────────────────────────────────────────────

  Future<void> _showDeleteTeamDialog(Map<String, dynamic> team) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Team'),
        content: Text(
          'Delete "${team['team_name']}"?\n\n'
          'All players will also be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _playerService.deleteTeam(team['id']);
        _refreshTeams();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${team['team_name']} deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Team'),
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(
            Icons.sports,
            color: colorScheme.secondary, // gold icon
            size: 28,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'logout') await _handleLogout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 20),
                  SizedBox(width: 12),
                  Text('Log Out'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _teamsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refreshTeams,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final teams = snapshot.data ?? [];

          if (teams.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sports, size: 64, color: colorScheme.secondary),
                  const SizedBox(height: 16),
                  const Text(
                    'No teams yet',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the button below to create your first team!',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refreshTeams(),
            child: ListView.builder(
              itemCount: teams.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) {
                final team = teams[i];
                final isOwner = team['is_owner'] == true;
                final isPlayer = team['is_player'] == true;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isPlayer
                          ? colorScheme.primaryContainer
                          : isOwner
                              ? const Color(0xFFFFF3CD)
                              : colorScheme.primaryContainer,
                      child: Icon(
                        isPlayer
                            ? Icons.directions_run // player icon
                            : isOwner
                                ? Icons.shield
                                : Icons.group,
                        color: isPlayer
                            ? colorScheme.primary
                            : isOwner
                                ? const Color(0xFFF4C430) // gold
                                : colorScheme.primary,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          team['team_name'] ?? 'Unnamed Team',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        if (isPlayer)
                          _badge('PLAYER', colorScheme.primary,
                              colorScheme.primaryContainer)
                        else if (isOwner)
                          _badge('OWNER', const Color(0xFF5C4A00),
                              const Color(0xFFFFF3CD)),
                      ],
                    ),
                    subtitle: Text(team['sport'] ?? 'General'),
                    // CHANGE (v1.3): Player-linked teams route to PlayerSelfViewScreen.
                    // Coach teams retain the existing popup menu + RosterScreen route.
                    trailing: isPlayer
                        ? null
                        : PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) async {
                              if (v == 'open') {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RosterScreen(
                                      teamId: team['id'],
                                      teamName: team['team_name'],
                                      sport: team['sport'],
                                    ),
                                  ),
                                );
                                _refreshTeams();
                              } else if (v == 'edit') {
                                await _showEditTeamDialog(team);
                              } else if (v == 'delete') {
                                await _showDeleteTeamDialog(team);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'open',
                                child: Row(children: [
                                  Icon(Icons.open_in_new, size: 20),
                                  SizedBox(width: 12),
                                  Text('Open Roster'),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit, size: 20),
                                  SizedBox(width: 12),
                                  Text('Edit Team'),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete,
                                      color: Colors.red, size: 20),
                                  SizedBox(width: 12),
                                  Text('Delete Team',
                                      style: TextStyle(color: Colors.red)),
                                ]),
                              ),
                            ],
                          ),
                    onTap: () async {
                      if (isPlayer) {
                        // CHANGE (v1.3): Players see their own read-only view.
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlayerSelfViewScreen(
                              teamId: team['id'],
                              teamName: team['team_name'],
                            ),
                          ),
                        );
                      } else {
                        // Coaches see the full roster management screen.
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RosterScreen(
                              teamId: team['id'],
                              teamName: team['team_name'],
                              sport: team['sport'],
                            ),
                          ),
                        );
                        _refreshTeams();
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTeamDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Team'),
      ),
    );
  }

  // ── Badge widget ──────────────────────────────────────────────────────────

  Widget _badge(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  // ── Create team dialog ────────────────────────────────────────────────────

  Future<void> _showCreateTeamDialog() async {
    final nameController = TextEditingController();
    final sportController = TextEditingController(text: 'General');
    final formKey = GlobalKey<FormState>();

    // BUG FIX (Bug 1): plain local variable, no underscore prefix.
    bool submitted = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Team'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Team Name',
                  hintText: 'e.g. Tigers',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter a team name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: sportController,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!submitted && formKey.currentState!.validate()) {
                    submitted = true;
                    Navigator.pop(ctx, true);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Sport',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!submitted && formKey.currentState!.validate()) {
                submitted = true;
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    // BUG FIX (bugfix.txt Issue 1): Defer disposal — same reason as above.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      sportController.dispose();
    });

    if (result == true && mounted) {
      try {
        await _playerService.createTeam(
          nameController.text.trim(),
          sportController.text.trim(),
        );
        _refreshTeams();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Team created!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating team: $e')),
          );
        }
      }
    }
  }
}