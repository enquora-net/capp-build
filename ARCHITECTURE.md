# Architecture

## Overview

This document describes the architecture of the Cappuccino build toolchain. It is written for Cappuccino contributors and users who want to
understand how the toolchain works and why it is built the way it is. No background in compiler theory or type systems is assumed.

---

## How a compiler works

A compiler operates as a transformation pipeline. Source code enters the front end and is progressively lowered through a series of discrete phases. Each phase translates the code into a more specialized representation until the final target format is emitted.

The Cappuccino build pipeline has eight phases:

1. **Validate the project structure** — ensure the existence of: a structurally valid Info.plist file at the project root, AppKit and Foundation frameworks whether concrete or symlinked, a valid MainMenu.xib if the ApplicationDelegate is configured to launch one, main.j and index.html entry points, and other rules which have historically been enforced informally or ad-hoc
2. **Walk the source tree** — find all Objective-J, Javascript, Interface Builder, graphics and other source files in the project
3. **Parse sources** — read each file and build a structured representation of its contents
4. **Resolve imports** — determine what each file depends on
5. **Topological sort** — order the files so that every dependency is processed before it is needed by another file
6. **Type check** — verify that the code is internally consistent
7. **Code generate** — produce the output
8. **Link** — assemble the final result

Each phase operates across explicit boundaries, consuming a well-defined input to produce a discrete output. A phase may succeed, fail, or emit a partially valid result with reportable diagnostics.

The performance gains realized by the Golang/Lisette implementation provide the computational headroom to enforce a strict separation of concerns via discrete passes. For a small community that cannot depend on dedicated compiler specialists, this transparent architecture is essential. It ensures the toolchain remains maintainable by allowing contributors to reason about isolated components without mastering the entire pipeline.

---

## The parsing phase

Parsing is managed by capp-parse, a discrete utility that operates in tandem with capp-build. It leverages tree-sitter, a high-performance incremental parsing library integrated into industry-standard tools like GitHub and Neovim.

The Objective-J tree-sitter grammar serves as a formal, unified specification. It functions as documentation and implementation simultaneously: it is readable by Objective-J developers, verifiable against the language definition, and directly executable by the parser. Within this framework, a syntax rule is the definitive implementation rather than a descriptive comment.

While `capp-parse` remains a standalone utility capable of communicating via stdout for third-party tooling, it is primarily integrated with capp-build through a native Go interface. This architecture enables the direct exchange of native data structures, bypassing the serialization overhead of text-based pipes.

This clean separation ensures the parser remains a decoupled component. It can be developed, tested, and reasoned about independently of the broader build pipeline, whether invoked as a library or as a discrete process.

---

## The semantic core

Parsing defines the syntax of the source code. The subsequent phases—import resolution, topological ordering, and type checking—determine its semantic intent. Collectively, these stages form the semantic core of the compiler.

The semantic core addresses the most complex challenges in language processing. Consider the nuances of import resolution:
* Ambiguity and Absence: If a file is missing, the compiler must distinguish between a simple typo, an incorrect path, or a failure in a preceding build step.
* Cyclic Dependencies: Circular imports (e.g., File A ‭‬ File B ‭‬ File A) must be detected and reported as actionable errors rather than allowing the compiler to enter an infinite loop.
* Conditional Validity: Imports may only be valid under specific build configurations or target environments.

A robust compiler must treat these as distinct scenarios. A tool that fails to differentiate—or worse, crashes when encountering them—is unreliable for professional development.

This philosophy extends to every phase of the pipeline. A type error is not merely "incorrect"; it has a specific provenance, a precise location, and a logical explanation. Similarly, an incomplete source tree is not "broken"—it is a partial state where some units remain valid and processable. The compiler’s responsibility is to provide granular diagnostics that guide the developer toward a resolution. 

---

## Encoding correctness in the compiler itself

While most compilers are not written in OCaml, it has long served as the "gold standard" for language implementation. This preference is not coincidental; the language was developed by researchers specifically to solve compiler-related problems. Industry-critical systems—such as Jane Street’s trading infrastructure, the Coq proof assistant, and the Flow type checker—rely on OCaml because its architecture mirrors the inherent structure of the problem domain.

A foundational principle in robust software construction is that code structure should reflect the problem’s logical states. If import resolution has four distinct outcomes, the implementation should feature four distinct, named, and explicitly handled cases—rather than a collection of boolean flags, nullable fields, or ambiguous strings.

Languages in the ML family—including OCaml, Haskell, and more recently, Rust—facilitate this through algebraic data types (ADTs) and exhaustive pattern matching. This approach allows a developer to define the exact set of possible outcomes for any given phase. The compiler then enforces correctness: it verifies that every possible outcome is handled at every call site. If a new state is introduced, the compiler identifies every location requiring an update, ensuring that no case is silently overlooked.

---

## The implementation language

