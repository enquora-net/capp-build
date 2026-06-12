# PHASE-8-BRIEF — session bootstrap for the compiler proper

Read PROGRESS-SNAPSHOT.md first; it carries project state. This file
carries the code-generation contract recovered from legacy output, the
settled decisions, the tier decomposition, and the validation oracle.
STATIC-BLOB-FORMAT.md governs the record framing; this file governs the
JavaScript payload.

## The contract: where it came from

The generated code must coexist with the legacy-built bundles in
`./Frameworks`, so the ABI is not a choice — it is whatever those bundles
speak. The authority is observed output of the legacy toolchain
(June 12 2026 recon):

- `~/Desktop/toolchain_test/Build/toolchain_test.build/Debug/
  Browser.environment/Sources/{AppController.j,main.j}` — complete
  per-file records for our 2-file regression app. **The byte-level
  oracle.**
- `~/Desktop/toolchain_test/Frameworks/Debug/Foundation/ObjJ.environment/
  Foundation.sj` and its release sibling — 96 files × two modes, the
  inference corpus for any construct toolchain_test lacks.
- Payload extraction script: the bundle/per-file parsers in
  `symbol_oracle.py`'s style; recon dumps were made with a 20-line
  python loader (re-derivable from STATIC-BLOB-FORMAT.md).

## Observed translation scheme (debug mode)

Imports — one statement per `@import`, concatenated on one line, source
order; angle-form gets `NO`, quote-form `YES`:

    objj_executeFile("Foundation/Foundation.j", NO);objj_executeFile("AppController.j", YES);

Class implementation:

    {var the_class = objj_allocateClassPair(CPObject, "AppController"),
    meta_class = the_class.isa;class_addIvars(the_class, [new objj_ivar("theWindow", "CPWindow")]);objj_registerClassPair(the_class);
    class_addMethods(the_class, [new objj_method(sel_getUid("awakeFromCib"), function $AppController__awakeFromCib(self, _cmd)
    {
        ...body...
    }

    ,["void"])]);
    }

- Method functions are named `$Class__selector` with `:` → `_`.
- Instance methods on `the_class`, class methods on `meta_class`
  (separate `class_addMethods(meta_class, [...])` call).
- The trailing type array is `[returnType, paramType...]` as written in
  source (`["void","CPNotification"]`).
- Categories: `var the_class = objj_getClass("CPSet")` + guard throw when
  absent; no allocate/register pair.
- Protocols: `objj_allocateProtocol("Name")`, `protocol_addProtocol` per
  inherited protocol (with lookup + SyntaxError throw when missing),
  `objj_registerProtocol`; method declarations via
  `protocol_addMethodDescriptions`.
- Typedefs: `{var the_typedef = objj_allocateTypeDef("Name");
  objj_registerTypeDef(the_typedef);}`.
- Conformance on implementations: `objj_getProtocol` + throw + 
  `class_addProtocol(the_class, aProtocol)`.

