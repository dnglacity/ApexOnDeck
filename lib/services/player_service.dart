import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player.dart';
import '../models/app_user.dart';
import 'offline_cache_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// player_service.dart  (AOD v1.5)
//
// CHANGE (Notes.txt v1.5 — Unified users):
//
//   REMOVED:
//     • All references to the `coaches` table → replaced by `users`.
//     • All references to `team_coaches` table → replaced by `team_members`.
//     • All references to `player_accounts` table → replaced by `user_id` FK
//       directly on the `players` row + `team_members` row with role='player'.
//     • getCurrentCoach() → getCurrentUser() returning AppUser.
//     • getTeamCoaches() → getTeamMembers() returning List<TeamMember>.
//     • addCoachToTeam() → addMemberToTeam() with explicit role parameter.
//     • linkPlayerToAccount() rewritten to use the new `link_player_to_user`
//       RPC that sets players.user_id AND upserts a team_members row with
//       role='player'.
//
//   RENAMED RPCs (requires Supabase migration):
//     • create_team  → unchanged (same params).
//     • link_player_to_account → link_player_to_user.
//
//   Retained from v1.4:
//     • addPlayerAndReturnId(), getPlayersPaginated(), offline cache.
//     • getGameRoster* methods — unchanged.
// ─────────────────────────────────────────────────────────────────────────────

class PlayerService {
  final _supabase = Supabase.instance.client;
  final _cache = OfflineCacheService();

  // ===========================================================================
  // CURRENT USER HELPERS
  // ===========================================================================

  /// Returns the `users` table ID (not auth.uid) for the current session.
  ///
  /// CHANGE (v1.5): Was get_current_coach_id → get_current_user_id (renamed).
  /// Cached in-memory for the lifetime of the service instance because this
  /// is called frequently from helper methods.
  String? _cachedUserId; // public.users.id

  Future<String?> _getCurrentUserId() async {
    if (_cachedUserId != null) return _cachedUserId;
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) return null;
      final row = await _supabase
          .from('users')
          .select('id')
          .eq('user_id', authUser.id)
          .maybeSingle();
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
  /// Used by AddPlayerScreen so it can immediately auto-link the player.
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

      // Keep offline cache current.
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
  /// CHANGE (v1.5): Queries players.user_id directly instead of going through
  /// the old player_accounts join table.
  Future<Player?> getMyPlayerOnTeam(String teamId) async {
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) return null;

      // Resolve the public.users.id for this auth session.
      final userRow = await _supabase
          .from('users')
          .select('id')
          .eq('user_id', authUser.id)
          .maybeSingle();
      if (userRow == null) return null;

      final userId = userRow['id'] as String;

      // Query the players row that has this user_id on the given team.
      final playerRow = await _supabase
          .from('players')
          .select()
          .eq('team_id', teamId)
          .eq('user_id', userId)
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

  /// Returns all teams the current user belongs to (any role).
  ///
  /// CHANGE (v1.5): Queries `team_members` (was `team_coaches`).
  /// Each entry includes `role` so the UI can route to the correct screen.
  Future<List<Map<String, dynamic>>> getTeams() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) return [];

      final response = await _supabase
          .from('team_members')
          .select('team_id, role, player_id, teams(id, team_name, sport, created_at)')
          .eq('user_id', userId);

      return (response as List).map((item) {
        final team = item['teams'] as Map<String, dynamic>;
        final role = item['role'] as String;
        return {
          'id': team['id'],
          'team_name': team['team_name'],
          'sport': team['sport'],
          'created_at': team['created_at'],
          'role': role,
          // Convenience booleans for UI — derived from role.
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

  // CHANGE (v1.5): getPlayerLinkedTeams() is removed.
  // All team memberships (coach AND player) now come from a single call to
  // getTeams() which queries team_members and filters by role on the client.

  /// Creates a new team via the `create_team` SECURITY DEFINER RPC.
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
      // Invalidate cached user ID so next call re-resolves from DB.
    } catch (e) {
      debugPrint('Error creating team: $e');
      throw Exception('Error creating team: $e');
    }
  }

  /// Updates team name and sport.
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

  /// Deletes a team (cascades to players and team_members).
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
  // TEAM MEMBER OPERATIONS  (replaces COACH OPERATIONS)
  // ===========================================================================

  /// Returns the `users` row for the current auth session.
  ///
  /// CHANGE (v1.5): Was getCurrentCoach() → getCurrentUser().
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) return null;
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
  /// CHANGE (v1.5): Queries `team_members` joined with `users`.
  /// Was getTeamCoaches() which only returned coaches.
  Future<List<TeamMember>> getTeamMembers(String teamId) async {
    try {
      final response = await _supabase
          .from('team_members')
          .select('id, team_id, user_id, role, player_id, users(name, email, organization)')
          .eq('team_id', teamId)
          .order('role', ascending: true); // owners first, then coaches, then players

      return (response as List).map((m) => TeamMember.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching team members: $e');
      throw Exception('Error fetching team members: $e');
    }
  }

  /// Adds a user to a team with the specified [role].
  ///
  /// CHANGE (v1.5): Replaces addCoachToTeam(). Now accepts any role
  /// ('owner'|'coach'|'player').  Looks up the user by email in the
  /// `users` table (not `coaches`).
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

      // Check for duplicate membership.
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
  /// [playerEmail].
  ///
  /// CHANGE (v1.5): Calls the renamed `link_player_to_user` RPC.
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
  /// CHANGE (v1.5): Operates on `team_members` instead of `team_coaches`.
  /// When removing a player, also clears players.user_id.
  Future<void> removeMemberFromTeam(String teamId, String userId) async {
    try {
      final currentUserId = await _getCurrentUserId();
      if (currentUserId == null) throw Exception('Not logged in');

      final isRemovingSelf = userId == currentUserId;

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

      // If this member is linked to a player row, unlink it first.
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
  ///
  /// CHANGE (v1.5): Operates on `team_members` instead of `team_coaches`.
  Future<void> transferOwnership(String teamId, String newOwnerUserId) async {
    try {
      final isOwner = await _isTeamOwner(teamId);
      if (!isOwner) {
        throw Exception('Only the current owner can transfer ownership');
      }

      final currentUserId = await _getCurrentUserId();
      if (currentUserId == null) throw Exception('Not logged in');

      // Demote current owner → coach.
      await _supabase
          .from('team_members')
          .update({'role': 'coach'})
          .eq('team_id', teamId)
          .eq('user_id', currentUserId);

      // Promote new owner.
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

  /// Updates the role of an existing team member.
  ///
  /// NEW (v1.5): Allows owners to change a coach → player or vice-versa
  /// without removing and re-adding.  Cannot set role to 'owner' this way
  /// (use transferOwnership for that).
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
  // GAME ROSTER OPERATIONS  (unchanged from v1.4)
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