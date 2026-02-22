import 'package:flutter/material.dart';
import '../services/player_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// manage_coaches_screen.dart  (AOD v1.3)
//
// ManageCoachesScreen — view and manage all coaches on a team.
//
// CHANGE (Notes.txt v1.3): RPC for add_player_account.
//   A new "Link Player → Account" FAB action lets coaches retroactively link
//   an existing player row to a user account by email.  This calls the
//   Supabase RPC `link_player_to_account` (defined in add_player_account_rpc.sql).
//   The RPC finds the auth.users row by email, resolves the coach ID, and
//   upserts into player_accounts.  The coach does NOT need to know the
//   user's coach ID — only their email.
//
// BUG FIX (Bug 8): When a coach removes themselves, popUntil(isFirst) is used
//   so RosterScreen doesn't try to stream players for a team they left.
// ─────────────────────────────────────────────────────────────────────────────

class ManageCoachesScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const ManageCoachesScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<ManageCoachesScreen> createState() => _ManageCoachesScreenState();
}

class _ManageCoachesScreenState extends State<ManageCoachesScreen> {
  final _playerService = PlayerService();
  late Future<List<Map<String, dynamic>>> _coachesFuture;

  /// The current user's coach ID — used for "YOU" badge and self-removal logic.
  String? _currentCoachId;

