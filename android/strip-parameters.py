#!/usr/bin/env python3
"""Remove the MethodParameters attribute from .class files.

Why this exists
---------------
javac 21 and later write a MethodParameters attribute into every method.  The d8
that ships with build-tools 34 -- the newest build-tools that F-Droid's SDK
transparency log can verify, and so the newest a build service can install --
cannot read that attribute.  It fails with an internal NullPointerException and
the build stops there:

    Error in .../MainActivity$1.class:
    java.lang.NullPointerException: Cannot invoke "String.length()" because
    "<parameter1>" is null

The attribute carries the parameter names of a method and nothing more.  Names
are not part of the dex format and nothing in this app reads them, so removing
the attribute is lossless: the same classes, minus a note a dex never carried.

build.sh calls this only after the dexer has actually refused the classes, so a
toolchain that does read the attribute (build-tools 36, say) never sees a
difference of a single byte.

Everything else is copied byte for byte, including the constant pool entry that
names the attribute (which is simply left unreferenced).  Each rewritten file is
then walked end to end again to prove it is still a well-formed class file with
no MethodParameters attribute left in it.
"""
import pathlib
import struct
import sys

# Constant pool tag -> size of the entry after the tag byte.  CONSTANT_Utf8 (1)
# is variable length and handled on its own; the two long entries take two slots.
FIXED = {3: 4, 4: 4, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4,
         15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}

TARGET = "MethodParameters"


def u2(b, i):
    return struct.unpack_from(">H", b, i)[0]


def u4(b, i):
    return struct.unpack_from(">I", b, i)[0]


def constant_pool_end(b):
    i, n, idx = 10, u2(b, 8), 1
    while idx < n:
        tag = b[i]
        i += 1
        if tag == 1:
            i += 2 + u2(b, i)
        elif tag in (5, 6):
            i += 8
            idx += 1
        else:
            i += FIXED[tag]
        idx += 1
    return i


def find_utf8(b, want):
    """Pool index of the string `want`, or None."""
    i, n, idx = 10, u2(b, 8), 1
    while idx < n:
        tag = b[i]
        i += 1
        if tag == 1:
            ln = u2(b, i)
            if b[i + 2:i + 2 + ln].decode("utf-8", "replace") == want:
                return idx
            i += 2 + ln
        elif tag in (5, 6):
            i += 8
            idx += 1
        else:
            i += FIXED[tag]
        idx += 1
    return None


def skip_attributes(b, j):
    """`j` points at an attributes_count; return the offset just after them."""
    n = u2(b, j)
    j += 2
    for _ in range(n):
        j += 6 + u4(b, j + 2)
    return j


def layout(b):
    """Return (offset of the first method, number of methods)."""
    j = constant_pool_end(b) + 6                      # access, this, super
    j += 2 + 2 * u2(b, j)                             # interfaces
    n_f = u2(b, j)                                    # fields
    j += 2
    for _ in range(n_f):
        j += 6                                        # access, name, descriptor
        j = skip_attributes(b, j)
    n_m = u2(b, j)
    return j + 2, n_m


def method_attributes(b):
    """Yield (name_index, length, offset) for every method attribute."""
    j, n_m = layout(b)
    for _ in range(n_m):
        j += 6
        n = u2(b, j)
        j += 2
        for _ in range(n):
            yield u2(b, j), u4(b, j + 2), j
            j += 6 + u4(b, j + 2)


def class_attributes_offset(b):
    j, n_m = layout(b)
    for _ in range(n_m):
        j += 6
        j = skip_attributes(b, j)
    return j


def strip(path):
    """Drop every MethodParameters attribute.  Returns how many were removed."""
    path = pathlib.Path(path)
    b = path.read_bytes()
    if b[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError(f"{path}: not a class file")
    name_idx = find_utf8(b, TARGET)
    if name_idx is None:
        return 0                                      # nothing to do; file untouched

    # Rebuild the method attribute tables without that one attribute, copying
    # every other attribute exactly as it was, and the pool and fields as they are.
    methods_start, n_m = layout(b)
    j = methods_start
    out, removed = bytearray(b[:methods_start]), 0
    for _ in range(n_m):
        header = b[j:j + 6]
        j += 6
        n = u2(b, j)
        j += 2
        keep, dropped = bytearray(), 0
        for _ in range(n):
            ni, ln = u2(b, j), u4(b, j + 2)
            if ni == name_idx:
                dropped += 1
            else:
                keep += b[j:j + 6 + ln]
            j += 6 + ln
        removed += dropped
        out += header + struct.pack(">H", n - dropped) + keep
    out += b[j:]

    # Prove it: the file must still end exactly where its own structure says it
    # ends, and no method may still carry the attribute.
    end = skip_attributes(out, class_attributes_offset(out))
    if end != len(out):
        raise ValueError(f"{path}: rewritten class file does not end cleanly "
                         f"({end} of {len(out)} bytes)")
    if any(a[0] == name_idx for a in method_attributes(out)):
        raise ValueError(f"{path}: a MethodParameters attribute survived")

    path.write_bytes(out)
    return removed


def main(argv):
    targets = []
    for arg in argv:
        p = pathlib.Path(arg)
        targets += sorted(p.rglob("*.class")) if p.is_dir() else [p]
    if not targets:
        print("usage: strip-parameters.py <classes-dir-or-file>...", file=sys.stderr)
        return 2
    total = 0
    for p in targets:
        total += strip(p)
    print(f"  MethodParameters : {total} removed, {len(targets)} class file(s) "
          f"proved well formed afterwards")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
