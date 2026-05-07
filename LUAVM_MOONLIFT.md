# LuaJIT VM — Moonlift Metaprogram Compilation Design

Target: one `.so` emitted by a metaprogram. Host Lua runs once at compile time,
building ASDL trees. The Moonlift tree compiles to native code.

---

## Model

Moonlift metaprogramming is ASDL construction, spliced via `@{value}` at
parser-known positions. The host Lua never interpolates strings — it uses
the Moonlift host API to build `MoonTree.Expr`, `MoonTree.Stmt`, and
`MoonOpen.RegionFrag` nodes directly.

```
Host Lua (compile time, runs once)
  │
  ├─► moon.region("name", params, conts, builder_fn)
  │       → RegionFragValue containing a MoonOpen.RegionFrag
  │
  ├─► ExprValue + overloaded operators
  │       a + b, a:shl(n), a:band(mask), a:lt(b), etc.
  │       → MoonTree.ExprBinary, ExprCompare, etc.
  │
  ├─► b:emit(frag, args, fills)
  │       → MoonTree.StmtUseRegionFrag
  │
  └─► Raw Tr.StmtSwitch(op_ref, arms, {}, {})
          → MoonTree.StmtSwitch

  ↓ splice via @{switch_hole} in Moonlift source

Moonlift template (module with hole at stmt position)
  │  export func vm_dispatch(base, pc, knum, kgc) -> i32
  │      return region -> i32
  │      entry loop()
  │          let op: u8 = as(u8, pc[0] & 0xFF)
  │          @{dispatch_table}       ← RegionSlot → SlotValueRegion({switch})
  │          jump loop()
  │      end
  │  end
  │
  ▼
Compiled .so — one exported symbol: vm_dispatch
```

The `@{dispatch_table}` hole is stmt-position: parser creates `RegionSlot`,
host fills with `SlotValueRegion({switch_stmt})`, open_expand replaces the
hole with the switch. Each switch arm emits a handler region via
`StmtUseRegionFrag`, inlined by open_expand with the `loop` continuation.

---

## Layer 1 — bytecode definitions

```lua
local BCDEFS = {
    ISLT  = { op = 0,  amode = "var", bmode = "var",
              handler_fn = make_comparison_handler },
    ISGE  = { op = 1,  amode = "var", bmode = "var",
              handler_fn = make_comparison_handler },
    ADDVV = { op = 10, amode = "dst", bmode = "var", cmode = "var",
              handler_fn = make_arithmetic_handler },
    TGETV = { op = 20, amode = "dst", bmode = "var", cmode = "var",
              handler_fn = make_table_get_handler },
    CALL  = { op = 30, amode = "base", bmode = "lit", cmode = "lit",
              handler_fn = make_call_handler },
    RET   = { op = 40, amode = "rbase", bmode = "lit",
              handler_fn = make_return_handler },
    -- ... ~80 total
}
```

---

## Layer 2 — handler regions via host API

Each handler is built with `moon.region(name, params, conts, builder_fn)`.
Params are `moon.param(name, type)`. Conts are `moon.cont(params)`.
The builder function receives a `BlockBuilder` and uses `b:expr`, `b:if_`,
`b:jump`, `b:emit` to construct the body.

