# Static Blob Format

Archaeologically recovered from the Objective-J runtime source.
Primary sources: `MarkedStream.js`, `Executable.js`, `FileDependency.js`,
`FileExecutable.js`, `bundletask.js`. Verified against live `Foundation.sj`
and `AppKit.sj` artifacts from a `toolchain_test` build.

---

## Overview

The static blob is the pre-compiled, deployment-ready artifact produced by
the Objective-J build system for each framework and application. It is a
UTF-8 text file using the `.sj` extension. The format is a streaming,
length-prefixed record sequence rooted at a `@STATIC;1.0;` header.

The `@STATIC` magic distinguishes pre-compiled content from raw Objective-J
source. The ObjJ runtime loader checks for this prefix and selects the
static execution path rather than the compilation path.

There are two structural levels: the **bundle** format used for framework
`.sj` files (e.g. `Foundation.sj`), and the **per-file** format embedded
within each bundle entry. The per-file format is also the direct output of
the ObjJ compiler for a single source file.

---

## Record Encoding

All records share the same wire encoding:

```
<marker>;<decimal_length>;<content>
```

- **marker** — a single ASCII character identifying the record type.
- **decimal_length** — the length of `<content>` in **UTF-16 code units**
  (JavaScript `String.length`), encoded as ASCII decimal digits,
  terminated by `;`. *Not* a byte count: the legacy writer measures JS
  string lengths, and the two differ wherever the content contains
  non-ASCII characters. Proof: `CPDate.j` in the debug `Foundation.sj`
  declares `t;31723;` over a payload of 31,724 UTF-8 bytes — one U+00B1
  (`±`) accounts for the difference. (Corrected June 12 2026; earlier
  revisions of this document said "byte count", which holds only for
  ASCII payloads such as the toolchain_test records.)
- **content** — exactly `decimal_length` UTF-16 code units of text,
  serialized as UTF-8.

There are no separators between records. Framing is entirely governed by
the length field. The stream is terminated by an end record:

```
e;
```

The end marker carries no length or content field.

---

## Bundle Format

Used for framework `.sj` files produced by `bundletask.js`.

```
@STATIC;1.0;<entry>...<entry>e;
```

Each entry is a path record immediately followed by a text record:

```
p;<name_len>;<source_filename>t;<record_len>;<per-file-record>
```

- `p` — **path**: the source filename relative to the framework's source
  root (e.g. `CPObject.j`). When `flattensSources` is true, only the
  basename is stored.
- `t` — **text**: the complete per-file static record for that source file
  (see Per-File Format below). The length covers the entire nested
  `@STATIC;1.0;...` string.

### Bundle — Non-Image Resource Entries

Non-image resources (CSS, property lists, etc.) embedded in a bundle use
a variant encoding produced by `bundletask.js`. The `p` marker is written
without a standard length/content pair; instead, the resource path and raw
file contents are concatenated and written as a single length-prefixed
string immediately after `p;`:

```
p;<path_len>;<resource_path><raw_contents>
```

The MarkedStream parser reads `path_len` bytes and stops, leaving the raw
contents as the opening bytes of the following record. This is an irregular
encoding. No `t` record follows a resource entry.

### Bundle Statistics (observed)

| Bundle                      | p/t pairs | i (local) | I (std) | t records | S records |
|-----------------------------|-----------|-----------|---------|-----------|-----------|
| Foundation.sj (release)     | 96        | 411       | 0       | 96        | 0         |
| Foundation.sj (debug)       | 96        | 411       | 0       | 96        | 96        |
| AppKit.sj (browser/release) | 204       | 644       | 235     | 204       | 0         |

---

## Per-File Format

The direct output of the ObjJ compiler for a single `.j` source file, and
the content of each `t` record within a bundle.

```
@STATIC;1.0;<dependency>...<dependency>[<sourcemap>]t;<code_len>;<js_code>[e;]
```

Records appear in this order:

1. Zero or more dependency records (any mix of `i` and `I`), in source order.
2. Zero or one source map record (`S`), present in debug builds only.
3. Exactly one text record (`t`) containing the compiled JavaScript.
4. Optional end marker `e;`. The stream parser stops at end of input
   if `e;` is absent.

### Per-File Markers

| Marker | Name           | Content                                     | Source construct               |
|--------|----------------|---------------------------------------------|--------------------------------|
| `i`    | local import   | bare filename, e.g. `CPObject.j`            | `@import "CPObject.j"`         |
| `I`    | standard import | framework-relative path, e.g. `Foundation/CPObject.j` | `@import <Foundation/CPObject.j>` |
| `S`    | source map     | base64-encoded source map JSON              | compiler `-g -S` flags         |
| `t`    | text           | compiled JavaScript                         | body of the source file        |

