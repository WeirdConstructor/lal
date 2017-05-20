-- See Copyright Notice in lal.lua

local util = {}

-----------------------------------------------------------------------------

function util.count_occurences(str, substitution)
    local cnt = 0
    for _ in string.gmatch(str, substitution) do
        cnt = cnt + 1
    end
    return cnt
end
-----------------------------------------------------------------------------

function util.is_table(v)
    return util.is_not_nil(v) and type(v) == 'table'
end
-----------------------------------------------------------------------------

function util.is_nil(v)
    return v == nil or v == util.LNIL
end
-----------------------------------------------------------------------------

function util.is_not_nil(v)
    return not(v == nil or v == util.LNIL)
end
-----------------------------------------------------------------------------

function util.is_sym(str)
    return type(str) == 'string' and string.sub(str, 1, 1) == '\xFE'
end
-----------------------------------------------------------------------------

function util.is_kw(str)
    return type(str) == 'string' and string.sub(str, 1, 1) == '\xFD'
end
-----------------------------------------------------------------------------

function util.strip_sym(str)
    if (util.is_sym(str)) then return string.sub(str, 2) end
    return str
end
-----------------------------------------------------------------------------

function util.strip_kw(str)
    if (util.is_kw(str))  then return string.sub(str, 2) end
    if (util.is_sym(str)) then return string.sub(str, 2) end
    return str
end
-----------------------------------------------------------------------------

function util.uservar(var_name)
    var_name = util.strip_sym(var_name)

    var_name = string.gsub(var_name, '%_', '_U')
    var_name = string.gsub(var_name, '%-([AEGHUPQMSLCIXTDBZR_])', '__%1')
    var_name = string.gsub(var_name, '%-', '_')
    var_name = string.gsub(var_name, '%+', '_P')
    var_name = string.gsub(var_name, '%?', '_Q')
    var_name = string.gsub(var_name, '%!', '_M')
    var_name = string.gsub(var_name, '%*', '_S')
    var_name = string.gsub(var_name, '%$', '_L')
    var_name = string.gsub(var_name, '%:', '_C')
    var_name = string.gsub(var_name, '%&', '_A')
    var_name = string.gsub(var_name, '%~', '_I')
    var_name = string.gsub(var_name, '%^', '_X')
    var_name = string.gsub(var_name, '@',  '_T')
    var_name = string.gsub(var_name, '/',  '_D')
    var_name = string.gsub(var_name, '\\', '_B')
    var_name = string.gsub(var_name, '%%', '_Z')
    var_name = string.gsub(var_name, '%>', '_G')
    var_name = string.gsub(var_name, '%<', '_H')
    var_name = string.gsub(var_name, '%=', '_E')

    if (   var_name == "if"
        or var_name == "while"
        or var_name == "do"
        or var_name == "begin"
        or var_name == "end"
        or var_name == "function")
    then
        var_name = var_name .. "_R"
    end

    return var_name
end
-----------------------------------------------------------------------------

local g_temporary_var_counter = 0
function util.tmpvar(prefix)
    if (not prefix) then prefix = "tmp" end
    prefix = util.strip_sym(prefix)
    g_temporary_var_counter = g_temporary_var_counter + 1
    return string.format('_lal_%s%d', prefix, g_temporary_var_counter)
end
-----------------------------------------------------------------------------

function util.quote_lua_string(str)
    str = string.gsub(str, '["\\\r\n\a\t\b]', function (c)
        if     (c == '"')  then return '\\"'
        elseif (c == '\\') then return '\\\\'
        elseif (c == '\r') then return '\\r'
        elseif (c == '\n') then return '\\n'
        elseif (c == '\a') then return '\\a'
        elseif (c == '\b') then return '\\b'
        elseif (c == '\t') then return '\\t'
        end
    end)
    str = string.gsub(str, '[^%g%s]', function (c)
        return string.format("\\x%X", string.byte(c))
    end)
    return string.format('"%s"', str)
end
-----------------------------------------------------------------------------

util.lal_runtime_error_context_lines = 10

