# CruiseConnect — Architecture & Refactor Blueprint

> Status: living document. Captures the clean-architecture target, the layer
> rules, and the prioritized, **strictly behavior-preserving** refactor plan.
> Created 2026-06-26 during the post-Codex structure pass.

## 1. Layer model (dependencies point INWARD only)

```
presentation  ──▶  application  ──▶  data  ──▶  domain
   (UI)            (providers)      (services)   (pure models)
```

1. **`domain/`** — innermost. Pure Dart value objects (`models/`) + repository
   abstractions. MUST NOT import Flutter, Supabase, Mapbox, http, or anything
   from `data`/`application`/`presentation`. Reference DTO shape: Codex's
   `community_chat_message.dart` (const ctor + `fromJson`/`toJson` + defensive
   `_readMap` helpers).
2. **`data/`** — implements domain abstractions. `services/` (Supabase / Mapbox /
   GraphHopper / http access) + pure IO-free helpers (`geo_distance.dart`,
   `geo_bearing.dart`, `route_semantics.dart`, `route_debug_state.dart`). May
   import `domain` + external SDKs. MUST NOT import `application`/`presentation`.
3. **`application/`** — `providers/` (ChangeNotifier). **This is the de-facto DI
   container**: `main.dart` registers a `MultiProvider`. There is intentionally
   NO `get_it`/`riverpod`; new injectable seams are added as thin instance
   facades over the existing static services (additive). May import `domain` +
   `data`. MUST NOT import `presentation`.
4. **`presentation/`** — outermost. `pages/` + `widgets/` + `controllers/`. Talks
   to `application` via `context.read/watch`. Target: depend downward through
   providers, not reach into the DB SDK directly. Reference controller shape:
   Codex's `cruise_navigation_controller.dart` (pure, param-injected, no State).

**Dependency rules**
- Inward-only; no outward or sideways imports across layer boundaries.
- `domain` is dependency-free and Flutter-free.
- DTOs cross the `data → presentation` boundary as TYPED objects; but a boundary
  DTO that maps to mutable/optimistic UI state (e.g. a chat store that carries
  synthetic non-DB keys like `_status`/`client_tag`) stays normalization-only —
  do NOT thread an immutable DTO into a store that mutates maps in place.
- Pure math/string utilities are cross-cutting; until physically moved to
  `core/` they live in `data/services/` but must remain IO-free.

## 2. Target folder structure

`SAFE-NOW` = mechanical, verifiable, reversible. `BLUEPRINT` = deferred until
after the store launch (blocked by 62 test files importing services by exact
path + mockito mock paths — physical relocation is a big-bang import rewrite).

```
lib/
├── main.dart                       [MultiProvider DI graph — do NOT restructure]
├── core/                           [pure, IO-free cross-cutting]
│   ├── constants.dart              [API keys/tokens — NEVER print, NEVER move]
│   ├── deep_links.dart  input_limits.dart
│   └── (BLUEPRINT) geo/, routing/  ← move geo_*/route_semantics here later
├── domain/
│   ├── models/                     [pure value objects + DTOs]
│   └── repositories/               [abstractions]
├── application/providers/          [ChangeNotifier = DI seam]
├── data/
│   ├── repositories/               [concrete impls]
│   └── services/                   [~60 files; BLUEPRINT: cluster into
│       routing/ navigation/ social/ maps/ user/ gamification/ sub-folders]
└── presentation/
    ├── controllers/                [cruise_navigation_controller.dart (Codex)]
    ├── pages/
    │   ├── cruise_mode_page.dart    [god-object — shrink via SAFE pure extracts]
    │   └── cruise/route_loading_phases.dart   [SAFE-NOW ✓ done]
    └── widgets/cruise/             [extracted presentational widgets]
```

## 3. Done in this pass (behavior-preserving, each verified by `flutter analyze` + full `flutter test`)

| Commit | Change | Verification |
|--------|--------|--------------|
| `chore(arch)` | Removed 10 dead/orphaned files (scaffolding widgets, orphan `RouteBookmark` model+repo+impl, dead dialogs/widgets, the template `widget_test.dart`). 0 inbound refs confirmed on `main`. | analyze clean, 862 tests green |
| `refactor(arch)` | Extracted **`RouteLoadingPhases`** (5 loading-phrase lists + selection/clamp) out of `cruise_mode_page` into a pure, tested `presentation/pages/cruise/route_loading_phases.dart`. | + new test (9 cases), 871 green |
| `refactor(arch)` | Extracted **`GeoBearing`** (6 pure angle/bearing statics, byte-identical formulas) out of `cruise_mode_page` into `data/services/geo_bearing.dart` (sibling of Codex's `GeoDistance`). All ~14 call sites delegate. | + new test (pinned math), 880 green |

Net: two god-object methods/constant-clusters became pure, **independently
testable** modules; dead weight removed; new regression coverage added where
the page itself has almost no unit tests.

## 4. Prioritized blueprint (NOT yet executed — deferred for safety / launch)

Ordered safest-first. Each is strictly behavior-preserving and must be verified
with `flutter analyze` + `flutter test` after every step.

1. **`RouteManeuverParser` extraction** *(biggest win, test-covered → self-verifying)* —
   move the ~1,250-line maneuver/coordinate/icon/translation cluster out of
   `route_service.dart` into `route_maneuver_parser.dart`. HARD CONSTRAINT: keep
   `extractManeuvers`, `extractCoordinates`, `iconForManeuver`, `formatDistance`,
   `directionText`, `filterManeuvers` as one-line instance delegators on
   `RouteService` — 6 test files in `test/route/` call them as instance methods.
   Change no string/regex/threshold.
2. **Presentational widget extraction from `cruise_mode_page`** — marker/puck/
   info/POI/construction builders → `widgets/cruise/`. *Touches the visually
   critical, crash-historically-sensitive puck → do with on-device QA, not
   pre-launch blind.*
3. **`AuthProvider.currentUserId` + pass-through actions** — migrate the 18
   direct `AuthService.*` + 15 `Supabase.instance.client` reaches in presentation
   to go through the provider (additive; keep the statics).
4. **Typed `GroupChatMessage` DTO** mirroring Codex's `CommunityChatMessage`,
   applied only at the `GroupChatService.fetchMessages` boundary.
5. **Physical `data/services/` clustering** + moving pure helpers into `core/` —
   BLUEPRINT only; blocked by 62 hardcoded test-import paths.

## 5. Explicit do-not-touch (high-risk hot paths)

- `route_service.dart` `_invoke` + the fallback cascade (`generateRoundTrip`,
  `_tryRoutePoolFallback`, …): splitting risks reordering side effects =
  changing which fallback wins.
- `cruise_mode_page` stateful builders/helpers reading live nav/GPS/camera state.
- `RouteServiceException` / `RouteErrorType` (referenced by 7/4 files) — moving
  them is wide churn; extracting only the mappers would create a circular import.
- `core/constants.dart` / `secrets.dart` — NEVER print keys, NEVER move.
- Never undo any hunk of Codex commit `3c53805`.
