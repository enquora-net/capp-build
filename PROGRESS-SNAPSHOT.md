# capp-build — Milestone Reference, June 12 2026

## Current state

**The lowering tier is complete.** Builds and runs with zero lint warnings
on Lisette 0.3.4 against capp-parse BoundaryVersion 2. All corpora lower
with **zero unhandled and zero malformed diagnostics**:

- `toolchain_test` (2-file application): 7 top-level statements, 0 diagnostics
- AppKit (CappuccinoSource, 221 files): clean
- Foundation: clean
- Fieldwork (production application): clean

The sole deferred construct is the **destructuring tier** (array/object
patterns in declarator names, catch parameters, and for-in/of bindings),
still routed through named catch-alls. Its last observed corpus footprint
was a single `array_pattern` in CappuccinoSource Foundation. The model
already represents it fully (`DestructuringPattern`, `ObjectPattern`,
`ArrayPattern`, `Pattern`/`RestPattern`/`AssignmentPattern`, and
`Destructuring` variants on `VariableDeclaratorName`, `ForBinding`, and
`CatchParameter`), so closing it is arms-only work whenever wanted.

Phases 1–5 do real work; lowering runs inside phases 3 and 4; phases 6–9
are typed stubs. `UNHANDLED-EXPRESSIONS.txt` is now historical — the
worklist it ranked has been worked to zero.

## Pipeline

**Phase 1 ValidateProjectStructure** — Implemented. Parses Info.plist,
constructs `ValidatedProject` proof object. Three typed constructors
accumulate all defects before returning. `./Frameworks` is canonical;
`OBJJ_INCLUDE_PATHS` in `index.html` acknowledged as the runtime resolution
mechanism but not yet read.

**Phase 2 WalkSourceTree** — Implemented. Directory traversal, file
classification by extension, skip list `["Frameworks", "Build",
".cappuccino"]`. Delegates to `capp.SourcePaths`; skip matching
case-insensitive in capp-parse core.

**Phase 3 ParseSources** — Implemented. Calls `capp.ParseProject`, extracts
`RawImport` values, and lowers each CST to its typed `Program` while the
trees are live (trees do not outlive phase 3). `ParsedUnit` carries
`{ source, imports, program }`. Lowering diagnostics print inline with
file:line:col plus a summary line. 0-based source positions.

**Phase 4 ResolveImports** — Implemented. Fixed-point iteration over
quote-form imports building `ImportEdge` values. Transitively discovered
files are lowered while their trees are live; parse-error files carry a
zero-filled empty `Program`. **Resolved June 12:** frontier units stay
edges-only — no retained AST, no symbols. AppKit, Foundation, and the other
contents of `./Frameworks` are produced by the legacy toolchain until the
normal application project structure is fully handled, so resolution of
symbols against framework bundles is a later, separate mechanism, not a
phase 4/6 concern.

**Phase 5 TopologicalSort** — Implemented and adversarially tested. Kahn's
algorithm with DFS cycle extraction. Found real import cycles in
AppKit/Foundation. `CycleError` implements Go `error`.

**Phase 6 BuildSymbolTable** — **Implemented June 12; compiles and lints
clean (`lis check`: 19 files, no issues). toolchain_test verified exact
against independent ground truth** (1 class, 2 methods, 1 ivar, 0
diagnostics — see EXPECTED-SYMBOL-COUNTS.md). Consumes
`ParsedUnit.program` in `ctx.sorted.order` —
the first consumer that never touches a string-keyed node; imports no
capp-parse constant. Symbol structs extended beyond the stub: every symbol
carries `guards: Slice<PreprocGuard>` (the full `#if` condition stack,
negated for `#else` branches); `MethodSymbol` gains `is_variadic` and
`is_synthesized`; `ProtocolSymbol` records inherited protocols and splits
`required`/`optional` per the ordered markers (initial state required);
`GlobalSymbol` added for `@global` at top level and inside implementations.
`@accessors` synthesizes getter/setter `MethodSymbol`s per the legacy
Preprocessor.js rules — property defaults to the ivar name, default setter
preserves a leading underscore as prefix (`_name` → `_setName:`), readonly
suppresses the setter, an explicit method with the same selector wins
silently — with one recorded deviation: symbols carry the declared ivar
type, not the legacy `(id)`. Selector reconstruction and type rendering
come from `cst_ops`, not reimplemented. Walk is pure return-and-merge
(`Harvest`/`IvarHarvest` accumulators).

