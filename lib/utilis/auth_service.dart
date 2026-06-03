import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _keyPass = "admin_password";
  static const String _keyDepotId = "depot_id";
  static const String _keyMagasinId = "magasin_id"; 
  static const String _keyRole = "user_role";

  static Future<void> setPassword(String newPass) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPass, newPass);
  }

  static Future<String> getPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPass) ?? "9596"; 
  }

  static Future<void> setDepotId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDepotId, id);
  }

  static Future<int?> getDepotId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDepotId);
  }

  // --- Gestion du Magasin ---
  static Future<void> setMagasinId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMagasinId, id);
  }

  static Future<int?> getMagasinId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyMagasinId); // Correction de la clé ici
  }

  // Alias pour la compatibilité avec l'ancien code
  static Future<void> setBoutiqueId(int id) => setMagasinId(id);
  static Future<int?> getBoutiqueId() => getMagasinId();

  static Future<void> setRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRole, role);
  }

  static Future<String> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRole) ?? "vendeur";
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDepotId);
    await prefs.remove(_keyMagasinId);
    await prefs.remove(_keyRole);
  }

  static const String _masterKey = "arsene@123";

  static Future<bool> resetPasswordWithMasterKey(String enteredMasterKey) async {
    if (enteredMasterKey == _masterKey) {
      await setPassword("9596");
      return true;
    }
    return false;
  }

  static Future<bool> isAppAuthorized() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool("app_authorized") ?? false;
  }

  static Future<bool> authorizeDevice(String code) async {
    if (code == _masterKey) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("app_authorized", true);
      return true;
    }
    return false;
  }
}
