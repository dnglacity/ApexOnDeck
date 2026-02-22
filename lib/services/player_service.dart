import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sweatdex/models/player.dart';
import 'offline_cache_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// player_service.dart  (AOD v1.4)
//
// CHANGES (v1.4):
//
//   NEW — addPlayerAndReturnId():
//     Inserts a player row and returns the generated UUID so AddPlayerScreen
//     can immediately call linkPlayerToAccount() without a second round-trip.
//
//   CHANGE — getPlayersPaginated():
//     New method that accepts [from] and [to] row indices and calls
//     Supabase .range(from, to) for infinite-scroll pagination.
//     RosterScreen now calls this instead of the bulk getPlayers().
//     getPlayers() is kept for internal callers (game roster restoration,
//     attendance summary, etc.) that need the full list.
//
//   All changes from v1.3 are retained unchanged.
// ─────────────────────────────────────────────────────────────────────────────

class PlayerService {
  final _supabase = Supabase.instance.client;
  final _cache = OfflineCacheService();

  // ===========================================================================
  // PLAYER OPERATIONS
  // ===========================================================================

  /// Inserts a new player row.
  /// RLS: coach must satisfy is_team_member(team_id).
  Future<void> addPlayer(Player player) async {
    try {
      await _supabase.from('players').insert(player.toMap());
    } catch (e) {
      debugPrint('Error adding player: $e');
      throw Exception('Error adding player: $e');
    }
  }

