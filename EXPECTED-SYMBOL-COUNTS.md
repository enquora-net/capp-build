# EXPECTED-SYMBOL-COUNTS — phase 6 oracle, June 12 2026

Ground-truth symbol counts for the lowering corpora, derived independently
of the compiler by `symbol_oracle.py` (project root): a comment- and
string-aware textual scan mirroring phase 2's file set (`*.j`/`*.sj`,
skipping `Frameworks`, `Build`, `.cappuccino` case-insensitively) and the
table's counting rules (both `#if` branches count; synthesis follows the
legacy accessor rules including explicit-method suppression).

The summary line phase 6 prints maps onto these numbers as:

- `classes` = primaries + categories (every `@implementation` is its own
  ClassSymbol); the parenthesised figure is categories alone.
- `methods` = explicit definitions + expected synthesized accessors;
  the parenthesised figure is synthesized alone.

## toolchain_test — verified June 12, exact match

1 class (0 categories), 0 protocols, 0 forwards, 0 typedefs, 0 globals,
2 methods (0 synthesized), 1 ivar, 0 diagnostics.

## AppKit (221 files)

| | |
|---|---|
| classes | **509** (317 primaries + **192** categories) |
| protocols | **30** (34 required + 196 optional method declarations) |
| forwards | **155** |
| typedefs | **62** |
| globals | **154** |
| methods | **6825** (6185 explicit + **640** synthesized) |
| ivars | **1862** (367 `@accessors` directives; 66 accessor selectors suppressed by explicit methods) |
| diagnostics | **0** |

Zero diagnostics is itself a test of guard semantics: `CPPlatform` and
`CPPlatformString` are each implemented twice (`Platform/` and
`Platform/DOM/`), but one site of each pair sits in the `#else` branch of
`#if PLATFORM(DOM)` (Platform/CPPlatform.j:73-76, CPPlatformString.j:41-44).
Only one occurrence of each is unguarded, so the strict policy correctly
stays silent. A duplicate-primary Error on either name means guard tagging
is broken.

## Foundation (96 files)

| | |
|---|---|
| classes | **183** (117 primaries + **66** categories) |
| protocols | **7** (25 required + 5 optional method declarations) |
| forwards | **29** |
| typedefs | **30** |
| globals | **12** |
| methods | **1870** (1745 explicit + **125** synthesized) |
| ivars | **349** (76 `@accessors` directives; 16 accessor selectors suppressed by explicit methods) |
| diagnostics | **2 Warnings, 0 Errors** (below) |

The two expected warnings are genuine findings, not noise:

1. `duplicate category @implementation CPSet(CPKeyValueCoding)` —
   declared in both `CPSet+KVO.j:387` and `CPSet/_CPSet.j:469`, unguarded.
2. `duplicate method -isEqual: in @implementation CPIndexSet` —
   `CPIndexSet.j` defines `-isEqual:` at lines 138 **and** 179, no
   preprocessor involvement. An upstream Cappuccino defect the legacy
   runtime resolves silently (the later definition wins).

Any diagnostic beyond these two — or their absence — is the worklist.

## Caveats

- The oracle is textual. Method and ivar counts assume Cappuccino house
  style (signatures beginning at line start, one field per declaration);
  drift of a handful in either direction warrants inspecting the specific
  file before suspecting phase 6.
- Synthesized counts replicate the suppression rule (explicit instance
  method with the same selector wins) per class block; cross-file category
  methods are not consulted, exactly as in phase 6, where occupancy is
  per-implementation.
- `@class` comma lists: none exist in either corpus (the grammar's forward
  declaration carries a single identifier, so this was worth confirming).
- AppKit and Foundation currently halt at phase 5 on real import cycles,
  so this oracle is exercisable only once cycle-breaking (or a
  table-over-discovery-order debug path) lets them reach phase 6.
  toolchain_test and Fieldwork (after its cycles are resolved) are the
  near-term corpora.

Re-derive after upstream changes with:

    python3 symbol_oracle.py <corpus-root> ...
