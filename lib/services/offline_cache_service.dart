import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// offline_cache_service.dart  (AOD v1.3 — NEW)
//
// Provides a lightweight JSON cache backed by shared_preferences.
// Used by PlayerService to persist players and game_rosters locally so
// the app remains functional in gyms with poor or no network signal.
//
// DEPENDENCY: Add to pubspec.yaml:
//   shared_preferences: ^2.3.2
//   (or whatever the current stable version is at build time)
//
// DESIGN:
//   • Cache entries are stored as JSON strings under namespaced keys, e.g.:
//       "aod_players_<teamId>"
//       "aod_game_rosters_<teamId>"
//   • Each cache entry includes an ISO-8601 timestamp so stale data can be
//     detected and optionally ignored.
//   • The service is intentionally low-level; PlayerService wraps it with
//     the correct type conversions.
//
// OFFLINE STRATEGY (used in PlayerService):
//   1. Try Supabase fetch.
//   2. On success → write result to cache and return it.
//   3. On failure (SocketException, etc.) → read from cache and return stale
//      data with a warning.
//   4. On reconnect (next successful fetch) → overwrite the cache.
// ─────────────────────────────────────────────────────────────────────────────

class OfflineCacheService {
  // Singleton — one SharedPreferences instance per app lifecycle.
  static OfflineCacheService? _instance;
  SharedPreferences? _prefs;

  OfflineCacheService._();

  /// Returns the singleton instance.  Call [init()] before first use.
  factory OfflineCacheService() {
    _instance ??= OfflineCacheService._();
    return _instance!;
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Must be awaited once during app startup (e.g., in main() or initState).
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Internal key prefix — prevents collisions with other packages.
  static const _prefix = 'aod_cache_';

  // ── Write ───────────────────────────────────────────────────────────────────

  /// Stores [data] as a JSON-encoded list under [key].
  /// Also writes a companion timestamp key for staleness detection.
  Future<void> writeList(String key, List<Map<String, dynamic>> data) async {
    try {
      await _ensureInitialised();
      final entry = {
        'timestamp': DateTime.now().toIso8601String(),
        'data': data,
      };
      await _prefs!.setString('$_prefix$key', jsonEncode(entry));
    } catch (e) {
      // Cache writes are non-fatal — log and continue.
      debugPrint('⚠️ OfflineCacheService.writeList error: $e');
    }
  }

  // ── Read ────────────────────────────────────────────────────────────────────

  /// Returns the cached list for [key], or null if no cache exists.
  ///
  /// [maxAgeMinutes] — if the cached entry is older than this many minutes,
  /// null is returned (treats the cache as expired).  Pass null to always
  /// return cached data regardless of age.
  Future<List<Map<String, dynamic>>?> readList(
    String key, {
    int? maxAgeMinutes,
  }) async {
    try {
      await _ensureInitialised();
      final raw = _prefs!.getString('$_prefix$key');
      if (raw == null) return null;

      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final timestamp = DateTime.tryParse(entry['timestamp'] as String? ?? '');

      // Check staleness.
      if (maxAgeMinutes != null && timestamp != null) {
        final age = DateTime.now().difference(timestamp);
        if (age.inMinutes > maxAgeMinutes) {
          debugPrint('OfflineCacheService: cache "$key" expired (${age.inMinutes}m)');
          return null;
        }
      }

      final data = (entry['data'] as List)
          .cast<Map<String, dynamic>>();
      return data;
    } catch (e) {
      debugPrint('⚠️ OfflineCacheService.readList error: $e');
      return null;
    }
  }

  // ── Metadata ────────────────────────────────────────────────────────────────

  /// Returns the timestamp of the last write for [key], or null.
  Future<DateTime?> lastUpdated(String key) async {
    try {
      await _ensureInitialised();
      final raw = _prefs!.getString('$_prefix$key');
      if (raw == null) return null;
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      return DateTime.tryParse(entry['timestamp'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  // ── Invalidate ─────────────────────────────────────────────────────────────

  /// Removes a single cache entry.
  Future<void> invalidate(String key) async {
    try {
      await _ensureInitialised();
      await _prefs!.remove('$_prefix$key');
    } catch (e) {
      debugPrint('⚠️ OfflineCacheService.invalidate error: $e');
    }
  }

  /// Clears ALL cache entries written by this service.
  Future<void> clearAll() async {
    try {
      await _ensureInitialised();
      final keys = _prefs!.getKeys().where((k) => k.startsWith(_prefix));
      for (final k in keys) {
        await _prefs!.remove(k);
      }
    } catch (e) {
      debugPrint('⚠️ OfflineCacheService.clearAll error: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _ensureInitialised() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Convenience key builders ────────────────────────────────────────────────

  /// Cache key for the player list of a team.
  static String playersKey(String teamId) => 'players_$teamId';

  /// Cache key for the game_rosters list of a team.
  static String gameRostersKey(String teamId) => 'game_rosters_$teamId';
}