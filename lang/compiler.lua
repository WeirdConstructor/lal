-- See Copyright Notice in lal.lua

local Node     = require 'lal/lang/codegen'
local utl      = require 'lal/lang/util'
local Parser   = require 'lal/lang/parser'
local List     = require 'lal/util/list'
local class    = require 'lal/util/class'

local support_bltins = require 'lal/lang/builtins'
local support_syn    = require 'lal/lang/syntax_forms'
local support_opt    = require 'lal/lang/opt_builtins'
-----------------------------------------------------------------------------

local Compiler = class()

-----------------------------------------------------------------------------

local mSyntaxes = { }

function Compiler:init(mRootEnv)
    self.LEnvStack         = List()
    self.mEnv              = { }
    self.mGlobalEnv        = self.mEnv
    self.LJEStack          = List()
    self.LDeclBltinStack   = List()
    self.mJumpLabels       = { }
    self.iCurLine          = 0
    self.sInputName        = 'unknown'
    self.sInputPath        = '.'
    self.vErrForm          = nil
    self.LDebugPosStack    = List()

    for k, v in pairs(support_bltins) do
        self.mGlobalEnv[k] = self.to_builtin(v)
    end

    for k, v in pairs(support_syn) do
        self.mGlobalEnv[k] = self.to_syntax(v, support_bltins[k])
    end

    for k, v in pairs(support_opt.synforms) do
        self.mGlobalEnv[k] = self.to_syntax(v, support_opt.builtins[k])
    end

    local mEvalEnv = self.mGlobalEnv


    if (mRootEnv) then
        for k, v in pairs(mRootEnv) do
            self.mGlobalEnv[k] = v
        end
    end
end
-----------------------------------------------------------------------------

function Compiler.to_builtin(func)
    return {
        sType     = "builtin",
        file      = "lal.lang.builtins",
        func      = func,
    }
end
-----------------------------------------------------------------------------

function Compiler.to_syntax(compile_func, builtin_func)
    return {
        sType     = "syntax",
        func      = compile_func,
        prim_func = builtin_func,
    }
end
-----------------------------------------------------------------------------

local function merge_eval_env(to_env, from_env)
    for k, v in pairs(from_env) do
        if (utl.is_table(v) and v.prim_func) then
            to_env[utl.uservar(k)] = v.prim_func
        else
            to_env[utl.uservar(k)] = v
        end
    end
end
-----------------------------------------------------------------------------

function Compiler:global_eval_env()
    local mGlobEnv = self.mGlobalEnv
    local mEvalEnv = {}
    merge_eval_env(mEvalEnv, mGlobEnv)
    mEvalEnv['_lal_global_env'] = mGlobEnv
    return mEvalEnv, mGlobEnv
end
-----------------------------------------------------------------------------

function Compiler:local_env()
    local local_env = {}
    self.LEnvStack:foreach(function (env)
        for k, v in pairs(env) do local_env[k] = v end
    end)
    for k, v in pairs(self.mEnv) do local_env[k] = v end
    return local_env
end
-----------------------------------------------------------------------------

function Compiler:local_eval_env()
    local local_env = {}
    self.LEnvStack:foreach(function (env)
        merge_eval_env(local_env, env)
    end)
    merge_eval_env(local_env, self.mEnv)
    local_env['_lal_global_env'] = self:local_env()
    return local_env
end
-----------------------------------------------------------------------------

function Compiler:err(sFmt, ...)
    local sMsg =
        string.format(
            "[%s:%d] Compiler Error in Form: %s\n    Error: " .. sFmt,
            self.sInputName,
            self.iCurLine,
            string.format("\nForm: %s", Parser.lal_print_string(self.vErrForm)),
            ...)
    error(sMsg, 0)
end
-----------------------------------------------------------------------------

