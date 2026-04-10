# Architecture

## Overview

This document describes the architecture of the Cappuccino build toolchain
rewrite. It is written for Cappuccino contributors and users who want to
understand how the toolchain works and why it is built the way it is. No
background in compiler theory or type systems is assumed.

---

## How a compiler works

A compiler is a pipeline. Source code enters one end, and something useful
comes out the other. In between, the source passes through a series of
distinct phases, each of which transforms it from one representation into
another.

The Cappuccino build pipeline has eight phases:

1. **Validate the project structure** — ensure the existence of: a structurally valid Info.plist file at the project root, AppKit and Foundation frameworks whether concrete or symlinked, a valid MainMenu.xib if the ApplicationDelegate is configured to launch one, main.j and index.html entry points, and other rules which have historically been enforced informally or ad-hoc
2. **Walk the source tree** — find all Objective-J, Javascript, Interface Builder, graphics and other source files in the project
3. **Parse sources** — read each file and build a structured representation of its contents
4. **Resolve imports** — determine what each file depends on
5. **Topological sort** — order the files so that every dependency is processed before it is needed by another file
6. **Type check** — verify that the code is internally consistent
7. **Code generate** — produce the output
8. **Link** — assemble the final result

Each phase has a well-defined input and a well-defined output. Each phase can
succeed, fail, or produce a result that is incomplete in a known and reportable
way. The boundary between phases is explicit.

This is not a novel architecture. It is the architecture every serious compiler
uses, for the same reasons: it is understandable, testable, and maintainable.
Each phase can be developed, tested, and reasoned about independently. A bug
in import resolution does not require understanding code generation to fix.

---

## The parsing phase

