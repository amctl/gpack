# Define runtime lookup and archive update behavior

Type: grilling
Status: resolved
Blocked by: 01, 02, 04

## Question

Specify how a game/runtime consumer identifies and reads an asset: normalized
path, stable asset ID, or both; whole-asset reads versus byte-range/streaming
reads; whether multiple readers may use one open archive concurrently; and
what archive replacement/update behavior the runtime must support. The archive
may ship separately from the executable, but that does not by itself require
partial updates or a filesystem mount.

## Comments

- User decisions: callers identify assets by normalized path; one read returns
  the complete asset; the runtime opens a read-only archive, and the application
  replaces the complete archive outside gpack. Stable IDs, byte-range reads,
  partial updates, and filesystem mounting are not v1 requirements. One open
  read-only archive must support multiple concurrent independent asset reads.

## Answer

The runtime API looks up assets by normalized path and returns a complete
asset. It opens a read-only archive that may be distributed separately; the
application replaces the complete archive outside gpack. One open archive
supports multiple concurrent independent reads. V1 does not require stable
asset IDs, byte-range reads, partial archive updates, or filesystem mounting.
