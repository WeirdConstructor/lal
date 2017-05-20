-- See Copyright Notice in lal.lua

local utl      = require 'lal/lang/util'
local List     = require 'lal/util/list'
local class    = require 'lal/util/class'
-----------------------------------------------------------------------------
-- LUA <5.3 compat:

if (not math.tointeger) then
    math.tointeger = math.floor
end
-----------------------------------------------------------------------------


local Parser = class()

function Parser:init()
    self.pos             = 1
    self._1              = ""
    self.buffer          = ""
    self.cur_line        = 1
    self.input_name      = '<eval>'
    self.input_path      = '.'
    self.table_parse_pos = {}
    self.debug_pos_info  = List()
end
-----------------------------------------------------------------------------

function Parser.lal_read_string(str)
    local val = nil
    pcall(function () val = Parser():parse_expression(str) end)
    return val
end
-----------------------------------------------------------------------------

function Parser.lal_quote_string(str)
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
        return string.format("\\x%X;", string.byte(c))
    end)
    return string.format('"%s"', str)
end
-----------------------------------------------------------------------------

function Parser.create_ref_map(v, ref_map)
    if (not ref_map) then
        ref_map = { __lal_count = 0 }
    end

    if (type(v) == 'table') then
        if (type(ref_map[v]) == "boolean") then
            ref_map[v] = ref_map.__lal_count
            ref_map.__lal_count = ref_map.__lal_count + 1
            return ref_map

        elseif (type(ref_map[v]) == "number") then
            return ref_map

        else
            ref_map[v] = true
        end

        if (v[1] ~= nil) then
            for _, e in ipairs(v) do
                Parser.create_ref_map(e, ref_map)
            end

        elseif (next(v)) then
            for k, e in pairs(v) do
                Parser.create_ref_map(k, ref_map)
                Parser.create_ref_map(e, ref_map)
            end
        end
    end

    return ref_map
end
-----------------------------------------------------------------------------

function Parser.lal_print_map(v, ref_map, verbatim)
    local map = List()
    for k, v in pairs(v) do
        map:push(Parser.lal_print_string(k, ref_map, verbatim))
        map:push(Parser.lal_print_string(v, ref_map, verbatim))
    end

    return ('{' .. (map:concat ' ') .. '}')
end
-----------------------------------------------------------------------------

function Parser.lal_print_list(v, ref_map, verbatim)
    local list = List()
    for _, v in ipairs(v) do
        list:push(Parser.lal_print_string(v, ref_map, verbatim))
    end

    return ('(' .. (list:concat ' ') .. ')')
end
-----------------------------------------------------------------------------

function Parser.lal_print_string(val, ref_map, verbatim)
    if (not ref_map) then
        ref_map = Parser.create_ref_map(val)
    end

    if (type(val) == 'string') then
        if (utl.is_sym(val)) then
            return utl.strip_sym(val)
        elseif (utl.is_kw(val)) then
            if (verbatim) then
                return utl.strip_kw(val)
            else
                return utl.strip_kw(val) .. ':'
            end
        elseif (verbatim) then
            return val
        else
            return Parser.lal_quote_string(val)
        end

    elseif (type(val) == 'number') then
        return tostring(val)

    elseif (utl.is_nil(val)) then
        return 'nil'

    elseif (utl.is_table(val)) then
        local ref      = ref_map[val]
        local ref_pref = ""
        if (ref) then
            if (type(ref) == 'number') then
                ref = string.format("#%d", ref)
                ref_map[val] = ref
                ref_pref = ref .. "="

            elseif (type(ref) == "string") then
                return ref .. "#"
            end
        end

        if (val[1] ~= nil) then
            return ref_pref .. Parser.lal_print_list(val, ref_map, verbatim)

        elseif (not next(val)) then
            return ref_pref .. '()'

        else
            return ref_pref .. Parser.lal_print_map(val, ref_map, verbatim)
        end
    elseif (type(val) == 'boolean') then
        if (val) then return '#true'
        else          return '#false'
        end

    else
        return tostring(val)
    end
end
-----------------------------------------------------------------------------

function Parser:push_nested_debug_info(description)
    self.debug_pos_info:push({ desc = description, line = self.cur_line })
end
-----------------------------------------------------------------------------

function Parser:pop_nested_debug_info()
    self.debug_pos_info:pop()
end
-----------------------------------------------------------------------------

