# KDWarm — Changelog

## [0.6.9] — 2026-06-18

### Added
- **VarDumper capture panel** — new Dumps sidebar item intercepts `dump()`/`dd()` calls from Symfony/Laravel PHP apps via a TCP socket server (port 9912) and displays them in a native SwiftUI tree view. Enabled per-toggle; injects `auto_prepend_file` hook via `php.ini` without modifying app code.
- **ER diagram** — Database panel now shows an entity-relationship diagram built from live FK introspection, rendered with native CoreGraphics layout engine.
- **Persistent query history** — executed SQL stored newest-first with recall, consecutive deduplication, 500-entry cap, and clear history.
- **Multi-tab query workspace** — SQL editor supports independent query tabs, each preserving its own SQL, result, error, and busy state.
- **Tunnel QR share UI** — active tunnel rows show a QR button; popover renders the public URL as a CoreImage QR code plus selectable text for quick mobile testing.
- **Xdebug toggle** — per-PHP-version Xdebug control via `conf.d/20-xdebug.ini`; enable provisions and verifies the `.so` before patching config.
- **VS Code debug config** — PHP site menu generates `.vscode/launch.json` with port `9003`, preserving existing configs and mapping nested docroots.
- **MySQL + PostgreSQL database creation** — dedicated Create Database actions for both engines.
- **Multi-engine manual import** — import supports MySQL `.sql`, PostgreSQL `.sql/.dump`, SQLite `.sqlite/.db`, and MongoDB dump folders with read-only gating.
- **Add Site two-mode flow** — create new folder by name or choose existing, with editable domain and PHP version.
- **MongoDB Create Database edge case** — materializes empty databases via a starter collection.

### Fixed
- **Cloudflare tunnel links/assets** — quick tunnel proxies through a dedicated loopback nginx vhost preserving the public `trycloudflare.com` Host; app links, CSS, JS, redirects, and child routes no longer collapse to local `.test` URLs.
- **Secure-site tunnel redirects** — tunnel vhost injects `HTTPS` / `X-Forwarded-*` FastCGI params so secure apps see public HTTPS without local-domain redirect loop.
- **Tunnel cleanup** — stale `tunnel-*.conf` vhosts removed when stale launchd jobs are reaped.

### Testing
- `xcodebuild -project KDWarm.xcodeproj -scheme KDWarmKit-Tests -destination 'platform=macOS' test` — 530 tests, 30 skipped, 0 failures.
- `xcodebuild -project KDWarm.xcodeproj -scheme KDWarm -destination 'platform=macOS' build` — build succeeded.

---

## [Unreleased] — 2026-06-15 — Phase 8: MongoDB Document Track (M4 Milestone)

### Added
- **Root `DatabaseDriver` protocol** (`kind` + `ping`) — common ancestor now refined by both `RelationalDriver` (MySQL/PostgreSQL/SQLite) and the new `DocumentDriver`. Relational driver contracts are unchanged.
- **MongoDB driver** (`MongoDriver`, MongoKitten — pure Swift, no libmongoc) — connect/list databases & collections / paginated `find` with JSON filter / `aggregate` (server-side `$limit`) / insert·update·delete / create·drop collection. Per-operation connect with `MongoCluster` disconnect; managed-engine preflight maps not-installed/not-running like the SQL drivers; read-only connections reject all writes. Managed MongoDB profile (loopback, no-auth, :27017) always in the sidebar.
- **Document track UI** — separate from the relational grid: `CollectionTreeView` (databases → collections, create/drop via context menu), `DocumentListView` (paginated JSON cards, JSON filter bar), `DocumentEditorView` (validated JSON insert/edit). `DatabaseSectionView` routes relational vs document by connection kind; one shared connection sidebar drives both `DatabaseViewModel` and the new `DocumentViewModel`.
- **BSON↔JSON mapper** (`MongoJSONMapper`) — extended-JSON-style hints for ObjectId/Date/Binary/Timestamp (round-trip) and Decimal128 (display-only; BSON 8.x exposes no public string initializer). Documents cross the NIO→@MainActor boundary as the `Sendable` `DocumentRecord`; no BSON types leak into the VM or UI.
- **Tests** — `MongoJSONMapperTests` + `DocumentViewModelTests` (CI-blocking, engine-free); `MongoDriverIntegrationTests` (opt-in `KDWARM_DB_IT=1`, validated against MongoDB 7.0). Suite: 318 pass, 28 skipped, 0 failures.

### Changed
- **project.yml** — added `MongoKitten` + `MongoCore` (link statically; `otool -L` confirms no new dylib).