```lua
local function make_arithmetic_handler(name, op_sym, meta_name, session)
    local T = session.T
    local C, Sem = T.MoonCore, T.MoonSem

    return moon.region("handler_" .. name,
        {
            moon.param("base",  moon.ptr(moon.u8)),
            moon.param("pc",    moon.ptr("BCIns")),
            moon.param("ra_ofs", moon.u8),
            moon.param("rb_ofs", moon.u8),
            moon.param("rc_ofs", moon.u8),
            moon.param("knum",  moon.ptr("TValue")),
            moon.param("kgc",   moon.ptr("GCRef")),
        },
        { loop = moon.cont({}) },
        function(b)
            -- Named refs to params
            local base  = b:param("base")
            local ra_ofs = b:param("ra_ofs")
            local rb_ofs = b:param("rb_ofs")
            local rc_ofs = b:param("rc_ofs")

            -- ra = base + (ra_ofs * 8)
            local ra = base + (ra_ofs * moon.int(8))
            local rb = base + (rb_ofs * moon.int(8))
            local rc = base + (rc_ofs * moon.int(8))

            -- Load TValues
            local rbv = api.load(rb, moon.ptr("TValue"))
            local rcv = api.load(rc, moon.ptr("TValue"))

            -- Type guard: check NaN-tag bits
            local tag_mask = moon.int(0xFFF8)
            local num_tag  = moon.int(0)
            -- tvisnum(v) = (v.u64 >> 47) < 0xFFF0
            -- For host API, express as bit mask check
            local rbv_tag = api.load(rb, moon.u64):lshr(moon.int(47))
            local rcv_tag = api.load(rc, moon.u64):lshr(moon.int(47))
            local is_num = rbv_tag:lt(moon.int(0xFFF0))
                          :band(rcv_tag:lt(moon.int(0xFFF0)))

            b:if_(is_num,
                function(then_b)
                    -- Extract numbers (low 48 bits are IEEE 754 double)
                    local rbn = api.load(rb, moon.f64)
                    local rcn = api.load(rc, moon.f64)
                    local result = nil
                    if     op_sym == "+" then result = rbn + rcn
                    elseif op_sym == "-" then result = rbn - rcn
                    elseif op_sym == "*" then result = rbn * rcn
                    end
                    -- Store result at ra
                    api.store(ra, result)
                    -- Advance PC
                    local pc_val = b:param("pc")
                    local pc_next = pc_val + moon.int(4)  -- sizeof BCIns
                    api.store(pc_val, pc_next)
                    -- Jump back to dispatch loop
                    then_b:jump(b:param("loop"))
                end,
                function(else_b)
                    -- Fallback: call metamethod helper
                    -- (simplified — real impl emits a C helper call)
                    else_b:jump(b:param("loop"))
                end)
        end)
end
```

---

## Layer 3 — dispatch table

The switch statement is built entirely in host Lua using raw ASDL
constructors. It references function-local bindings by name — the
Moonlift template defines them with `let` and the semantic layer
resolves named references during typecheck.

```lua
local function build_dispatch_switch(session, handler_frags)
    local T   = session.T
    local Tr  = T.MoonTree
    local O   = T.MoonOpen
    local B   = T.MoonBind
    local Sem = T.MoonSem

    -- Reference the Moonlift local variable `op` (defined by `let op: u8 = ...`
    -- in the template). At typecheck time this resolves to the let-binding.
    local op_ref = Tr.ExprRef(
        Tr.ExprSurface,
        B.ValueRefName("op"))

    local arms = {}
    for name, def in pairs(BCDEFS) do
        local frag = handler_frags[name]          -- RegionFragValue
        local slot = O.RegionFragSlot(
            session:symbol_key("splice.region_frag", name),
            name)
        local frag_ref = O.RegionFragRefSlot(slot)

        -- Args passed to the handler: base, pc, ra_ofs, rb_ofs, rc_ofs, knum, kgc
        local args = {
            Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("base")),
            Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("pc")),
            -- ra/rb/rc offsets decoded from the instruction bits
            Tr.ExprBinary(Tr.ExprSurface, T.MoonCore.BinBitAnd,
                Tr.ExprBinary(Tr.ExprSurface, T.MoonCore.BinLShr,
                    Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("ins")),
                    Tr.ExprLit(Tr.ExprSurface, T.MoonCore.LitInt("8"))),
                Tr.ExprLit(Tr.ExprSurface, T.MoonCore.LitInt("0xFF"))),
            Tr.ExprBinary(Tr.ExprSurface, T.MoonCore.BinLShr,
                Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("ins")),
                Tr.ExprLit(Tr.ExprSurface, T.MoonCore.LitInt("24"))),
            Tr.ExprBinary(Tr.ExprSurface, T.MoonCore.BinBitAnd,
                Tr.ExprBinary(Tr.ExprSurface, T.MoonCore.BinLShr,
                    Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("ins")),
                    Tr.ExprLit(Tr.ExprSurface, T.MoonCore.LitInt("16"))),
                Tr.ExprLit(Tr.ExprSurface, T.MoonCore.LitInt("0xFF"))),
            Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("knum")),
            Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("kgc")),
        }

        -- Continuation fill: loop → jump back to entry block
        local cont_fills = {
            O.ContBinding("loop",
                O.ContTargetLabel(Tr.BlockLabel("loop")))
        }

        local emit_stmt = Tr.StmtUseRegionFrag(
            Tr.StmtSurface,
            session:symbol_key("emit", name),
            frag_ref,
            args,
            {},
            cont_fills)

        arms[#arms + 1] = Tr.SwitchStmtArm(
            Sem.SwitchKeyRaw(tostring(def.op)),
            { emit_stmt })
    end

    return Tr.StmtSwitch(Tr.StmtSurface, op_ref, arms, {}, {})
end
```

