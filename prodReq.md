# Product Requirements Document
## Apex On Deck (AOD)

**Version:** 1.12
**Date:** March 1, 2026
**Platforms:** Android · iOS · Web (GitHub Pages)
**Stack:** Flutter / Dart 3.x · Supabase (Auth + PostgREST + Realtime)

---

## 1. Purpose & Problem Statement

Sports coaches spend significant time managing rosters on paper or across multiple disconnected tools. Athletes and guardians have no real-time visibility into team status, game-day lineups, or upcoming matches.

**Apex On Deck** is a mobile-first roster management platform that gives coaches a single system of record for their team — from player profiles and attendance to game-day lineups and match scheduling — while giving athletes and guardians an authenticated, read-only view of their own data.

---

## 2. Target Users

| Persona | Description | Primary Goal |
|---|---|---|
| **Owner** | Team creator; full admin access | Manage team, members, and settings |
| **Coach** | Staff member with roster privileges | Build and manage rosters; create game-day lineups |
| **Team Manager** | Non-coaching staff with coach-level access | Assist with roster management |
| **Player (Athlete)** | Registered athlete linked to a player profile | View own stats, status, and team roster |
| **Team Parent (Guardian)** | Parent/guardian of a linked player | View their athlete's profile and team roster |

---

## 3. Scope

### In Scope — v1.12

- User authentication (sign-up, sign-in, password reset, email change, account deletion)
- Multi-team support (one user may belong to multiple teams in different roles)
- Player profile management (CRUD, jersey number, position, status, nickname, guardian contact)
- Attendance / status tracking per player
- Game-day lineup builder with starter slots and substitutes, per-game position overrides
- Saved game roster management
- Match scheduling (home/away, date, opponent, notes)
- Match invite code generation (6-character shareable code)
- Offline caching of player lists and game rosters (60-minute TTL)
- Role-based access control enforced at both UI and database layers
- Calendar view (month-view scaffold; event population planned)

### Out of Scope — v1.12

- Live score tracking or stat recording during matches
- In-app messaging or notifications
- Calendar event population from match/roster data (UI placeholder only)
- Public-facing team pages
- Payment or subscription management

---

## 4. Functional Requirements

### 4.1 Authentication

| ID | Requirement |
|---|---|
| AUTH-01 | Users must be able to create an account with email and password |
| AUTH-02 | Users must be able to sign in with email and password |
| AUTH-03 | Users must be able to request a password-reset email |
| AUTH-04 | Users must be able to change their email address (requires current password re-authentication) |
| AUTH-05 | Email change must cascade across `public.users`, `players.athlete_email`, and `players.guardian_email` atomically |
| AUTH-06 | Users must be able to permanently delete their account after explicit acknowledgement |
| AUTH-07 | App routing must react to auth state changes without manual navigation calls |
| AUTH-08 | On `passwordRecovery` event, the app must surface the `ResetPasswordScreen` automatically |

### 4.2 Team Management

| ID | Requirement |
|---|---|
| TEAM-01 | Authenticated users may create one or more teams |
| TEAM-02 | Team creation must execute via a `SECURITY DEFINER` RPC; the creator becomes the team `owner` |
| TEAM-03 | Owners may edit team name and sport |
| TEAM-04 | Users who belong to multiple teams must be presented a team selection screen on login |
| TEAM-05 | A player who is linked to a team via `players.user_id` must have a `team_members` row automatically created by a DB trigger (role = `player`) |
| TEAM-06 | After linking, a player's team must appear on their team selection screen without a manual refresh |

### 4.3 Roster Management

| ID | Requirement |
|---|---|
| ROSTER-01 | Coaches may add players to a team roster with: first name, last name, nickname, jersey number, position, athlete email, and guardian email |
| ROSTER-02 | Coaches may edit any player profile field |
| ROSTER-03 | Coaches may delete individual players via swipe-to-dismiss |
| ROSTER-04 | Coaches may bulk-select and delete multiple players |
| ROSTER-05 | Roster list must paginate at 20 players per page with infinite scroll |
| ROSTER-06 | Each player must display a status indicator (e.g., Active, Injured, Inactive) |
| ROSTER-07 | Coaches may update a player's status |
| ROSTER-08 | Roster must support real-time updates via Supabase Realtime stream |