Ivar references in method bodies → `self.ivarName` (resolved against the
class's ivar set, including inherited project-known ivars — the symbol
table's job). Method parameters and locals are untouched.

Message send (debug form):

    ((___r1 = self.theWindow), ___r1 == null ? ___r1 : (___r1.isa.method_msgSend["setFullPlatformWindow:"] || _objj_forward)(___r1, (self.theWindow.isa.method_dtable["setFullPlatformWindow:"], "setFullPlatformWindow:"), YES))

- Receiver evaluated once into `___rN`; `var ___rN;` declarations are
  emitted at the *end* of the enclosing function body.
- Release form drops the `(recv.isa.method_dtable["sel"], "sel")` comma
  artifact, passing the bare selector string.
- Simple receivers (a parameter or `self`) skip the temporary:
  `(indexes == null ? indexes : (indexes.isa.method_msgSend["copy"] || ...`.
- Super: `(objj_getClass("Class").super_class.method_dtable["sel"] ||
  _objj_forward)(self, "sel", args...)` — no null guard.

Top-level declarations are rewritten for eval-scope escape:

    function main(args, namedArgs) { ... }   →   main = function(args, namedArgs) { ... }

(The same global-escape rule applies to top-level `var` — verify exact
form against the corpus when the arm is written.)

Other observations: comments are stripped entirely — **no** blank-line
echo (June 12 correction: the earlier guess that comment line structure
echoes into blank lines is wrong; the oracle's leading `\n\n` is the
compiler's debug-mode prologue, see the emitter law below); `YES`,
`NO`, `nil` pass through (runtime globals); `@"…"` is a plain string;
`@{…}` involves `new CFMutableDictionary()`; `@[…]`, `@selector`,
`@ref`/`@deref` forms still to be extracted from the corpus when their
tiers are implemented. 38 bare `objj_msgSend(` occurrences in Foundation
remain to be classified (likely class-message or special-receiver forms).

## The emitter law (recovered June 12 2026 — tier A prerequisite)

The law is no longer inferred from output samples: the legacy code
generator itself ships inside
`toolchain_test/Frameworks/Objective-J/Objective-J.js` (minified; the
acorn-based ObjJAcornCompiler with its visitor table). It was beautified
and transcribed. Everything below is read from that generator and
confirmed against the oracle payloads. Where the generator is quirky,
the quirk is the law.

**File shape.** Debug payloads begin with `\n\n` — emitted by
`compilePass2()` iff source maps are enabled; release payloads have no
prologue. (Our first target keeps `\n\n`: it is the debug form minus
the `S` record.) Imports emit `objj_executeFile("<path>", YES|NO);`
with **no** newline before or after — dependency statements and the
first real statement concatenate on one line. Comments vanish without
trace. No extra trailing newline: the file ends with whatever the last
statement emits.

**Indentation.** Unit: 4 spaces. Statement emitters print the current
indentation themselves, then their body at indent+1. Block braces print
at one level *less* than the current indentation (`{` and `}` align
with the enclosing statement); a bare block nested directly in a block
indents one extra level. The function-body block appends `var ___r1,
___r2, …;\n` before its closing brace when dispatch temporaries exist
(tier C hook).

**Statement templates** (`<i>` = current indentation; every statement
ends its own line unless noted):

    expr-stmt   <i><expr>;\n        — parenthesized iff expr is
                ObjectExpression, FunctionExpression, assignment with
                object-pattern LHS, binary whose left is a function
                expression, or non-directive "use strict" literal
    block       <i-1>{\n …body… <i-1>}\n   — trailing \n omitted for
                function-expression bodies and skip-indent positions
                (try/catch/finally blocks, arrow bodies)
    if          <i>if (<test>)\n …+1…      — \n omitted when the
                consequent is an EmptyStatement (yields `if (x);\n`)
    else        <i>else\n …+1…   |  <i>else;\n (empty alt)
    else-if     <i>else <if-statement printed with no leading indent>
    while       <i>while (<test>)\n …+1…   — same EmptyStatement rule
    do          <i>do\n …+1… <i>while (<test>);\n
    for         <i>for (<init?>; <test?>; <update?>)\n …+1…
                init prints inline (no indent, `, ` separators); a bare
                `in` binary in init position is parenthesized
    for-in      <i>for (<left> in <right>)\n …+1…
    for-of      for(<left> of <right>)\n …+1…   — quirk: NO leading
                indentation, no space after `for`; ` await ` if async
    switch      <i>switch(<disc>) {\n        — no space after `switch`
                cases at +1: `case <t>:\n` / `default:\n`,
                consequents at +2; closes <i>}\n
    try         <i>try <block>\n<i>catch(<p>) <block>\n<i>finally <block>\n
                — `catch` with no param has no parens; the blocks print
                without leading indent or trailing \n; one final \n
    labeled     <label>: <body>   — quirk: no leading indentation
    return      <i>return;\n | <i>return <arg>;\n
    throw       <i>throw <arg>;\n
    break/cont  <i>break;\n | <i>break <label>;\n (likewise continue)
    debugger    <i>debugger;\n
    empty       ;\n               — no indentation
    var         <i>var <d1>,\n<i>    <d2>, …;\n — continuation lines at
                indent + 4 literal spaces; declarator is `<id>` or
                `<id> = <init>`; kind text (var/let/const) preserved;
                in for-init: `var a = 1, b = 2` (no indent/;/\n)
    function    <i><name> = function(<p1>, <p2>)\n<block with \n>
                — transformNamedFunctionDeclarationToAssignment is ON
                in static-blob builds: the global-escape rewrite. It
                applies to ANY named function the emitter sees,
                declaration or expression. `async` precedes, `*`
                follows the `function` keyword, space-joined.
    fn-expr     same emitter; body block emits no trailing \n. Quirk:
                the emitter always prefixes the CURRENT indentation,
                even mid-expression — at depth 1 an initializer reads
                `x =     function(…)`.

**Expression spacing.** Single spaces around binary, logical, and
assignment operators and ` ? `/` : `. Prefix unary ops take a space
only for word operators (delete, in, instanceof, new, typeof, void);
postfix `++`/`--` attach directly. `, ` after commas in argument
lists, array literals, object literals, sequences, parameter lists,
and for-init declarators. Object literals have no inner brace padding:
`{a: 1, b: 2}`. Member access `.name`, computed `[expr]`, optional
`?.`/`?.[`. `new C(args)` always prints the parens, including zero-arg.
Spread/rest `...` attaches directly.

**Literals and identifiers.** Verbatim raw source text — numbers,
strings (original quotes and escapes), and regexes are echoed exactly
as written; `@"…"` drops the `@` and keeps the rest. Identifiers print
their names; `this` is literal. Template literals echo raw quasi text
around `${expr}`. Parenthesized expressions are preserved as nodes
(acorn preserveParens) and re-emitted as `(<expr>)`.

**Parenthesization.** Two tables; smaller binds tighter.
Node precedence P: Member/Call/New 1; Chain 2; FunctionExpression/
Arrow/Import 3; Unary/Update 4; Binary 5; Logical 6; Conditional 7;
Assignment 8; everything else −1.
Operator precedence T: `* / %` 3; `+ -` 4; `<< >> >>>` 5;
`< <= > >= in instanceof` 6; `== != === !==` 7; `&` 8; `^` 9; `|` 10;
`&&` 11; `||` 12; `??` 13.
A child operand is parenthesized iff P[child] > P[parent], or
P[child] = P[parent] with parent ∈ {Binary, Logical} and
(T[parent.op] < T[child.op], or T equal and the child is the right
operand). Forced parens regardless: the left operand of `**`; an arrow
function as a binary left operand; both operands of `??`; sequence
expressions (always `(a, b)`); `await` arguments (`await (x)`).

**Record framing.** Lengths are UTF-16 code units, not bytes — see the
June 12 correction in STATIC-BLOB-FORMAT.md. ASCII payloads (all of
toolchain_test) are unaffected.

## Settled decisions

1. **ABI**: the observed modern inlined dispatch, exactly. Not the older
   `objj_msgSend` ABI.
2. **First target mode**: debug-form payload *without* the `S` record
   (the format makes `S` optional). This is what the byte oracle holds.
   Release form (mechanical simplification of sends) follows; source maps
   (`S`), release optimisations, and HTTP/2 delivery are deferred and
   recorded.
3. **Oracle**: byte-equality of the `t` payload against the legacy
   records for toolchain_test (after stripping `S`). For corpora beyond
   it: structural equivalence — parse ours and theirs with a JS parser
   and compare normalised ASTs (sandbox has node; acorn). Byte-equality
   is aspirational beyond toolchain_test, structural equivalence is the
   gate.
4. **#if in codegen**: requires evaluating `PLATFORM(...)`-style
   conditions against a build-feature environment the legacy jake
   supplied. Deferred behind a named diagnostic per the house catch-all
   pattern; application corpora barely use it. The typed PreprocCondition
   is already in the AST and `PreprocGuard` in the table when the
   evaluator lands.
5. **Tier decomposition** (implementation order):
   - **A. JS printer** (`js_print.lis`): typed AST → JavaScript text for
     the entire JS statement/expression surface, including the top-level
     global-escape rewrite. The volume item; everything else hangs off
     it. Oracle: main.j payload byte-exact.
   - **B. ObjJ structure scaffolds**: implementations, methods (function
     wrappers + type arrays), ivars, accessor bodies (getter/setter per
     phase-6 synthesis), protocols, typedefs, conformance, imports.
     Oracle: AppController.j byte-exact except the send.
   - **C. Dispatch**: message sends incl. temporaries, null guards,
     super, debug/release variants. Oracle: AppController.j byte-exact;
     then Foundation structural sweep.
   - **D. ObjJ expressions**: @selector, @"", @[…], @{…}, @ref/@deref —
     extract exact forms from Foundation pairs as each arm is written.
   - **E. Records + modes**: per-file record composition in phase 8
     (i/I/t), Clean mode, then phase 9 bundle assembly (trivial per
     STATIC-BLOB-FORMAT.md).
6. **Validation flow per tier**: extract the construct's legacy form from
   the Foundation debug/release pair, write the arm, compare on
   toolchain_test and a chosen Foundation file, byte-first then
   structural.

## Working method (proven in phases 6–7, keep)

Re-extract exact ADT shapes from cst.lis before generating arms — the
printer touches the *entire* expression surface, so this matters more
than ever. Validate working copies (balance, duplicate fns, callees,
shapes) before write-back; byte-compare after copy. Lisette lint facts
accumulate in PROGRESS-SNAPSHOT.md — read them before writing code.

## Open items

- Exact `@[…]`, `@{…}`, `@selector`, `@ref`/`@deref` payload forms.
- Classification of the bare `objj_msgSend(` occurrences.
- Top-level `var` global-escape exact form. (The recovered generator
  shows no rewrite of top-level `var` in the JS path — VariableDeclaration
  prints as-is; eval-scope escape for `var` is handled elsewhere if at
  all. Confirm against a corpus instance when one arises.)
- ~~Whitespace law~~ — resolved June 12; see "The emitter law" above.
  The legacy generator itself was recovered from
  `Frameworks/Objective-J/Objective-J.js` and transcribed.
- `_$selector`-style collisions: method function names mangle `:` → `_`;
  confirm no further mangling (e.g. for `_` prefixed selectors) in corpus.
