import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// auth_service.dart  (AOD v1.5)
//
// CHANGE (Notes.txt v1.5 — Unified users):
//   All references to the `coaches` table are replaced with the `users` table.
//   The DB trigger `on_auth_user_created` now inserts into `users` (not
//   `coaches`).  The retry helper polls `users` instead of `coaches`.
//
//   getCurrentUser() returns an AppUser (from the `users` table).
//   The concept of "getting the current coach" is gone — there is only a user,
//   whose role is determined per-team from the `team_members` table.
// ─────────────────────────────────────────────────────────────────────────────

class AuthService {
  final _supabase = Supabase.instance.client;

  // ── Getters ───────────────────────────────────────────────────────────────

  /// The currently authenticated Supabase auth user, or null if not signed in.
  User? get currentUser => _supabase.auth.currentUser;

  /// True when a user is currently signed in.
  bool get isLoggedIn => currentUser != null;

  // ── Sign Up ───────────────────────────────────────────────────────────────

  /// Creates a new auth user and waits for the DB trigger to create the
  /// corresponding `users` row, then updates `organization` if provided.
  ///
  /// The DB trigger `on_auth_user_created` inserts into `public.users`
  /// using `name` and `email` from raw_user_meta_data / auth.users.
  ///
  /// BUG FIX (Bug 5 — retained from v1.4): Polling retry instead of fixed delay.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    String? organization,
  }) async {
    // Create the auth user. The DB trigger creates the public.users row.
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'name': name,
        'organization': organization,
      },
    );

    // If an organization was provided, update the users row once the trigger
    // has created it.
    if (response.user != null &&
        organization != null &&
        organization.isNotEmpty) {
      await _updateOrganizationWithRetry(response.user!.id, organization);
    }

    return response;
  }

  // ── Organization update retry ─────────────────────────────────────────────

  static const int _maxTriggerRetries = 5;
  static const Duration _triggerRetryDelay = Duration(milliseconds: 300);

  /// Polls until the `users` row for [authUserId] exists (created by the DB
  /// trigger), then writes [organization] to it.
  ///
  /// Failure is non-fatal — sign-up was still successful.
  Future<void> _updateOrganizationWithRetry(
      String authUserId, String organization) async {
    for (int attempt = 1; attempt <= _maxTriggerRetries; attempt++) {
      await Future.delayed(_triggerRetryDelay);
      try {
        // CHANGE (v1.5): poll `users` table instead of `coaches`.
        final existing = await _supabase
            .from('users')
            .select('id')
            .eq('user_id', authUserId)
            .maybeSingle();

        if (existing != null) {
          // Row exists — write the organization field.
          await _supabase
              .from('users')
              .update({'organization': organization})
              .eq('user_id', authUserId);
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Organization update attempt $attempt failed: $e');
      }
    }
    debugPrint(
        '⚠️ Could not update organization after $_maxTriggerRetries attempts.');
  }

  // ── Sign In ───────────────────────────────────────────────────────────────

  /// Signs in with email and password.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  /// Returns the raw `users` map for the currently signed-in user, or null.
  ///
  /// CHANGE (v1.5): Queries `users` table (was `coaches`).
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      final authUser = currentUser;
      if (authUser == null) return null;

      return await _supabase
          .from('users')
          .select()
          .eq('user_id', authUser.id)
          .single();
    } catch (e) {
      debugPrint('Get user profile error: $e');
      return null;
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────

  /// Signs the current user out.
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // ── Password Reset ────────────────────────────────────────────────────────

  /// Sends a password reset email to [email].
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  // ── Auth State Stream ─────────────────────────────────────────────────────

  /// Stream of auth state changes — used by [AuthWrapper] to react to
  /// sign-in and sign-out events.
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}