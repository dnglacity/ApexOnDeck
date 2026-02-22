import 'package:flutter/material.dart';
import 'package:sweatdex/models/player.dart';
import '../services/player_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// add_player_screen.dart  (AOD v1.4)
//
// CHANGE (Notes.txt v1.4 — Position field):
//   A new "Position" text field has been added between Jersey Number and
//   Nickname.  It maps to the new `position` column on the `players` table
//   (see add_position_column.sql migration).
//
// CHANGE (Notes.txt v1.4 — Auto link player to account):
//   After a successful save (add OR edit), the screen now checks whether a
//   student email was provided.  If so, it automatically attempts to call
//   PlayerService.linkPlayerToAccount() using that email.  This removes
//   the need for coaches to manually visit Manage Coaches → "Link Player →
//   Account" as a separate step.
//
//   The auto-link is best-effort: if the player has not yet registered an
//   account with that email, the RPC raises an exception which is caught
//   silently (the save still succeeds).  A subtle info banner is shown so
//   the coach knows the link was or was not established.
// ─────────────────────────────────────────────────────────────────────────────

class AddPlayerScreen extends StatefulWidget {
  final String teamId;
  final Player? playerToEdit;

  const AddPlayerScreen({super.key, required this.teamId, this.playerToEdit});

  @override
  State<AddPlayerScreen> createState() => _AddPlayerScreenState();
}

class _AddPlayerScreenState extends State<AddPlayerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _playerService = PlayerService();

  // Controllers for all player fields.
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _jerseyController = TextEditingController();
  final _positionController = TextEditingController(); // CHANGE (v1.4)
  final _studentIdController = TextEditingController();
  final _studentEmailController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill all controllers when in Edit Mode.
    if (widget.playerToEdit != null) {
      final player = widget.playerToEdit!;
      _nameController.text = player.name;
      _nicknameController.text = player.nickname ?? '';
      _jerseyController.text = player.jerseyNumber ?? '';
      _positionController.text = player.position ?? '';   // CHANGE (v1.4)
      _studentIdController.text = player.studentId ?? '';
      _studentEmailController.text = player.studentEmail ?? '';
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Build the player object from current field values.
      final player = Player(
        id: widget.playerToEdit?.id ?? '',
        teamId: widget.teamId,
        name: _nameController.text.trim(),
        nickname: _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        jerseyNumber: _jerseyController.text.trim().isEmpty
            ? null
            : _jerseyController.text.trim(),
        // CHANGE (v1.4): persist position.
        position: _positionController.text.trim().isEmpty
            ? null
            : _positionController.text.trim(),
        studentId: _studentIdController.text.trim().isEmpty
            ? null
            : _studentIdController.text.trim(),
        studentEmail: _studentEmailController.text.trim().isEmpty
            ? null
            : _studentEmailController.text.trim(),
      );

      String savedPlayerId;

      if (widget.playerToEdit == null) {
        // ── Add mode ──────────────────────────────────────────────────────────
        // addPlayer() now returns the newly created player's UUID so we can
        // pass it straight to linkPlayerToAccount without a separate lookup.
        savedPlayerId = await _playerService.addPlayerAndReturnId(player);
      } else {
        // ── Edit mode ─────────────────────────────────────────────────────────
        await _playerService.updatePlayer(player);
        savedPlayerId = player.id;
      }

      // CHANGE (v1.4): Auto-link player → account if a student email was given.
      // This replaces the separate "Link Player → Account" manual step.
      final email = _studentEmailController.text.trim();
      if (email.isNotEmpty && mounted) {
        await _attemptAutoLink(
          playerId: savedPlayerId,
          email: email,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.playerToEdit == null
                  ? '${player.name} added to roster!'
                  : '${player.name} updated!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // return true so callers can refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Auto-link helper ───────────────────────────────────────────────────────

  /// CHANGE (v1.4): Automatically attempts to link [playerId] to the Supabase
  /// account registered under [email].
  ///
  /// On success: shows a green "Linked to account" banner.
  /// On failure (e.g. account not yet created): shows a subtle info banner
  /// and does NOT block the save.  The coach can retry via Manage Coaches
  /// once the player has registered.
  Future<void> _attemptAutoLink({
    required String playerId,
    required String email,
  }) async {
    try {
      await _playerService.linkPlayerToAccount(
        teamId: widget.teamId,
        playerId: playerId,
        playerEmail: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$email linked to player account.'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // Silently ignore — the player account may not exist yet.
      // The coach can link manually later from Manage Coaches.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Player saved. Account link skipped — '
              'the player may not have registered yet.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _jerseyController.dispose();
    _positionController.dispose();  // CHANGE (v1.4)
    _studentIdController.dispose();
    _studentEmailController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.playerToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Player' : 'Add New Player'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // ── Name (Required) ──────────────────────────────────────────
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Player Full Name *',
                  hintText: 'e.g., John Smith',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Jersey Number (Optional) ─────────────────────────────────
              TextFormField(
                controller: _jerseyController,
                decoration: const InputDecoration(
                  labelText: 'Jersey Number',
                  hintText: 'e.g., 23, 00, 12A',
                  prefixIcon: Icon(Icons.numbers),
                  border: OutlineInputBorder(),
                  helperText: 'Can include letters (e.g., 12A)',
                ),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // ── Position (Optional) — CHANGE (v1.4) ─────────────────────
              // Free-text field so it works for any sport.
              // e.g. "Point Guard", "Pitcher", "Center Back", "Left Wing".
              TextFormField(
                controller: _positionController,
                decoration: const InputDecoration(
                  labelText: 'Position',
                  hintText: 'e.g., Point Guard, Pitcher, Center Back',
                  prefixIcon: Icon(Icons.sports),
                  border: OutlineInputBorder(),
                  helperText: 'Optional — works for any sport',
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // ── Nickname (Optional) ──────────────────────────────────────
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  hintText: 'e.g., Big Mike',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // ── Divider ──────────────────────────────────────────────────
              const Divider(height: 32),
              Text(
                'Student Information (Optional)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              // CHANGE (v1.4): Hint about auto-linking.
              Text(
                'Adding an email will automatically link this player to their '
                'app account when they sign up.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),

              // ── Student ID (Optional) ────────────────────────────────────
              TextFormField(
                controller: _studentIdController,
                decoration: const InputDecoration(
                  labelText: 'Student ID',
                  hintText: 'e.g., S12345',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // ── Student Email (Optional) — triggers auto-link ─────────────
              TextFormField(
                controller: _studentEmailController,
                decoration: const InputDecoration(
                  labelText: 'Student Email',
                  hintText: 'e.g., student@school.edu',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                  // CHANGE (v1.4): remind coach about auto-link
                  helperText: 'Used to link this player to their app account',
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      !value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // ── Submit Button ────────────────────────────────────────────
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submitData,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          isEditing ? 'Update Player' : 'Add to Roster',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
              ),

              // ── Cancel (edit mode only) ──────────────────────────────────
              if (isEditing) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}