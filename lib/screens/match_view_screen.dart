import 'package:flutter/material.dart';
import '../models/match.dart';
import '../services/player_service.dart';

// =============================================================================
// match_view_screen.dart  (AOD v1.12)
//
// Full-screen view for a single match. Opened when the user taps a match card
// in MatchesScreen. The top-right overflow menu includes "Match Settings".
// =============================================================================

enum _MatchMenuItem { settings }

class MatchViewScreen extends StatefulWidget {
  final Match match;

  const MatchViewScreen({super.key, required this.match});

  @override
  State<MatchViewScreen> createState() => _MatchViewScreenState();
}

class _MatchViewScreenState extends State<MatchViewScreen> {
  late Match _match;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _shortMonthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _dayNames = [
    '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _match = widget.match;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isPast = _match.date.isBefore(DateTime.now());

    return Scaffold(
        appBar: AppBar(
          title: Text(_match.title, overflow: TextOverflow.ellipsis),
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_match),
          ),
          actions: [
            PopupMenuButton<_MatchMenuItem>(
              onSelected: (item) {
                if (item == _MatchMenuItem.settings) {
                  _showMatchSettings(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _MatchMenuItem.settings,
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined),
                      SizedBox(width: 12),
                      Text('Match Settings'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Status chip ─────────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(isPast ? 'Past' : 'Upcoming'),
                backgroundColor: isPast
                    ? cs.surfaceContainerHighest
                    : cs.primaryContainer,
                labelStyle: TextStyle(
                  color: isPast ? cs.onSurfaceVariant : cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            const SizedBox(height: 16),

            // ── Teams ────────────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _TeamBlock(
                    label: 'My Team',
                    name: _match.myTeamName,
                    cs: cs,
                    tt: tt,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'vs.',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Expanded(
                  child: _TeamBlock(
                    label: 'Opponent',
                    name: _match.opponentName,
                    cs: cs,
                    tt: tt,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // ── Date & time ──────────────────────────────────────────────────────
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Date',
              value:
                  '${_dayNames[_match.date.weekday]}, ${_monthNames[_match.date.month - 1]} ${_match.date.day}, ${_match.date.year}',
              cs: cs,
              tt: tt,
            ),
            const SizedBox(height: 14),

            // ── Location ─────────────────────────────────────────────────────────
            _InfoRow(
              icon: _match.isHome ? Icons.home_outlined : Icons.directions_bus_outlined,
              label: 'Location',
              value: _match.isHome ? 'Home' : 'Away',
              cs: cs,
              tt: tt,
            ),

            // ── Notes ────────────────────────────────────────────────────────────
            if (_match.notes.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Notes',
                style: tt.labelLarge?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _match.notes,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
    );
  }

  void _showMatchSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MatchSettingsSheet(
        onEdit: () => _openEditSheet(context),
        onDelete: () => _confirmDelete(context),
      ),
    );
  }

  // ── Edit match ──────────────────────────────────────────────────────────────

  void _openEditSheet(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final opponentCtrl = TextEditingController(text: _match.opponentName);
    final myTeamCtrl = TextEditingController(text: _match.myTeamName);
    final notesCtrl = TextEditingController(text: _match.notes);
    DateTime selectedDate = _match.date;
    bool isHome = _match.isHome;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        'Edit Match',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 20),

                      // ── Teams row ──────────────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: myTeamCtrl,
                              decoration: const InputDecoration(
                                labelText: 'My Team *',
                                border: OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text('vs.', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: opponentCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Opponent *',
                                border: OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Date ──────────────────────────────────────────────
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2040),
                          );
                          if (picked != null) {
                            setSheetState(() => selectedDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date *',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            '${_shortMonthNames[selectedDate.month - 1]} ${selectedDate.day}, ${selectedDate.year}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Home / Away ────────────────────────────────────────
                      Row(
                        children: [
                          const Text('Location:',
                              style: TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(width: 12),
                          ChoiceChip(
                            label: const Text('Home'),
                            selected: isHome,
                            onSelected: (_) => setSheetState(() => isHome = true),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Away'),
                            selected: !isHome,
                            onSelected: (_) => setSheetState(() => isHome = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Notes ─────────────────────────────────────────────
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 24),

                      // ── Save ──────────────────────────────────────────────
                      FilledButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setSheetState(() => isSaving = true);
                                try {
                                  await PlayerService().updateMatch(
                                    matchId: _match.id,
                                    opponentName: opponentCtrl.text.trim(),
                                    myTeamName: myTeamCtrl.text.trim(),
                                    matchDate: selectedDate,
                                    isHome: isHome,
                                    notes: notesCtrl.text.trim(),
                                  );
                                  final updated = _match.copyWith(
                                    myTeamName: myTeamCtrl.text.trim(),
                                    opponentName: opponentCtrl.text.trim(),
                                    date: selectedDate,
                                    isHome: isHome,
                                    notes: notesCtrl.text.trim(),
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) setState(() => _match = updated);
                                } catch (e) {
                                  setSheetState(() => isSaving = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                }
                              },
                        icon: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Save Changes'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Delete match ────────────────────────────────────────────────────────────

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Match'),
        content: Text(
          'Are you sure you want to delete "${_match.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx); // close dialog
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await PlayerService().deleteMatch(_match.id);
                if (mounted) nav.pop(null); // null signals deletion to parent
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _TeamBlock extends StatelessWidget {
  final String label;
  final String name;
  final ColorScheme cs;
  final TextTheme tt;

  const _TeamBlock({
    required this.label,
    required this.name,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.5),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          textAlign: TextAlign.center,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: tt.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

class _MatchSettingsSheet extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MatchSettingsSheet({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Match Settings',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Match'),
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text('Delete Match', style: TextStyle(color: cs.error)),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
