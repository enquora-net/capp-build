# Import Phase Repair Plan

## Problems

1. Import resolution only searches beside the importing file.
   `resolve_local` treats every quoted import as `dirname(importer) + importPath`. That misses Cappuccino code-directory layouts where a quoted import may resolve through a configured source root or nested code directory rather than the importing file's directory.

2. Phase 4 can discover parsed units that downstream phases never receive.
   The fixed-point importer parses newly discovered files into `next_frontier`, but those units are not merged back into `ctx.parsed`. Phase 5, phase 6, and phase 8 still consume the original parse set, so the import graph can name files that sorting, symbol harvesting, type checking, and compilation cannot see.

3. Source discovery ownership is split.
   Phase 2 walks the project tree up front, while phase 4 also performs transitive discovery. Either phase 2 should define the complete source universe and phase 4 should resolve within that universe, or phase 4 should return an expanded parsed universe that becomes the canonical input for later phases.

4. Framework imports have only archive semantics today.
   Angle-bracket imports are recorded as framework dependencies and intentionally excluded from the source graph. That is appropriate for applications consuming prebuilt framework bundles, but framework-source compilation needs a way to distinguish external prebuilt framework imports from imports that should resolve inside the current framework source tree.

5. Halt-on-error reporting is too terse at the library boundary.
   The pipeline stops correctly when a phase emits Error diagnostics, but `BuildResult.message` has only the phase name and error count. API consumers and CLI summaries need the concrete failing diagnostics, including file and source position where available.

## Implementation Plan

1. Improve diagnostic summaries first.
   Preserve halt-on-error semantics, but include the first few Error diagnostics in `BuildResult.message`. Keep the full `diags` slice unchanged for structured consumers.

2. Improve import-resolution diagnostics.
   When a quoted import fails, report the candidate path that was searched. This does not solve nested code directories, but it makes the current failure mode actionable.

3. Introduce an explicit import-root model.
   Add a typed representation for code directories/import roots, produced by validation or source walking. Resolution should use a deterministic search order and return a structured outcome such as resolved local source, external framework, missing import, or ambiguous import.

4. Choose one canonical parsed universe.
   Prefer having phase 2 define all project source files and phase 4 resolve against that indexed set. If transitive discovery remains necessary, phase 4 must return the expanded `ParsedUnits` or a new combined semantic object consumed by phases 5 through 8.

5. Add focused fixtures.
   Cover same-directory imports, nested code-directory imports, missing imports with searched-path diagnostics, and the case where a resolved import would otherwise be outside the downstream parsed universe.
