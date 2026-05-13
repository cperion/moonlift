return {
    lexer = require("moonlift.lisle.lexer"),
    parser = require("moonlift.lisle.parser"),
    sema = require("moonlift.lisle.sema"),
    decision = require("moonlift.lisle.decision"),
    codegen_lua = require("moonlift.lisle.codegen_lua"),
    compile = require("moonlift.lisle.compile"),
    runtime = require("moonlift.lisle.runtime"),
}