local function lua_code_context_at_line(lua_code, line, context_line_cnt)
    if (not line) then
        line = 0
    end
    local start_line = line - context_line_cnt
    local end_line   = line + context_line_cnt

    local format_buffer = {}
    local i = 1
    table.insert(format_buffer, "=== START LUA ===\n")
    string.gsub(lua_code, "[^\r\n]+", function (code_line)
        local marker = " "
        if (i == line) then marker = "*" end
        if (context_line_cnt == -1
            or (i >= start_line and i <= end_line))
        then
            table.insert(
                format_buffer,
                string.format("%4d:%s %s\n", i, marker, code_line))
        end
        i = i + 1
    end)
    table.insert(format_buffer, "=== END LUA ===\n")
    return table.concat(format_buffer, "")
end
-----------------------------------------------------------------------------

function find_lal_error_line(lal_lua_source, at_line, add_info)
--    print("FIND:" .. at_line .. "/" .. add_info)
    local last_info = {"unknown", 0}
    local end_info
    local i = 1
    string.gsub(lal_lua_source, "([^\r\n]*)\r?\n", function (line)
        local file, line_nr = string.match(line, ".*%-%-%[%[([^:]+):([^%]]+)%]%].*")
--        print("M:" .. tostring(file) .. "/" .. tostring(line_nr))
        if (line_nr) then last_info = { file, line_nr, add_info } end
        if (i >= at_line and not end_info) then end_info = last_info end
--        print("SRC[" .. tostring(i) .. "/" .. tostring(at_line) .. "]{"..tostring(last_info[2]).."}: " .. line)
        i = i + 1
    end)
    return end_info
end
-----------------------------------------------------------------------------

function analyze_lal_backtrace(stack_offs)
    if (not stack_offs) then stack_offs = 0 end
    local bt = {}
    local so = 2 + stack_offs
    while true do
        local frame = debug.getinfo(so, "nSl")
        if (not frame)        then return bt end
        if (not frame.source) then return bt end
        if (string.match(frame.source, "^.LAL.")) then
            table.insert(bt,
                find_lal_error_line(frame.source, frame.currentline + 1, tostring(frame.name)))
        else
            table.insert(bt,
                string.format(
                    "%s:%s [%s]",
                    frame.source,
                    frame.currentline,
                    tostring(frame.name))
            )
        end
        so = so + 1
    end
    return bt
end
-----------------------------------------------------------------------------

function util.lal_backtrace(stack_offs)
    local backtrace = analyze_lal_backtrace(stack_offs)
    if (backtrace[1]) then
        local bt_l = {}
        local line_nr = backtrace[1][2], backtrace[1][1]
        for i, v in ipairs(backtrace) do
            if (type(v) == "table") then
                table.insert(bt_l,
                    string.format("       *LAL: %s:%s [%s]", v[1], tostring(v[2]), v[3]))
            else
                table.insert(bt_l,
                    string.format("        Lua: %s", v))
            end
        end
        local bt = table.concat(bt_l, "\n");
        return "\nLAL stack traceback:\n" .. bt
            .. "\nLua " ..  debug.traceback(nil, 3)
    else
        return "\nLua " .. debug.traceback(nil, 3);
    end
end
-----------------------------------------------------------------------------

function util.exec_lua_code_func(lua_func, args)
    local Parser = require 'lal.lang.parser'

    local err_func = function (error_value, f)
        return "LAL-Lua Runtime Error: "
            .. tostring(Parser.lal_print_string(error_value))
            .. util.lal_backtrace(2);
    end

    local ok, v
    if (args) then
        ok, v = xpcall(function () return lua_func(table.unpack(args)) end, err_func)
    else
        ok, v = xpcall(lua_func, err_func)
    end

    if (ok) then return v else error(v, 0) end
end
-----------------------------------------------------------------------------

local function lal_eval_lua_code(lua_code, code_name, lua_env)
    if (not code_name) then code_name = "?" end
    if (not lua_env) then lua_env = _ENV end
    local code_function, error_str = load(lua_code, "*LAL*:" .. code_name .. ":\n" .. lua_code, "t", lua_env)
    if (not code_function) then
        error(lua_code_context_at_line(lua_code, 0, 10000)
              .. "LAL-Compile Lua Error: " .. error_str, 0)
    end
    return code_function
end
-----------------------------------------------------------------------------

function util.exec_lua(lua_code, code_name, lua_env)
    local code_fun = lal_eval_lua_code(lua_code, code_name, lua_env)
    return util.exec_lua_code_func(code_fun)
end
-----------------------------------------------------------------------------

util.LNIL = {'LAL-NIL-SENTINEL'}

-----------------------------------------------------------------------------

return util