function Parser:err(fmt, ...)
    local msg         = string.format(fmt, ...)
    local source_code = string.sub(string.sub(self.buffer, self.pos), 1, 50)
    source_code       = string.gsub(source_code, "\r?\n", "")

    local opt_info = ""
    if (#self.debug_pos_info > 0) then
        opt_info =
            string.format(", while parsing %s starting at line %d\n",
                self.debug_pos_info[#self.debug_pos_info].desc,
                self.debug_pos_info[#self.debug_pos_info].line)
    end

    error(string.format(
        "[%s:%d] Parser Error: %s, at: %s%s",
        self.input_name,
        self.cur_line,
        msg,
        source_code .. "...",
        opt_info), 0)
end
-----------------------------------------------------------------------------

function Parser:expect_direct(pat, bLookahead, bDebug)
    local cap, real = self.buffer:match(pat, self.pos)
    if (cap) then
        if (bDebug) then
            log.dbg("matched '%1' on '%2' (%3)\n", pat, string.sub(self.buffer, self.pos), cap)
        end
        if (not bLookahead) then
            self.cur_line = self.cur_line + utl.count_occurences(cap, "\n")
            self.pos      = self.pos + cap:len()
        end
        self._1 = cap
        return true
    else
        if (bDebug) then
            log.dbg("NOT matched '%1' on '%2'\n", pat, string.sub(self.buffer, self.pos))
        end
        self._1 = ""
        return false
    end
end
function Parser:expect(pat, bLookahead, bDebug)
    local skip = self.buffer:match("^([\r\n%s]+)", self.pos)
    if (skip) then
        self.cur_line = self.cur_line + utl.count_occurences(skip, "\n")
        self.pos      = self.pos + skip:len()
        if (bDebug) then
            log.dbg("skipped ws %1\n", skip:len())
        end
    end

    return self:expect_direct(pat, bLookahead, bDebug)
end
function Parser:expectSkipComments(pat, bLookahead, bDebug)
    self:skip_comments();
    return self:expect(pat, bLookahead, bDebug)
end
-----------------------------------------------------------------------------

function Parser:capture_position(table)
    self.table_parse_pos[tostring(table)] = {
        line = self.cur_line,
        name = self.input_name,
        path = self.input_path
    }
end
-----------------------------------------------------------------------------

function Parser:parse_list()
    local list = {}
    self:reg_struct(list)

    self:expect("^(%()")
    self:capture_position(list)
    self:push_nested_debug_info("list")

    while (not self:expectSkipComments("^%)", true)) do
        table.insert(list, self:parse_value())
        self:expect("^([%s]*)")
    end

    self:expect("^(%))")

    self:pop_nested_debug_info()

    return list
end
-----------------------------------------------------------------------------

function Parser:parse_quoted_list()
    local quoted_list = { '\xfelist' }
    self:reg_struct(quoted_list)

    self:expect("^(%[)")
    self:capture_position(quoted_list)
    self:push_nested_debug_info("quoted list")

    while (not self:expectSkipComments("^%]", true)) do
        table.insert(quoted_list, self:parse_value())
        self:expect("^([%s]*)")
    end

    self:expect("^(%])")

    self:pop_nested_debug_info()

    return quoted_list
end
-----------------------------------------------------------------------------

function Parser:parse_map()
    local map = {}
    self:reg_struct(map)

    self:expect("^({)")
    self:capture_position(map)
    self:push_nested_debug_info("map")

    while (not self:expectSkipComments("^}", true)) do
        local key = self:parse_value()
        map[key] = self:parse_value()
        self:expect("^([%s]*)")
    end

    self:expect("^(})")

    self:pop_nested_debug_info()

    return map
end
-----------------------------------------------------------------------------

function Parser:parse_string_escape(escaped_char)
    local char

    if (escaped_char == '\\x') then
        if (self:expect_direct("^([a-zA-Z0-9]+;)")) then
            escaped_char = self._1
            local char_number =
                tonumber(
                    string.upper(
                        string.sub(
                            escaped_char,
                            1, string.len(escaped_char) - 1)),
                    16)
            if (char_number > 0xFF) then
                self:err("bad hex escape, can't represent values "
                      .. "bigger than 0xFF in Lua strings.")
            end
            char = string.char(char_number)

        else
            self:err("bad hex escape in string")
        end

    elseif (escaped_char == '\\a')  then char = "\a"
    elseif (escaped_char == '\\b')  then char = "\b"
    elseif (escaped_char == '\\t')  then char = "\t"
    elseif (escaped_char == '\\n')  then char = "\n"
    elseif (escaped_char == '\\r')  then char = "\r"
    elseif (escaped_char == '\\"')  then char = '"'
    elseif (escaped_char == '\\\\') then char = '\\'
    elseif (escaped_char == '\\|')  then char = '|'
    else                            char = string.sub(escaped_char, 2)
    end

    return char
end
-----------------------------------------------------------------------------

function Parser:parse_string()
    self:expect("^(\")")
    local str_buffer = {}
    while (not self:expect_direct("^\"", true)) do

        if (self:expect_direct("^(\\[^%s\r\n])")) then
            table.insert(str_buffer, self:parse_string_escape(self._1))

        elseif (self:expect_direct("^(\\%s*\r?\n%s*)")
                or self:expect_direct("^(\\%s*\r%s*)"))
        then
            -- nothing
        elseif (self:expect_direct("^(\\%s*\r?\n)")) then
            -- nothing

        elseif (self:expect_direct("^([^\"\\][^\"\\]*)")) then
            table.insert(str_buffer, self._1)

        else
            self:err("bad string parsing state")
        end
    end
    self:expect_direct("^(\")")

    return table.concat(str_buffer)
end
-----------------------------------------------------------------------------

function Parser:parse_quoted_string()
    self:expect("^(#q)")

    local start_line = self.cur_line

    self:expect_direct("^(['])")
    local quote = self._1

    local str_list = {}
    local at_end = false
    while (not at_end) do
        if (self:expect_direct("^('')")) then
            table.insert(str_list, "'")

        elseif (self:expect_direct("^(')")) then
            at_end = true

        elseif (self:expect_direct("^([^']+)")) then
            table.insert(str_list, self._1)

        else
            self:err(
                "EOF while parsing quoted string"
                .. ", started at line "
                .. tostring(start_line))
        end
    end

    return table.concat(str_list, "")
end
-----------------------------------------------------------------------------

function Parser:parse_multiline_string_interpolated(start_line, end_regex)
    local str_expr = { "\xFEstr" }
    self:reg_struct(str_expr)

    while (not self:expect_direct(end_regex)) do
        local val

        if (self:expect_direct("^(#{[^}]*})")) then
            val = "\xFE" .. string.match(self._1, "#{([^}]*)}")

        elseif (self:expect_direct("^(##)")) then
            val = "#"

        elseif (self:expect_direct("^(#)")) then
            val = self:parse_value()

        elseif (self:expect_direct("^([^#\r\n]+)")) then
            val = self._1

        elseif (self:expect_direct("^(\r?\n)")) then
            val = "\n"

        elseif (self:expect_direct("^$")) then
            self:err(
                "EOF while parsing interp. multi line string"
                .. ", started at line "
                .. tostring(start_line))

        else
            self:err(
                "bad state while parsing interp. multi line string"
                .. ", started at line "
                .. tostring(start_line))
        end

        if (val) then
            table.insert(str_expr, val)
        end
    end

    return str_expr
end
-----------------------------------------------------------------------------

function Parser:parse_multiline_string()
    self:expect("^(#<)")

    local start_line = self.cur_line

    self:expect_direct("^([#<])")
    local is_interpolating = self._1 == "#"
    self:expect_direct("^([A-Za-z][A-Za-z0-9]*)")
    local end_word = self._1
    self:expect_direct("^(\r?\n)")

    local end_regex = "^(\r?\n" .. end_word .. ")"

    if (is_interpolating) then
        return self:parse_multiline_string_interpolated(start_line, end_regex)
    end

    local str_list = {}
    self:reg_struct(str_list)

    while (not self:expect_direct(end_regex)) do

        if (self:expect_direct("^([^\r\n]+)")) then
            table.insert(str_list, self._1)

        elseif (self:expect_direct("^\r?\n")) then
            -- skip

        elseif (self:expect_direct("^$")) then
            self:err(
                "EOF while parsing multi line string"
                .. ", started at line "
                .. tostring(start_line))

        else
            self:err(
                "bad state while parsing multi line string"
                .. ", started at line "
                .. tostring(start_line))
        end

    end

    return table.concat(str_list, "\n")
end
-----------------------------------------------------------------------------

function Parser:parse_nested_comment()
    self:expect("^(#|)")

    while (not self:expect("^|#", true)) do
        if (self:expect("^#|", true)) then
            self:parse_nested_comment()

        elseif (self:expect("^(|[^#])", false)) then
            -- next

        elseif (self:expect("^(#[^|])", false)) then
            -- next

        elseif (self:expect("^([^|#]+)", false)) then
            -- next
        end
    end

    self:expect("^(|#)")
end
-----------------------------------------------------------------------------

function Parser:skip_comments()
    local found_comment = true
    while found_comment do
        if (self:expect("^#|", true)) then
            self:parse_nested_comment()

        elseif (self:expect("^(;[^\n]*\r?\n)")) then
            -- skip one line comment

        elseif (self:expect("^(#;%s*)")) then
            self:parse_value() -- ignored datum

        else
            found_comment = false
        end
    end
end
-----------------------------------------------------------------------------

function Parser:parse_value()
    if (not self.ref_map) then
        self.ref_map = {}
    end

    self:skip_comments()

    if (self:expect("^%(", true)) then
        return self:parse_list()

    elseif (self:expect("^%[", true)) then
        return self:parse_quoted_list()

    elseif (self:expect("^\"", true)) then
        return self:parse_string()

    elseif (self:expect("^(#%d+#)")) then
        return self:get_struct(self._1)

    elseif (self:expect("^(#%d+=)")) then
        self.pending_label = self._1
        return self:parse_value()

    elseif (self:expect("^#<", true)) then
        return self:parse_multiline_string()

    elseif (self:expect("^#q", true)) then
        return self:parse_quoted_string()

    elseif (self:expect("^{", true)) then
        return self:parse_map()

    elseif (self:expect("^([$@]^?!?)")) then
        return '\xfe' .. self._1

    elseif (self:expect("^(')")) then
        return { '\xfequote', self:parse_value() }

    elseif (self:expect("^(`)")) then
        return { '\xfequasiquote', self:parse_value() }

    elseif (self:expect("^(,@)")) then
        return { '\xfeunquote-splicing', self:parse_value() }

    elseif (self:expect("^(,)")) then
        return { '\xfeunquote', self:parse_value() }

    elseif (self:expect("^([-+]?%d%d*%.%d*)")) then
        return tonumber(self._1)

    elseif (self:expect("^([-+]?%d%d*)")) then
        return math.tointeger(self._1)

    elseif (self:expect("^%.%.!")) then
        return '\xfe..!'

    elseif (self:expect("^%.!")) then
        return '\xfe.!'

    elseif (self:expect("^%.%.")) then
        return '\xfe..'

    elseif (self:expect("^%.")) then
        return '\xfe.'

    elseif (self:expect("^(;[^\r\n]*)\r?\n")) then
        return '\xfe.'

    elseif (self:expect("^([^%s%)%]%}%(%[%{\",][^%s%)%]%}%(%[%{\",]*)")) then
        if (self._1 == '#true' or self._1 == '#t') then
            return true

        elseif (self._1 == '#false' or self._1 == '#f') then
            return false

        elseif (self._1 == 'nil') then
            return utl.LNIL

        elseif (string.match(self._1, ".*:$")) then
            return '\xfd' .. string.sub(self._1, 1, #self._1 - 1)

        else
            return '\xfe' .. self._1
        end

    else
        self:err(string.format("unable to parse"))

    end
end
-----------------------------------------------------------------------------

function Parser:setup(s, input_name, input_path)
    if (input_name and not input_path) then
        local path_parts = {}
        for v in string.gmatch(input_name, '([^/\\]+)') do
            table.insert(path_parts, v)
        end
        path_parts[#path_parts] = nil

        input_path = table.concat(path_parts, '/')
    end

    self.buffer = s
    self.pos    = 1
    if (input_name) then self.input_name = input_name end
    if (input_path) then self.input_path = input_path end
end
-----------------------------------------------------------------------------

function Parser:reg_struct(v)
    if (self.pending_label) then
        local lbl = string.sub(self.pending_label, 1, string.len(self.pending_label) - 1)
        self.ref_map[lbl] = v
        self.pending_label = nil
    end
end
-----------------------------------------------------------------------------

function Parser:get_struct(lbl)
    lbl = string.sub(lbl, 1, string.len(lbl) - 1)
    local v = self.ref_map[lbl]
    if (not v) then
        self:err("Couldn't parse, unknown datum label encountered: " .. v)
    end
    return v
end
-----------------------------------------------------------------------------

function Parser:parse_program(s, input_name, input_path)
    self:setup(s, input_name, input_path)

    self.ref_map = {}
    local program = { "\xfebegin" }
    self:capture_position(program)
    while (self:expect("^.+", true)) do
        table.insert(program, self:parse_value())
        self:skip_comments()
    end

    return program, self.table_parse_pos
end
-----------------------------------------------------------------------------

function Parser:parse_expression(s, input_name, input_path)
    self:setup(s, input_name, input_path)

    self.ref_map = {}
    local val = self:parse_value()
    self:skip_comments()

    if (self:expect("^([^%s]+)")) then
        self:err(string.format("EOF expected\n",
                            input_name,
                            string.sub(self.buffer, self.pos)))
    end

    return val, self.table_parse_pos
end
-----------------------------------------------------------------------------

return Parser

--$ local p = Parser()
--$ print(log.dump(p:parse([[
--$ 
--$ (fooo
--$ 
--$       (+ 3  43 ) 32 432 4324 23)
--$ 
--$ 
--$ ]])))
--$ 
