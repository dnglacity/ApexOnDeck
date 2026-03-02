Apex On Deck (AOD) — Security & Compliance Overview
                             **Version:** v1.12 | **Date:** 2026-03-01 (reviewed 2026-03-01)

                             ---

                             ## 1. Application Overview

                             Apex On Deck (AOD) is a Flutter-based roster management application for sports coaches, athletes, and guardians. It targets Android, iOS, and Web (GitHub Pages). The backend is Supabase (PostgreSQL + PostgREST + Realtime + Auth). The app stores and processes personally identifiable information (PII) for minors (student athletes) and adults (coaches, guardians), which places it squarely within the scope of several privacy and data-protection frameworks.

                             ---

                             ## 2. Application Functions

                             ### 2.1 Authentication & Identity

                             | Function | Description |
                             |---|---|
                             | `signUp` | Creates a new auth user; embeds profile metadata in `raw_user_meta_data`; validates response.user != null against silent failures; blocks submission if age-confirmation checkbox is unchecked |
                             | `signIn` | Email/password authentication via Supabase Auth |
                             | `signOut` | Terminates the session; triggers in-memory and on-disk cache wipe |
                             | `resetPassword` | Sends a password-reset email via Supabase magic-link flow |
                             | `changePassword` | Re-authenticates the user before updating the credential |
                             | `changeEmail` | Re-authenticates, then cascades the change across `public.users`, `players.athlete_email`, and `players.guardian_email` via a SECURITY DEFINER RPC, then updates the Supabase Auth record; all failure paths return the same generic message to prevent email enumeration |
                             | `deleteAccount` | Invokes the `delete_account` SECURITY DEFINER RPC to remove all user data (including JSONB roster scrub); signs out afterward |
                             | `updateProfile` | Allows in-session profile edits (name, nickname, organization) |

                             ### 2.2 Team Management

                             | Function | Description |
                             |---|---|
                             | `createTeam` | Creates a team and automatically assigns the creator the `owner` role via the `create_team` RPC |
                             | `updateTeam` | Edits team name and sport (owner-only, enforced by RLS) |
                             | `deleteTeam` | Cascading delete of a team, its players, and member records (owner-only) |
                             | `getTeams` | Returns the teams the authenticated user belongs to with role context; uses a 5-minute in-memory TTL cache |
                             | `transferOwnership` | Atomically promotes a new owner and demotes the current owner via a SECURITY DEFINER RPC |

                             ### 2.3 Roster & Player Management

                             | Function | Description |
                             |---|---|
                             | `addPlayerAndReturnId` | Inserts a new player row with PII (name, email, jersey, position) |
                             | `getPlayers` / `getPlayersPaginated` | Retrieves the roster for a team; falls back to on-device cache on network failure (mobile only) |
                             | `getPlayerStream` | Real-time Supabase channel subscription to the player table |
                             | `updatePlayer` | Updates all mutable fields of a player record |
                             | `updatePlayerStatus` / `bulkUpdateStatus` | Sets attendance status (present, absent, late, excused) on one or all players |
                             | `bulkDeletePlayers` / `deletePlayer` | Permanently removes player records; each deletion routes through the `delete_player` SECURITY DEFINER RPC which scrubs all game roster JSONB references atomically |
                             | `getAttendanceSummary` | Returns per-status counts for a team for reporting |
                             | `getJerseyNumbers` | Returns the set of jersey numbers already assigned on a team; used for uniqueness warnings |

                             ### 2.4 Team Member Management

                             | Function | Description |
                             |---|---|
                             | `addMemberToTeam` | Adds a registered user to a team by email via the `add_member_to_team` RPC |
                             | `removeMemberFromTeam` | Delegates to the `remove_member_from_team` SECURITY DEFINER RPC; sole-owner guard and DELETE are performed atomically inside a single transaction with row-level locking |
                             | `updateMemberRole` | Changes a member's role; blocks direct promotion to owner (must use `transferOwnership`) |
                             | `getTeamMembers` | Lists all members of a team with joined user profiles |
                             | `lookupUserByEmail` | Searches the `public.users` table by email via RPC (used for adding members and linking players) |
                             | `linkPlayerToAccount` | Associates a player row with a registered user account via the `link_player_to_user` RPC |
                             | `linkGuardianToPlayer` | Stores a guardian email against a player record via RPC |

                             ### 2.5 Game Roster Management

                             | Function | Description |
                             |---|---|
                             | `createGameRoster` | Creates a named game-day lineup with starter slots and attribution |
                             | `updateGameRosterLineup` | Saves starters/substitutes arrays and starter_slots count to a roster row |
                             | `updateGameRosterMeta` | Updates mutable metadata (game_date) on an existing roster |
                             | `duplicateGameRoster` | Clones an existing roster under a new title |
                             | `deleteGameRoster` | Permanently removes a saved game roster |
                             | `getGameRosters` / `getGameRosterStream` | Retrieves or subscribes to game rosters for a team; uses offline cache fallback (mobile only) |

                             ### 2.6 Team Invite System

                             | Function | Description |
                             |---|---|
                             | `getOrCreateTeamInvite` | Generates or retrieves an active 6-character invite code with an expiry timestamp |
                             | `redeemTeamInvite` | Validates a code and adds the authenticated user to the associated team; auto-creates a pre-filled player row linked to the new member |
                             | `revokeTeamInvite` | Deactivates the current invite code for a team |

                             ### 2.7 Offline Cache

                             | Function | Description |
                             |---|---|
                             | `writeList` / `readList` | Persists player and game roster data to `flutter_secure_storage` (mobile only) with a configurable TTL (default 60 min); no-op on Web |
                             | `clearAll` | Wipes all on-device cache entries on sign-out to prevent cross-account data leakage on shared devices |
                             | `evictExpired` | Background cleanup of stale cache entries on app launch |

                             ---

                             ## 3. Data Inventory

                             ### 3.1 Personal Data Collected

                             | Data Element | Subject | Sensitivity |
                             |---|---|---|
                             | First name, last name | Coach, athlete, guardian, team manager | PII |
                             | Email address | All user types | PII |
                             | Password (hashed by Supabase Auth) | All user types | Credential |
                             | Guardian email | Guardian | PII |
                             | Jersey number, position, nickname | Athlete | PII (low sensitivity) |
                             | Attendance status | Athlete | Behavioral record |
                             | Organization / school / club name | Coach/user | Institutional PII |
                             | Game roster lineups (JSONB) | Athlete | Derived record |
                             | `created_at` timestamps | All records | Metadata |

                             ### 3.2 Data at Rest

                             - Supabase PostgreSQL database (hosted on Supabase cloud infrastructure)
                             - `flutter_secure_storage` device-local cache (iOS Keychain / Android Keystore with `EncryptedSharedPreferences`) — **mobile only**
                             - **Web target:** offline cache is fully disabled (`kIsWeb` guard in `OfflineCacheService`); no PII is persisted to browser storage

                             ### 3.3 Data in Transit

                             - All Supabase API calls use HTTPS (TLS 1.2+)
                             - Realtime subscriptions use WSS (WebSocket Secure)

                             ---

                             ## 4. Security Controls — Current Implementation

                             ### 4.1 Authentication

                             - **Email/password authentication** via Supabase Auth (bcrypt password hashing server-side)
                             - **Re-authentication before sensitive operations:** `changeEmail` and `changePassword` both require the current password before allowing the change
                             - **Email normalization:** All email addresses are trimmed and lowercased before use, preventing duplicate accounts from case variations
                             - **Null-user validation on sign-up:** Guards against silent Supabase failures (rate-limit, trigger errors) returning HTTP 200 with no user object
                             - **Password-recovery flow:** Handled by `ResetPasswordScreen` reacting to the `passwordRecovery` auth event from Supabase
                             - **COPPA age-gate (partial):** Sign-up form requires the user to check "I confirm I am 13 or older" before the account is created

                             ### 4.2 Authorization & Row-Level Security (RLS)

                             - **Role-based access model:** Five roles — `owner`, `coach`, `player`, `team_parent`, `team_manager`
                             - **RLS on all tables:** Team and player queries are filtered server-side by the authenticated user's membership in `team_members`
                             - **SECURITY DEFINER RPCs for privileged operations:** `create_team`, `add_member_to_team`, `delete_account`, `change_user_email`, `link_player_to_user`, `link_guardian_to_player`, `transfer_ownership`, `get_or_create_team_invite`, `redeem_team_invite`, `revoke_team_invite`, `remove_member_from_team`, `delete_player`, `get_current_user_id` — these run as the function owner, bypassing client-supplied JWTs for operations that require elevated trust
                             - **Atomic sole-owner guard:** `remove_member_from_team` RPC performs the owner count check and DELETE inside a single transaction with row-level locking (`FOR UPDATE` / `FOR SHARE`) preventing TOCTOU races
                             - **Client-side role checks** (defense-in-depth): `_isTeamOwner()` verifies caller role before destructive team operations; `updateMemberRole()` blocks direct promotion to `owner`

                             ### 4.3 Logging & Observability

                             - **Domain-only email logging:** `signIn` logs only the email domain on auth failure — never the full address
                             - **No full PII in logs:** Debug logs reference user IDs or domains, not names or full email addresses
                             - **PostgrestException sanitization:** All 18+ catch blocks in `player_service.dart` route through `_dbError()` or an inline `PostgrestException` check; raw table names, column names, and constraint details are replaced with static messages before reaching the UI
                             - **Email enumeration prevention:** `changeEmail` returns the same generic message on all RPC failure paths regardless of whether the cause is a duplicate-key violation or any other error

                             ### 4.4 Offline Cache Security

                             - **Encrypted storage (mobile):** `OfflineCacheService` uses `flutter_secure_storage` (iOS Keychain / Android Keystore with `EncryptedSharedPreferences`); all cached PII is encrypted at rest on mobile
                             - **Disabled on Web:** `OfflineCacheService` is a compile-time no-op when `kIsWeb` is true — no PII is ever written to browser storage on the Web target
                             - **Cache wipe on sign-out:** `clearCache()` is called on every sign-out path (account settings, password reset, normal sign-out) to remove all on-device data
                             - **TTL enforcement:** Cache entries expire after 60 minutes by default; eviction runs in the background at app launch
                             - **Key namespacing:** Cache keys use the `aod_cache_` prefix to prevent accidental overlap with other libraries

                             ### 4.5 Input Validation & Sanitization

                             - **Jersey number sanitization:** `FilteringTextInputFormatter` blocks non-alphanumeric characters at the keyboard level; `_sanitizeJersey()` strips non-alphanumeric chars and clamps to 4 characters at save time as defense-in-depth against API-level bypasses
                             - **Email normalization:** Trim + lowercase applied before all auth and member-lookup operations

                             ### 4.6 Secrets Management

                             - Supabase credentials (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) are injected at build time via `--dart-define-from-file=config.json` and are never hardcoded in source
                             - `config.json` is excluded from version control

                             ---

                             ## 5. Security & Compliance Hurdles

                             ### 5.1 COPPA (Children's Online Privacy Protection Act)

                             **Risk Level: HIGH (partially mitigated)**

                             The app collects PII from student athletes who may be under 13. COPPA applies to operators of online services directed at children under 13 (or with actual knowledge they are collecting data from children under 13).

                             **Current mitigations:**
                             - **Age-confirmation checkbox (v1.12):** Sign-up now requires the user to check "I confirm I am 13 or older" — provides a soft gate and establishes user acknowledgment

                             **Remaining concerns:**
                             - The age-gate is a checkbox — there is no technical enforcement or parental consent workflow for users who falsely confirm age
                             - Guardian email is collected but there is no formal parental consent verification mechanism

                             **Recommendations:**
                             - Document in the privacy policy and App Store listings that the app is intended for users 13 and older
                             - Implement a formal parental consent workflow if the app is ever extended to users under 13

                             ---

                             ### 5.2 FERPA (Family Educational Rights and Privacy Act)

                             **Risk Level: MEDIUM-HIGH**

                             FERPA protects educational records of students at schools receiving federal funding. If AOD is used by public school coaches and stores attendance records linked to students, it may fall under FERPA's definition of an "educational record" or a system that processes such records on behalf of a school.

                             **Concerns:**
                             - Attendance records (status: present/absent/late/excused) may be considered educational records if used in conjunction with school operations
                             - If coaches are school employees and AOD is used on behalf of the school, AOD could be classified as a "school official" with legitimate educational interest — requiring a formal data-sharing agreement

                             **Recommendations:**
                             - Add a terms-of-service clause clarifying the scope of data use and the relationship between AOD and educational institutions
                             - Consider a data-processing agreement (DPA) template for schools that adopt AOD formally
                             - Ensure student records can be exported and/or deleted on request (right of access and correction under FERPA)

                             ---

                             ### 5.3 GDPR / CCPA (General Data Protection / California Consumer Privacy)

                             **Risk Level: MEDIUM**

                             If any users or athletes are located in the EU or California, GDPR and/or CCPA requirements apply.

                             **Concerns:**
                             - No explicit privacy policy or consent banner is present in the current UI
                             - No mechanism to export all personal data on user request (GDPR Article 20 — data portability)
                             - ~~Account deletion removes auth and public data without scrubbing game roster JSONB entries~~ **RESOLVED (v1.12):** `delete_player` SECURITY DEFINER RPC atomically scrubs all game roster JSONB references before deletion; `delete_account` scrubs all players linked to the account before tearing down the account rows
                             - ~~`shared_preferences` on-device data is not encrypted~~ **RESOLVED (v1.12):** Cache migrated to `flutter_secure_storage` (mobile); Web cache disabled entirely
                             - No documented data retention policy

                             **Recommendations:**
                             - Add a privacy policy accessible from the login screen
                             - Implement a "Download my data" export feature
                             - Document and enforce a data retention policy (e.g., inactive accounts deleted after 2 years)

                             ---

                             ### 5.4 On-Device Cache Exposure

                             **Risk Level: LOW**

                             ~~The `OfflineCacheService` persisted player PII and game roster data to `shared_preferences` in plaintext.~~ **RESOLVED (v1.12):** Mobile cache migrated to `flutter_secure_storage`; Web cache disabled entirely via `kIsWeb` compile-time guard — no PII is written to browser storage on the Web target.

                             **Remaining concerns:**
                             - Cached mobile data still includes full player names, emails, guardian emails; payload minimization has not been applied (low priority given encryption)

                             **Recommendations:**
                             - Consider limiting cached fields to the minimum necessary (e.g., name and jersey number only) as additional defense-in-depth

                             ---

                             ### 5.5 Invite Code Security

                             **Risk Level: LOW-MEDIUM**

                             Team invite codes are 6-character alphanumeric codes with an expiry time.

                             **Concerns:**
                             - A 6-character code from a typical [A-Z0-9] charset has approximately 2.2 billion combinations; without rate-limiting on the `redeem_team_invite` RPC, brute-force enumeration is theoretically possible
                             - Anyone with the code (e.g., a forwarded group chat message) can join the team without the coach's explicit approval of each individual

                             **Recommendations:**
                             - Confirm and document rate-limiting on the `redeem_team_invite` RPC (ideally at the Supabase edge or PostgREST level)
                             - Consider adding an `accepted_by` audit log on invite redemptions
                             - Add an optional coach-approval step before the redeemed user gains full team access

                             ---

                             ### 5.6 Role Escalation

                             **Risk Level: LOW-MEDIUM**

                             **Concerns:**
                             - `updateMemberRole()` blocks client-side promotion to `owner` and requires `transferOwnership()`, but this enforcement is an application-level check rather than a SECURITY DEFINER RPC
                             - A modified client could potentially bypass this check and issue a direct `UPDATE team_members SET role='owner'` if RLS does not explicitly block self-promotion or promotion-to-owner by non-owners
                             - ~~The `removeMemberFromTeam` sole-owner guard was implemented client-side, creating a potential TOCTOU race condition~~ **FIXED (v1.12):** `removeMemberFromTeam` now delegates to the `remove_member_from_team` SECURITY DEFINER RPC which performs the owner count and DELETE inside a single transaction with row-level locking
                             - ~~`deletePlayer` removed the player row without scrubbing game roster JSONB entries~~ **FIXED (v1.12):** `deletePlayer` now calls the `delete_player` SECURITY DEFINER RPC which atomically scrubs all roster references and deletes the player row in a single transaction

                             **Recommendations:**
                             - Move the owner-promotion block into a SECURITY DEFINER RPC so it is enforced at the database layer
                             - Add an RLS policy that prevents any user from directly setting `role = 'owner'` on `team_members` without going through the `transfer_ownership` RPC

                             ---

                             ### 5.7 Supabase Anon Key Exposure (Web Target)

                             **Risk Level: LOW-MEDIUM**

                             The Supabase `ANON_KEY` is embedded in the compiled web bundle (JavaScript) at build time via `--dart-define-from-file`. On the Web target (GitHub Pages), this key is visible to anyone who inspects the JavaScript bundle.

                             **Concerns:**
                             - The anon key is designed to be public-facing and is scoped by RLS, but if RLS policies have gaps, the anon key provides a direct entry point to the Supabase API from outside the app
                             - Any user can open DevTools, extract the anon key, and make arbitrary PostgREST queries against the Supabase project's public schema

                             **Recommendations:**
                             - Regularly audit all RLS policies on every table (`players`, `teams`, `team_members`, `game_rosters`, `users`, `team_invites`) to ensure no row is accessible without a valid authenticated session
                             - Enable Supabase's built-in rate limiting and consider adding custom rate-limit rules for auth endpoints
                             - Confirm the service role key is never present in client code or build artifacts

                             ---

                             ### 5.8 Error Message Information Leakage

                             **Risk Level: LOW (largely resolved)**

                             ~~Some error messages passed to the UI included raw exception text, potentially disclosing schema names, constraint names, or internal structure.~~ **RESOLVED (v1.12):** All `player_service.dart` catch blocks now route through `_dbError()` which replaces `PostgrestException` details with a static "Update failed." message. `changeEmail` returns the same generic message on all failure paths.

                             **Remaining concerns:**
                             - `linkPlayerToAccount` surfaces readable RPC exception strings for "No account found for $playerEmail" (includes the email address) and "No player found on this team" — these are intentional user-facing messages but include PII (the email)

                             **Recommendations:**
                             - Review whether `linkPlayerToAccount` error messages should omit the email address (replace with "No account found for this email address")

                             ---

                             ### 5.9 Missing Input Validation

                             **Risk Level: LOW (partially resolved)**

                             **Current mitigations:**
                             - ~~`jerseyNumber` stored without sanitization — minor XSS vector on Web~~ **RESOLVED (v1.12):** Jersey number field uses `FilteringTextInputFormatter` (alphanumeric only, max 4 chars) with a server-side `_sanitizeJersey()` backup

                             **Remaining concerns:**
                             - Email fields are normalized (trim + lowercase) but not validated against an email regex before being sent to the database
                             - Free-text fields (`firstName`, `lastName`, `organization`, `teamName`, `position`) have no maximum-length constraint enforced client-side, relying entirely on database column constraints

                             **Recommendations:**
                             - Add client-side email format validation before submitting auth or member-lookup requests
                             - Enforce reasonable character limits on text inputs (e.g., max 50 chars for names)

                             ---

                             ## 6. Compliance Summary Table

                             | Framework | Applicability | Current Status | Priority |
                             |---|---|---|---|
                             | COPPA | High — minor athletes likely in user base | Age-confirmation checkbox added (v1.12); no parental consent flow | **High** |
                             | FERPA | Medium-High — school athlete data, attendance records | No DPA; no data-export feature | **High** |
                             | GDPR | Medium — EU users possible | No privacy policy; no data portability | **Medium** |
                             | CCPA | Medium — California users likely | No privacy policy; no opt-out mechanism | **Medium** |
                             | General data security | All deployments | Strong RLS + SECURITY DEFINER RPCs; encrypted mobile cache; Web cache disabled; cache wipe on all logout paths; JSONB scrub on player/account delete; PostgrestException sanitization; email enumeration prevention (all v1.12) | **Ongoing** |

                             ---

                             ## 7. Recommended Remediation Priorities

                             1. **Add a privacy policy** accessible from the login screen before public launch (addresses GDPR, CCPA, and App Store requirements)
                             2. **Implement formal parental consent** for users under 13 if the app is extended below high school age (COPPA); current age-confirmation checkbox is a soft gate only
                             3. **Move owner-promotion enforcement into a SECURITY DEFINER RPC** so the block on `updateMemberRole()` is enforced at the database layer, not just the client
                             4. **Add a "Download my data" export feature** (GDPR Article 20 data portability)
                             5. **Review `linkPlayerToAccount` error messages** to avoid including the email address in user-facing exception strings
                             6. **Add client-side email format validation** before submitting auth and member-lookup requests
                             7. **Document and enforce a data retention policy** (e.g., inactive accounts purged after 2 years)
