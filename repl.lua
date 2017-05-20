-- See Copyright Notice in lal.lua

local lal       = require 'lal/lal'
local util      = require 'lal/lang/util'
local Compiler  = require 'lal/lang/compiler'
local Parser    = require 'lal/lang/parser'

local do_print_lua_code = false

local function read_line()
    io.stdout:write("> ")
    io.stdout:flush()
    local line = io.stdin:read("*l")
    local value, compiler_env = nil, nil

    local compiler = Compiler()
    local parser   = Parser()
    local env      = _ENV
    local init_lua_code = compiler.lal_lua_env_reset .. "\nreturn _ENV"
    if (do_print_lua_code) then
        print("CODE[" .. tostring(init_lua_code) .. "]")
    end
    env = util.exec_lua(init_lua_code, "repl", env)
    env._LALRT_GLOB_ENV = env

    while (line) do
        local ok, err = pcall(function ()
            local val, table_parse_pos = parser:parse_program(line, "stdin")
            local lua_code = compiler:compile_toplevel(val, table_parse_pos, true, true)
            if (do_print_lua_code) then
                print("CODE[" .. tostring(lua_code) .. "]");
            end
            value = util.exec_lua(lua_code, "repl", env)
            compiler:setGlobalEnv("\xfe_", value)
        end)
        if (ok) then
            io.stdout:write("=> " .. Parser.lal_print_string(value) .. "\n")
        else
            io.stdout:write("ERROR: " .. err .. "\n")
        end
        io.stdout:write("> ")
        io.stdout:flush()
        line = io.stdin:read("*l")
    end
end

for arg in ipairs(table.pack(...)) do
    if (arg == "-d") then
        do_print_lua_code = true;
    end
end

read_line()