function Compiler:lookupInEnv(sSym, vForm)
    local sID  = utl.strip_sym(sSym)
    local mEnv = self.mEnv
    local i    = 0
    while (mEnv and mEnv[sID] == nil) do
        mEnv = self.LEnvStack[#self.LEnvStack - i]
        i = i + 1
    end

    -- TODO: Implement Scope-Blocks that track each variable access
    --       and save the position the variable was used at.
    --       Every popEnv() then needs to look at the accessed variables
    --       and issue an error if there is no corresponding (define ...)
    --       statement.
    if (not(mEnv) or mEnv[sID] == nil) then
        self:err("No such symbol in env: %s", sID)
    end

    return mEnv[sID]
end
-----------------------------------------------------------------------------

function Compiler:setGlobalEnv(sSym, vVal)
    self.mGlobalEnv[utl.strip_sym(sSym)] = vVal
end
-----------------------------------------------------------------------------

function Compiler:setEnv(sSym, vVal)
    self.mEnv[utl.strip_sym(sSym)] = vVal
end
-----------------------------------------------------------------------------

function Compiler:touchVar(sFName)
    if (self.mEnv[utl.strip_sym(sFName)] == nil) then
        return self:mkUservar(sFName)
    else
        return utl.uservar(sFName)
    end
end
-----------------------------------------------------------------------------
function Compiler:touchBuiltin(sym, bltin)
    if (not bltin) then
        local vV = self:lookupInEnv(sym)
        bltin = vV
    end
    self.LDeclBltinStack[#self.LDeclBltinStack][utl.strip_sym(sym)] = bltin
end
-----------------------------------------------------------------------------

function Compiler:pushBuildinDecls()
    self.LDeclBltinStack:push({})
    -- TODO: Optimize, by pushing all builtin-resolving into code generator!
    --       Do this by creating a special "builtin" code-gen-node!
    self:touchBuiltin("\xFEstrip-kw")
    self:touchBuiltin("\xFEstrip-sym")
end
-----------------------------------------------------------------------------

function Compiler:popBuildinDecls()
    return self.LDeclBltinStack:pop()
end
-----------------------------------------------------------------------------

function Compiler:pushJumpEnv()
    self.LJEStack:push(self.mJumpLabels)
    self.mJumpLabels = { }
end
-----------------------------------------------------------------------------

function Compiler:popJumpEnv()
    self.mJumpLabels = self.LJEStack:pop()
end
-----------------------------------------------------------------------------

function Compiler:pushEnv()
    self.LEnvStack:push(self.mEnv)
    self.mEnv = { }
end
-----------------------------------------------------------------------------

function Compiler:popEnv()
    self.mEnv = self.LEnvStack:pop()
end
-----------------------------------------------------------------------------

function Compiler:mkUservar(sVarUserName)
    self.mEnv[utl.strip_sym(sVarUserName)] = false
    return utl.uservar(sVarUserName)
end
-----------------------------------------------------------------------------

function Compiler:node(...)
    local n = Node(...)
    n:set_source_pos(self.iCurLine, self.sInputName)
    return n
end
-----------------------------------------------------------------------------

function Compiler:compileQuasiQuote(v)
--print("QQ " .. log.dump(v))
    if (type(v) == 'string') then
        if (utl.is_kw(v)) then
            return self:node('keyword', { v })
        elseif (utl.is_sym(v)) then
            return self:node('symbol', { v })
        else
            return self:node('string', { v })
        end

    elseif (type(v) == 'number') then
        return self:node('number', { v })

    elseif (utl.is_nil(v)) then -- XXX: LNIL is a table-value-sentinel!
        return self:node('nil', { v })

    elseif (utl.is_table(v)) then
        if (v[1]) then
            if (utl.is_sym(v[1]) and utl.strip_sym(v[1]) == 'unquote') then
                return self:compile(v[2])

            elseif (utl.is_sym(v[1]) and utl.strip_sym(v[1]) == 'unquote-splicing') then
                return self:node('qsplice', { self:compile(v[2]) })

            elseif (utl.is_sym(v[1]) and utl.strip_sym(v[1]) == 'quasiquote') then
                return self:compileQuasiQuote(v[2])

            else
                local LL = List()
                List(v):foreach(function (v)
                    LL:push(self:compileQuasiQuote(v))
                end)
                return self:node('qlist', LL:table())
            end

        elseif (not next(v)) then
            self:node('list', {})

        else
            local m = { }
            for k, v in pairs(v) do m[self:compileQuasiQuote(k)] = self:compileQuasiQuote(v) end
            return self:node('map', { m })
        end
    elseif (type(v) == 'boolean') then
        return self:node('boolean', { v })

    end
end
-----------------------------------------------------------------------------

function Compiler:compileQuote(v)
    if (type(v) == 'string') then
        if (utl.is_kw(v)) then
            return self:node('keyword', { v })
        elseif (utl.is_sym(v)) then
            return self:node('symbol', { v })
        else
            return self:node('string', { v })
        end

    elseif (type(v) == 'number') then
        return self:node('number', { v })

    elseif (utl.is_nil(v)) then -- XXX: LNIL is a table-value-sentinel!
        return self:node('nil', { v })

    elseif (utl.is_table(v)) then
        if (v[1]) then
            return
                self:node('list',
                    List(v):map(function (v)
                        return self:compileQuote(v)
                    end):table())

        elseif (not next(v)) then
            return self:node('list', {})

        else
            local m = { }
            for k, v in pairs(v) do m[self:compileQuote(k)] = self:compileQuote(v) end
            return self:node('map', { m })
        end
    elseif (type(v) == 'boolean') then
        return self:node('boolean', { v })

    end
end
-----------------------------------------------------------------------------

function Compiler:compileValue(v)
    if (type(v) == 'string') then
        return self:node('string', { v })

    elseif (type(v) == 'number') then
        return self:node('number', { v })

    elseif (utl.is_nil(v)) then -- XXX: LNIL is a table-value-sentinel!
        return self:node('nil', { v })

    elseif (utl.is_table(v)) then
        if (v[1]) then
            return
                self:node('list',
                    List(v):map(function (v)
                        return self:compile(v)
                    end):table())

        elseif (not next(v)) then
            return self:node('list', {})

        else
            local m = { }
            for k, v in pairs(v) do m[self:compile(k)] = self:compile(v) end
            return self:node('map', { m })
        end
    elseif (type(v) == 'boolean') then
        return self:node('boolean', { v })

    end
end
-----------------------------------------------------------------------------

function Compiler:loadUsedBuiltins(bltins, oNode)
    local mLibs     = {}
    local mBuiltins = {}
    for k, v in pairs(bltins) do
        if (v.sType == "lua_env_builtin") then
            mBuiltins[utl.uservar(k)] = { name = v.name }

        elseif (v.sType == "library") then
            -- define load-library
            -- the codegen should emit something, that uses load() and sets
            -- the chunkname to the source code of the LAL-compileoutput
            -- that was read from the file. then the backtraces should still
            -- give proper error output.
            -- TODO FIXME XXX

        else -- sType == "builtin" from external Lua file
            if (not v.file) then
                error("Compiler internal error: No file for builtin '" .. k .. "'");
            end
            if (not mLibs[v.file]) then mLibs[v.file] = {} end
            if (v.in_lib_name) then
                mLibs[v.file][v.in_lib_name] = utl.uservar(k)
            else
                mLibs[v.file][k] = utl.uservar(k)
            end
        end
    end
    return self:node('load_lua_libs', { mLibs, mBuiltins, oNode })
end
-----------------------------------------------------------------------------

Compiler.lal_lua_env_reset = [[
if (os.getenv("LALRT_LIB")) then package.path = package.path .. ";" .. os.getenv("LALRT_LIB") .. '/lal/?.lua'; end;
local _ENV = { _lal_lua_base_ENV = _ENV, _lal_lua_base_pairs = pairs };
for k, v in _lal_lua_base_pairs(_lal_lua_base_ENV) do _ENV["_lal_lua_base_" .. k] = v end;
]]
-----------------------------------------------------------------------------

function Compiler:compile_internal_code(v)
    self:pushJumpEnv()
    self:pushBuildinDecls()
    local oDefMacroNode = self:compile(v)
    local builtins = self:popBuildinDecls()
    self:popJumpEnv()

    local oChunk =
        self:node('tailContext', {
            self:loadUsedBuiltins(builtins, oDefMacroNode)
        }):gen(true)
    return self.lal_lua_env_reset .. oChunk:chunk(), oDefMacroNode
end
-----------------------------------------------------------------------------

function Compiler:compile_toplevel(v, table_parse_pos, no_env_reset, gen_global_assigns)
    if (table_parse_pos) then
        self.m_mTablePos = table_parse_pos
    end

    local oChunk
    local bOk, sErr = xpcall(function ()
        self:pushJumpEnv()
        self:pushBuildinDecls()
        self:pushDebugPos(v)

        local old_glob_ass = self.assign_to_global_env
        self.assign_to_global_env = gen_global_assigns
        local oNode = self:compile(v)
        self.assign_to_global_env = old_glob_ass

        local bltins = self:popBuildinDecls()
        self:popJumpEnv()

        oNode = self:node('tailContext', { self:loadUsedBuiltins(bltins, oNode) })

        self:popDebugPos()

        oChunk = oNode:gen(true)
        assert(oChunk:isReturning())
    end, function (sMsg)
        if (string.match(sMsg, '^\\[[^\\]+\\] Compiler Error:')) then
            return tostring(sMsg)
        else
            return tostring(sMsg) .. "\nTraceback:\n" .. debug.traceback(nil, 2)
        end
    end)
    if (not bOk) then error(sErr, 0) end
    if (no_env_reset) then
        return oChunk:chunk()
    else
        return self.lal_lua_env_reset .. oChunk:chunk()
    end
end
-----------------------------------------------------------------------------

function Compiler:compile_block(v, iOffs, lAddBlock)
    local LBlock = List()
    for i = iOffs, #v do LBlock:push(self:compile(v[i])) end
    if (lAddBlock) then
        for _, v in ipairs(lAddBlock) do LBlock:push(v) end
    end
    return self:node('block', LBlock:table())
end
-----------------------------------------------------------------------------

function Compiler:pushDebugPos(vForm)
    if (not self.m_mTablePos) then
        self.iCurLine   = 0
        self.sInputName = 'eval'
        self.sInputPath = '.'
        self.vErrForm   = {}
        return
    end

    self.LDebugPosStack:push({
        line = self.iCurLine,
        name = self.sInputName,
        path = self.sInputPath,
        form = self.vErrForm,
    })
    local pos = self.m_mTablePos[tostring(vForm)]
    if (pos) then
        self.iCurLine   = pos.line
        self.sInputName = pos.name
        self.sInputPath = pos.path
    end
    self.vErrForm = vForm
end
-----------------------------------------------------------------------------

function Compiler:popDebugPos()
    local pos = self.LDebugPosStack:pop()
    if (pos) then
        self.iCurLine   = pos.line
        self.sInputName = pos.name
        self.sInputPath = pos.path
        self.vErrForm   = pos.form
    end
end
-----------------------------------------------------------------------------

function Compiler:isMacroSym(sSym)
    if (not utl.is_sym(sSym)) then return false end
    local v = self:lookupInEnv(sSym)
    if (utl.is_table(v) and v.sType == 'primitive-macro') then
        return true, v.func, v.lua_code
    end
    return false
end
-----------------------------------------------------------------------------

function Compiler:macroexpand(v)
    if (type(v) ~= 'table') then return v end

    local bIsMacro, fMacro = self:isMacroSym(v[1])

    if (not bIsMacro) then return v end

    while (bIsMacro) do
        local LArgs = List()
        for i = 2, #v do LArgs:push(self:macroexpand(v[i])) end

        v = fMacro(table.unpack(LArgs:table()))
        if (utl.is_nil(v) or utl.is_nil(v[1])) then
            break
        end
        bIsMacro, fMacro = self:isMacroSym(v[1])
    end

    return v
end
-----------------------------------------------------------------------------

function Compiler:compile(v)
--    log.dbg("compile: %1\n", log.dump(v))
    v = self:macroexpand(v)

    -- XXX: no test for LNIL here is ok or we detect maps
    if (utl.is_table(v) and v[1]) then
        self:pushDebugPos(v)

        if (utl.is_nil(v[1])) then
            self:err(
                "Expected not nil in first element of function call special form!")
        end

        local sF = v[1]

        if (utl.is_sym(sF)) then
            local vF = self:lookupInEnv(sF)
--            log.trc("compile call/syn: %1\n", vF)
            if (utl.is_table(vF) and vF.sType == 'syntax') then
                local r
                local ok, err = pcall(function ()
                    r = vF.func(self, sF, v)
                end)
                self:popDebugPos()
                if (err) then
                    self:err("LAL-Syntax error '" .. utl.strip_sym(sF) .. "': %s\n", err)
                end
                return r
            end
        end

        local LArgs = List(v):map(function (v) return self:compile(v) end)
        local n = self:node('funcall', LArgs:table())
        self:popDebugPos()
        return n

    elseif (utl.is_kw(v)) then
        return self:node('keyword', { v })

    elseif (utl.is_sym(v)) then
        local vV = self:lookupInEnv(v)
        if (utl.is_table(vV) and (vV.sType == "builtin"
                                  or vV.sType == "library"
                                  or vV.sType == "lua_env_builtin"))
        then
            self:touchBuiltin(v, vV)

        elseif (utl.is_table(vV) and vV.sType == "syntax" and vV.prim_func) then
            self:touchBuiltin(v, self.to_builtin(vV.prim_func))
        end
        return self:node('var', { utl.uservar(v) })

    else
        return self:compileValue(v)
    end
end
-----------------------------------------------------------------------------

function Compiler:import_library(lib)
    for k, v in pairs(lib) do
        self.mGlobalEnv[k] = v
    end
end
-----------------------------------------------------------------------------

function Compiler.compile_lal_code(lal_code, environment, input_file)
    local compiler = Compiler(environment)
    local parser   = Parser()

    local val, table_parse_pos = parser:parse_program(lal_code, input_file)
    local lua_code = compiler:compile_toplevel(val, table_parse_pos)
    if (compiler.do_print_output) then
        print("DEBUG-PRINT-OUTPUT " .. compiler.do_print_output .. "> [\n" .. lua_code .. "\n]\n")
    end
    return lua_code, compiler:global_eval_env()
end
-----------------------------------------------------------------------------

return Compiler