**Phase 7 TypeCheck** — **Implemented June 12; compiles and lints clean;
toolchain_test verified exact** (all-zero summary: AppController's chain
exits to external CPObject before anything is checkable). Operates
entirely on `ctx.symbols`; no AST or CST consulted.
Scope is governed by decidability against the bootstrap world (project
symbols only): inheritance cycles among project-known classes → Error;
protocol-inheritance cycles → Error; protocol conformance → Warning per
missing required selector, reported only when the requirement closure is
complete and the class's ancestry terminates at a project-known root —
typed as `AncestryTerminal.Root | External | Cycle`, with open-world cases
counted indeterminate and silent. Implementations are sought across the
whole class group (primary + categories + synthesized accessors, unioned
across `#if` guards — the lenient reading). Name-unified `ClassWorld` /
`ProtoWorld` views; pure construction; reuses phase 6's `selector_key`.
**Deferred until the world closes:** message-send resolution, selector
signature verification at call sites, variable scope/usage analysis — all
need the full framework symbol surface to avoid systematic false
positives; the last also needs AST dataflow that belongs with phase 8
design.

**Phase 8 Compile — tier A implemented June 12 (evening session);
Phase 9 Archive — stub.** The JavaScript printer (`js_print.lis`, ~1100
lines) covers the full JS statement/expression surface of the typed AST:
all 28 Statement variants (8 routed through named deferral diagnostics —
the ObjJ/preproc tiers), all 10 Expression and all 30 PrimaryExpression
variants (8 ObjJ deferrals), patterns, classes, ES modules, and the
global-escape rewrite. `phase08_compile.lis` composes per-file records
(imports from `unit.imports`, payload behind the debug `\n\n` prologue,
no S record) and writes them to `Build/capp-build.build/<Mode>/Sources/`
— a deliberately distinct directory so the legacy
`Build/<project>.build` oracle is never clobbered. **Gate status: the
printer's hand-traced main.j payload and full record are byte-exact
against the legacy record (208 and 294 bytes, verified via
payload_oracle.py); `lis check` and the binary run remain to be executed
on the host** — the build sandbox has no Lisette toolchain, per the
established working method.

The emitter law was *recovered, not inferred*: the legacy generator
itself ships inside `toolchain_test/Frameworks/Objective-J/Objective-J.js`
(the acorn-based ObjJAcornCompiler); it was beautified and its visitor
table transcribed into PHASE-8-BRIEF.md ("The emitter law"), then
confirmed against oracle payloads (the un-indented `default:`, for-of
without indentation, `switch(` spacing, and `var` continuation rules all
corpus-verified). Two corrections to earlier recon: comments strip
without any blank-line echo (the leading `\n\n` is the compiler's
debug-mode prologue, emitted iff source maps are on — release payloads
have none); and **record-framing lengths are UTF-16 code units, not
bytes** (JS String.length; proven by CPDate.j's U+00B1 in Foundation.sj;
STATIC-BLOB-FORMAT.md corrected).

Tier decomposition unchanged (A: JS printer → B: ObjJ scaffolds →
C: dispatch → D: ObjJ expressions → E: records/modes); B–D route through
named deferral warnings. Deferred within phase 8: source maps, release
optimisations, HTTP/2 delivery, #if evaluation (needs the build-feature
environment legacy jake supplied; named diagnostic until then),
Clean-mode artefact removal.

**Tier A decisions (June 12, this session):**

1. *StringLiteral carries raw text* — the emitter echoes literals
   verbatim (quote character included), which the fragment/escape parts
   cannot reconstruct; `text: string` added to the model, populated at
   the single construction site in lower.lis via `node.Text()`.
