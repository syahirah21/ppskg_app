import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/theme_toggle.dart';

/// Sign-in page shown before the app. Brown SmartMap header with the RISDA
/// logo, then the ID and password form on the cream page.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.login(_username.text, _password.text);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal log masuk: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final form = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Log Masuk',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Masukkan ID pengguna dan kata laluan anda',
                  style: theme.textTheme.bodySmall?.copyWith(color: smartMuted),
                ),
                const SizedBox(height: 24),
                Text('ID pengguna', style: labelStyle),
                const SizedBox(height: 8),
                TextField(
                  controller: _username,
                  enabled: !_loading,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                  decoration: _decoration(
                    theme,
                    hint: 'cth: ali.ahmad',
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Kata laluan', style: labelStyle),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  enabled: !_loading,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration:
                      _decoration(
                        theme,
                        hint: 'Kata laluan',
                        icon: Icons.lock_outline,
                      ).copyWith(
                        suffixIcon: IconButton(
                          tooltip: _obscure
                              ? 'Tunjuk kata laluan'
                              : 'Sembunyi kata laluan',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: smartOrange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: smartOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Log Masuk',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Untuk kegunaan pegawai RISDA sahaja',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: smartMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (isDesktop(context)) {
      return Scaffold(
        body: Row(
          children: [
            const Expanded(flex: 5, child: _BrandPanel()),
            Expanded(
              flex: 4,
              child: Center(child: SingleChildScrollView(child: form)),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(gradient: headerGradient),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      MediaQuery.paddingOf(context).top + 48,
                      24,
                      40,
                    ),
                    child: Column(
                      children: [
                        Image.asset('assets/images/risda_logo.png', height: 72),
                        const SizedBox(height: 14),
                        Text(
                          'PPSKG',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'RISDA · Lot Getah Malaysia',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  form,
                ],
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              right: 12,
              child: const ThemeModeButton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bordered field matching the edit pop-up's inputs.
InputDecoration _decoration(
  ThemeData theme, {
  required String hint,
  required IconData icon,
}) => InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(
    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
  ),
  filled: true,
  fillColor: theme.colorScheme.surface,
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: smartBorder.withValues(alpha: 0.9)),
  ),
  disabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: smartBorder.withValues(alpha: 0.5)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: smartGold, width: 1.5),
  ),
  prefixIcon: Icon(icon, size: 20),
);

/// Left half of the desktop login: RISDA brand on the brown gradient, with
/// the three things the app does.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(gradient: headerGradient),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            right: -120,
            bottom: -100,
            child: Opacity(
              opacity: 0.06,
              child: Image.asset('assets/images/risda_logo.png', width: 520),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset('assets/images/risda_logo.png', height: 84),
                    const SizedBox(height: 24),
                    Text(
                      'PPSKG',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RISDA · Lot Getah Malaysia',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: smartGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 36),
                    const _Feature(
                      icon: Icons.dashboard_outlined,
                      title: 'Dashboard',
                      text: 'Ringkasan lot getah mengikut negeri dan status',
                    ),
                    const _Feature(
                      icon: Icons.map_outlined,
                      title: 'Peta',
                      text: 'Lihat lot getah sebenar di atas peta',
                    ),
                    const _Feature(
                      icon: Icons.manage_search_outlined,
                      title: 'Cari & Kemaskini',
                      text: 'Lengkapkan status torehan dan tahun tanam',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Feature({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: smartGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: smartGold.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: 20, color: smartGold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
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
