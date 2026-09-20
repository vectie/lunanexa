# Contract compatibility policy

`lunanexa.v1` is the canonical provider-neutral contract. Additive optional
fields and new capability values may be introduced in a minor product release.
Removing or renaming fields, changing their meaning, or changing JSON encoding
requires a new contract version and a parallel migration window.

Consumers must reject unknown major contract versions. LunaNexa validates the
canonical envelope before admission. Compatibility endpoints translate into
this envelope and never become an alternative source of lifecycle vocabulary.

An optional field that is absent is **omitted** from the encoded document, not
written as `null`. That is what lets a new field be added without disturbing the
bytes of every existing document -- and, because assignment and heartbeat
authenticity is a MAC over that document, without disturbing their signature
material either. `DesiredAssignment.group` is the worked example: it is present
only for a paired placement, so a single-machine assignment signs exactly what it
signed before the field existed.

`Int64` values are encoded as JSON strings to preserve exact values across
runtimes. Enum values use their stable constructor names. Golden fixtures under
`tests/fixtures` are release artifacts and changes to them require interface
review.

Opaque identifiers use ASCII letters, digits, `-`, `_`, `.`, and `:` only;
path separators, whitespace, control characters, and interpolation syntax are
not valid identifiers. A SHA-256 digest is exactly `sha256:` followed by 64
hexadecimal digits. These lexical rules are security invariants of v1, not
presentation suggestions.