2. *Method-rewrite deviation* — the legacy emitter with the global-escape
   transform enabled would print object-literal and class methods as
   `name = (...)`, invalid JavaScript. Corpus-invisible either way; the
   printer uses the transform-OFF mechanics (valid JS) for method values
   only. Named functions everywhere else rewrite unconditionally, as the
   runtime's default flag does.
3. *`using` declarations* — no legacy emitter exists; mechanical
   variable-declaration shape.
4. *record_length counts code points* — equals UTF-16 units throughout
   the BMP; a supplementary-plane character would be off by one, none
   exist in any corpus, and `payload_oracle.py check` exposes the case.
5. *@import is the one ObjJ statement tier A owns* — the legacy emitter
   writes `objj_executeFile(...)` inline at the statement's source
   position and the main.j oracle includes the prelude; the remaining
   ObjJ statements stay tier B deferrals.
6. *Directive prologue* — leading string-literal expression statements
   print bare; a non-directive `"use strict"` parenthesizes, matching
   acorn's directive semantics.

## CST model and operations

**cst.lis** (~120 ADTs) — Full-fidelity declaration-only ADT model of the
complete grammar. No longer mostly inert: the lowering instantiates the
large majority of its types; the remainder is the destructuring tier and a
handful of deliberately unreachable forms.

**cst_ops.lis** — Operations over the model (selector reconstruction, type
rendering, `position()` closure making `Statement.position()` total).
Verified by `capp-build verify model`: 16 checks, all passing.

## Lowering (lower.lis, ~4200 lines)

Complete and corpus-validated. The single firebreak: untyped CSTNode →
typed AST, executing inside phases 3 and 4. Read-only `Lowering { path }`
context; all helpers pure return-and-merge. Every kind and field string
from capp-parse's constant surface — zero literals — with one principled
exception: anonymous token kinds are their literal text (`"else"`,
`"else if"`, `":"`, `"*"`, `"async"`, `"@optional"`, `"@required"`,
comparison operators), used where the grammar provides no named node.

**Arm inventory (all tiers):**

- *Statements*: if/else, while, do, with, labeled, throw, switch
  (case/default), for (+ legacy `for (var x = init in y)` initializer),
  for-in/of, try/catch/finally, block scope, var/let/const,
  break/continue, empty/debugger/return, expression statements.
- *JS expressions*: assignment (standard and `@deref` targets; compound
  operators recovered by anonymous-child scan — `assignment_expression`
  has no operator field), augmented assignment, binary/unary/ternary/
  update, new, await, **yield** (optional argument; `yield*` via anonymous
  `*`), subscript, member access, calls (optional-chain and template calls
  surfaced as unhandled by design), object/array literals with spread,
  function expressions, **arrow functions** (single-identifier and list
  parameters; expression and block bodies), **generator functions**
  (expression and declaration forms), **template strings**
  (fragment/escape/substitution parts), regex.
- *ObjJ literals*: `@"…"`, `@selector` (unary/keyword by anonymous-colon
  discrimination), `@{…}` (key/value wrapper-node descent), `@[…]`,
  `@ref`/`@deref`.
- *ObjJ declarations*: `@class`, `@global`, `@typedef`, `@protocol` with
  ordered `@optional`/`@required` markers and bodiless method
  declarations; message expressions; class implementations.
- *`@accessors`*: full attribute grammar — `KeyValue` (`property = name`,
  anonymous `=`) vs `Flag`; accessor names `Simple`/`Setter`/`Keyword` by
  colon presence and part count. Populates `ObjjFieldDefinition.accessors`.
- *Preprocessor*: `#if` blocks with the complete condition grammar
  (condition → disjunction → conjunction → negation → primary; primary
  discriminates call/grouped/comparison/identifier — callee field, nested
  condition, anonymous operator scan), body/else split by ordered
  full-children walk; ivar `#if` blocks (recursive, over
  `PreprocIvarItem`); statement- and member-level `#preproc` directives.
- *Implementation members*: methods, `@global`, variable declarations,
  generator function declarations, preproc directives, empty statements.