  @override
  void initState() {
    super.initState();
    _loadCurrentCoach();
    _refreshCoaches();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadCurrentCoach() async {
    try {
      final coach = await _playerService.getCurrentCoach();
      if (mounted) {
        setState(() => _currentCoachId = coach?['id']);
      }
    } catch (e) {
      debugPrint('Error loading current coach: $e');
    }
  }

  void _refreshCoaches() {
    setState(() {
      _coachesFuture = _playerService.getTeamCoaches(widget.teamId);
    });
  }

  // ── Add coach dialog ──────────────────────────────────────────────────────

  Future<void> _showAddCoachDialog() async {
    final emailController = TextEditingController();
    final roleController =
        TextEditingController(text: 'Assistant Coach');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Coach'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Coach email input.
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Coach Email',
                  hintText: 'coach@example.com',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Role input.
              TextFormField(
                controller: roleController,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(context, true);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Role',
                  hintText: 'e.g., Assistant Coach',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await _playerService.addCoachToTeam(
          widget.teamId,
          emailController.text.trim(),
          roleController.text.trim(),
        );
        _refreshCoaches();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Coach added successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    emailController.dispose();
    roleController.dispose();
  }

  // ── Link player to account dialog ─────────────────────────────────────────
  //
  // NEW (Notes.txt v1.3): RPC for add_player_account.
  // Allows a coach to retroactively link an existing player row to a user
  // account by entering the player's email.  The `link_player_to_account`
  // SECURITY DEFINER RPC handles the lookup and upsert atomically.

  Future<void> _showLinkPlayerDialog() async {
    // Step 1: Fetch all players on this team so the coach can pick one.
    List<Map<String, dynamic>> players = [];
    try {
      final rawPlayers = await _playerService.getPlayers(widget.teamId);
      players = rawPlayers
          .map((p) => {'id': p.id, 'name': p.name, 'jersey': p.jerseyNumber})
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading players: $e')),
        );
      }
      return;
    }

    if (players.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No players on this team to link.')),
        );
      }
      return;
    }

    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedPlayerId;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Link Player → Account'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Explanatory text.
                  Text(
                    'Enter the player\'s registered email and select '
                    'their roster entry.  They will be able to see '
                    'their team view after signing in.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),

                  // Player picker.
                  DropdownButtonFormField<String>(
                    value: selectedPlayerId,
                    decoration: const InputDecoration(
                      labelText: 'Select Player',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    items: players
                        .map((p) => DropdownMenuItem<String>(
                              value: p['id'] as String,
                              child: Text(
                                  '${p['name']}${p['jersey'] != null ? ' (#${p['jersey']})' : ''}'),
                            ))
                        .toList(),
                    onChanged: (v) => setLocal(() => selectedPlayerId = v),
                    validator: (_) => selectedPlayerId == null
                        ? 'Please select a player'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Account email.
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Player\'s Account Email',
                      hintText: 'player@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter an email';
                      }
                      if (!v.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Link'),
            ),
          ],
        ),
      ),
    );

    emailController.dispose();

    if (result == true && selectedPlayerId != null && mounted) {
      try {
        // Call the SECURITY DEFINER RPC that looks up the auth user by
        // email and upserts the player_accounts row.
        await _playerService.linkPlayerToAccount(
          teamId: widget.teamId,
          playerId: selectedPlayerId!,
          playerEmail: emailController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Player linked to account!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ── Remove coach ──────────────────────────────────────────────────────────

  /// BUG FIX (Bug 8): When the coach removes themselves, popUntil(isFirst)
  /// is used so we don't land on RosterScreen — which would fire player-stream
  /// queries that RLS now blocks because the user is no longer a team member.
  Future<void> _confirmRemoveCoach(Map<String, dynamic> coach) async {
    final isSelf = coach['id'] == _currentCoachId;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSelf ? 'Leave Team' : 'Remove Coach'),
        content: Text(
          isSelf
              ? 'Are you sure you want to leave this team?'
              : 'Remove ${coach['name']} from this team?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isSelf ? 'Leave' : 'Remove'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _playerService.removeCoachFromTeam(
            widget.teamId, coach['id'] as String);

        if (!mounted) return;

        if (isSelf) {
          // FIX (Bug 8): Pop all the way back to TeamSelectionScreen.
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }

        _refreshCoaches();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${coach['name']} removed')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ── Transfer ownership dialog ─────────────────────────────────────────────

  Future<void> _showTransferOwnershipDialog(
      List<Map<String, dynamic>> coaches) async {
    final eligibleCoaches =
        coaches.where((c) => c['is_owner'] != true).toList();

    if (eligibleCoaches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No other coaches to transfer ownership to')),
      );
      return;
    }

    final selectedCoach = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: eligibleCoaches.map((coach) {
            return ListTile(
              leading: CircleAvatar(
                child: Text((coach['name'] as String)[0].toUpperCase()),
              ),
              title: Text(coach['name'] as String),
              subtitle: Text(coach['role'] as String),
              onTap: () => Navigator.pop(context, coach),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedCoach != null && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Transfer'),
          content: Text(
            'Transfer team ownership to ${selectedCoach['name']}?\n\n'
            'You will no longer be the owner but will remain on the team.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Transfer'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        try {
          await _playerService.transferOwnership(
              widget.teamId, selectedCoach['id'] as String);
          _refreshCoaches();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Ownership transferred to ${selectedCoach['name']}')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.teamName} Coaches'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _coachesFuture,
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
                  ElevatedButton(
                    onPressed: _refreshCoaches,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final coaches = snapshot.data ?? [];

          final currentCoach = coaches.firstWhere(
            (c) => c['id'] == _currentCoachId,
            orElse: () => {},
          );
          final isCurrentUserOwner =
              currentCoach.isNotEmpty && currentCoach['is_owner'] == true;

          return Column(
            children: [
              // ── Role banner ──────────────────────────────────────────────
              if (isCurrentUserOwner)
                Card(
                  margin: const EdgeInsets.all(16),
                  color: Colors.amber[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.shield, color: Colors.amber[700]),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('You are the team owner',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                'You can manage coaches, transfer ownership, '
                                'and link players to accounts.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _showTransferOwnershipDialog(coaches),
                          child: const Text('Transfer'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  margin: const EdgeInsets.all(16),
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('You are a coach on this team',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                'You can add coaches or leave the team.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Coaches list ─────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: coaches.length,
                  itemBuilder: (context, index) {
                    final coach = coaches[index];
                    final isOwner = coach['is_owner'] == true;
                    final isCurrentUser = coach['id'] == _currentCoachId;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isOwner
                              ? Colors.amber[100]
                              : Colors.blue[100],
                          child: Icon(
                            isOwner ? Icons.shield : Icons.person,
                            color:
                                isOwner ? Colors.amber[700] : Colors.blue,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(coach['name'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            if (isCurrentUser) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('YOU',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[900])),
                              ),
                            ],
                            if (isOwner) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('OWNER',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber[900])),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(coach['role'] as String),
                            Text(
                              coach['email'] as String? ?? '',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        trailing: _buildTrailingActions(
                          coach,
                          isOwner,
                          isCurrentUser,
                          isCurrentUserOwner,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      // ── FAB: Add Coach OR Link Player (for owners) ────────────────────────
      // CHANGE (v1.3): Owner gets a speed-dial style menu; non-owners keep
      // the single "Add Coach" button.
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildFab() {
    // [Inference] Only owners are likely to link players.  Non-owners get
    // the simpler single-button FAB to reduce UI complexity.
    return FloatingActionButton.extended(
      onPressed: _showFabMenu,
      icon: const Icon(Icons.add),
      label: const Text('Actions'),
    );
  }

  /// Shows a bottom sheet with coach management actions.
  void _showFabMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Add Coach'),
              subtitle: const Text('Invite a coach by email'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddCoachDialog();
              },
            ),
            // NEW (v1.3): Link Player → Account
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Link Player → Account'),
              subtitle: const Text(
                  'Retroactively link an existing player to their account'),
              onTap: () {
                Navigator.pop(ctx);
                _showLinkPlayerDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildTrailingActions(
    Map<String, dynamic> coach,
    bool isOwner,
    bool isCurrentUser,
    bool isCurrentUserOwner,
  ) {
    if (isOwner && !isCurrentUser) return null;
    if (isCurrentUser || isCurrentUserOwner) {
      return IconButton(
        icon: Icon(
          isCurrentUser ? Icons.exit_to_app : Icons.remove_circle,
          color: Colors.red,
        ),
        onPressed: () => _confirmRemoveCoach(coach),
        tooltip: isCurrentUser ? 'Leave team' : 'Remove coach',
      );
    }
    return null;
  }
}