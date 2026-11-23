# GPack

GPack is a Goose-oriented project for building and consuming binary archives
of game/runtime assets.

## Language

**Asset**:
A regular file included in an archive and made available to a runtime consumer.
_Avoid_: resource, blob (unless referring to bytes rather than a named asset)

**Asset path**:
A normalized, safe relative path that identifies an asset in an archive.
_Avoid_: filesystem path (when referring to the archive's canonical name)

**Archive**:
A versioned binary package of assets and the information needed to find them.
_Avoid_: bundle (unless referring to a third-party format)

**Packing**:
Creating an archive from a set of input assets.
_Avoid_: bundling

**Runtime lookup**:
Finding and reading an asset from an archive by its asset path without
extracting the full archive.
_Avoid_: mounting (unless a filesystem mount is explicitly designed)