### 4.4 Team Members

| ID | Requirement |
|---|---|
| MEMBER-01 | Coaches may invite users to the team by email address, assigning a role at invite time |
| MEMBER-02 | Coaches may remove members from the team |
| MEMBER-03 | Removing a member whose `player_id` is set must un-link `players.user_id` before deleting the `team_members` row |
| MEMBER-04 | Coaches may link a player profile to an existing user account (by email lookup) |
| MEMBER-05 | Coaches may link a guardian to a player profile |
| MEMBER-06 | All member mutations must go through SECURITY DEFINER RPCs |

### 4.5 Game-Day Lineup Builder

| ID | Requirement |
|---|---|
| LINEUP-01 | Coaches may create a game-day roster with a configurable number of starter slots |
| LINEUP-02 | The lineup builder must present two tabs: **Available Players** and **Roster** |
| LINEUP-03 | Players are divided into **Starting Lineup** and **Substitutes** sections |
| LINEUP-04 | Each player entry in the lineup must show a tappable position chip |
| LINEUP-05 | Tapping the position chip must allow a per-game position override (stored with the saved roster) |
| LINEUP-06 | Tab state (scroll position, loaded data) must be preserved across tab switches |
| LINEUP-07 | Coaches may save a completed lineup with a title, game date, and starter slot count |
| LINEUP-08 | Saved rosters must be retrievable and re-openable for editing |
| LINEUP-09 | Coaches may delete saved rosters |
| LINEUP-10 | A saved roster may be associated with a match via the Match View screen |

### 4.6 Match Scheduling

| ID | Requirement |
|---|---|
| MATCH-01 | Coaches may create a match with: team name, opponent name, date/time, home/away flag, and notes |
| MATCH-02 | Matches are displayed in a list sorted by date |
| MATCH-03 | Tapping a match opens a full-screen detail view |
| MATCH-04 | Coaches may edit or delete a match from the detail view |
| MATCH-05 | Coaches may generate a 6-character invite code for a match |
| MATCH-06 | Coaches may attach a saved game roster to a match from the detail view |

### 4.7 Athlete / Guardian Self-View

| ID | Requirement |
|---|---|
| SELF-01 | Players and guardians must be routed directly to a read-only self-view after login |
| SELF-02 | The self-view must display the player's own profile card, current status, and a teammate list |
| SELF-03 | All data on the self-view must be read-only; no editing is permitted |
| SELF-04 | Pull-to-refresh must reload all data from the server |

### 4.8 Account Settings

| ID | Requirement |
|---|---|
| ACCT-01 | Users may edit their first name, last name, and nickname |
| ACCT-02 | Email is displayed as read-only; a dedicated edit flow (password-gated) handles changes |
| ACCT-03 | Users may delete their account after checking an acknowledgement checkbox |
| ACCT-04 | The current app version must be visible in Account Settings |

### 4.9 Offline Support

| ID | Requirement |
|---|---|
| OFFLINE-01 | Player lists must be cached locally with a 60-minute TTL keyed by team ID |
| OFFLINE-02 | Saved game rosters must be cached locally with a 60-minute TTL keyed by team ID |
| OFFLINE-03 | Stale cache must be served when the network is unavailable |
| OFFLINE-04 | Cache must be invalidated on explicit user refresh or after TTL expiry |

---

