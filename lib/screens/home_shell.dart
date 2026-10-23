import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/profile_drawer.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'search_screen.dart';

/// One tab of the app, shown in the bottom bar on phones and in the
/// sidebar on desktop.
typedef _Destination = ({
  IconData icon,
  IconData selectedIcon,
  String label,
  String subtitle,
});

const List<_Destination> _destinations = [
  (
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    label: 'Dashboard',
    subtitle: 'Ringkasan lot getah',
  ),
  (
    icon: Icons.map_outlined,
    selectedIcon: Icons.map,
    label: 'Peta',
    subtitle: 'Lot di atas peta',
  ),
  (
    icon: Icons.manage_search_outlined,
    selectedIcon: Icons.manage_search,
    label: 'Cari & Kemaskini',
    subtitle: 'Lot belum lengkap',
  ),
];

/// Navigation between the dashboard, the map and the search/update screen:
/// a bottom bar on phones, a SmartMap-style brown sidebar on desktop. All
/// tabs stay alive so switching doesn't reload their data.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// The map is only built once the Peta tab is first opened.
  bool _mapOpened = false;

  void _select(int i) => setState(() {
    _index = i;
    if (i == 1) _mapOpened = true;
  });

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    final pages = IndexedStack(
      index: _index,
      children: [
        const DashboardScreen(),
        _mapOpened ? MapScreen(active: _index == 1) : const SizedBox(),
        const SearchScreen(),
      ],
    );
    return Scaffold(
      endDrawer: const ProfileDrawer(),
      // Opened only from the avatar, so edge swipes still pan the map.
      endDrawerEnableOpenDragGesture: false,
      // Every tab has a dark header strip, so status bar icons are white.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: desktop
            ? Row(
                children: [
                  _Sidebar(selected: _index, onSelect: _select),
                  Expanded(child: pages),
                ],
              )
            : Stack(
                children: [
                  pages,
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
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}

/// Dark brown desktop sidebar: RISDA brand on top, the tabs, then the
/// signed-in officer at the bottom (opens the profile panel).
class _Sidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _Sidebar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [smartBrown, Color(0xFF362A1D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                Image.asset('assets/images/risda_logo.png', height: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PPSKG',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'RISDA · Lot Getah Malaysia',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'MENU',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white38,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final (i, d) in _destinations.indexed)
            _SidebarItem(
              destination: d,
              selected: i == selected,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: _SidebarProfile(),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? smartInk : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? smartGold : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: selected ? smartInk : smartGold,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        destination.subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: selected
                              ? smartInk.withValues(alpha: 0.7)
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The officer's initials, name and jawatan; tapping opens the profile.
class _SidebarProfile extends StatelessWidget {
  const _SidebarProfile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthService.user,
      builder: (context, user, _) => Material(
        color: Colors.white.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Scaffold.of(context).openEndDrawer(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: smartGold,
                  child: Text(
                    user?.initials ?? '?',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: smartInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        user?.jawatan ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: smartGold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_vert, size: 18, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
