#!/usr/bin/env python3
"""Byte-level payload oracle for capp-build phase 8 code generation.

Companion to symbol_oracle.py. Parses @STATIC;1.0; records per
STATIC-BLOB-FORMAT.md, strips the S (source map) record from legacy
per-file records, and byte-compares against our compiler's output.

Length semantics (discovered June 12 2026, correcting the format doc):
record lengths are JS String.length values — UTF-16 code units — not
bytes. They coincide for ASCII payloads; CPDate.j in Foundation.sj
(one U+00B1) proves the unit. Parsing therefore happens on decoded
text; comparison happens on bytes.

Commands:
  check   FILE...                    validate framing; round-trip must be
                                     byte-identical to the input
  extract FILE [--t-only] [-o OUT]   print the legacy record with S
                                     stripped (or just the t payload)
  extract BUNDLE.sj --file NAME ...  same, pulling the per-file record
                                     out of a bundle first
  diff    LEGACY OURS [--t-only] [--file NAME]
                                     strip S from LEGACY, byte-compare
                                     against OURS (a record or payload
                                     our toolchain wrote); exit 1 and
                                     report first divergence on mismatch

The tier-A gate is:
  payload_oracle.py diff \
      toolchain_test/Build/toolchain_test.build/Debug/Browser.environment/Sources/main.j \
      <our main.j record> --t-only
"""
import argparse, sys

MAGIC = "@STATIC;1.0;"


def u16len(s):
    """JS String.length: UTF-16 code units."""
    return len(s) + sum(1 for c in s if ord(c) > 0xFFFF)


def take_units(s, i, n):
    """Substring of s starting at codepoint index i spanning exactly n
    UTF-16 code units. Returns (substring, next_codepoint_index)."""
    chunk = s[i:i + n]                       # fast path: BMP-only
    extra = sum(1 for c in chunk if ord(c) > 0xFFFF)
    while extra:
        chunk = s[i:i + n - extra]
        extra = u16len(chunk) - n
        if extra >= 0:
            break
        extra = sum(1 for c in chunk if ord(c) > 0xFFFF)  # re-shrink
    if u16len(chunk) != n:
        return None, i
    return chunk, i + len(chunk)


class Record:
    def __init__(self, marker, content):
        self.marker = marker      # one-char str
        self.content = content    # str

    def encode(self):
        if self.marker == "e":
            return "e;"
        return f"{self.marker};{u16len(self.content)};{self.content}"


def parse_stream(text, what):
    """Parse a @STATIC;1.0; stream into Records. Strict: any framing
    defect is fatal. Returns (records, saw_end)."""
    if not text.startswith(MAGIC):
        sys.exit(f"{what}: missing {MAGIC} header")
    i = len(MAGIC)
    records, saw_end = [], False
    while i < len(text):
        marker = text[i]
        if text[i:i + 2] == "e;":
            saw_end = True
            i += 2
            if i != len(text):
                sys.exit(f"{what}: {len(text) - i} chars after e; terminator")
            break
        if text[i + 1:i + 2] != ";":
            sys.exit(f"{what}: index {i}: marker {marker!r} not followed by ';'")
        j = text.index(";", i + 2)
        length = int(text[i + 2:j])
        content, nxt = take_units(text, j + 1, length)
        if content is None:
            sys.exit(f"{what}: index {i}: record {marker!r} declares {length} "
                     f"units, stream exhausted")
        records.append(Record(marker, content))
        i = nxt
    return records, saw_end


def encode_stream(records, saw_end):
    out = MAGIC + "".join(r.encode() for r in records)
    if saw_end:
        out += "e;"
    return out


def bundle_member(text, name, what):
    """Pull the per-file record for NAME from a bundle stream."""
    records, _ = parse_stream(text, what)
    names = []
    for k, rec in enumerate(records):
        if rec.marker == "p":
            names.append(rec.content)
            if rec.content == name:
                if k + 1 < len(records) and records[k + 1].marker == "t":
                    return records[k + 1].content
                sys.exit(f"{what}: p;{name} not followed by a t record")
    sys.exit(f"{what}: no member {name!r}; members: {', '.join(names[:10])}"
             + (" ..." if len(names) > 10 else ""))


