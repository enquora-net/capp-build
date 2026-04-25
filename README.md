# capp-build

The Cappuccino source-code compiler.
It transforms Objective-J and JavaScript source trees into deployable `.sj` archives ready for delivery to a web browser.

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full description of the pipeline
design and implementation rationale.

---

## What the compiler does

Objective-J is a syntactically-valid superset of JavaScript that implements the message-passing model of Objective-C, itself derived from Smalltalk.
Where a conventional JavaScript call invokes a function directly, an Objective-J message send asks an object to respond to a named message.
The object decides at runtime how to respond — or whether to respond at all.
This is the foundation of Cocoa's architecture and the source of its compositional flexibility.

The compiler translates expressions of this message-passing model into direct JavaScript function calls that a browser can execute.
The separate Objective-J runtime acts as a runtime dispatcher which connects messages with the objects which are their intended receivers. 

Output is assembled into `.sj` archives — Cappuccino's linked bundle format — optimized for consumption by a web browser and delivered using any HTTP server or loaded using the 'file://' URL scheme.

---

## Pipeline

The build pipeline has eight phases:

1. **Validate** — project structure, Info.plist, framework availability, entry points
2. **Walk** — collect all source files in the project tree
3. **Parse** — produce a concrete syntax tree for each source file via `capp-parse`
4. **Resolve** — determine import dependencies across the source tree
5. **Sort** — topological ordering so every dependency precedes its consumers
6. **Type check** — verify semantic consistency across the resolved tree
7. **Generate** — emit JavaScript from the type-checked IR
8. **Link** — assemble the final `.sj` archives

---

## Relationship to capp-parse

Parsing is delegated entirely to `capp-parse`, which wraps the tree-sitter
Objective-J grammar. `capp-build` invokes `capp-parse` as a subprocess and
consumes its structured output. This separation means:

- The parser can be developed, tested, and distributed independently
- Third-party tooling — linters, editors, static analysers — consume the same
  grammar through the same interface
- A grammar fix propagates to every consumer simultaneously

`capp-parse` accepts source file paths and writes a structured concrete syntax
tree to stdout. `capp-build` reads that output and constructs its typed IR,
from which all subsequent phases proceed.

The structured output is a tree-sitter s-expression representing the concrete syntax tree, from which capp-build constructs its typed intermediate representation by transduction.

Ultimately, `capp-parse` will be used as a library and  communication will be direct using native data structures. The current communication is a convenience to bootstrap development.

---

## Implementation

`capp-build` is a [Lisette](https://lisette.run) application.
Lisette is a language inspired by OCaml and Rust which compiles to idiomatic Go.
The semantic core - import resolution, topological ordering, type checking, and code generation - is expressed in Lisette.
Algebraic types and structural pattern matching make unhandled cases a compile-time error rather than a runtime one.
The entirety of the build process is written in Lisette.
This is compiled to idiomatic Go, with no external dependencies.
The final version will be folded into the single Cappuccino toolchain application, itself written in Go and distributed as a single platform-native binary.

Functionality to walk the source tree is included here, as well as in `capp-parse`.
When development is complete and this is folded into the parent application, a shared package will be used.

See [Lisette.md](LISETTE.md) for Lisette language reference.

---

## Commands

```
capp-build build [flags] <project>

Flags:
      --output   path    output directory (default: build/)
```

The command surface is provisional. It will be refined as the pipeline
matures and absorbed by the `cappuccino` omnibus toolchain on release.