  /// CHANGE (v1.4): Inserts a new player and returns the generated UUID.
  ///
  /// Used by AddPlayerScreen so it can immediately auto-link the player to
  /// their account without needing a separate fetch to discover the new ID.
  Future<String> addPlayerAndReturnId(Player player) async {
    try {
      // Use .select('id').single() to retrieve the auto-generated UUID from
      // the database in the same request (Supabase returns the full row).
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
  /// Used internally (game roster restoration, attendance summary).
  /// For the UI player list use [getPlayersPaginated] instead.
  ///
  /// CHANGE (v1.3): Offline cache fallback.
  Future<List<Player>> getPlayers(String teamId) async {
    try {
      final response = await _supabase
          .from('players')
          .select()
          .eq('team_id', teamId)
          .order('name', ascending: true);

      final players =
          (response as List).map((d) => Player.fromMap(d)).toList();

      // Keep cache up to date with fresh data.
      await _cache.writeList(
        OfflineCacheService.playersKey(teamId),
        players.map((p) => p.toMap()..['id'] = p.id).toList(),
      );

      return players;
    } catch (e) {
      debugPrint('Error fetching players — checking cache: $e');
      if (e is SocketException || e.toString().contains('network')) {
        final cached = await _cache.readList(
          OfflineCacheService.playersKey(teamId),
        );
        if (cached != null) {
          debugPrint('Using cached players for team $teamId');
          return cached.map((d) => Player.fromMap(d)).toList();
        }
      }
      throw Exception('Error fetching players: $e');
    }
  }

  /// CHANGE (v1.4): Paginated player fetch using Supabase .range().
  ///
  /// Fetches rows [from]..[to] (inclusive, 0-based) ordered by name.
  /// RosterScreen uses this with an infinite-scroll ListView:
  ///
  ///   - Page 0:  from = 0,  to = pageSize - 1  (rows 0..19)
  ///   - Page 1:  from = 20, to = 39
  ///   - Stop when response.length < pageSize (no more rows).
  ///
  /// Returns an empty list on network failure if no cache exists.
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
      // On first page and offline: fall back to full cache.
      if (from == 0 &&
          (e is SocketException || e.toString().contains('network'))) {
        final cached = await _cache.readList(
            OfflineCacheService.playersKey(teamId));
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

  // ── NEW (v1.3) ─────────────────────────────────────────────────────────────

  /// Returns the Player row linked to the current auth account on [teamId].
  Future<Player?> getMyPlayerOnTeam(String teamId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final coach = await _supabase
          .from('coaches')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (coach == null) return null;

      final link = await _supabase
          .from('player_accounts')
          .select('player_id')
          .eq('coach_id', coach['id'] as String)
          .eq('team_id', teamId)
          .maybeSingle();

      if (link == null) return null;

      final playerRow = await _supabase
          .from('players')
          .select()
          .eq('id', link['player_id'] as String)
          .maybeSingle();

      if (playerRow == null) return null;
      return Player.fromMap(playerRow);
    } catch (e) {
      debugPrint('Error fetching my player: $e');
      return null;
    }
  }

  // ===========================================================================
  // TEAM OPERATIONS
  // ===========================================================================

  /// Returns all teams the authenticated coach belongs to.
  Future<List<Map<String, dynamic>>> getTeams() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final coach = await _supabase
          .from('coaches')
          .select('id')
          .eq('user_id', user.id)
          .single();

      final coachId = coach['id'];

      final response = await _supabase
          .from('team_coaches')
          .select('team_id, is_owner, teams(id, team_name, sport, created_at)')
          .eq('coach_id', coachId);

      return (response as List).map((item) {
        final team = item['teams'];
        return {
          'id': team['id'],
          'team_name': team['team_name'],
          'sport': team['sport'],
          'created_at': team['created_at'],
          'is_owner': item['is_owner'] ?? false,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching teams: $e');
      throw Exception('Error fetching teams: $e');
    }
  }

  /// Returns teams where the current account is linked as a player.
  Future<List<Map<String, dynamic>>> getPlayerLinkedTeams() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final coach = await _supabase
          .from('coaches')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (coach == null) return [];

      final coachId = coach['id'];

      final response = await _supabase
          .from('player_accounts')
          .select('team_id, is_player, teams(id, team_name, sport, created_at)')
          .eq('coach_id', coachId)
          .eq('is_player', true);

      return (response as List).map((item) {
        final team = item['teams'];
        return {
          'id': team['id'],
          'team_name': team['team_name'],
          'sport': team['sport'],
          'created_at': team['created_at'],
          'is_owner': false,
          'is_player': true,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching player-linked teams: $e');
      return [];
    }
  }

  /// Creates a new team via the `create_team` SECURITY DEFINER RPC.
  Future<void> createTeam(String teamName, String sport) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
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

  /// Updates team name and sport.
  Future<void> updateTeam(
      String teamId, String teamName, String sport) async {
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

  /// Deletes a team (cascades to players and team_coaches).
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

  Future<bool> _isTeamOwner(String teamId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;
      final coach = await _supabase
          .from('coaches')
          .select('id')
          .eq('user_id', user.id)
          .single();
      final result = await _supabase
          .from('team_coaches')
          .select('is_owner')
          .eq('team_id', teamId)
          .eq('coach_id', coach['id'])
          .maybeSingle();
      return result?['is_owner'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _isCoachOnTeam(String teamId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;
      final coach = await _supabase
          .from('coaches')
          .select('id')
          .eq('user_id', user.id)
          .single();
      final result = await _supabase
          .from('team_coaches')
          .select('id')
          .eq('team_id', teamId)
          .eq('coach_id', coach['id'])
          .maybeSingle();
      return result != null;
    } catch (e) {
      return false;
    }
  }

  // ===========================================================================
  // GAME ROSTER OPERATIONS
  // ===========================================================================

  /// Returns all saved game rosters for [teamId], newest first.
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
      debugPrint('Error fetching game rosters — checking cache: $e');
      if (e is SocketException || e.toString().contains('network')) {
        final cached = await _cache.readList(
          OfflineCacheService.gameRostersKey(teamId),
        );
        if (cached != null) return cached;
      }
      throw Exception('Error fetching game rosters: $e');
    }
  }

  /// Returns a single game_roster row by [rosterId], or null if not found.
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

  /// Returns a Supabase Realtime stream of game_rosters.
  /// Client-side team_id filter applied (Supabase .stream() limitation).
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

  /// Inserts a new game roster row and returns the generated UUID.
  Future<String> createGameRoster({
    required String teamId,
    required String title,
    String? gameDate,
    int starterSlots = 5,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      final coach = user != null
          ? await _supabase
              .from('coaches')
              .select('id')
              .eq('user_id', user.id)
              .maybeSingle()
          : null;

      final result = await _supabase
          .from('game_rosters')
          .insert({
            'team_id': teamId,
            'title': title,
            'game_date': gameDate,
            'starter_slots': starterSlots,
            'starters': [],
            'substitutes': [],
            if (coach != null) 'created_by': coach['id'],
          })
          .select('id')
          .single();

      return result['id'] as String;
    } catch (e) {
      debugPrint('Error creating game roster: $e');
      throw Exception('Error creating game roster: $e');
    }
  }

  /// Updates the starters and substitutes JSON arrays for an existing roster.
  /// CHANGE (v1.4): Each entry now supports an optional `position_override`
  /// key so per-game position overrides are persisted alongside player IDs.
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
      debugPrint('Error updating game roster lineup: $e');
      throw Exception('Error updating game roster lineup: $e');
    }
  }

  /// Deletes a game roster row by [rosterId].
  Future<void> deleteGameRoster(String rosterId) async {
    try {
      await _supabase.from('game_rosters').delete().eq('id', rosterId);
    } catch (e) {
      debugPrint('Error deleting game roster: $e');
      throw Exception('Error deleting game roster: $e');
    }
  }

  // ===========================================================================
  // COACH OPERATIONS
  // ===========================================================================

  /// Returns the coaches row for the current user, or null.
  Future<Map<String, dynamic>?> getCurrentCoach() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;
      return await _supabase
          .from('coaches')
          .select()
          .eq('user_id', user.id)
          .single();
    } catch (e) {
      debugPrint('Error fetching coach: $e');
      return null;
    }
  }

