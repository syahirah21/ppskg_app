import 'package:flutter/foundation.dart';

/// The officer currently signed in.
class AuthUser {
  final String username;

  /// Name shown in the app and filled in as "Nama pegawai" when editing.
  final String displayName;

  /// Job title, shown in the profile panel.
  final String jawatan;

  /// Office the officer belongs to, e.g. "RISDA Daerah Kuala Pilah".
  final String pejabat;

  final String negeri;

  final String emel;

  /// When this session started.
  final DateTime loginAt;

  const AuthUser({
    required this.username,
    required this.displayName,
    required this.jawatan,
    required this.pejabat,
    required this.negeri,
    required this.emel,
    required this.loginAt,
  });

  /// Up to two initials for the avatar, e.g. "Nur Aisyah" -> "NA".
  String get initials {
    final words = displayName.trim().split(RegExp(r'\s+'));
    return words.take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
  }
}

/// Thrown by [AuthService.login] with a message to show on the login form.
class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Signs officers in and out. The app shows the login screen whenever
/// [user] is null.
///
/// There is no backend yet: [login] only accepts the one shared account
/// below. Replace the body of [login] with the real call (e.g. ArcGIS
/// generateToken or the SmartMap API) once it's decided; nothing else
/// needs to change.
class AuthService {
  AuthService._();

  static const String _demoUsername = '123';
  static const String _demoPassword = 'Risda123';
  // Dummy officer until real staff records are connected.
  static const String _demoName = 'NUR AISYAH BINTI AHMAD';
  static const String _demoJawatan = 'Pegawai Pembangunan Pekebun Kecil';
  static const String _demoPejabat = 'RISDA Daerah Kuala Pilah';
  static const String _demoNegeri = 'Negeri Sembilan';
  static const String _demoEmel = 'nur.aisyah@risda.gov.my';

  static final user = ValueNotifier<AuthUser?>(null);

  static Future<void> login(String username, String password) async {
    final id = username.trim();
    if (id.isEmpty) throw const AuthException('Masukkan ID pengguna');
    if (password.isEmpty) throw const AuthException('Masukkan kata laluan');
    // Placeholder for the network round trip.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (id != _demoUsername || password != _demoPassword) {
      throw const AuthException('ID pengguna atau kata laluan salah');
    }
    user.value = AuthUser(
      username: id,
      displayName: _demoName,
      jawatan: _demoJawatan,
      pejabat: _demoPejabat,
      negeri: _demoNegeri,
      emel: _demoEmel,
      loginAt: DateTime.now(),
    );
  }

  static void logout() => user.value = null;
}
