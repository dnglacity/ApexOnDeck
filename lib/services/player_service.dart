import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player.dart';
import '../models/app_user.dart';
import 'offline_cache_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// player_service.dart  (AOD v1.6)
//
// BUG FIX (Issue 1 — no team data on login):
//   getMyPlayerOnTeam() previously compared players.user_id to auth.uid().
//   players.user_id stores public.users.id (a different UUID to auth.users.id).
//   Fix: resolve public.users.id first via _getCurrentUserId(), then compare.
//
//   getTeams() previously called _getCurrentUserId() but would return [] when
//   that returned null (e.g. if the public.users trigger row had not yet been
//   committed at login).  Added a one-retry delay so new sign-ups work cleanly.
//
// OPTIMIZATION (Notes.txt v1.6):
//   • _getCurrentUserId() already caches in _cachedUserId; now also retried
//     once with a 500ms delay before giving up, reducing "no teams" on fresh
//     login when the DB trigger is slightly behind.
//   • getTeams() now explicitly orders by team_name for deterministic UI.
//   • getTeamMembers() now orders by name ASC within each role group for
//     a more predictable display order.
//
// All v1.5 changes retained (unified users, team_members, link_player_to_user).
// ─────────────────────────────────────────────────────────────────────────────

class PlayerService {
  final _supabase = Supabase.instance.client;
  final _cache = OfflineCacheService();

  // ===========================================================================
  // CURRENT USER HELPERS
  // ===========================================================================

  /// Returns the `public.users` table PK (`id`) for the current auth session.
  ///
  /// This bridges `auth.uid()` (auth.users.id) → public.users.id.
  /// Cached in-memory for the lifetime of the service instance because this
  /// is called by nearly every method.
  ///
  /// CHANGE (v1.6): Added one automatic retry with a 500 ms delay to handle
  /// the race condition where the on_auth_user_created trigger has not yet
  /// committed the users row when this is first called at login.
  String? _cachedUserId; // public.users.id

  Future<String?> _getCurrentUserId({bool allowRetry = true}) async {
    if (_cachedUserId != null) return _cachedUserId;
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) return null;

      final row = await _supabase
          .from('users')
          .select('id')
          .eq('user_id', authUser.id) // auth.users.id → public.users.user_id
          .maybeSingle();

      if (row == null && allowRetry) {
        // CHANGE (v1.6): Trigger may not have committed yet on first login.
        // Wait 500 ms and retry once.
        await Future.delayed(const Duration(milliseconds: 500));
        return _getCurrentUserId(allowRetry: false);
      }

