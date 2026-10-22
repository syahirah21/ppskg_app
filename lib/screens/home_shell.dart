import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/profile_drawer.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'search_screen.dart';

/// Bottom navigation between the dashboard, the map and the search/update
/// screen. All tabs stay alive so switching doesn't reload their data.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// The map is only built once the Peta tab is first opened.
  bool _mapOpened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: const ProfileDrawer(),
      // Opened only from the avatar, so edge swipes still pan the map.
      endDrawerEnableOpenDragGesture: false,
      // Every tab has a dark header strip, so status bar icons are white.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            IndexedStack(
              index: _index,
              children: [
                const DashboardScreen(),
                _mapOpened ? MapScreen(active: _index == 1) : const SizedBox(),
                const SearchScreen(),
              ],
            ),
            // Solid strip so scrolled content never shows under the
            // white status bar icons.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top,
              child: const ColoredBox(color: smartBrown),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          if (i == 1) _mapOpened = true;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Peta',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_search_outlined),
            selectedIcon: Icon(Icons.manage_search),
            label: 'Cari & Kemaskini',
          ),
        ],
      ),
    );
  }
}