Parsing is handled by `capp-parse`, a separate program that runs alongside
`capp-build`. It uses [tree-sitter](https://tree-sitter.github.io), a
battle-tested parser generator used by many editors and tools including
GitHub's code search and Neovim.

The Objective-J grammar for tree-sitter is a formal specification of the
language's syntax. It is simultaneously documentation, specification, and
implementation — readable by anyone who knows Objective-J, verifiable against
the language definition, and executable by the parser. A syntax rule in the
grammar is the syntax rule, not a comment describing it.

`capp-parse` communicates with `capp-build` over a simple text interface:
file paths go in, structured descriptions of the parsed source come out. This
clean separation means the parser can be developed, tested, and reasoned about
entirely independently of the rest of the build pipeline.

---

## The semantic core

Parsing tells us what the source code *says*. The phases that follow — import
resolution, topological ordering, type checking — determine what it *means*.
This is called the semantic core of the compiler.

The semantic core is where the interesting and difficult problems live.
Consider import resolution alone. When a file imports another, several things
can happen:

- The imported file exists and is unambiguous — straightforward
- The imported file does not exist — an error, but what kind? Missing file?
  Typo in the path? A file that should have been created but wasn't?
- The import creates a cycle — file A imports file B which imports file A —
  which must be detected and reported clearly
- The import is conditionally valid depending on build configuration

Each of these is a distinct situation requiring distinct handling. A compiler
that treats them identically — or worse, that handles only the first case and
crashes or silently misbehaves on the others — is not a reliable tool.

The same reasoning applies to every phase. A type error is not simply "wrong"
— it has a specific cause, a specific location, and a specific explanation
that helps the developer fix it. An incomplete source tree is not simply
"broken" — some files may be valid and processable while others are not, and
the compiler should report the distinction clearly.

---

## Encoding correctness in the compiler itself

A well-known principle in compiler construction — and in software generally —
is that the structure of the code should reflect the structure of the problem.
If import resolution has four distinct outcomes, the code should have four
distinct, named, explicitly handled cases. Not a boolean flag and two nullable
fields. Not a string that might say "cycle" or "missing" or "resolved". Four
named cases, each carrying exactly the information relevant to that case, each
handled explicitly everywhere in the codebase.

Languages in the ML family — OCaml, Haskell, and more recently Rust — provide
this directly through a feature called algebraic types combined with exhaustive
pattern matching. You define the exact set of possible outcomes. The compiler
then verifies, at every point in the codebase that handles those outcomes, that
all of them are handled. If you add a new outcome later, the compiler points to
every place that needs updating. Nothing can be silently forgotten.

OCaml has been the implementation language of choice for serious compiler work
for decades. Jane Street's trading infrastructure, the Coq proof assistant, the
Flow type checker — all OCaml. The fit between the language and the problem
domain is not coincidental. The language was developed by researchers building
exactly these kinds of tools.

---

## The implementation language

The semantic core of `capp-build` is written in
[Lisette](https://lisette.run) — a domain-specific language that provides
OCaml and Rust-style correctness guarantees while compiling to idiomatic,
human-readable Go.

Lisette is best understood as a DSL for expressing domain logic correctly. It
is not a general-purpose language competing with Go. It is a precise tool for
the specific class of problem the semantic core represents: a bounded set of
domain states with formally specified transitions, where an unhandled case has
consequences.

The relationship to the broader language landscape:

- **OCaml** is the academic and industrial standard for this style of
  programming. Lisette's type system is directly inspired by it.
- **Rust** is the contemporary language that brought these ideas to the widest
  audience. Lisette's syntax resembles Rust's. It reads like idiomatic Python with a little extra syntax to enforce correctness
- **Go** is the compilation target. Every Lisette source file compiles to
  idiomatic Go. The generated code is readable, auditable, and participates
  fully in the Go toolchain. The language contains only twenty-five keywords and very few novel concepts. It was designed at Google by some of the leading figures in computing science history - specifically with simplicity and maintainability as a goal

Lisette adds no runtime dependency and no operational complexity. The deployed
toolchain is a standard Go binary. The Lisette source and the generated Go are
both available in the repository. A contributor who knows Go can read the
generated output without knowing Lisette. A contributor reading the Lisette
source does not need to know Go. Both can be reviewed and effectively used by those without specialist computer science backgrounds. Special care is taken to avoid constructs which may be unfamiliar to those new to either language.

A small example illustrates the point. The build pipeline phases, expressed
as a Lisette type:

```rust
enum BuildPhase {
    ValidateProjectStructure,
    WalkSourceTree,
    ParseSources,
    ResolveImports,
    TopologicalSort,
    TypeCheck,
    CodeGenerate,
    Link,
}
```

This is not just code which is iterated over to directly invoke the function for each phase. It is a formal statement that exactly eight build phases
exist, checkable by the compiler. It will reject any code that handles some but not all of them.
Add a ninth phase and the compiler identifies every place in the codebase
that needs updating. No grep required. These phases themselves decompose into similarly-specified steps. It is not possible to miss a step - compilation will fail with an explicit message if any part of the process is not internally consistent.

A shared feature of languages in this family are that when the program compiles, it almost always runs, and runs correctly.

The same principle applies to import resolution states, type checking results,
source tree entries, and every other concept in the semantic core where an
unhandled case would produce a wrong result silently.

Languages lacking Go's exceptional tooling and high-performance compiled output encourage conflation of concerns into a small number of implementation files. This obscures intent and hampers long-term maintenance. Lisette and Go encourage the opposite - clear separation of concerns into short files which are both complete and correct within their own boundaries.

---

## Why this matters for Cappuccino specifically

The Cappuccino user community is small. In large projects, bugs surface quickly
through volume of usage. Edge cases are found because thousands of people
exercise the code in ways the author did not anticipate.

In a small community, edge cases surface slowly — or not at all until a new
user encounters them on their first serious project. A new user who hits a
compiler bug does not file a bug report. They conclude the tool is not ready
and move on.

The exhaustive type system addresses this directly. A compiler whose semantic
core is expressed in algebraic types cannot have the class of bugs that arise
from unhandled cases. The compiler verifies completeness over the entire
problem space at build time, not through accumulated test cases. An unusual
import topology, an edge case in operator precedence, an Objective-J construct
the original author did not anticipate — all require explicit handling before
the toolchain will build.

This is the same standard a new user subconsciously expects:
that the tool works correctly on their code, not just on the code the author
tested.

---

## The Go layer

Everything outside the semantic core is standard Go:

- The `cobra`-based CLI surface — `cappuccino build`, `cappuccino run`,
  `cappuccino scaffold`, and the rest
- File system operations and source tree walking
- Subprocess management for `capp-parse`, allowing usage by external tools
- Any functionality requiring third-party Go libraries

Go is excellent at this work:
- single binary deployment,
- nearly realtime performance,
- trivial cross-compilation to macOS, Windows and Linux, ARM or Intel,
- support for deployable embedded assets such as project scaffolding templates and editor support files,
- a comprehensive standard library, sufficient without external dependencies,
- straightforward concurrency.

These properties are exactly what a build tool needs for its operational layer.
Go provides them without ceremony.

The boundary between Lisette and Go is clean and deliberate:
- Lisette provides the logic that benefits from correctness guarantees,
- Go provides the infrastructure that benefits from operational simplicity.

Neither intrudes on the other's domain.

---

## Further reading

- [Lisette](https://lisette.run) — the DSL used for the semantic core
- [Lisette reference documentation](https://github.com/ivov/lisette/tree/main/docs/reference)
- [tree-sitter](https://tree-sitter.github.io) — the parser generator used by `capp-parse`