def strip_s(records):
    return [r for r in records if r.marker != "S"]


def t_payload(records, what):
    ts = [r for r in records if r.marker == "t"]
    if len(ts) != 1:
        sys.exit(f"{what}: expected exactly one t record, found {len(ts)}")
    return ts[0].content


def load_record(path, member, what):
    text = open(path, "rb").read().decode("utf-8")
    if member:
        text = bundle_member(text, member, what)
    return text


def first_divergence(a, b):
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i
    return None if len(a) == len(b) else n


def show_divergence(legacy, ours, at):
    lo = max(0, at - 40)
    print(f"first divergence at byte {at}", file=sys.stderr)
    print(f"  legacy [{lo}:{at + 40}]: {legacy[lo:at + 40]!r}", file=sys.stderr)
    print(f"  ours   [{lo}:{at + 40}]: {ours[lo:at + 40]!r}", file=sys.stderr)
    print(f"  lengths: legacy {len(legacy)}, ours {len(ours)}", file=sys.stderr)


def cmd_check(args):
    status = 0
    for path in args.files:
        raw = open(path, "rb").read()
        text = raw.decode("utf-8")
        records, saw_end = parse_stream(text, path)
        if encode_stream(records, saw_end).encode("utf-8") != raw:
            print(f"{path}: round-trip MISMATCH", file=sys.stderr)
            status = 1
            continue
        pairs = sum(1 for r in records if r.marker == "p")
        if pairs:
            summary = (f"{pairs} p/t pairs, "
                       + f"{sum(1 for r in records if r.marker == 't')} t records")
        else:
            summary = " ".join(
                f"{r.marker};{u16len(r.content)}"
                + (f";{r.content}" if r.marker in "iIp" else "")
                for r in records)
        end = "e;" if saw_end else "(no e;)"
        print(f"{path}: ok, round-trip exact — {summary} {end}")
    return status


def cmd_extract(args):
    text = load_record(args.file, args.member, args.file)
    records, saw_end = parse_stream(text, args.file)
    out = (t_payload(records, args.file) if args.t_only
           else encode_stream(strip_s(records), saw_end))
    data = out.encode("utf-8")
    if args.output:
        open(args.output, "wb").write(data)
    else:
        sys.stdout.buffer.write(data)
    return 0


def cmd_diff(args):
    text = load_record(args.legacy, args.member, args.legacy)
    records, saw_end = parse_stream(text, args.legacy)
    want = (t_payload(records, args.legacy) if args.t_only
            else encode_stream(strip_s(records), saw_end)).encode("utf-8")
    ours = open(args.ours, "rb").read()
    if args.t_only and ours.startswith(MAGIC.encode()):
        # Our side is a full record; compare its t payload.
        recs, _ = parse_stream(ours.decode("utf-8"), args.ours)
        ours = t_payload(recs, args.ours).encode("utf-8")
    at = first_divergence(want, ours)
    if at is None:
        print(f"BYTE-EXACT ({len(want)} bytes): {args.ours}")
        return 0
    show_divergence(want, ours, at)
    return 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("check", help="validate framing and round-trip")
    p.add_argument("files", nargs="+")
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser("extract", help="print record with S stripped")
    p.add_argument("file")
    p.add_argument("--file", dest="member", help="member name within a bundle")
    p.add_argument("--t-only", action="store_true", help="just the t payload")
    p.add_argument("-o", "--output")
    p.set_defaults(fn=cmd_extract)

    p = sub.add_parser("diff", help="strip S from legacy, compare to ours")
    p.add_argument("legacy")
    p.add_argument("ours")
    p.add_argument("--file", dest="member", help="member name within a legacy bundle")
    p.add_argument("--t-only", action="store_true", help="compare t payloads only")
    p.set_defaults(fn=cmd_diff)

    args = ap.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
