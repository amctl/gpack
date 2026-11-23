# Define archive safety and reproducibility guarantees

Type: grilling
Status: resolved

## Question

What threat model and deterministic-output promise should v1 make? Decide
path normalization and rejection rules, duplicate handling, symlink behavior,
metadata/timestamp treatment, input mutation behavior, integrity versus
authenticity, decompression/resource limits, and cross-platform/toolchain
guarantee boundaries. Use concrete pack, list, verify, and extract scenarios.

## Comments

- User decisions so far: inputs are regular files only; archive paths are
  normalized safe relative paths and unsafe paths are rejected. Reproducibility
  means identical input bytes, options, and pinned codec build produce
  identical archive bytes. V1 detects accidental corruption and makes no
  authenticity/signature claim. Archives may be distributed separately from
  the executable.
- Recommended defaults still awaiting confirmation: omit source timestamps
  and permissions from the archive; reject colliding normalized paths; fail
  when a source change is detected during packing, while documenting that the
  input tree must remain stable for the duration of a build.

## Answer

V1 stores normalized safe relative asset paths and file bytes, omits source
timestamps and permissions, and rejects duplicate paths after normalization.
Symlinks and other non-regular inputs are excluded. Packing fails when it
detects a source file changing during the build; callers must keep the input
tree stable for the build duration. Reproducibility is byte-for-byte for the
same input bytes, options, and pinned codec build. Integrity checks detect
accidental corruption; gpack makes no authenticity or signature claim. These
guarantees apply to archives that may be distributed separately from the
executable. Resource limits and exact checksum coverage remain to be specified
in the format contract.