## [Unreleased] — 2026-06-15 — Phase 7: PostgreSQL & SQLite (M3 Milestone)

### Added
- **PostgreSQL driver** (`PostgresDriver`, PostgresNIO) — connect/browse/SQL/CRUD/structure for managed + external PostgreSQL. Browse-level "database" maps to a PG schema; server-side read-only via `default_transaction_read_only`; write guard via transaction + `RETURNING 1`. Managed PG profile (loopback, trust auth, no TLS) always in the sidebar.
- **SQLite driver** (`SQLiteDriver`, GRDB.swift) — file-based connections via a file picker; full browse/SQL/CRUD/structure using GRDB's vendored engine and PRAGMA introspection; read-only opens the file read-only.
- **Engine picker** in `AddConnectionSheet` (MySQL / PostgreSQL / SQLite) — host form vs SQLite file picker.
- **Tests** — `SQLiteDriverTests` + `SQLDialectMultiEngineTests` (CI-blocking, engine-free); `PostgresDriverIntegrationTests` (opt-in `KDWARM_DB_IT=1`). Suite: 287 pass, 24 skipped, 0 failures.

### Changed
- **SQLDialect** is now a per-kind strategy: identifier quoting + placeholder style (`?` for MySQL/SQLite, `$N` for PostgreSQL). MySQL output unchanged.
- **project.yml** — added `postgres-nio` + `GRDB.swift` (both link statically; `otool -L` confirms no dylib creep).

### Deferred
- Import/Export (`DumpService`) for PostgreSQL/SQLite — stays MySQL-only this phase; `canDump` gated to MySQL connections.

## [0.3.0] — 2026-06-15 — Phase 3 & 4: MySQL Relational UI + Row CRUD (M1 & M2a Milestones)

### Added
- **Database Editor dashboard section** — MySQL/PostgreSQL connection picker (managed + saved profiles), schema tree browser (databases → tables), paginated table data explorer, and SQL query runner with results grid.
- **RelationalDriver abstraction** — Pure Swift driver protocol + MySQLNIO concrete impl; EventLoopGroup lifecycle, per-query connection pooling.
- **DatabaseViewModel** — @MainActor Observable state machine: connection selection → database/table pick → pagination + SQL execution. Generation tokens prevent stale async results.
- **Credential storage** — KeychainStore (secure password vault) + ConnectionStore (JSON metadata for saved profiles).
- **AppKit ResultsGridView** — Runtime-dynamic column rendering from QueryResult; NULL and blob type awareness.
- **Engine gateway** — Connection failures (engine not installed/running) route to ServiceManager install/start UI instead of dead ends.

### Changed
- **DashboardWindow** — `.database` promoted from DEBUG harness to shipped sidebar item with "cylinder.split.1x2" icon.
- **UI hierarchy** — Database views in KDWarm app target; ViewModel + driver logic in KDWarmKit (7 unit tests).

### Phase 4: Row CRUD + Destructive Guard (M2a)

Row-level insert, update, delete for single-table browse with server-safe SQL composition:

#### Added
- **DML composition** (`SQLDialect.swift`) — Parameterized INSERT/UPDATE/DELETE with `?` placeholders; identifier quoting; keyless-write refusal (no UPDATE/DELETE without primary key).
- **Transactional writes** (`MySQLDriver+CRUD.swift`) — `START TRANSACTION → prepared DML → COMMIT` with `affectedRows == 1` guard; rolls back if count mismatches.
- **Cell-to-SQL mapping** (`MySQLCellMapper.swift`) — Binds Cell values (incl. BLOB as binary) to parameterized statements.
- **Destructive guard** (`DestructiveGuard.swift`) — Flags keyless DELETE/UPDATE + DROP/TRUNCATE; UX confirm net (NOT a trust boundary — real boundary is server-side read-only in Phase 9).
- **Row editor UI** (`RowEditorView.swift`) — Insert/edit sheet with NULL toggle per nullable column; PK read-only in edit mode.
- **TableDataView toolbar** — Add/edit/delete row buttons + delete confirm + edit-error alert; row selection binding.
- **Query editor destructive confirm** — Alert for destructive SQL (DROP/TRUNCATE/unkeyed DELETE/UPDATE).

#### Changed
- **DatabaseViewModel** — Added edit state: `canEditRows`, `editDisabledReason`, `primaryKeyColumns`, `pendingDangerousSQL`, `editError`; insert/update/delete row ops keyed on primary key.
- **RelationalDriver protocol** — Added `insert`, `update`, `delete` methods.
- **ResultsGridView** — Row selection binding; double-click-to-edit.

