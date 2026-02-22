// ─────────────────────────────────────────────────────────────────────────────
// app_user.dart  (AOD v1.5)
//
// CHANGE (Notes.txt v1.5 — Unified users):
//   Replaces the old `coaches` model entirely.  Every person in the system
//   (owner, coach, player) is an AppUser.  Their role within a specific team
//   is stored on the `team_members` join table, NOT on this model.
//
//   This model maps 1-to-1 with the `users` table in Supabase, which is
//   populated by a DB trigger on auth.users (on_auth_user_created).
// ─────────────────────────────────────────────────────────────────────────────

class AppUser {
  /// Primary key — same UUID as auth.users.id.
  final String id;

  /// Matches auth.users.id (used to resolve the current user's profile).
  final String userId;

  /// Display name entered at registration.
  final String name;

  /// Email address — copied from auth.users at trigger time.
  final String email;

  /// Optional school / club / organization name.
  final String? organization;

  final DateTime? createdAt;

  const AppUser({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    this.organization,
    this.createdAt,
  });

  // ── Deserialise from Supabase row ──────────────────────────────────────────
  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      organization: map['organization'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  // ── Serialise for update ───────────────────────────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'name': name,
      'email': email,
      if (organization != null) 'organization': organization,
    };
  }

  // ── Copy helper ────────────────────────────────────────────────────────────
  AppUser copyWith({
    String? id,
    String? userId,
    String? name,
    String? email,
    String? organization,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      organization: organization ?? this.organization,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TeamMember  (AOD v1.5)
//
// Represents a row from `team_members` joined with the `users` profile.
// Role values: 'owner' | 'coach' | 'player'
// (extensible — future roles like 'assistant_coach' can be added without
//  schema changes since role is a plain TEXT column).
//
// The `playerId` field is populated when role == 'player' and the member
// has been linked to a specific `players` roster row.
// ─────────────────────────────────────────────────────────────────────────────

class TeamMember {
  final String teamMemberId; // team_members.id (PK)
  final String teamId;
  final String userId;        // users.id (FK → public.users)
  final String role;          // 'owner' | 'coach' | 'player'
  final String? playerId;     // players.id — set when role == 'player'

  // Denormalised user profile fields (joined from users table).
  final String name;
  final String email;
  final String? organization;

  const TeamMember({
    required this.teamMemberId,
    required this.teamId,
    required this.userId,
    required this.role,
    this.playerId,
    required this.name,
    required this.email,
    this.organization,
  });

  // ── Convenience role checks ────────────────────────────────────────────────

  bool get isOwner => role == 'owner';
  bool get isCoach => role == 'coach' || role == 'owner';
  bool get isPlayer => role == 'player';

  // ── Deserialise from a joined Supabase row ─────────────────────────────────
  // Expected shape (from team_members joined with users):
  //   { id, team_id, user_id, role, player_id,
  //     users: { name, email, organization } }
  factory TeamMember.fromMap(Map<String, dynamic> map) {
    final userMap = map['users'] as Map<String, dynamic>? ?? {};
    return TeamMember(
      teamMemberId: map['id'] as String? ?? '',
      teamId: map['team_id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      role: map['role'] as String? ?? 'player',
      playerId: map['player_id'] as String?,
      name: userMap['name'] as String? ?? '',
      email: userMap['email'] as String? ?? '',
      organization: userMap['organization'] as String?,
    );
  }

  // ── Display helper ─────────────────────────────────────────────────────────
  String get roleLabel {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'coach':
        return 'Coach';
      case 'player':
        return 'Player';
      default:
        // Capitalise unknown roles gracefully.
        return role[0].toUpperCase() + role.substring(1);
    }
  }
}