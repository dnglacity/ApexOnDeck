import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// player.dart  (AOD v1.4)
//
// CHANGE (Notes.txt v1.4): Added `position` field.
//   • Stored as a nullable String in the DB column `position` on the
//     `players` table (see migration script add_position_column.sql).
//   • Exposed via toMap() so AddPlayerScreen can persist it.
//   • Added displayPosition getter for safe display fallback.
// ─────────────────────────────────────────────────────────────────────────────

class Player {
  final String id;
  final String teamId;
  final String name;
  final String? studentId;
  final String? studentEmail;
  final String? jerseyNumber;
  final String? nickname;

  // CHANGE (v1.4): New position field — nullable, optional.
  // Examples: "Point Guard", "Pitcher", "Center Back", "QB".
  final String? position;

  final String status;
  final DateTime? createdAt;

  Player({
    required this.id,
    required this.teamId,
    required this.name,
    this.studentId,
    this.studentEmail,
    this.jerseyNumber,
    this.nickname,
    this.position,          // CHANGE (v1.4)
    this.status = 'present',
    this.createdAt,
  });

  // ── Deserialise from Supabase row ──────────────────────────────────────────
  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      id: map['id'] ?? '',
      teamId: map['team_id'] ?? '',
      name: map['name'] ?? '',
      studentId: map['student_id'],
      studentEmail: map['student_email'],
      jerseyNumber: map['jersey_number']?.toString(),
      nickname: map['nickname'],
      position: map['position'],   // CHANGE (v1.4)
      status: map['status'] ?? 'present',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
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
      'position': position,         // CHANGE (v1.4)
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
    String? position,             // CHANGE (v1.4)
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
      position: position ?? this.position,   // CHANGE (v1.4)
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Display helpers ────────────────────────────────────────────────────────

  String get displayJersey => jerseyNumber ?? '-';

  String get displayName => nickname != null ? '$name ($nickname)' : name;

  /// CHANGE (v1.4): Returns position label, or dash if unset.
  String get displayPosition => position?.isNotEmpty == true ? position! : '-';

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
    return status[0].toUpperCase() + status.substring(1);
  }
}