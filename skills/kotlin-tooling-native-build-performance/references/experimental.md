# Experimental Switches

Offer these last, label them experimental in the report, and keep them out of
the default recommendation set. Get the user's agreement before enabling any
of them.

## Incremental compilation of klib artifacts

```properties
# gradle.properties
kotlin.incremental.native=true
```

Recompiles only the changed part of a klib into the final binary, which helps
warm rebuilds after small edits. If it causes broken or inconsistent builds,
revert it and file a YouTrack issue with a minimized reproducer.

## smallBinary

The `smallBinary` binary option sets `-Oz` as the default LLVM optimization
level to shrink release binaries and their link time. It can cost runtime
performance, so verify hot paths before keeping it. It applies to release
binaries — it is not a fix for slow debug loops.

## LLVM backend customization

Customizing the LLVM backend is a last resort when nothing else helps, and is
out of scope for a routine performance pass — point the user at the official
documentation instead of improvising compiler flags.

Docs: https://kotlinlang.org/docs/native-binary-options.html and
https://kotlinlang.org/docs/native-improving-compilation-time.html