      _cachedUserId = row?['id'] as String?;
      return _cachedUserId;
    } catch (e) {
      debugPrint('_getCurrentUserId error: $e');
      return null;
    }
  }

  /// Clears the cached user ID — call on sign-out.
  void clearCache() {
    _cachedUserId = null;
  }

  // ===========================================================================
  // PLAYER OPERATIONS
  // ===========================================================================

  /// Inserts a new player row (without returning the ID).
  Future<void> addPlayer(Player player) async {
    try {
      await _supabase.from('players').insert(player.toMap());
    } catch (e) {
      debugPrint('Error adding player: $e');
      throw Exception('Error adding player: $e');
    }
  }

  /// Inserts a new player and returns the generated UUID.
  ///
  /// Used by AddPlayerScreen to immediately auto-link the player by ID.
  Future<String> addPlayerAndReturnId(Player player) async {
    try {
      final result = await _supabase
          .from('players')
          .insert(player.toMap())
          .select('id')
          .single();
      return result['id'] as String;
    } catch (e) {
      debugPrint('Error adding player: $e');
      throw Exception('Error adding player: $e');
    }
  }

  /// Fetches ALL players for [teamId], ordered by name.
  ///
  /// Used internally (game roster restoration, bulk actions).
  /// For the paginated UI list use [getPlayersPaginated].
  Future<List<Player>> getPlayers(String teamId) async {
    try {
      final response = await _supabase
          .from('players')
          .select()
          .eq('team_id', teamId)
          .order('name', ascending: true);

      final players = (response as List).map((d) => Player.fromMap(d)).toList();

      // Keep offline cache current after a successful network fetch.
      await _cache.writeList(
        OfflineCacheService.playersKey(teamId),
        players.map((p) => p.toMap()..['id'] = p.id).toList(),
      );

      return players;
    } catch (e) {
      debugPrint('Error fetching players — checking cache: $e');
      if (e is SocketException || e.toString().contains('network')) {
        final cached =
            await _cache.readList(OfflineCacheService.playersKey(teamId));
        if (cached != null) {
          return cached.map((d) => Player.fromMap(d)).toList();
        }
      }
      throw Exception('Error fetching players: $e');
    }
  }

  /// Paginated player fetch using Supabase .range() for infinite-scroll.
  Future<List<Player>> getPlayersPaginated({
    required String teamId,
    required int from,
    required int to,
  }) async {
    try {
      final response = await _supabase
          .from('players')
          .select()
          .eq('team_id', teamId)
          .order('name', ascending: true)
          .range(from, to);

      return (response as List).map((d) => Player.fromMap(d)).toList();
    } catch (e) {
      debugPrint('Error fetching paginated players: $e');
      // Fall back to cached first page only when offset is 0.
      if (from == 0 &&
          (e is SocketException || e.toString().contains('network'))) {
        final cached =
            await _cache.readList(OfflineCacheService.playersKey(teamId));
        if (cached != null) {
          return cached
              .map((d) => Player.fromMap(d))
              .skip(from)
              .take(to - from + 1)
              .toList();
        }
      }
      throw Exception('Error fetching players: $e');
    }
  }

  /// Returns the Player row linked to the current user on [teamId].
  ///
  /// BUG FIX (v1.6 — Issue 1):
  ///   The previous implementation resolved the public.users.id correctly
  ///   but then compared `players.user_id` to `auth.uid()` in the query,
  ///   which is always false because players.user_id = public.users.id, not
  ///   auth.users.id.  Now uses the resolved userId from _getCurrentUserId().
  Future<Player?> getMyPlayerOnTeam(String teamId) async {
    try {
      // Resolve the public.users.id for this auth session.
      // This is the value stored in players.user_id.
      final userId = await _getCurrentUserId();
      if (userId == null) return null;

      // BUG FIX (v1.6): Compare players.user_id to public.users.id (userId),
      // NOT to auth.uid() (auth.users.id) — they are different UUIDs.
      final playerRow = await _supabase
          .from('players')
          .select()
          .eq('team_id', teamId)
          .eq('user_id', userId) // public.users.id, not auth.uid()
          .maybeSingle();

      if (playerRow == null) return null;
      return Player.fromMap(playerRow);
    } catch (e) {
      debugPrint('Error fetching my player: $e');
      return null;
    }
  }

  /// Real-time stream of players for [teamId].
  Stream<List<Player>> getPlayerStream(String teamId) {
    return _supabase
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('team_id', teamId)
        .order('name', ascending: true)
        .map((maps) => maps.map((m) => Player.fromMap(m)).toList());
  }

  /// Overwrites all mutable fields for a player row.
  Future<void> updatePlayer(Player player) async {
    try {
      await _supabase
          .from('players')
          .update(player.toMap())
          .eq('id', player.id);
    } catch (e) {
      debugPrint('Error updating player: $e');
      throw Exception('Error updating player: $e');
    }
  }

  /// Updates only the `status` field for a single player.
  Future<void> updatePlayerStatus(String playerId, String status) async {
    try {
      await _supabase
          .from('players')
          .update({'status': status}).eq('id', playerId);
    } catch (e) {
      debugPrint('Error updating status: $e');
      throw Exception('Error updating status: $e');
    }
  }

  /// Sets [status] on every player in [teamId] in a single query.
  Future<void> bulkUpdateStatus(String teamId, String status) async {
    try {
      await _supabase
          .from('players')
          .update({'status': status}).eq('team_id', teamId);
    } catch (e) {
      debugPrint('Error bulk updating status: $e');
      throw Exception('Error bulk updating status: $e');
    }
  }

  /// Deletes players by [playerIds] in a single query.
  Future<void> bulkDeletePlayers(List<String> playerIds) async {
    if (playerIds.isEmpty) return;
    try {
      await _supabase.from('players').delete().inFilter('id', playerIds);
    } catch (e) {
      debugPrint('Error bulk deleting: $e');
      throw Exception('Error bulk deleting players: $e');
    }
  }

  /// Deletes a single player by [id].
  Future<void> deletePlayer(String id) async {
    try {
      await _supabase.from('players').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting player: $e');
      throw Exception('Failed to delete player: $e');
    }
  }

  /// Returns attendance summary counts. Falls back to all-zeros on error.
  Future<Map<String, int>> getAttendanceSummary(String teamId) async {
    try {
      final players = await getPlayers(teamId);
      final summary = {'present': 0, 'absent': 0, 'late': 0, 'excused': 0};
      for (final p in players) {
        summary[p.status] = (summary[p.status] ?? 0) + 1;
      }
      return summary;
    } catch (e) {
      debugPrint('Error getting attendance: $e');
      return {'present': 0, 'absent': 0, 'late': 0, 'excused': 0};
    }
  }

  // ===========================================================================
  // TEAM OPERATIONS
  // ===========================================================================

  /// Returns all teams the current user belongs to (any role), sorted by name.
  ///
  /// CHANGE (v1.6): Added team_name ordering for deterministic display.
  ///   Added _getCurrentUserId() retry guard — on fresh login the users trigger
  ///   may not have committed; the retry in _getCurrentUserId() handles this
  ///   automatically, but we also throw a descriptive error if it still fails.
  Future<List<Map<String, dynamic>>> getTeams() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) {
        // If still null after retry, the users profile row may not exist yet.
        // Caller (TeamSelectionScreen) shows an error + Retry button.
        throw Exception(
            'User profile not found. Please sign out and sign in again.');
      }

      final response = await _supabase
          .from('team_members')
          .select(
            'team_id, role, player_id, '
            'teams(id, team_name, sport, created_at)',
          )
          .eq('user_id', userId) // public.users.id — matches team_members.user_id
          .order('teams(team_name)', ascending: true); // CHANGE (v1.6): deterministic order

      return (response as List).map((item) {
        final team = item['teams'] as Map<String, dynamic>;
        final role = item['role'] as String;
        return {
          'id': team['id'],
          'team_name': team['team_name'],
          'sport': team['sport'],
          'created_at': team['created_at'],
          'role': role,
          // Convenience booleans derived from role — used by UI widgets.
          'is_owner': role == 'owner',
          'is_coach': role == 'coach' || role == 'owner',
          'is_player': role == 'player',
          'player_id': item['player_id'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching teams: $e');
      throw Exception('Error fetching teams: $e');
    }
  }

  /// Creates a new team via the `create_team` SECURITY DEFINER RPC.
  /// The RPC inserts the team row and the owner team_members row atomically.
  Future<void> createTeam(String teamName, String sport) async {
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) {
        throw Exception('You must be logged in to create a team.');
      }
      await _supabase.rpc('create_team', params: {
        'p_team_name': teamName,
        'p_sport': sport,
      });
    } catch (e) {
      debugPrint('Error creating team: $e');
      throw Exception('Error creating team: $e');
    }
  }

  /// Updates team name and sport. Owner-only (enforced by DB policy).
  Future<void> updateTeam(String teamId, String teamName, String sport) async {
    try {
      await _supabase.from('teams').update({
        'team_name': teamName,
        'sport': sport,
      }).eq('id', teamId);
    } catch (e) {
      debugPrint('Error updating team: $e');
      throw Exception('Error updating team: $e');
    }
  }

  /// Deletes a team (cascades to players and team_members via FK).
  Future<void> deleteTeam(String teamId) async {
    try {
      final isOwner = await _isTeamOwner(teamId);
      if (!isOwner) {
        throw Exception('Only team owners can delete teams');
      }
      await _supabase.from('teams').delete().eq('id', teamId);
    } catch (e) {
      debugPrint('Error deleting team: $e');
      throw Exception('Error deleting team: $e');
    }
  }

  /// Returns the full team row or null.
  Future<Map<String, dynamic>?> getTeam(String teamId) async {
    try {
      return await _supabase
          .from('teams')
          .select()
          .eq('id', teamId)
          .single();
    } catch (e) {
      debugPrint('Error fetching team: $e');
      return null;
    }
  }

  // ── Internal ownership/membership checks ─────────────────────────────────

  /// Returns true if the current user has role='owner' on [teamId].
  Future<bool> _isTeamOwner(String teamId) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) return false;
      final result = await _supabase
          .from('team_members')
          .select('role')
          .eq('team_id', teamId)
          .eq('user_id', userId)
          .maybeSingle();
      return result?['role'] == 'owner';
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the current user has role='coach' or 'owner' on [teamId].
  Future<bool> _isCoachOrOwner(String teamId) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) return false;
      final result = await _supabase
          .from('team_members')
          .select('role')
          .eq('team_id', teamId)
          .eq('user_id', userId)
          .maybeSingle();
      final role = result?['role'] as String?;
      return role == 'owner' || role == 'coach';
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // TEAM MEMBER OPERATIONS
  // ===========================================================================

  /// Returns the `public.users` row for the current auth session.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) return null;
      // Select by auth.users.id stored in users.user_id column.
      return await _supabase
          .from('users')
          .select()
          .eq('user_id', authUser.id)
          .single();
    } catch (e) {
      debugPrint('Error fetching user: $e');
      return null;
    }
  }

  /// Returns all members of [teamId] with their role and user profile.
  ///
  /// CHANGE (v1.6): Orders by role then name so owners appear first,
  /// followed by coaches alphabetically, then players alphabetically.
  Future<List<TeamMember>> getTeamMembers(String teamId) async {
    try {
      final response = await _supabase
          .from('team_members')
          .select(
            'id, team_id, user_id, role, player_id, '
            'users(name, email, organization)',
          )
          .eq('team_id', teamId)
          .order('role',  ascending: true)  // owner < coach < player lexically
          .order('users(name)', ascending: true); // alpha within each role

      return (response as List).map((m) => TeamMember.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching team members: $e');
      throw Exception('Error fetching team members: $e');
    }
  }

  /// Adds a user to a team with the specified [role].
  /// Looks up the user by email in `public.users`.
  Future<void> addMemberToTeam({
    required String teamId,
    required String userEmail,
    required String role,
  }) async {
    try {
      // Resolve the user by email in the public.users table.
      final userResult = await _supabase
          .from('users')
          .select('id')
          .eq('email', userEmail)
          .maybeSingle();

      if (userResult == null) {
        throw Exception('No account found for email: $userEmail. '
            'The person must sign up first.');
      }

      final newUserId = userResult['id'] as String;

      // Prevent duplicate membership.
      final existing = await _supabase
          .from('team_members')
          .select('id')
          .eq('team_id', teamId)
          .eq('user_id', newUserId)
          .maybeSingle();

      if (existing != null) {
        throw Exception('This person is already a member of the team.');
      }

      await _supabase.from('team_members').insert({
        'team_id': teamId,
        'user_id': newUserId,
        'role': role,
        // player_id is null until explicitly linked to a player row.
      });
    } catch (e) {
      debugPrint('Error adding member: $e');
      throw Exception('Error adding member: $e');
    }
  }

  /// Links [playerId] on [teamId] to the app account registered under
  /// [playerEmail] via the `link_player_to_user` SECURITY DEFINER RPC.
  ///
  /// The RPC sets `players.user_id` and upserts a `team_members` row with
  /// role='player' and player_id pointing to the roster row.
  Future<void> linkPlayerToAccount({
    required String teamId,
    required String playerId,
    required String playerEmail,
  }) async {
    try {
      await _supabase.rpc('link_player_to_user', params: {
        'p_team_id': teamId,
        'p_player_id': playerId,
        'p_player_email': playerEmail,
      });
    } catch (e) {
      debugPrint('Error linking player: $e');
      final msg = e.toString();
      if (msg.contains('No user found')) {
        throw Exception(
            'No account found for $playerEmail. The player must sign up first.');
      } else if (msg.contains('No player found')) {
        throw Exception('Player not found on this team.');
      }
      throw Exception('Error linking player: $e');
    }
  }

  /// Removes [userId] (public.users.id) from [teamId].
  ///
  /// When removing a linked player member, also clears players.user_id.
  /// Cannot remove the last owner; use transferOwnership first.
  Future<void> removeMemberFromTeam(String teamId, String userId) async {
    try {
      final currentUserId = await _getCurrentUserId();
      if (currentUserId == null) throw Exception('Not logged in');

      final isRemovingSelf = userId == currentUserId;

      // Non-self removal requires the caller to be an owner.
      if (!isRemovingSelf) {
        final ownerRow = await _supabase
            .from('team_members')
            .select('role')
            .eq('team_id', teamId)
            .eq('user_id', currentUserId)
            .maybeSingle();
        if (ownerRow == null || ownerRow['role'] != 'owner') {
          throw Exception('Only team owners can remove other members.');
        }
      }

      // Guard: cannot remove the last owner.
      final memberRow = await _supabase
          .from('team_members')
          .select('role, player_id')
          .eq('team_id', teamId)
          .eq('user_id', userId)
          .single();

      if (memberRow['role'] == 'owner') {
        final owners = await _supabase
            .from('team_members')
            .select('id')
            .eq('team_id', teamId)
            .eq('role', 'owner');
        if ((owners as List).length <= 1) {
          throw Exception(
              'Cannot remove the only owner. Transfer ownership first.');
        }
      }

      // Unlink the player row before deleting the member row.
      final linkedPlayerId = memberRow['player_id'] as String?;
      if (linkedPlayerId != null) {
        await _supabase
            .from('players')
            .update({'user_id': null}).eq('id', linkedPlayerId);
      }

      await _supabase
          .from('team_members')
          .delete()
          .eq('team_id', teamId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Error removing member: $e');
      throw Exception('Error removing member: $e');
    }
  }

  /// Transfers the 'owner' role from the current user to [newOwnerUserId].
  /// Current owner is demoted to 'coach'.
  Future<void> transferOwnership(String teamId, String newOwnerUserId) async {
    try {
      final isOwner = await _isTeamOwner(teamId);
      if (!isOwner) {
        throw Exception('Only the current owner can transfer ownership');
      }

      final currentUserId = await _getCurrentUserId();
      if (currentUserId == null) throw Exception('Not logged in');

      // Demote current owner to coach.
      await _supabase
          .from('team_members')
          .update({'role': 'coach'})
          .eq('team_id', teamId)
          .eq('user_id', currentUserId);

      // Promote the new owner.
      await _supabase
          .from('team_members')
          .update({'role': 'owner'})
          .eq('team_id', teamId)
          .eq('user_id', newOwnerUserId);
    } catch (e) {
      debugPrint('Error transferring ownership: $e');
      throw Exception('Error transferring ownership: $e');
    }
  }

  /// Updates the role of an existing team member (owner-only).
  /// Cannot set role to 'owner' — use transferOwnership() for that.
  Future<void> updateMemberRole({
    required String teamId,
    required String userId,
    required String newRole,
  }) async {
    if (newRole == 'owner') {
      throw Exception('Use transferOwnership() to assign the owner role.');
    }
    try {
      final isOwner = await _isTeamOwner(teamId);
      if (!isOwner) {
        throw Exception('Only team owners can change member roles.');
      }
      await _supabase
          .from('team_members')
          .update({'role': newRole})
          .eq('team_id', teamId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Error updating member role: $e');
      throw Exception('Error updating member role: $e');
    }
  }

  // ===========================================================================
  // GAME ROSTER OPERATIONS  (unchanged from v1.5)
  // ===========================================================================

  Future<List<Map<String, dynamic>>> getGameRosters(String teamId) async {
    try {
      final response = await _supabase
          .from('game_rosters')
          .select()
          .eq('team_id', teamId)
          .order('created_at', ascending: false);

      final rows = (response as List).cast<Map<String, dynamic>>();
      await _cache.writeList(
          OfflineCacheService.gameRostersKey(teamId), rows);
      return rows;
    } catch (e) {
      debugPrint('Error fetching game rosters: $e');
      if (e is SocketException || e.toString().contains('network')) {
        final cached = await _cache
            .readList(OfflineCacheService.gameRostersKey(teamId));
        if (cached != null) return cached;
      }
      throw Exception('Error fetching game rosters: $e');
    }
  }

  Future<Map<String, dynamic>?> getGameRosterById(String rosterId) async {
    try {
      return await _supabase
          .from('game_rosters')
          .select()
          .eq('id', rosterId)
          .maybeSingle();
    } catch (e) {
      debugPrint('Error fetching game roster by id: $e');
      return null;
    }
  }

  /// Realtime stream of game rosters for [teamId], newest first.
  /// Uses .stream() with a client-side team_id filter because Supabase
  /// .stream() does not support server-side eq() filters.
  Stream<List<Map<String, dynamic>>> getGameRosterStream(String teamId) {
    return _supabase
        .from('game_rosters')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((r) => r['team_id'] == teamId)
            .cast<Map<String, dynamic>>()
            .toList());
  }

  Future<String> createGameRoster({
    required String teamId,
    required String title,
    String? gameDate,
    int starterSlots = 5,
  }) async {
    try {
      final userId = await _getCurrentUserId();

      final result = await _supabase
          .from('game_rosters')
          .insert({
            'team_id': teamId,
            'title': title,
            'game_date': gameDate,
            'starter_slots': starterSlots,
            'starters': [],
            'substitutes': [],
            if (userId != null) 'created_by': userId,
          })
          .select('id')
          .single();

      return result['id'] as String;
    } catch (e) {
      debugPrint('Error creating game roster: $e');
      throw Exception('Error creating game roster: $e');
    }
  }

  Future<void> updateGameRosterLineup({
    required String rosterId,
    required List<Map<String, dynamic>> starters,
    required List<Map<String, dynamic>> substitutes,
  }) async {
    try {
      await _supabase.from('game_rosters').update({
        'starters': starters,
        'substitutes': substitutes,
      }).eq('id', rosterId);
    } catch (e) {
      debugPrint('Error updating game roster: $e');
      throw Exception('Error updating game roster lineup: $e');
    }
  }

  Future<void> deleteGameRoster(String rosterId) async {
    try {
      await _supabase.from('game_rosters').delete().eq('id', rosterId);
    } catch (e) {
      debugPrint('Error deleting game roster: $e');
      throw Exception('Error deleting game roster: $e');
    }
  }
}