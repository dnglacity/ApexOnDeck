# Apex On Deck (AOD)

A Flutter roster-management app for sports coaches, athletes, and guardians. Coaches manage rosters, track attendance, build game-day lineups, and schedule matches. Athletes and guardians have a read-only self-view of their profile and team.

**Version:** v1.12
**Platforms:** Android · iOS · Web (GitHub Pages)
**Backend:** Supabase (Auth + PostgREST + Realtime + SECURITY DEFINER RPCs)

---

## Architecture

### Directory Layout

```
lib/
  main.dart                        — Supabase init, MyApp widget, Material 3 theme
  models/
    player.dart                    — Player data class (fromMap / toMap / copyWith)
    app_user.dart                  — AppUser + TeamMember data classes
    match.dart                     — Match data class (persisted to public.matches)
  services/
    auth_service.dart              — Auth operations (signUp, signIn, signOut, changeEmail, deleteAccount)
    player_service.dart            — All DB operations: players, teams, team_members, game_rosters, matches
    offline_cache_service.dart     — shared_preferences JSON cache (TTL-aware singleton)
  screens/
    auth_wrapper.dart              — Root widget; reacts to Supabase auth stream; drives all routing
    login_screen.dart              — Sign-in / sign-up / forgot-password UI
    reset_password_screen.dart     — Shown on passwordRecovery auth event
    team_selection_screen.dart     — Lists teams; routes coaches → RosterScreen, players → PlayerSelfViewScreen
    main_shell.dart                — Bottom navigation shell (Roster · Matches · Calendar)
    roster_screen.dart             — Coach-facing roster (paginated, bulk-delete, attendance tracking)
    add_player_screen.dart         — Form to add a new player to the roster
    manage_members_screen.dart     — Add/remove team members; link players to user accounts
    game_roster_screen.dart        — Game-day lineup builder (starters + substitutes, tab lazy-loading)
    saved_roster_screen.dart       — Lists saved game rosters
    matches_screen.dart            — Match list with create-event FAB (coach only)
    match_view_screen.dart         — Detail view / edit screen for a single match
    calendar_screen.dart           — Month-view calendar placeholder (future: schedule integration)
    player_self_view_screen.dart   — Athlete / guardian read-only profile view
    account_settings_screen.dart   — Email change, password reset, account deletion
  widgets/
    sport_autocomplete_field.dart  — Shared sport-search autocomplete widget
    error_dialog.dart              — Reusable error dialog
    date_input_field.dart          — Reusable date picker text field
```

## Data Models

### Player
Fields: `id`, `team_id`, `user_id`, `first_name`, `last_name`, `nickname`, `athlete_email`, `guardian_email`, `jersey_number`, `position`, `status`, `created_at`

### Match
Fields: `id`, `team_id`, `my_team_name`, `opponent_name`, `match_date`, `is_home`, `notes`, `created_at`

### AppUser / TeamMember
`AppUser` mirrors `public.users`. `TeamMember` extends it with `role` and optional `player_id` link.

---

## Offline Support

`OfflineCacheService` caches the following locally:

| Cache key | Data | TTL |
|---|---|---|
| `OfflineCacheService.playersKey(teamId)` | Player list for a team | 60 min |
| `OfflineCacheService.gameRostersKey(teamId)` | Saved game rosters | 60 min |

---

## Code Conventions

- **Imports:** all `lib/` imports use relative paths (e.g. `../models/player.dart`), not package-name imports.
- **Dart SDK:** `^3.11.0` — Dart 3.x patterns and null-safety required throughout.
- **pubspec name:** `apexondeck`
