# Establish the v1 user workflow and product contract

Type: grilling
Status: resolved

## Question

Who builds and consumes archives, through which commands and runtime API, and
what must v1 be able to do for the target game/runtime workload? Resolve the
build-time and runtime responsibilities, core workflows, supported platforms,
compatibility expectations, and v1 feature boundary. Keep this focused on the
product contract; format internals depend on it.

## Answer

V1 is a build-time CLI plus a runtime library/API: the CLI creates archives,
and runtime consumers read individual assets by path without extracting the
whole archive. The initial platform set is Linux, macOS, and Windows, matching
Goose's documented desktop support. V1 uses a new versioned gpack format and
makes no ZIP or other legacy import/export promise. The input model is regular
files only; paths are normalized as safe relative archive paths, and unsafe
paths are rejected. Exact CLI commands, lookup semantics, format layout,
metadata policy, codecs, integrity guarantees, and extraction scope remain
open for dependent decisions.