#### Known Limitations
- **Edit scope** — Single-table browse WITH primary key only; no-PK tables and SQL-runner/JOIN results remain read-only.
- **Nullable blank handling** — Empty-string-on-nullable-insert unreachable; blank → server default.
- **Destructive guard scope** — Does not flag REPLACE or ALTER..DROP.
- **Pagination edge case** — Empty trailing page when total rows are an exact multiple of page size.

### Phase 6: Structure/DDL + Import/Export (M2c — completes Milestone M2)

Table structure browsing, DDL (create/alter/drop), and database/table import-export via the on-demand `mysqldump`/`mysql` clients.

#### Added
- **DDL composition** (`SQLDialect+DDL.swift`) — CREATE/ALTER (add/drop column)/DROP TABLE generation; identifiers quoted via `quoteIdent`, column types restricted via `sanitizeType` (raw types can't extend DDL). Every statement is shown verbatim and confirmed before running (no blind DDL).
- **Schema introspection** (`MySQLDriver+Structure.swift`) — `indexes()` from `information_schema.STATISTICS`, grouped into `IndexInfo`; new `ColumnDefinition` DDL-input model.
- **DumpService** (`DumpService.swift` + `DumpServiceValidation.swift`) — `mysqldump`/`mysql` via off-main `Process`. Credentials ride a `--defaults-extra-file` (created mode 0600, defer-deleted) — never argv/env. Host/db/table/user allowlist-validated; user values passed after a `--` argv terminator. Engine-not-installed → typed `engineNotInstalled` (no crash). Partial export file removed on failure.
- **Structure UI** (`TableStructureView.swift`) — Columns + indexes view with DDL actions and SQL-preview confirm.
- **DDL form** (`DDLActionSheet.swift`) — Create-table / add-column composer (delegates SQL composition to the view model).
- **Import/Export sheet** (`ImportExportSheet.swift`) — Export DB/table to `.sql`; import into a NEW database by default (created up front); replacing an existing database requires an explicit confirm.

#### Changed
- **DatabaseViewModel** — Added `currentIndexes`, `pendingDDL`, `ddlError`, `dumpStatus`, `DumpStatus` enum, injected `DumpService`; structure/DDL and dump orchestration split into `DatabaseViewModelStructure.swift` + `DatabaseViewModelDump.swift`.
- **RelationalDriver protocol** — Added `indexes(database:table:)`.
- **DatabaseSectionView** — New Structure tab + Import/Export toolbar button.

#### Security
- **Read-only contract extended to writes via dump** — Import (a write/DDL channel that bypasses the driver's `SET SESSION TRANSACTION READ ONLY`) is gated on `!readOnly` in both UI and view model; `confirmDDL()` also refuses on read-only connections (defense-in-depth).

#### Known Limitations
- **mysqldump/server version skew** — On external hosts a client/server version mismatch surfaces as a raw stderr error (documented, not auto-handled).
- **Import is whole-DB** — No table-level import; a dump loads into one target database.

### Testing
- **Phase 3:** `DatabaseViewModelTests` — 7 unit tests covering state machine transitions, pagination, async invariants.
- **Phase 4:** `SQLDialectDMLTests` — 7 tests (parameterized INSERT/UPDATE/DELETE, identifier quoting, keyless-write refusal). `DestructiveGuardTests` — 7 tests (flag detection). `DatabaseViewModel CRUD tests` — edit state, insert/update/delete row ops. `MySQLDriverCRUDTests` — optional integration suite (gated on `KDWARM_DB_IT=1`).
- **Build status:** 236 logic tests pass, 13 skipped (integration).
- All existing tests pass; integration suite gated on `KDWARM_DB_IT=1`.

---

## [0.2.0] — 2026-06-13 — MongoDB Extension + Driver Abstraction

### Added
- MongoDB (v7.0) on-demand install via fastdl.mongodb.org (SSPL-1.0 attribution, no redistribution).
- Driver abstraction groundwork for multi-DB support.

---

## [0.1.0] — 2026-05-XX — MVP: Site Manager + Services

### Added
- Manual site registration under `~/Sites/WWW/` with editable `.test` domains.
- Trusted local TLS via mkcert + System Keychain integration.
- Service manager (Nginx, PHP-FPM, MySQL, PostgreSQL, Redis, Mailpit).
- Runtime manager (bundled PHP 7.4/8.1/8.3/8.4, Node 22; on-demand Python/Go/Ruby/Java).
- Per-version `php.ini` editor with syntax validation.
- Log viewer with severity filtering.
- Mail catcher (Mailpit).
- Auto-update via Sparkle.