---

## Layer 4 — the template

```moonlift
return module
    export func vm_dispatch(
        base:    ptr(u8),
        pc:      ptr(BCIns),
        knum:    ptr(TValue),
        kgc:     ptr(GCRef)
    ) -> i32
        return region -> i32
        entry loop()
            let ins:   u32 = as(u32, pc[0])
            let op:    u8  = as(u8, ins & 0xFF)
            let ra_ofs: u8 = as(u8, (ins >> 8) & 0xFF)
            let rb_ofs: u32 = ins >> 24
            let rc_ofs: u8 = as(u8, (ins >> 16) & 0xFF)

            @{dispatch_table}    -- RegionSlot → SlotValueRegion({switch_stmt})

            jump loop()
        end
    end
end
```

No metaprogramming in the Moonlift source beyond `@{dispatch_table}`.
All the complexity lives in the host Lua that built the switch_stmt ASDL.

---

## Layer 5 — assembly

```lua
local function build_vm()
    local T = pvm.context(); A.Define(T)
    local session = Session.new({ prefix = "vm", T = T })

    -- Generate handler regions
    local handler_frags = {}
    for name, def in pairs(BCDEFS) do
        handler_frags[name] = def.handler_fn(name, session)
    end

    -- Build the dispatch switch ASDL
    local switch_stmt = build_dispatch_switch(session, handler_frags)

    -- Eval the template: splice injection + compilation
    local src = [[
        return module
        export func vm_dispatch(
            base: ptr(u8), pc: ptr(BCIns),
            knum: ptr(TValue), kgc: ptr(GCRef)
        ) -> i32
            return region -> i32
            entry loop()
                let ins: u32 = as(u32, pc[0])
                let op: u8  = as(u8, ins & 0xFF)
                @{dispatch_table}
                jump loop()
            end
        end
    ]]
    local compiled = Host.eval(src)  -- switch_stmt fills the slot

    return compiled  -- CompiledModule, .get("vm_dispatch") → callable
end
```

---

## Scaling to the full VM

**Tracer**: each bytecode's recording recipe is a `RegionFrag` that emits IR.
The recording loop is identical to the interpreter dispatch — a switch on
opcode, each arm emitting the recipe region.

**Code generator**: each IR opcode is a `RegionFrag` that emits machine code
bytes into an mcode buffer (`ptr(u8)` + offset). The codegen loop is a switch
on IR opcode.

**Snapshots**: the stack walker is a `RegionFrag` parameterized by the frame
layout (a view over the Lua stack).

All of these follow the same pattern: host Lua builds ASDL switch/region
trees, splices them into a Moonlift module, compiles to a `.so`. No Lua at
runtime.
