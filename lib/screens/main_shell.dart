import 'package:flutter/material.dart';
import 'team_selection_screen.dart';
import 'calendar_screen.dart';

// =============================================================================
// main_shell.dart  (AOD v1.12)
//
// Root shell for authenticated users. Hosts a BottomNavigationBar with:
//   0 — Teams   (TeamSelectionScreen)
//   1 — Schedule (CalendarScreen)
//
// IndexedStack keeps both screens alive so scroll / load state is preserved
// when the user switches tabs.
// =============================================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _screens = <Widget>[
    TeamSelectionScreen(),
    CalendarScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Body is the active screen; IndexedStack keeps state across tab switches.
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withValues(alpha: 0.55),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: 'Teams',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
        ],
      ),
    );
  }
}
