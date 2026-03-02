// =============================================================================
// match.dart  (AOD v1.12)
//
// Match model — persisted to public.matches in Supabase.
// Fields mirror the DB columns defined in supabase_script.md.
// =============================================================================

class Match {
  final String id;
  final String teamId;
  final String myTeamName;
  final String opponentName;
  final DateTime date;
  final bool isHome; // true = Home, false = Away
  final String notes;
  final DateTime? createdAt;

  const Match({
    required this.id,
    required this.teamId,
    required this.myTeamName,
    required this.opponentName,
    required this.date,
    required this.isHome,
    this.notes = '',
    this.createdAt,
  });

  String get title => '$myTeamName vs. $opponentName';
  String get locationLabel => isHome ? 'Home' : 'Away';

  factory Match.fromMap(Map<String, dynamic> m) => Match(
        id: m['id'] as String,
        teamId: m['team_id'] as String,
        myTeamName: m['my_team_name'] as String,
        opponentName: m['opponent_name'] as String,
        date: DateTime.parse(m['match_date'] as String).toLocal(),
        isHome: m['is_home'] as bool? ?? true,
        notes: m['notes'] as String? ?? '',
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String).toLocal()
            : null,
      );

  Map<String, dynamic> toMap() => {
        'team_id': teamId,
        'my_team_name': myTeamName,
        'opponent_name': opponentName,
        'match_date': date.toUtc().toIso8601String(),
        'is_home': isHome,
        'notes': notes,
      };

  Match copyWith({
    String? id,
    String? teamId,
    String? myTeamName,
    String? opponentName,
    DateTime? date,
    bool? isHome,
    String? notes,
    DateTime? createdAt,
  }) =>
      Match(
        id: id ?? this.id,
        teamId: teamId ?? this.teamId,
        myTeamName: myTeamName ?? this.myTeamName,
        opponentName: opponentName ?? this.opponentName,
        date: date ?? this.date,
        isHome: isHome ?? this.isHome,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
      );
}
