return [[
(type DFamilyKey
  (DKeyCopy class src_const same_value)
  (DKeyIntBin op scalar lhs_const rhs_const commutative rhs_pow2)
  (DKeyBitBin op scalar rhs_const)
  (DKeyShiftRotate op scalar rhs_const rhs_small_imm)
  (DKeyCompareBranch op scalar rhs_const fused_branch rhs_is_zero)
  (DKeyLoadStore is_load shape base_kind has_index const_disp align_bytes trap_kind)
  (DKeyAddress base_kind elem_size const_offset)
  (DKeyCall target_kind argc has_result result_class)
  (DKeyControl kind)
  (DKeyReturn has_value class)
  (DKeyOther kind)
)

(term lower_rule (key fi cmd const_map))

(rule lower_rule 100
  ((DKeyCopy class src_const same_value) fi cmd const_map)
  (when "same_value")
  (lua "return ctx.decision(fi.cmd_index, 'copy.noop', 0, ctx.D.DAsmComment('copy noop'))"))

(rule lower_rule 90
  ((DKeyCopy class src_const same_value) fi cmd const_map)
  (when "src_const and src_const.kind ~= 'DConstUnknown' and (src_const.kind == 'DConstNull' or (src_const.kind == 'DConstInt' and tonumber(src_const.raw) == 0))")
  (lua "return ctx.decision(fi.cmd_index, 'copy.zero', 1, ctx.D.DAsmMove(ctx.op_vreg(cmd.dst), ctx.D.DOpImmI64('0'), class))"))

(rule lower_rule 80
  ((DKeyCopy class src_const same_value) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'copy.mov', 2, ctx.D.DAsmMove(ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.src), class))"))

(rule lower_rule 100
  ((DKeyIntBin op scalar lhs_const rhs_const commutative rhs_pow2) fi cmd const_map)
  (when "rhs_const and rhs_const.kind == 'DConstInt' and tonumber(rhs_const.raw) ~= nil and tonumber(rhs_const.raw) >= -2147483648 and tonumber(rhs_const.raw) <= 2147483647 and (op == 'BackIntAdd' or op == 'BackIntSub')")
  (lua "return ctx.decision(fi.cmd_index, 'intbin.imm32', 1, ctx.D.DAsmBinary(op .. '.imm', ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.D.DOpImmI64(rhs_const.raw), scalar))"))

(rule lower_rule 95
  ((DKeyIntBin op scalar lhs_const rhs_const commutative rhs_pow2) fi cmd const_map)
  (when "rhs_const and rhs_const.kind == 'DConstInt' and op == 'BackIntMul' and rhs_pow2 and tonumber(rhs_const.raw) and tonumber(rhs_const.raw) > 0")
  (lua "local n = tonumber(rhs_const.raw); local sh = math.floor(math.log(n) / math.log(2)); return ctx.decision(fi.cmd_index, 'intbin.mul_pow2', 1, ctx.D.DAsmBinary('BackShiftLeft.imm', ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.D.DOpImmI64(tostring(sh)), scalar))"))

(rule lower_rule 80
  ((DKeyIntBin op scalar lhs_const rhs_const commutative rhs_pow2) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'intbin.reg', 3, ctx.D.DAsmBinary(op, ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.op_vreg(cmd.rhs), scalar))"))

(rule lower_rule 90
  ((DKeyBitBin op scalar rhs_const) fi cmd const_map)
  (when "rhs_const and rhs_const.kind == 'DConstInt'")
  (lua "return ctx.decision(fi.cmd_index, 'bitbin.imm', 1, ctx.D.DAsmBinary(op .. '.imm', ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.D.DOpImmI64(rhs_const.raw), scalar))"))

(rule lower_rule 80
  ((DKeyBitBin op scalar rhs_const) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'bitbin.reg', 2, ctx.D.DAsmBinary(op, ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.op_vreg(cmd.rhs), scalar))"))

(rule lower_rule 90
  ((DKeyShiftRotate op scalar rhs_const rhs_small_imm) fi cmd const_map)
  (when "rhs_small_imm and rhs_const and rhs_const.kind == 'DConstInt'")
  (lua "return ctx.decision(fi.cmd_index, 'shiftrotate.imm', 1, ctx.D.DAsmBinary(op .. '.imm', ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.D.DOpImmI64(rhs_const.raw), scalar))"))

(rule lower_rule 80
  ((DKeyShiftRotate op scalar rhs_const rhs_small_imm) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'shiftrotate.reg', 3, ctx.D.DAsmBinary(op, ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.op_vreg(cmd.rhs), scalar))"))

(rule lower_rule 95
  ((DKeyCompareBranch op scalar rhs_const fused_branch rhs_is_zero) fi cmd const_map)
  (when "fused_branch")
  (lua "return ctx.decision(fi.cmd_index, 'cmp.fused-branch', 0, ctx.D.DAsmComment('compare fused with following branch'))"))

(rule lower_rule 80
  ((DKeyCompareBranch op scalar rhs_const fused_branch rhs_is_zero) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'cmp.setcc', 1, ctx.D.DAsmCompareSet(ctx.D.DccNE, ctx.op_vreg(cmd.dst), ctx.op_vreg(cmd.lhs), ctx.op_vreg(cmd.rhs), scalar))"))

(rule lower_rule 90
  ((DKeyLoadStore is_load shape base_kind has_index const_disp align_bytes trap_kind) fi cmd const_map)
  (when "cmd.kind == 'CmdLoadInfo'")
  (lua "return ctx.decision(fi.cmd_index, 'mem.load', 1, ctx.D.DAsmLoad(ctx.op_vreg(cmd.dst), ctx.addr_operand(cmd.addr, const_map), cmd.ty))"))

(rule lower_rule 80
  ((DKeyLoadStore is_load shape base_kind has_index const_disp align_bytes trap_kind) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'mem.store', 1, ctx.D.DAsmStore(ctx.addr_operand(cmd.addr, const_map), ctx.op_vreg(cmd.value), cmd.ty))"))

(rule lower_rule 95
  ((DKeyAddress base_kind elem_size const_offset) fi cmd const_map)
  (when "cmd.kind == 'CmdPtrOffset'")
  (lua "return ctx.decision(fi.cmd_index, 'addr.lea', 1, ctx.D.DAsmLea(ctx.op_vreg(cmd.dst), ctx.D.DOpMem(ctx.D.DAddress(ctx.D.DPhysRegId(-1), nil, cmd.elem_size or 1, cmd.const_offset or 0))))"))

(rule lower_rule 90
  ((DKeyAddress base_kind elem_size const_offset) fi cmd const_map)
  (when "cmd.kind == 'CmdStackAddr'")
  (lua "return ctx.decision(fi.cmd_index, 'addr.stack', 1, ctx.D.DAsmLea(ctx.op_vreg(cmd.dst), ctx.D.DOpMem(ctx.D.DAddress(ctx.D.DPhysRegId(5), nil, 1, 0))))"))

(rule lower_rule 85
  ((DKeyAddress base_kind elem_size const_offset) fi cmd const_map)
  (when "cmd.kind == 'CmdDataAddr'")
  (lua "return ctx.decision(fi.cmd_index, 'addr.label', 1, ctx.D.DAsmLea(ctx.op_vreg(cmd.dst), ctx.D.DOpLabel(ctx.D.DLabelId('D_' .. ctx.to_label(ctx.idkey(cmd.data))))))"))

(rule lower_rule 84
  ((DKeyAddress base_kind elem_size const_offset) fi cmd const_map)
  (when "cmd.kind == 'CmdFuncAddr'")
  (lua "return ctx.decision(fi.cmd_index, 'addr.label', 1, ctx.D.DAsmLea(ctx.op_vreg(cmd.dst), ctx.D.DOpLabel(ctx.D.DLabelId('F_' .. ctx.to_label(ctx.idkey(cmd.func))))))"))

(rule lower_rule 83
  ((DKeyAddress base_kind elem_size const_offset) fi cmd const_map)
  (when "cmd.kind == 'CmdExternAddr'")
  (lua "return ctx.decision(fi.cmd_index, 'addr.label', 1, ctx.D.DAsmLea(ctx.op_vreg(cmd.dst), ctx.D.DOpLabel(ctx.D.DLabelId('E_' .. ctx.to_label(ctx.idkey(cmd.func))))))"))

(rule lower_rule 90
  ((DKeyCall target_kind argc has_result result_class) fi cmd const_map)
  (when "cmd.target and cmd.target.kind == 'BackCallIndirect'")
  (lua "local args = {}; for i=1,#(cmd.args or {}) do args[#args+1] = ctx.op_vreg(cmd.args[i]) end; local res=nil; if cmd.result and cmd.result.kind=='BackCallValue' then res=ctx.op_vreg(cmd.result.dst) end; return ctx.decision(fi.cmd_index, 'call.generic', 1, ctx.D.DAsmCall(ctx.op_vreg(cmd.target.callee), args, res))"))

(rule lower_rule 89
  ((DKeyCall target_kind argc has_result result_class) fi cmd const_map)
  (when "cmd.target and cmd.target.kind == 'BackCallDirect'")
  (lua "local args = {}; for i=1,#(cmd.args or {}) do args[#args+1] = ctx.op_vreg(cmd.args[i]) end; local res=nil; if cmd.result and cmd.result.kind=='BackCallValue' then res=ctx.op_vreg(cmd.result.dst) end; local op = ctx.D.DOpLabel(ctx.D.DLabelId('F_' .. ctx.to_label(ctx.idkey(cmd.target.func)))); return ctx.decision(fi.cmd_index, 'call.generic', 1, ctx.D.DAsmCall(op, args, res))"))

(rule lower_rule 88
  ((DKeyCall target_kind argc has_result result_class) fi cmd const_map)
  (lua "local args = {}; for i=1,#(cmd.args or {}) do args[#args+1] = ctx.op_vreg(cmd.args[i]) end; local res=nil; if cmd.result and cmd.result.kind=='BackCallValue' then res=ctx.op_vreg(cmd.result.dst) end; local op = ctx.D.DOpLabel(ctx.D.DLabelId('E_' .. ctx.to_label(ctx.idkey(cmd.target.func)))); return ctx.decision(fi.cmd_index, 'call.generic', 1, ctx.D.DAsmCall(op, args, res))"))

(rule lower_rule 95
  ((DKeyControl kind) fi cmd const_map)
  (when "cmd.kind == 'CmdJump'")
  (lua "return ctx.decision(fi.cmd_index, 'ctl.jump', 1, ctx.D.DAsmJump(ctx.label_of(cmd.dest)))"))

(rule lower_rule 94
  ((DKeyControl kind) fi cmd const_map)
  (when "cmd.kind == 'CmdBrIf'")
  (lua "return ctx.decision(fi.cmd_index, 'ctl.brif', 1, ctx.D.DAsmBrIf(ctx.op_vreg(cmd.cond), ctx.label_of(cmd.then_block), ctx.label_of(cmd.else_block)))"))

(rule lower_rule 93
  ((DKeyControl kind) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'ctl.switch', 2, ctx.D.DAsmComment('switch lowered by fallback chain'))"))

(rule lower_rule 95
  ((DKeyReturn has_value class) fi cmd const_map)
  (when "cmd.kind == 'CmdReturnValue'")
  (lua "return ctx.decision(fi.cmd_index, 'ret.value', 1, ctx.D.DAsmRetValue(ctx.op_vreg(cmd.value)))"))

(rule lower_rule 94
  ((DKeyReturn has_value class) fi cmd const_map)
  (lua "return ctx.decision(fi.cmd_index, 'ret.void', 1, ctx.D.DAsmRetVoid)"))

(default lower_rule
  (lua "return ctx.decision(fi.cmd_index, 'other.comment', 99, ctx.D.DAsmComment('no specialized lowering for ' .. tostring(cmd.kind)))"))
]]
