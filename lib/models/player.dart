import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// player.dart  (AOD v1.5)
//
// CHANGE (Notes.txt v1.5 — Unified users):
//   Added `userId` field (nullable FK → public.users.id).
//   This replaces the old player_accounts join table.  When a player signs up
//   and their account is linked, this column is populated directly on the
//   players row.  The team_members row for that user is set to role='player'
//   with player_id pointing to this row.
//
// Retained from v1.4:
//   • position field and displayPosition getter.
//   • All status helpers and copy/toMap/fromMap.
// ─────────────────────────────────────────────────────────────────────────────

class Player {
  final String id;
  final String teamId;
  final String name;
  final String? studentId;
  final String? studentEmail;
  final String? jerseyNumber;
  final String? nickname;
  final String? position;

  // CHANGE (v1.5): Direct link to public.users.id.
  // Replaces the old player_accounts join table.
  // Null when the player has not yet been linked to an app account.
  final String? userId;

  final String status;
  final DateTime? createdAt;

  const Player({
    required this.id,
    required this.teamId,
    required this.name,
    this.studentId,
    this.studentEmail,
    this.jerseyNumber,
    this.nickname,
    this.position,
    this.userId,           // CHANGE (v1.5)
    this.status = 'present',
    this.createdAt,
  });

  // ── Deserialise from Supabase row ──────────────────────────────────────────
  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      id: map['id'] as String? ?? '',
      teamId: map['team_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      studentId: map['student_id'] as String?,
      studentEmail: map['student_email'] as String?,
      jerseyNumber: map['jersey_number']?.toString(),
      nickname: map['nickname'] as String?,
      position: map['position'] as String?,
      userId: map['user_id'] as String?,   // CHANGE (v1.5)
      status: map['status'] as String? ?? 'present',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  // ── Serialise for Supabase insert/update ───────────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      'team_id': teamId,
      'name': name,
      'student_id': studentId,
      'student_email': studentEmail,
      'jersey_number': jerseyNumber,
      'nickname': nickname,
      'position': position,
      'user_id': userId,       // CHANGE (v1.5)
      'status': status,
    };
  }

  // ── Copy helper ────────────────────────────────────────────────────────────
  Player copyWith({
    String? id,
    String? teamId,
    String? name,
    String? studentId,
    String? studentEmail,
    String? jerseyNumber,
    String? nickname,
    String? position,
    String? userId,            // CHANGE (v1.5)
    String? status,
    DateTime? createdAt,
  }) {
    return Player(
      id: id ?? this.id,
      teamId: teamId ?? this.teamId,
      name: name ?? this.name,
      studentId: studentId ?? this.studentId,
      studentEmail: studentEmail ?? this.studentEmail,
      jerseyNumber: jerseyNumber ?? this.jerseyNumber,
      nickname: nickname ?? this.nickname,
      position: position ?? this.position,
      userId: userId ?? this.userId,       // CHANGE (v1.5)
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Display helpers ────────────────────────────────────────────────────────

  String get displayJersey => jerseyNumber ?? '-';

  String get displayName => nickname != null ? '$name ($nickname)' : name;

  String get displayPosition => position?.isNotEmpty == true ? position! : '-';

  /// True when this player row is linked to an app account.
  bool get hasLinkedAccount => userId != null && userId!.isNotEmpty;

  // ── Status helpers ─────────────────────────────────────────────────────────

  Color get statusColor {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      case 'excused':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'present':
        return Icons.check_circle;
      case 'absent':
        return Icons.cancel;
      case 'late':
        return Icons.access_time;
      case 'excused':
        return Icons.event_busy;
      default:
        return Icons.help;
    }
  }

  String get statusLabel {
    if (status.isEmpty) return 'Unknown';
    return status[0].toUpperCase() + status.substring(1);
  }
}