The case convention is systematic: lowercase `i` denotes a local
(quote-form) import; uppercase `I` denotes a standard (angle-bracket)
import. Uppercase `S` denotes the source map.

### Per-File Example — No Imports (release)

`_CGGeometry.j`, which contains no `@import` directives:

```
@STATIC;1.0;t;9589;{var the_typedef = objj_allocateTypeDef("CGPoint");
...
```

### Per-File Example — Local Imports (release)

`CPCache.j` from Foundation:

```
@STATIC;1.0;i;9;CPObject.ji;14;CPDictionary.ji;9;CPString.jt;<len>;<js>
```

### Per-File Example — Standard Imports (release)

`_CPAutocompleteMenu.j` from AppKit, which imports from Foundation:

```
@STATIC;1.0;I;19;Foundation/CPObject.ji;13;CPTextField.ji;14;CPTableView.ji;16;_CPMenuWindow.jt;<len>;<js>
```

### Per-File Example — Source Map (debug)

The debug build of any file adds an `S` record between the last dependency
and the `t` record:

```
@STATIC;1.0;i;9;CPObject.j...S;<map_len>;<base64_sourcemap>t;<len>;<js>
```

---

## Data URL Format

Image sprites are stored in `dataURLs.txt` alongside the `.sj` bundle,
using a variant record structure. The `u` record carries the resource path;
it is immediately followed by a bare length/content pair (no marker) carrying
the data URI:

```
@STATIC;1.0;u;<path_len>;<resource_path><dataurl_len>;<data_uri>...e;
```

- `u` — **URL**: the resource path relative to the bundle root
  (e.g. `Resources/action_button.png`).
- The following `<dataurl_len>;<data_uri>` pair is the
  `data:image/...;base64,...` string. It carries no marker character.

---

## MHTML Format

Sprited images are also written in MHTML form in `MHTMLPaths.txt` and
`MHTMLData.txt`. `MHTMLPaths.txt` uses the same `@STATIC;1.0;u;...`
structure as `dataURLs.txt`, substituting `mhtml:` URIs. `MHTMLData.txt`
is a raw MIME multipart document (not `@STATIC`-framed) and is outside
the scope of this specification.

---

## Complete Marker Reference

| Marker | Level      | Name            | Notes                                      |
|--------|------------|-----------------|--------------------------------------------|
| `p`    | bundle     | path            | source filename; precedes each `t` entry   |
| `t`    | bundle     | text            | per-file record; follows each `p` entry    |
| `u`    | data URL   | URL             | resource path; content follows without marker |
| `e`    | both       | end             | stream terminator; no length or content    |
| `i`    | per-file   | local import    | `@import "..."` — bare filename            |
| `I`    | per-file   | standard import | `@import <...>` — `Framework/file.j` path |
| `S`    | per-file   | source map      | base64 JSON; debug builds only             |
| `t`    | per-file   | text            | compiled JavaScript payload                |

---

## Source Files

| File | Role |
|---|---|
| `Objective-J/MarkedStream.js` | Stream reader — canonical parser |
| `Objective-J/Executable.js` | Per-file writer (`toMarkedString`) and reader (`decompile`) |
| `Objective-J/FileDependency.js` | Dependency record writer (`i`/`I`) |
| `Objective-J/FileExecutable.js` | Bundle loader and compiler entry point |
| `Objective-J/CommonJS/lib/objective-j/jake/bundletask.js` | Bundle writer (`defineStaticTask`) |

---

## Implementation Notes for capp-build

**Reading a bundle** requires a streaming parser that:

1. Validates the `@STATIC;1.0;` header.
2. Reads alternating `p`/`t` pairs until `e;`.
3. Extracts the filename from each `p` record and the per-file record
   from each `t` record.
4. Ignores unknown markers by consuming their length-delimited content
   (forward-compatible by design; `MarkedStream` does exactly this).

**Writing a bundle** requires:

1. Emitting `@STATIC;1.0;`.
2. For each compiled source file, emitting `p;<name_len>;<name>` followed
   by `t;<record_len>;<per-file-record>`.
3. Emitting `e;`.

**Writing a per-file record** requires the output of the ObjJ-to-JavaScript
compiler for one source file, composed as:

1. `@STATIC;1.0;`
2. One `i` or `I` record per `@import` directive, in source order,
   using lowercase for quote-form and uppercase for angle-bracket form.
3. Optionally one `S` record if source maps are enabled.
4. One `t` record containing the compiled JavaScript.

The per-file record length needed for the enclosing bundle `t` record is
the byte length of the entire per-file string, measured after composition.
