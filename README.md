# capp-build

Cappuccino 2.0 – an infrastructure-grade Objective-J compiler and production archiver for the[ Cappuccino Project's](https://cappuccino.dev) port of AppKit and Foundation to the web.

capp-build is a component of the [Cappuccino toolchain](https://github.com/enquora-net/cappuccino). 
It transforms Objective-J source trees into deployment-ready `.sj` archives in the same layout as the legacy jake toolchain. Existing projects, server configurations, and deployment scripts require no changes.

The semantic core is written in [Lisette](https://lisette.run/) — a language with Rust syntax and OCaml-grade algebraic type semantics, compiling to idiomatic Go. OCaml is the language of choice for compilers and theorem provers - precisely because its type system makes unhandled cases a compile-time error;
Lisette brings that guarantee to a Go runtime. The binary has no runtime dependencies and is distributed as a single platform-native executable.

---

## Installation

Download the binary for your platform from the[ releases page](https://github.com/enquora-net/capp-build/releases), make it executable, and place it in your PATH.

The Objective-J Tree-sitter dynamic library must be installed separately.
Download the appropriate binary for your platform from the[ tree-sitter-objj releases page](https://github.com/enquora-net/tree-sitter-objj/releases) and install it to `/usr/local/lib`. The `cappuccino install` command will manage this automatically in a forthcoming release.

---

## Performance
`capp-build` is architected for real-time performance. On Apple Silicon M4, a full debug build of a NibApplication project — including framework copying and deliverable assembly — completes in under 100ms, and the full AppKit + Foundation corpus (221 files, production source) in 750–1,000ms. These are complete compilation runs, not incremental or partial builds. Incremental builds are a future enhancement. At these speeds, a full rebuild on every keystroke is practical, enabling real-time error reporting in the editor — a capability the Node toolchain cannot approach.

---

## Commands
```
capp-build build [flags] <project>

Flags:
      --mode     debug|release|clean  build mode (default: debug)
      --http2                         HTTP/2 per-file delivery (default: HTTP/1)
      --output   path                 output directory (default: Build/)
```

```
capp-build verify model     verify the CST model against the grammar
capp-build smoke            run smoke tests against the installed grammar
```

The command surface will be refined as development matures and absorbed into the `cappuccino` omnibus binary on release. Community feedback on the command surface is welcome during this beta.

---

## Pipeline
The build pipeline has nine phases:

1. **Validate** — project structure, Info.plist auto-completion, framework availability, entry points
2. **Walk** — collect all source files in the project tree
3. **Parse** — produce a concrete syntax tree for each source file via `capp-parse`
4. **Resolve** — determine import dependencies across the source tree
5. **Sort** — topological ordering so every dependency precedes its consumers
6. **Symbols** — build the class, method, protocol, ivar, and accessor symbol table
7. **Type check** — verify semantic consistency across the resolved tree
8. **Compile** — emit JavaScript from the type-checked IR, byte-exact against the legacy compiler
9. **Archive** — assemble the final `.sj` bundles and application deliverable

Each phase operates across explicit boundaries, consuming a well-defined input and producing a discrete output. The pipeline runs to completion on the full AppKit and Foundation corpora with no unhandled expressions.

---

## Output layout
The assembled output matches the legacy jake toolchain exactly:
```
Build/<Mode>/<Name>/
  index.html
  Info.plist                    (280NPLIST format)
  Resources/                    (.cib and other deployment artifacts)
  Browser.environment/
    <Name>.sj                   (assembled static bundle)
    MHTMLTest.txt
  CommonJS.environment/
    <Name>.sj
  Frameworks/                   (source Frameworks/ tree, copied verbatim)
```

---

## Known limitations
**Grammar library must be installed manually.** capp-build requires the Objective-J tree-sitter grammar dynamic library at `/usr/local/lib`. Download the appropriate binary from the[ tree-sitter-objj releases page](https://github.com/enquora-net/tree-sitter-objj/releases).
Automatic installation will be handled by `cappuccino install` in a forthcoming release.

**XIB compilation is not part of this tool.** The `.xib` → `.cib` compilation step is performed by `capp-nib2cib`, which is under development as a separate component. Before building, compile your XIB files using the legacy `nib2cib`tool and commit the resulting `.cib` files to your project's `Resources/`directory. capp-build copies them into the build output as-is.

**Info.plist size reporting is approximate.** `CPApplicationSize` reports the application bundle size only, not the total of all loaded framework bundles. The loading progress bar will reach 100% slightly later than with a legacy build. This will be corrected once framework compilation produces bundles whose sizes are known at archive time.

**HTTP/2 delivery is not yet implemented.** capp-build currently targets HTTP/1.x delivery.
HTTP/2 support will be added alongside the built-in development server in the Cappuccino omnibus CLI.

**Windows** — cross-compiled binaries are provided but have not been formally tested end-to-end. Reports are welcome.

---

## Relationship to capp-parse
Parsing is delegated entirely to `capp-parse`, which wraps the tree-sitter Objective-J grammar. `capp-build` integrates it as a Go library, exchanging native data structures directly. The subprocess communication path that exists for external tooling is not used internally.
This separation means:
- The parser can be developed, tested, and distributed independently.
- Third-party tooling — linters, editors, static analysers — consume the same
  grammar through the same interface.
- A grammar fix propagates to every consumer simultaneously.

---

## Implementation
`capp-build` is a [Lisette](https://lisette.run) application. Lisette is inspired by OCaml and Rust and compiles to idiomatic Go. The semantic core — import resolution, topological ordering, type checking, and code generation — is expressed in Lisette. Algebraic data types and exhaustive pattern matching make unhandled cases a compile-time error rather than a runtime one.
Both the Lisette source (`src/`) and the generated Go output (`target/`) are maintained in the repository.
Go developers can audit the generated output without prior exposure to Lisette; the Lisette source conveys the domain logic without the operational detail.
See [ARCHITECTURE.md](ARCHITECTURE.md) for design rationale and pipeline internals, and [LISETTE.md](LISETTE.md) for the Lisette language reference.

---

## Build
See [DEVELOPERS.md](DEVELOPERS.md) for environment setup and build instructions.

---

## License

Copyright David Richardson. The binaries distributed here may be freely run for any purpose. All other rights are reserved pending transfer to the Cappuccino Project, at which point this software will be released under
AGPL-3.0.