  /// Returns all coaches on [teamId] with role and ownership flag.
  Future<List<Map<String, dynamic>>> getTeamCoaches(String teamId) async {
    try {
      final response = await _supabase
          .from('team_coaches')
          .select('coaches(id, name, email, organization), role, is_owner')
          .eq('team_id', teamId)
          .order('is_owner', ascending: false);

      return (response as List).map((item) {
        final coach = item['coaches'];
        return {
          'id': coach['id'],
          'name': coach['name'],
          'email': coach['email'],
          'organization': coach['organization'],
          'role': item['role'],
          'is_owner': item['is_owner'] ?? false,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching coaches: $e');
      throw Exception('Error fetching coaches: $e');
    }
  }

  /// Looks up a coach by email and adds them to [teamId].
  Future<void> addCoachToTeam(
      String teamId, String coachEmail, String role) async {
    try {
      final coachResult = await _supabase
          .from('coaches')
          .select('id')
          .eq('email', coachEmail)
          .maybeSingle();

      if (coachResult == null) {
        throw Exception('No coach found with email: $coachEmail');
      }

      final coachId = coachResult['id'];
      final existing = await _supabase
          .from('team_coaches')
          .select('id')
          .eq('team_id', teamId)
          .eq('coach_id', coachId)
          .maybeSingle();

      if (existing != null) {
        throw Exception('This coach is already on the team');
      }

      await _supabase.from('team_coaches').insert({
        'team_id': teamId,
        'coach_id': coachId,
        'role': role,
        'is_owner': false,
      });
    } catch (e) {
      debugPrint('Error adding coach: $e');
      throw Exception('Error adding coach: $e');
    }
  }

  // ── NEW (v1.3): RPC for add_player_account ─────────────────────────────────

  /// Retroactively links an existing [playerId] on [teamId] to a user account
  /// identified by [playerEmail].  Calls the `link_player_to_account`
  /// SECURITY DEFINER RPC.
  ///
  /// CHANGE (v1.4): Also called automatically from AddPlayerScreen after a
  /// successful save (auto-link feature).
  Future<void> linkPlayerToAccount({
    required String teamId,
    required String playerId,
    required String playerEmail,
  }) async {
    try {
      await _supabase.rpc('link_player_to_account', params: {
        'p_team_id': teamId,
        'p_player_id': playerId,
        'p_player_email': playerEmail,
      });
    } catch (e) {
      debugPrint('Error linking player to account: $e');
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

  /// Removes [coachId] from [teamId].
  Future<void> removeCoachFromTeam(String teamId, String coachId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final currentCoach = await _supabase
          .from('coaches')
          .select('id')
          .eq('user_id', user.id)
          .single();

      final currentCoachId = currentCoach['id'];
      final isRemovingSelf = coachId == currentCoachId;

      if (!isRemovingSelf) {
        final ownerRow = await _supabase
            .from('team_coaches')
            .select('is_owner')
            .eq('team_id', teamId)
            .eq('coach_id', currentCoachId)
            .maybeSingle();

        if (ownerRow == null || ownerRow['is_owner'] != true) {
          throw Exception('Only team owners can remove other coaches');
        }
      }

      final coachToRemove = await _supabase
          .from('team_coaches')
          .select('is_owner')
          .eq('team_id', teamId)
          .eq('coach_id', coachId)
          .single();

      if (coachToRemove['is_owner'] == true) {
        final owners = await _supabase
            .from('team_coaches')
            .select('id')
            .eq('team_id', teamId)
            .eq('is_owner', true);

        if ((owners as List).length <= 1) {
          throw Exception(
              'Cannot remove the only owner. Transfer ownership first.');
        }
      }

      await _supabase
          .from('team_coaches')
          .delete()
          .eq('team_id', teamId)
          .eq('coach_id', coachId);
    } catch (e) {
      debugPrint('Error removing coach: $e');
      throw Exception('Error removing coach: $e');
    }
  }

  /// Transfers ownership from the current coach to [newOwnerId].
  Future<void> transferOwnership(String teamId, String newOwnerId) async {
    try {
      final isOwner = await _isTeamOwner(teamId);
      if (!isOwner) {
        throw Exception('Only the current owner can transfer ownership');
      }

      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final currentCoach = await _supabase
          .from('coaches')
          .select('id')
          .eq('user_id', user.id)
          .single();

      final currentCoachId = currentCoach['id'];

      await _supabase
          .from('team_coaches')
          .update({'is_owner': false})
          .eq('team_id', teamId)
          .eq('coach_id', currentCoachId);

      await _supabase
          .from('team_coaches')
          .update({'is_owner': true})
          .eq('team_id', teamId)
          .eq('coach_id', newOwnerId);
    } catch (e) {
      debugPrint('Error transferring ownership: $e');
      throw Exception('Error transferring ownership: $e');
    }
  }
}