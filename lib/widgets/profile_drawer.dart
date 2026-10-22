import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

/// Round gold avatar with the signed-in officer's initials, for the
/// Dashboard header. Tapping it opens the [ProfileDrawer].
class ProfileAvatarButton extends StatelessWidget {
  final VoidCallback onTap;

  const ProfileAvatarButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthService.user,
      builder: (context, user, _) => Tooltip(
        message: 'Profil',
        child: Material(
          color: smartGold,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white24, width: 2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: Text(
                  user?.initials ?? '?',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: smartInk, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel that slides in from the right with the officer's profile, the
/// current session and the logout button.
class ProfileDrawer extends StatelessWidget {
  const ProfileDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.user.value;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Drawer(
      width: 310,
      backgroundColor: smartCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHeader(user: user),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                const _SectionLabel('Maklumat pegawai'),
                _InfoCard(
                  children: [
                    _InfoTile(
                      icon: Icons.apartment_outlined,
                      label: 'Pejabat',
                      value: user?.pejabat ?? '-',
                    ),
                    _InfoTile(
                      icon: Icons.place_outlined,
                      label: 'Negeri',
                      value: user?.negeri ?? '-',
                    ),
                    _InfoTile(
                      icon: Icons.mail_outline,
                      label: 'Emel',
                      value: user?.emel ?? '-',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Sesi'),
                _InfoCard(
                  children: [
                    _InfoTile(
                      icon: Icons.schedule,
                      label: 'Log masuk',
                      value: user == null ? '-' : _fmtLoginAt(user.loginAt),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: smartBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text(
                    'Log keluar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: smartOrange.withValues(alpha: 0.1),
                    foregroundColor: smartOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'RISDA · Lot Getah Malaysia',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: smartMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Brown header: faded RISDA logo behind, avatar with a gold ring, name,
/// jawatan badge and the ID / status chips.
class _ProfileHeader extends StatelessWidget {
  final AuthUser? user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(gradient: headerGradient),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            bottom: -30,
            child: Opacity(
              opacity: 0.07,
              child: Image.asset('assets/images/risda_logo.png', width: 190),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 8,
              8,
              22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PROFIL PEGAWAI',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white60,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: smartGold, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: smartGold,
                    child: Text(
                      user?.initials ?? '?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: smartInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    user?.displayName ?? '-',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: smartGold.withValues(alpha: 0.16),
                    border: Border.all(
                      color: smartGold.withValues(alpha: 0.45),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    user?.jawatan ?? '-',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: smartGold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _HeaderChip(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.badge_outlined,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 5),
                          Text('ID ${user?.username ?? '-'}'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HeaderChip(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6FCF7A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Aktif'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final Widget child;

  const _HeaderChip({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
        child: child,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: smartMuted,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// White card holding [_InfoTile]s, with thin dividers between them.
class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: smartBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 60, color: smartBorder),
            child,
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: smartGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: smartGoldDeep),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: smartMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// E.g. "Hari ini, 3:05 PTG" (PG before noon, PTG after).
String _fmtLoginAt(DateTime t) {
  final now = DateTime.now();
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final time = '$h:$m ${t.hour < 12 ? 'PG' : 'PTG'}';
  return today ? 'Hari ini, $time' : '${t.day}/${t.month}/${t.year}, $time';
}

/// Asks before signing out, so a stray tap doesn't drop the officer back
/// to the login page.
Future<void> _confirmLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Log keluar?'),
      content: Text(
        'Anda log masuk sebagai ${AuthService.user.value?.displayName ?? '-'}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log keluar'),
        ),
      ],
    ),
  );
  if (ok == true) AuthService.logout();
}