The semantic core of `capp-build` is written in [Lisette](https://lisette.run) — a domain-specific language designed to provide OCaml and Rust-style correctness guarantees while targeting idiomatic, human-readable Go.

Lisette is a specialized tool for expressing domain logic with formal precision. It does not compete with Go as a general-purpose language; instead, it addresses the specific challenges inherent in the semantic core: managing a bounded set of domain states with explicitly defined transitions where unhandled cases are unacceptable.

**Architectural Lineage**:

- **OCaml** Serves as the high-assurance reference for this programming paradigm. Lisette’s type system is directly derived from OCaml's rigorous model.
- **Rust** The contemporary vehicle that popularized these concepts. Lisette adopts a Rust-like syntax, resulting in code that reads like Python but with the structural enforcement of a strictly typed language.
- **Go** The native compilation target. Every Lisette source file generates idiomatic Go code that is readable, auditable, and fully compatible with the standard Go toolchain. By targeting Go—a language designed at Google for simplicity and maintainability—the toolchain remains accessible and performant.


**Integration and Accessibility**

Lisette introduces no runtime dependencies or operational overhead; the final toolchain is distributed as a standard, statically linked Go binary. Both the Lisette source and the generated Go output are maintained in the repository, ensuring transparency.

This dual-representation strategy supports a diverse contributor base:
* Go developers can audit the generated output and understand the toolchain's execution without prior exposure to Lisette.
* Application developers can read the Lisette source to understand the domain logic without needing to master Go’s low-level implementation details.

The architecture intentionally avoids esoteric constructs, ensuring that the codebase remains maintainable by developers without specialist backgrounds in formal language theory.

The following example demonstrates this structural enforcement. The build pipeline phases are defined as a discrete Lisette type:

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

This is more than a simple enumeration for iteration; it is a formal declaration of the toolchain’s architecture. The compiler enforces this specification, rejecting any code that fails to handle the entire set. If a ninth phase is introduced, the compiler identifies every call site requiring an update, eliminating the need for manual searching via grep.

These phases decompose into similarly specified sub-steps, ensuring that it is impossible to omit a requirement—compilation will fail with an explicit diagnostic if any part of the process is internally inconsistent. A shared characteristic of this language family is that a successful compilation strongly correlates with logical correctness during execution.

This principle of exhaustive handling applies to every facet of the semantic core: import resolution states, type-checking results, and source tree entries. Where other languages might encourage the conflation of concerns into monolithic files to manage complexity, the Lisette-Go architecture promotes the opposite: a clear separation into concise, modular files that are verified as complete and correct within their own boundaries.

---

## Why this matters for Cappuccino specifically

In large-scale projects, high usage volumes naturally surface bugs; edge cases are exposed as thousands of users exercise the codebase in unforeseen ways. In a smaller community, these same edge cases may surface slowly—often only when a new developer begins their first serious project.For these users, encountering a compiler bug is rarely a catalyst for a bug report; instead, it is a signal that the tool is immature, leading them to abandon the platform.

The exhaustive type system addresses this risk at the architectural level. By expressing the semantic core through algebraic data types, we eliminate the entire class of bugs stemming from unhandled cases. The compiler verifies logical completeness across the entire problem space during its own build process, rather than relying on the gradual accumulation of test cases.

Whether it is an unusual import topology, a rare edge case in operator precedence, or an Objective-J construct the original author did not anticipate—the toolchain requires explicit, defined handling before it can be compiled. This approach ensures the tool meets the standard a new user instinctively expects: that it functions correctly on their code, not just on the code the maintainer happened to test.

---

## The Go layer

Everything outside the semantic core is standard Go:

- **CLI Surface**: Managed via [cobra](https://github.com/spf13/cobra), providing the cappuccino build, run, and scaffold commands.
- **System Operations**: High-performance file system traversal and source tree walking.
- **Process Management**: Orchestration of capp-parse as a subprocess, maintaining accessibility for external tooling.
- **Library Integration**: Any functionality leveraging the broader Go ecosystem or third-party libraries.

Go is uniquely suited for this operational layer, providing:
- **Static Binaries**: Single-file deployment with no external runtime requirements.
- **Near-Real-Time Performance**: Essential for a responsive developer toolchain.
- **Universal Cross-Compilation**: Trivial targeting of macOS, Windows, and Linux across ARM and Intel architectures.
- **Embedded Assets**: Native support for bundling project templates and editor configuration files directly into the binary.
- **Robust Standard Library**: A comprehensive suite of tools that minimizes reliance on external dependencies.
- **Straitforward Concurrency**: Efficient parallelization of build tasks.

The boundary between **Lisette** and **Go** is clean and deliberate:
- Lisette provides the logic that benefits from correctness guarantees,
- Go provides the infrastructure that benefits from operational simplicity.

Neither intrudes on the other's domain.

---

## Further reading

- [Lisette](https://lisette.run) — the DSL used for the semantic core
- [Lisette reference documentation](https://github.com/ivov/lisette/tree/main/docs/reference)
- [tree-sitter](https://tree-sitter.github.io) — the parser generator used by `capp-parse`