**Grammar accommodation (grammar.js:560-561, consumed deliberately):**
`preproc_if_block` admits bare anonymous `'else'` / `'else if'` keyword
tokens as direct children — the accommodation for if/else statements split
across preprocessor branches. The model deliberately carries no
representation; the walk skips them with a comment citing this. Precedent:
deliberate grammar tolerances whose meaning lives in the surrounding
statements may be consumed silently when the model's omission is itself a
recorded decision.

## Toolchain and dependency discipline

Unchanged from June 10: capp-parse BoundaryVersion 2 (154 node-kind + 53
field-name constants, `NamedChildCount`/`NamedChild`/`IsNamed`); pin cycle
via `make bump-parse` (commit-hash pins only); `smoke boundary` proves
typedefs/module/runtime agreement.

## Lisette facts (cumulative; new this session marked •)

- `import` reserved; trailing-operator line breaks; let-else idiom;
  `&local` for `Ref<T>` in struct fields and enum payloads; match on
  string scrutinees; `.map(fn_name)`; `map_or_else(||…, |x|…)`.
- • 0.3.4 broadened `match_as_if_let` (#680): any two-arm match with a
  unit arm is flagged. `if let` is the demanded idiom, including
  `if let None = x`, `if let Err(e) = expr`, `if let Ok(_) = expr`.
  All 53 resulting warnings across the codebase resolved.
- • `map_or_else` with both closures capturing the same locals compiles
  (Go semantics underneath; no Rust-style double-move complaint).
- • `Option<capp.CSTNode>` as a local works (boundary structs are plain
  values).
- • Conditional move of an accumulator slice into a struct inside one
  match arm, unused thereafter, compiles.
- • `manual_is_empty` lint covers strings: `s.length() == 0` / `> 0` must
  be `s.is_empty()` / `!s.is_empty()`.
- • `replaceable_with_zero_fill` lint: struct literals must not spell out
  zero-valued fields (`None`, `false`); use `Name { set_fields, .. }`.
  Empty-slice fields (`[]`) are tolerated.
- • `redundant_pattern_matching` lint: a match reducible to an Option
  predicate must use it — `Option.is_none()` / `is_some()` exist.
- Multiple `impl` blocks per type: still unverified — merged proactively.
- • Unqualified variant patterns resolve in match arms (scrutinee-typed)
  but NOT in `if let`: `if let Clean = mode` silently binds a catch-all
  (and then trips `redundant_if_let`); `if let BuildMode.Clean = mode`
  is required.
- • Go `(n int, err error)` returns surface as `Partial` with three
  variants — Ok, Err, Both; `?` is incompatible, explicit match
  required. Go funcs returning only `error` remain `?`-compatible.
- • `empty_match_arm` lint: an intentional no-op arm must be `()`,
  not `{}`.
- • `manual_map_or` / `manual_unwrap_or` lints: value-producing
  Option/Result matches must be `.map_or(default, |x| …)` /
  `.unwrap_or_else(|_| …)`.
- • `manual_compound_assignment` lint: `+=` is demanded on struct
  fields, including through a `Ref<T>` receiver — so field-level
  compound assignment is fully supported.

## Settled architectural decisions

(Unchanged: CST→AST single firebreak; match-arm dispatch with catch-all
diagnostics; cst.lis as completeness source of truth; constructors typed-in
/typed-out; hand-written ADTs, no codegen; lowering executes where trees
are live; declaration/operations file separation; deferred constructs route
through named catch-alls.) Plus, new: **grammar-accommodation skips** (see
above); **bare-struct producer + statement wrapper** as the standard split
when a node lowers both at statement position and inside a member context
(`objj_global_struct` / `objj_global_declaration`).

**Phase 6 decisions, resolved June 12** (the four open questions from
PHASE-6-BRIEF.md):

1. *Frontier units* — edges only; framework symbol resolution deferred (see
   phase 4 note above).
2. *Preproc-conditional symbols* — both branches recorded, condition-tagged:
   `guards: Slice<PreprocGuard>` carries the full `#if` stack, `negated`
   marking `#else`; consumers decide. Duplicate diagnostics consider only
   unguarded declarations, since the same name in opposing branches
   legitimately coexists.
3. *Accessor synthesis* — `MethodSymbol` entries at table-build time,
   mirroring objj runtime behaviour, marked `is_synthesized` so phase 8
   generates bodies. Declared ivar type used instead of the legacy `(id)`
   (recorded deviation).
4. *Conflict policy* — strict: duplicate unguarded primary
   `@implementation`/`@protocol` → Error naming both sites; duplicate
   (class, category) pair → Warning; duplicate selector within one
   implementation → Warning; categories never merge into primaries;
   forward-then-concrete and duplicate forwards/typedefs/globals silent.

## Deferred work

- **Destructuring tier** — the only remaining lowering gap; model complete,
  arms absent, named catch-alls in place. One known corpus instance.
- **Frontier units** — resolved June 12: edges only (phase 4 note).
- **Framework builds** — still blocked on source-level cycle-breaking;
  AppKit/Foundation are lowering corpora only. Fieldwork now also halts at
  phase 5 on a real 2-cycle (Documents.j ↔ DocumentsOverviewController.j);
  under investigation in source.
- **Diagnostic gating** — `build()` never fails on Error diagnostics and
  `main.lis` sets no non-zero exit status; phases 8/9 stubs report success
  (REVIEW.md findings 1, 3, 4). Deliberately deferred until the compiler is
  substantially complete; all are orchestration-layer, uncoupled from the
  phases.
- **Phase 5 frontier-edge hazard** (REVIEW.md finding 2) — an edge whose
  target is a frontier-only unit inflates `in_degree` of a retained node,
  which can misreport an acyclic graph as cyclic, and the `find_cycle`
  fallback can return a one-element path that `kahn` then indexes at [1].
  Latent only — requires a quote-form import of an unwalked local file —
  but cheap to harden when next in phase05: filter edges to retained
  endpoints before Kahn's, and guard the fallback.
- **Build directory configurability** — unchanged.
- **Windows** — single sweep near completion; Makefile openly POSIX-only.
- **"Boundary" nomenclature** — rename at leisure.
- **Lisette author notes** — leading-pipe or-pattern layout; recursive-ADT
  auto-boxing confirmation still outstanding.
- **NextStep.txt** — retire; superseded by this file and PHASE-6-BRIEF.md.

## Next concrete work

**Close the tier A gate on the host** (the sandbox session cannot run
Lisette): `lis check`, fix any lint findings, then
`capp-build build --mode debug` against toolchain_test and

    python3 payload_oracle.py diff \
      ~/Desktop/toolchain_test/Build/toolchain_test.build/Debug/Browser.environment/Sources/main.j \
      ~/Desktop/toolchain_test/Build/capp-build.build/Debug/Sources/main.j

(byte-exact in hand-trace simulation; the remaining risk is Lisette
mechanics, flagged candidates: compound `+=` on struct fields, `.*`
deref placement, `if let Clean =` on a non-prelude variant). Then tier B
(ObjJ scaffolds, AppController.j oracle). Before or alongside it:
richer phase 6/7 corpus exercise, gated on phase 5 — Fieldwork after its
2-cycle is resolved (in hand), AppKit/Foundation (30 and 7 project-local
protocols) after source-level cycle-breaking.

The comparison harness is `payload_oracle.py` (committed, alongside
symbol_oracle.py): `check` proves framing by byte-exact round-trip
(proven on both toolchain_test records and both Foundation.sj bundles),
`extract` pulls payloads (S stripped; `--file` reaches into bundles),
`diff` is the one-command gate.

Phase 6 corpus validation beyond toolchain_test is gated on phase 5:
Fieldwork and AppKit/Foundation all halt on real import cycles before the
table builds. Ground truth is prepared (EXPECTED-SYMBOL-COUNTS.md,
re-derivable via symbol_oracle.py): AppKit expects 509 classes/6825
methods/0 diagnostics; Foundation expects 183 classes/1870 methods and
exactly 2 warnings — the duplicate CPSet(CPKeyValueCoding) category and a
genuine upstream defect, -isEqual: defined twice in CPIndexSet.j (138,
179). Any deviation from the oracle is the worklist. Then phase 7.
