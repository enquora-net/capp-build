# capp-build — Milestone Reference, June 7 2026

## Current state

Builds and runs clean on Lisette 0.3.1. All lints addressed through current
version. Executes end to end against `toolchain_test` (2-file Cappuccino
application). Phases 1–5 do real work; phases 6–9 are typed stubs.

## Pipeline

**Phase 1 ValidateProjectStructure** — Implemented. Parses Info.plist,
constructs `ValidatedProject` proof object. Three typed constructors
(`parse_plist_meta`, `validate_framework_roots`, `validate_application`)
accumulate all defects before returning. `./Frameworks` is canonical;
`OBJJ_INCLUDE_PATHS` in `index.html` acknowledged as the runtime resolution
mechanism but not yet read.

**Phase 2 WalkSourceTree** — Implemented. Directory traversal, file
classification by extension, skip list `["Frameworks", "Build",
".cappuccino"]`. Delegates to `capp.SourcePaths`. The `"Build"`
capitalisation fix was the last applied correction.

**Phase 3 ParseSources** — Implemented. Calls `capp.ParseProject`, extracts
`RawImport` values from `objj_import` nodes. Narrow CST access — handles
only import nodes, not the full grammar. Carries 0-based source positions.

**Phase 4 ResolveImports** — Implemented. Fixed-point iteration over
quote-form imports building `ImportEdge` values. Angle-bracket imports
recorded as `FrameworkDep` without source resolution. Carries 1-based
positions (normalised from phase 3's 0-based).

**Phase 5 TopologicalSort** — Implemented and adversarially tested. Kahn's
algorithm with DFS cycle extraction. Survived four review rounds (O(V·E)
regression, backing-array aliasing, greedy-traversal dead-end, hidden
quadratic in cycle extraction). Found real import cycles in
AppKit/Foundation — the acid test. `CycleError` implements Go `error`
interface with cycle path and entry file/line/col.

**Phase 6 BuildSymbolTable** — Stub. Types declared: `SymbolTable`,
`ClassSymbol`, `IvarSymbol`, `MethodSymbol`, `ProtocolSymbol`,
`ForwardSymbol`, `TypedefSymbol`.

**Phase 7 TypeCheck** — Stub.

**Phase 8 Compile** — Stub. During bootstrap, jake produces compiled records
externally.

**Phase 9 Archive** — Stub.

## CST model (cst.lis, 904 lines)

Full-fidelity ADT model of the complete Objective-J grammar. ~120 types
covering JavaScript substrate plus ObjJ superset. Compiles clean. Recursive
types auto-boxed by compiler. `Statement.BlockStatement(StatementBlock)`
workaround for Go name collision. **Inert — no code instantiates any type.**

## Lowering (lower.lis)

Top-down skeleton for architectural review. `lower_program` implemented
(root level: hash_bang, statement list, extras filtering). `lower_statement`
stubs to `unhandled()` catch-all. Return-and-merge diagnostic discipline —
each helper returns `(result, diagnostics)`, callers merge. **Not wired into
any phase.** Node-kind string literals marked `CONST-PENDING` where
capp-parse lacks exported constants.

## Orchestration

`BuildPhase` enum with exhaustive `match` in `run()` — adding a variant
without a handler is a compile error. `BuildContext` carries `Option`-typed
output per phase. Phase isolation tested under real modification: phases
added, renumbered, split without cross-phase breakage.

## Key findings

**Framework import cycles** — Phase 5 found real cycles in Foundation and
AppKit. The legacy Node toolchain concealed them via lazy runtime loading.
These are latent defects, not a phase 5 fault. Must be resolved at source
level before the new toolchain can build frameworks. Does not block
application development; frameworks consumed as pre-built jake bundles.

**Michael Bach data point** — First external user project seen. 150+
Cappuccino applications with non-standard framework layout
(`Resources/cappFrameworks3/` instead of `./Frameworks`). Confirmed
`OBJJ_INCLUDE_PATHS` in `index.html` is the runtime resolution mechanism.
Decision: `./Frameworks` is canonical; the runtime directive should
eventually be read by phase 1 but is not urgent. The user's architecture
(one app per illusion) is itself the wrong pattern — should be one
application with illusions as frameworks.

## Settled architectural decisions

**CST→AST lowering** — the single firebreak where untyped CST becomes typed
AST. String dispatch on `node.Kind()` is irreducible (tree-sitter erases the
grammar's closed kind set to strings). Confined to `lower.lis`. Everything
downstream uses exhaustive `match` over closed Lisette sum types.

**Dispatch mechanism** — `match` on the kind string, one arm per grammar
node kind, catch-all recording unhandled kinds as diagnostics. No stored
function table; no query-based extraction; no hand-written parser. The
`match` arm is the dispatch.

**Completeness checking** — The compiler cannot check that all node kinds
have handlers (no reflection, `#[iterate]` limited to payload-free enums).
Source of truth is `cst.lis`, not `node-types.json`. Unhandled nodes emit
errors caught in CI against the AppKit/Foundation corpus — authoritative
because Objective-J's grammar is closed.

**Constructors as `impl`s on AST types** — typed-in, typed-out, no CST
knowledge. Handlers are free functions in `lower.lis` — CST-in, typed-out.
Dependency arrow: `lower.lis` → `cst.lis`, never reverse.

**Hand-written ADTs and handlers** — no code generator from
`node-types.json`. The grammar is stable and changes are small. If
generating dispatch, ADTs should also be generated — therefore neither.

**Pre-release commit history** — kept private on public release, following
Folio and Lisette precedent. Architectural and inline commentary is already
sufficient; commit history provides no additional value to consumers.

## Deferred work

**Build directory configurability** — Phase 2 skip and phase 9 output are
the same value hard-coded twice (`"Build"`). Must converge on one
`BuildConfig` value when the configuration resolver is built. Deferred:
configuration space genuinely unknown.

**Framework builds** — Blocked on source-level cycle-breaking in
Foundation/AppKit. Sequenced after pipeline proven on independent
applications.

**`node-types.json` code generation** — Declined for current scope. Noted as
framework-track trigger if total grammar coverage becomes a requirement.

**capp-parse expansion** — Expand node-kind constant surface (currently
three); add `NamedChild`/`NamedChildCount` iteration; case-insensitive
skip-dir matching in `core.SourcePaths`.

**Lisette author notes** — Confirm recursive-ADT auto-boxing as supported
guarantee; Go-name-collision disambiguation; payload-bearing enum iteration.

## NextStep.txt

**Stale.** Still lists phase 5 as "STUB — NEXT" and uses the old 1–8 phase
numbering (phase 6 BuildSymbolTable was split from TypeCheck during this
session, creating the 1–9 numbering). Should be updated before new work
resumes.

## Next concrete work

1. `impl`s on the AST types — constructors and operations (selector
   reconstruction, type rendering, position accessors). Pure functions over
   `cst.lis`, testable against hand-built values. First real load on the
   model.
2. Fill `lower_statement` dispatch arms breadth-first for
   `main.j`/`AppController.j` node kinds.
3. Wire `lower.lis` into phase 6.
4. Build symbol table from AST, not CST.
