# Changelog

All notable changes to capp-build are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## 2.0.0-beta.3 — 2026-10-20

### Added

- Frameworks package: a project whose root `Info.plist` declares
  `CPBundlePackageType` `CPKG` builds its member frameworks in order into
  `Build/modern/Frameworks`, alongside the legacy `Build/Frameworks` tree,
  which supplies what capp-build does not yet produce
- Framework products: each framework build writes a complete framework
  directory to `Build/modern/Frameworks/<Name>`
- Name resolution: every identifier resolves to a local, ivar, or a global of
  the project, its frameworks, the Objective-J runtime or the browser; an
  unresolved identifier is a compile error
- Emitter: `@accessors(copy)` setters and `@"..."` object literal property
  names
- Lowering: destructuring patterns
- Pipeline: preprocessing phase

### Fixed

- Ivars declared in categories, or inherited from classes in imported
  frameworks, were emitted without `self.`
- Framework archive records were named by source path instead of file name,
  so the runtime could not resolve `<Framework/File.j>` imports
- Source walk compiled nested projects (any subdirectory with its own
  `Info.plist`) and legacy `CommonJS` tooling into the enclosing framework
- Application `Info.plist` generation dropped every key outside a fixed set,
  including `CPPrincipalClass`, `CPApplicationDelegateClass` and
  `CPDefaultTheme`
- Unbalanced parentheses in array, dictionary and `@deref` output

### Changed

- Synced to Lisette v0.12, including its mutability model

### Platforms

macOS (arm64, x86_64), Linux (arm64, x86_64), Windows (arm64, x86_64).

---

## 2.0.0-beta.2 — 2026-06-29

### Fixed

- Tree walker: symlinked frameworks were treated as files, not directories,
  during validation and archive copy (`context.lis`, `phase01_validate.lis`,
  `phase09_archive.lis` all used `DirEntry.IsDir()`, which doesn't follow
  symlinks; switched to `os.Stat`, which does)
- Diagnostics: a single parse failure could cascade into repeated duplicate
  errors via tree-sitter's recovery; Phase 3 now reports each file once
- Diagnostics: Phase 2 (Walk) and Phase 4 (Imports) had overlapping,
  inconsistent error authority; reconciled, and Phase 4 now handles
  arbitrary-depth source trees correctly
- Diagnostics: console errors now name the specific file and condition
  instead of a generic phase-level failure

### Changed

- Synced to Lisette v0.6.0 syntax
- Replaced hand-written `all()` enumerator with `#[iterate]`-synthesised
  variants
- Fixed quadratic output growth in `js_print.lis` (Phase 8)

### Platforms

macOS (arm64, x86_64), Linux (arm64, x86_64), Windows (arm64, x86_64).

---

## 2.0.0-beta.1 — 2026-06-17

First public beta of capp-build, the new Cappuccino Objective-J compiler and
production archiver.

### What this is

capp-build compiles Objective-J applications and produces browser-loadable
build output in the same layout as the legacy jake toolchain. Existing server
configurations, deployment scripts, and application code require no changes.

### Added

- Full nine-phase compilation pipeline, implemented and verified against the
  legacy toolchain
- Project validation and Info.plist auto-completion (derives absent identity
  keys from project structure; writes corrections back to disk)
- Source tree walking and Objective-J parsing via `capp-parse`
- Import resolution and topological sort with cycle detection and reporting
- Symbol table construction: classes, methods, protocols, ivars, and
  synthesised `@accessors` getters and setters
- Protocol conformance checking across the resolved project graph
- JavaScript code generation, byte-exact against the legacy compiler in both
  debug and release modes
- Application deliverable assembly under `Build/Debug/<Name>/` and
  `Build/Release/<Name>/`: assembled `.sj` bundle, Info.plist in 280NPLIST
  format, framework tree, resources, index.html, and MHTMLTest.txt
- `--mode debug|release|clean` build mode selection
- `--http2` flag (HTTP/2 per-file delivery; implementation pending)
- `verify model` — CST model verification against the installed grammar
- `smoke` — smoke tests against the installed grammar
- Single binary distribution for macOS, Linux, and Windows on ARM64 and AMD64,
  cross-compiled via Zig from a macOS host
- SHA-256 checksum files for all release artifacts

### Known limitations

**Grammar library must be installed manually.** capp-build requires the
Objective-J tree-sitter grammar dynamic library at `/usr/local/lib`. Download
the appropriate binary from the
[tree-sitter-objj releases page](https://github.com/enquora-net/tree-sitter-objj/releases).
Automatic installation will be handled by `cappuccino install` in a
forthcoming release.

**XIB compilation is not part of this tool.** The `.xib` → `.cib`
compilation step is performed by `capp-nib2cib`, which is under development
as a separate component. Before building, compile your XIB files using the
legacy `nib2cib` tool and commit the resulting `.cib` files to your project's
`Resources/` directory. capp-build copies them into the build output as-is.

**Info.plist size reporting is approximate.** `CPApplicationSize` reports
the application bundle size only, not the total of all loaded framework
bundles. The loading progress bar will reach 100% slightly later than with a
legacy build. This will be corrected once framework compilation produces
bundles whose sizes are known at archive time.

**HTTP/2 delivery is not yet implemented.** capp-build currently targets
HTTP/1.x delivery. HTTP/2 support will be added alongside the built-in
development server in the Cappuccino omnibus CLI.

**Windows** — cross-compiled binaries are provided but have not been formally
tested end-to-end. Reports are welcome.

### Platforms

macOS (arm64, x86_64), Linux (arm64, x86_64), Windows (arm64, x86_64).
