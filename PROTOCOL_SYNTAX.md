# Protocol syntax

Moonlift protocols are tagged-union types used in control-result position.

```moonlift
type Scanner = hit(pos: i32) | miss(pos: i32)
```

When a named tagged union appears after `region ->`, its variants become region exits. Variant fields must be named.

```moonlift
region scan_until(p: ptr(u8), n: i32, target: i32) -> Scanner
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
```

This is equivalent to inline continuations:

```moonlift
region scan_until(p: ptr(u8), n: i32, target: i32;
    hit: cont(pos: i32), miss: cont(pos: i32))
```

The compiler lowers protocol exits to ordinary continuation slots before region normal form.

Current implementation:

- `type P = exit(field: T) | other(field: U)` parses as a tagged union with named variant fields.
- `region r(...) -> P` resolves `P` from preceding type declarations and synthesizes continuation slots.
- `jump exit(field = value)` is checked against the protocol exit fields.
- Inline continuation declarations still work.
- Data-style payload variants like `ok(i32)` are accepted for data, but cannot be used as protocol exits; protocol fields must be named.

Function protocols are intentionally deferred; this first step is region-exit protocol sugar over the existing continuation machinery.
