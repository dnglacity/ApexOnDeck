import 'package:flutter/material.dart';
import '../constants/date_constants.dart';
import '../services/auth_service.dart';
import '../services/player_service.dart';
import 'account_settings_screen.dart';

// =============================================================================
// calendar_screen.dart  (AOD v1.12)
//
// Schedule / calendar screen accessible via the bottom navigation bar.
// Displays a month-view calendar header and a placeholder events list.
// Future iterations will populate events from game_rosters / a schedules table.
// =============================================================================

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _playerService = PlayerService();
  final _authService = AuthService();

  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  DateTime get _firstDayOfMonth =>
      DateTime(_focusedMonth.year, _focusedMonth.month, 1);

  int get _daysInMonth =>
      DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;

  /// 0 = Mon … 6 = Sun (ISO weekday - 1).
  int get _startWeekday => (_firstDayOfMonth.weekday - 1) % 7;


  void _previousMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month - 1);
        _selectedDay = null;
      });

  void _nextMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month + 1);
        _selectedDay = null;
      });

  bool _isToday(int day) {
    final now = DateTime.now();
    return _focusedMonth.year == now.year &&
        _focusedMonth.month == now.month &&
        day == now.day;
  }

  bool _isSelected(int day) =>
      _selectedDay != null &&
      _selectedDay!.year == _focusedMonth.year &&
      _selectedDay!.month == _focusedMonth.month &&
      _selectedDay!.day == day;

  // ── Logout ───────────────────────────────────────────────────────────────────

  Future<void> _performLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _playerService.clearCache();
    await _authService.signOut();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(Icons.calendar_month,
              color: colorScheme.secondary, size: 28),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'accountSettings') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AccountSettingsScreen()),
                );
              } else if (v == 'logout') {
                await _performLogout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'accountSettings',
                child: Row(children: [
                  Icon(Icons.manage_accounts, size: 20),
                  SizedBox(width: 12),
                  Text('Account Settings'),
                ]),
              ),
              PopupMenuDivider(),
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
      body: Column(
        children: [
          _buildMonthHeader(colorScheme),
          _buildWeekdayRow(colorScheme),
          _buildDayGrid(colorScheme),
          const Divider(height: 1),
          Expanded(child: _buildEventsList(colorScheme)),
        ],
      ),
    );
  }

  // ── Month header (prev / title / next) ───────────────────────────────────────

  Widget _buildMonthHeader(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previousMonth,
            tooltip: 'Previous month',
          ),
          Text(
            '${kMonthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextMonth,
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }

  // ── Weekday label row ────────────────────────────────────────────────────────

  Widget _buildWeekdayRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: kWeekdayLabels
            .map((label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── Day grid ─────────────────────────────────────────────────────────────────

  Widget _buildDayGrid(ColorScheme cs) {
    final totalCells = _startWeekday + _daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: List.generate(rows, (row) {
          return Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final dayNumber = cellIndex - _startWeekday + 1;

              if (dayNumber < 1 || dayNumber > _daysInMonth) {
                return const Expanded(child: SizedBox(height: 40));
              }

              final today = _isToday(dayNumber);
              final selected = _isSelected(dayNumber);

              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDay = DateTime(
                      _focusedMonth.year, _focusedMonth.month, dayNumber)),
                  child: Container(
                    height: 40,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary
                          : today
                              ? cs.secondary.withValues(alpha: 0.25)
                              : Colors.transparent,
                      shape: BoxShape.circle,
                      border: today && !selected
                          ? Border.all(color: cs.secondary, width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: today || selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: selected
                              ? cs.onPrimary
                              : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ),
    );
  }

  // ── Events list ──────────────────────────────────────────────────────────────

  Widget _buildEventsList(ColorScheme cs) {
    final label = _selectedDay != null
        ? '${kMonthNames[_selectedDay!.month - 1]} ${_selectedDay!.day}'
        : kMonthNames[_focusedMonth.month - 1];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Events — $label',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              Icon(Icons.event_note,
                  size: 56, color: cs.onSurface.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                'No events scheduled',
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Game and practice scheduling coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