## 5. Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Security** | All sensitive DB mutations go through SECURITY DEFINER RPCs; no raw SQL from the client |
| **Security** | Row-Level Security (RLS) enforced on all Supabase tables |
| **Security** | Auth credentials injected at build time via `--dart-define-from-file`; never hardcoded |
| **Performance** | Roster paginated at 20 rows; infinite scroll prevents large payloads |
| **Performance** | All DB queries use explicit column lists; no `select('*')` |
| **Performance** | Concurrent user-ID lookups are deduplicated via a Completer guard |
| **Performance** | Game roster tabs use `AutomaticKeepAliveClientMixin` to avoid re-render on tab switch |
| **Reliability** | All async state management uses generation counters to discard stale responses |
| **Reliability** | All `TextEditingController` disposals are deferred to post-frame to avoid use-after-dispose |
| **Accessibility** | Material 3 semantics; sufficient color contrast between Deep Navy (#1A3A6B) and white |
| **Compatibility** | Dart SDK `^3.11.0`; null-safety required throughout |

---

## 6. Role & Permission Matrix

| Feature | Owner | Coach | Team Manager | Player | Team Parent |
|---|:---:|:---:|:---:|:---:|:---:|
| Create / delete team | ✓ | | | | |
| Edit team name / sport | ✓ | | | | |
| Add / edit / delete players | ✓ | ✓ | ✓ | | |
| Manage team members | ✓ | ✓ | ✓ | | |
| Link player to user | ✓ | ✓ | ✓ | | |
| Build / save game roster | ✓ | ✓ | ✓ | | |
| Create / edit matches | ✓ | ✓ | ✓ | | |
| Generate match invite | ✓ | ✓ | | | |
| View team roster | ✓ | ✓ | ✓ | ✓ | ✓ |
| View own player profile | ✓ | ✓ | ✓ | ✓ | ✓ |
| Edit own account settings | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## 7. Data Model Summary

### `public.users`
Populated by `handle_new_user` trigger on sign-up. Mirrors `auth.users`.

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | Same as auth.users.id |
| user_id | uuid | Foreign key → auth.users.id |
| first_name | text | |
| last_name | text | |
| nickname | text | Optional default display nickname |
| email | text | Synced from auth |
| organization | text | Optional school/club name |
| created_at | timestamptz | |

### `public.players`
One row per player on a team. May or may not be linked to a user account.

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| team_id | uuid FK | → teams.id |
| user_id | uuid FK | → public.users.id (nullable until linked) |
| first_name / last_name | text | |
| nickname | text | Per-roster display override |
| athlete_email | text | |
| guardian_email | text | |
| jersey_number | text | |
| position | text | |
| status | text | Active / Injured / Inactive / etc. |
| created_at | timestamptz | |

### `public.team_members`
Membership rows linking users to teams with a role.

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| team_id | uuid FK | → teams.id |
| user_id | uuid FK | → public.users.id |
| role | text | owner / coach / player / team_parent / team_manager |
| player_id | uuid FK | → players.id (nullable; set for role=player) |

### `public.matches`
Scheduled matches for a team.

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| team_id | uuid FK | → teams.id |
| my_team_name | text | |
| opponent_name | text | |
| match_date | timestamptz | |
| is_home | boolean | |
| notes | text | |
| created_at | timestamptz | |

### `public.game_rosters`
Saved game-day lineups.

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| team_id | uuid FK | → teams.id |
| title | text | |
| game_date | text | ISO date string |
| starter_slots | int | Number of starter positions |
| roster_data | jsonb | Array of `{player_id, slot_number, position_override}` |
| created_at | timestamptz | |

---

## 8. SECURITY DEFINER RPCs

| RPC | Purpose |
|---|---|
| `create_team` | Create a team and auto-assign the caller as owner |
| `add_member_to_team` | Resolve user by email and insert team_members row |
| `delete_account` | Delete auth + public user rows in a single transaction |
| `change_user_email` | Re-authenticate, then cascade email change across all tables |
| `link_player_to_user` | Set players.user_id and trigger membership sync |
| `link_guardian_to_player` | Set guardian linkage on a player row |
| `lookup_user_by_email` | Return public.users.id for a given email (coach-side lookup) |

---

## 9. Future Roadmap (Post-v1.12)

| Priority | Feature |
|---|---|
| High | Calendar integration — populate events from match and roster data |
| High | Push notifications for lineup publication and match reminders |
| Medium | Match invite code acceptance flow (athlete joins match via code) |
| Medium | Live attendance check-in at game time |
| Medium | Stat recording per player per match |
| Low | Public team page / shareable roster link |
| Low | Multi-season / archive support |
| Low | Subscription / payment management |
