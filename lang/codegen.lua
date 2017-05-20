-- See Copyright Notice in lal.lua

local utl       = require 'lal/lang/util'
local CodeChunk = require 'lal/lang/chunk'
local List      = require 'lal/util/list'
local class     = require 'lal/util/class'
-----------------------------------------------------------------------------

local function concatChunkValues(LChunks, sSep)
    return LChunks:map(function (oC) return oC:value() end):concat(sSep)
end
-----------------------------------------------------------------------------

local CodeNode = class()
-----------------------------------------------------------------------------

function CodeNode:init(sType, lArgs)
    self.sType   = sType
    self.LArgs   = List(lArgs)
end
-----------------------------------------------------------------------------

function CodeNode:chunk(...)
    local c = CodeChunk(...)
    if (self.pos) then
        c:p_if_has_output("--[[%s]]",
            string.format("%s:%d", self.pos[2], self.pos[1]))
    end
    return c
end
-----------------------------------------------------------------------------

function CodeNode:set_source_pos(line, input_name)
    self.pos = { line, input_name }
end
-----------------------------------------------------------------------------

function CodeNode:gen(bIsTail)
    if (not self['gen_' .. self.sType]) then
        error("No such code generator function: gen_" .. self.sType)
    end
    local v = self['gen_' .. self.sType](self, bIsTail)
    return v
end
-----------------------------------------------------------------------------

function CodeNode:gen_qsplice(bIsTail)
    local oQSplC = self.LArgs[1]:gen(false)
    oQSplC._qsplice_marker = true
    return oQSplC
end
-----------------------------------------------------------------------------

function CodeNode:handleReturnedChunks(LChunks)
    local bIsReturning = false
    LChunks = LChunks:map(function (oN)
        local oC = oN:gen(false)
        if (oC:isReturning()) then bIsReturning = true end
        return oC
    end)
    if (not bIsReturning) then
        return nil, LChunks
    end

    local oReturnChunk = self:chunk()

    LChunks:foreach(function (oC)
        if (oReturnChunk:isReturning()) then return end

        if (oC:isReturning()) then
            oReturnChunk:appendWithValue(oC)
        else
            oC:mergeUnusedValue()
            oReturnChunk:append(oC)
        end
    end)

    return oReturnChunk, nil
end
-----------------------------------------------------------------------------

function CodeNode:gen_qlist(bIsTail)
    local oRetC, LElems = self:handleReturnedChunks(self.LArgs)
    if (oRetC) then
        return oRetC
    end

    local oC      = self:chunk()
    local sOutTmp = oC:declTmpVar('ql', '{}')
    local sI      = oC:declTmpVar('qi', '1')

    LElems:foreach(function (v)
        oC:append(v)

        if (v._qsplice_marker) then
            local sQSTmp = oC:declTmpVar('qspl', v:value())
            local sITmp  = utl.tmpvar("i");
            local sLTmp  = utl.tmpvar("l");
            oC:p('if (_lal_lua_base_type(%s) == \'table\') then', sQSTmp)
            oC:p('    %s = #%s;', sLTmp, sOutTmp);
            oC:p('    for %s = 1, #%s do %s[%s + %s] = %s[%s]; end',
                 sITmp, sQSTmp, sOutTmp, sLTmp, sITmp, sQSTmp, sITmp);
--            oC:p('    _lal_lua_base_table.move(%s, 1, #%s, #%s + 1, %s);',
--                        sQSTmp, sQSTmp, sOutTmp, sOutTmp)
            oC:p('    %s = %s + #%s;', sI, sI, sQSTmp);
            oC:p('else')
            oC:p('    %s[%s] = %s;', sOutTmp, sI, sQSTmp)
            oC:p('    %s = %s + 1;', sI, sI)
            oC:p('end;')
        else
            oC:p('%s[%s] = %s;', sOutTmp, sI, v:value())
            oC:p('%s = %s + 1;', sI, sI)
        end
    end)

    oC:sideeffectFreeExpressionValue()
    oC:pV('%s', sOutTmp)
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_list(bIsTail)
    local oRetC, LElems = self:handleReturnedChunks(self.LArgs)
    if (oRetC) then
        return oRetC
    end

    local oC = self:chunk()
    oC:appendChunks(LElems)

    oC:expressionValue()
    oC:pV('{%s}', concatChunkValues(LElems, ", "))
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_map(bIsTail)
    local LAll    = List()
    local LKeys   = List()
    local LValues = List()
    for k, v in pairs(self.LArgs[1]) do
        LKeys:push(k)
        LValues:push(v)
        LAll:push(k)
        LAll:push(v)
    end

    local oRetC
    oRetC, LKeys = self:handleReturnedChunks(LKeys)
    if (oRetC) then return oRetC end
    oRetC, LValues = self:handleReturnedChunks(LValues)
    if (oRetC) then return oRetC end

    local oC = self:chunk()
    oC:appendChunks(LKeys)
    oC:appendChunks(LValues)

    oC:expressionValue()
    oC:pV('{')
    LKeys:foreach(function (oK)
        if (oK.sValueCompileType == 'keyword') then
            oC:pV('[%s] = %s, ', utl.quote_lua_string(utl.strip_kw(oK.sRawStringValue)), LValues:shift():value())

        elseif (oK.sValueCompileType == 'string') then
            oC:pV('[%s] = %s, ', utl.quote_lua_string(oK.sRawStringValue), LValues:shift():value())
        else
            oC:pV('[strip_kw(%s)] = %s, ', oK:value(), LValues:shift():value())
        end
    end)
    oC:pV('}')

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_string(bIsTail)
    return self:chunk(utl.quote_lua_string(self.LArgs[1])):compileType('string', self.LArgs[1])
end
-----------------------------------------------------------------------------

function CodeNode:gen_number(bIsTail)
    return self:chunk(tostring(self.LArgs[1])):compileType('number')
end
-----------------------------------------------------------------------------

function CodeNode:gen_boolean(bIsTail)
    if (self.LArgs[1]) then return self:chunk('true'):compileType('boolean')
    else return self:chunk('false'):compileType('boolean') end
end
-----------------------------------------------------------------------------

function CodeNode:gen_keyword(bIsTail)
    return self:chunk(utl.quote_lua_string(self.LArgs[1])):compileType('keyword', self.LArgs[1])
end
-----------------------------------------------------------------------------

function CodeNode:gen_symbol(bIsTail)
    return self:chunk(utl.quote_lua_string(self.LArgs[1])):compileType('symbol', self.LArgs[1])
end
-----------------------------------------------------------------------------

function CodeNode:gen_nil(bIsTail)
    return self:chunk('nil'):compileType('nil')
end
-----------------------------------------------------------------------------

function CodeNode:gen_not(bIsTail)
    local oCExpr = self.LArgs[1]:gen(false)
    local oC     = self:chunk()
    oC:append(oCExpr)
    oC:expressionValue()
    oC:pV('not(%s)', oCExpr:value())
    return oC
end
-----------------------------------------------------------------------------

function CodeNode.func_fld(field, table)
    return table[utl.strip_kw(field)]
end
-----------------------------------------------------------------------------

function CodeNode.func_fldM(field, table, arg)
    table[utl.strip_kw(field)] = arg
    return arg
end
-----------------------------------------------------------------------------

function CodeNode:gen_fieldOverAccess(bIsTail)
    local bArray = self.LArgs[1]
    local sVar   = self.LArgs[2]
    local oField = self.LArgs[3]:gen(false)
    local oTable = self.LArgs[4]:gen(false)
    local oBlock = self.LArgs[5]:gen(false)

    if (oField:isReturning()) then return oField end
    if (oTable:isReturning()) then return oTable end

    local oC = self:chunk()
    oC:append(oField)
    oC:append(oTable)

    local sTbl = oC:declTmpVar("tbl", oTable:value())
    local sFld

    if (oField.sValueCompileType == 'keyword') then
        sFld = string.format("[%s]", utl.quote_lua_string(utl.strip_kw(oField.sRawStringValue)))

    elseif (oField.sValueCompileType == 'symbol') then
        sFld = string.format("[%s]", utl.quote_lua_string(utl.strip_sym(oField.sRawStringValue)))

    elseif (oField.sValueCompileType == 'string') then
        sFld = string.format("[%s]", utl.quote_lua_string(oField.sRawStringValue))

    elseif (oField.sValueCompileType == 'number') then
        sFld = string.format("[%s]", tostring(oField:value()) + 1)

    else
        if (bArray) then
            sFld = oC:declTmpVar("fld", string.format("((%s) + 1)", oField:value()))
        else
            sFld = oC:declTmpVar("fld", string.format("strip_kw(%s)", oField:value()))
        end
        sFld = string.format("[%s]", sFld)
    end

    local sTmp = oC:declTmpVar("tmp")
    oC:p("do local %s = (%s)%s;", sVar, sTbl, sFld)
    if (oBlock:isReturning()) then
        oC:appendWithValue(oBlock)
        oC:p("end;")
        return oC
    else
        oC:append(oBlock, 1)
        oC:p("    %s = %s;", sTmp, oBlock:value())
        oC:p("    %s = %s;", sVar, sTmp)
        oC:p("    (%s)%s = %s;", sTbl, sFld, sTmp)
        oC:p("end;")
        oC:sideeffectFreeExpressionValue()
        oC:pV("%s", sVar)
    end
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_fieldAccess(bIsTail)
    local oFieldAcces = self.LArgs:shift():gen(false)
    if (oFieldAcces:isReturning()) then return oFieldAcces end

    local oRetC, LArgs = self:handleReturnedChunks(self.LArgs)
    if (oRetC) then return oRetC end

    local oCMap = LArgs:shift()

    local oC = self:chunk()
    oC:append(oFieldAcces)

    local sFieldAccess
    if (oFieldAcces.sValueCompileType == 'keyword') then
        sFieldAccess = string.format("[%s]", utl.quote_lua_string(utl.strip_kw(oFieldAcces.sRawStringValue)))

    elseif (oFieldAcces.sValueCompileType == 'symbol') then
        sFieldAccess = string.format("[%s]", utl.quote_lua_string(utl.strip_sym(oFieldAcces.sRawStringValue)))

    elseif (oFieldAcces.sValueCompileType == 'string') then
        sFieldAccess = string.format("[%s]", utl.quote_lua_string(oFieldAcces.sRawStringValue))

    else
        sFieldAccess = string.format("[strip_kw(%s)]", oFieldAcces:value())
    end

    if (#LArgs <= 0) then
        oC:append(oCMap)
        oC:expressionValue()
        oC:pV("((%s)%s)", oCMap:value(), sFieldAccess)

    elseif (#LArgs == 1) then
        oC:append(oCMap)
        oC:appendChunks(LArgs)
        local sTmpVar = oC:declTmpVar('facc', LArgs[1]:value())
        oC:p('(%s)%s = %s;', oCMap:value(), sFieldAccess, sTmpVar)
        oC:expressionValue()
        oC:pV('%s', sTmpVar)

    else
        oC:append(oCMap)
        oC:appendChunks(LArgs)
        local sTmpVar =
            oC:declTmpVar('facc',
                string.format('{%s}', concatChunkValues(LArgs, ",")))
        oC:p('(%s)%s = %s;', oCMap:value(), sFieldAccess, sTmpVar)
        oC:expressionValue()
        oC:pV('%s', sTmpVar)
    end

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_block(bIsTail)
    local oC = self:chunk()

    local oLastChunk
    oC:appendChunks(
        self.LArgs:map(function (v, i)
            if (oLastChunk) then return nil end

            local oCL
            if (i == #self.LArgs) then
                oCL = v:gen(bIsTail)
            else
                oCL = v:gen(false)
            end

            if (oCL:isReturning()) then
                oLastChunk = oCL
                return oCL
            end

            if (i == #self.LArgs) then
                oLastChunk = oCL
            else
                oCL:mergeUnusedValue()
            end

            return oCL
        end)
        :filter(function (v) return v end))

    if (oLastChunk) then
        oC:valueFrom(oLastChunk)
        if (bIsTail and not oLastChunk:isReturning()) then
            oC:mergeValueAsReturn()
        end
    else
        oC:pV('nil')
    end

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_tailContext()
    local oC = self.LArgs[1]:gen(true)
    if (not oC:isReturning()) then
        oC:mergeValueAsReturn()
    end
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_count(bIsTail)
    local oCL = self.LArgs[1]:gen(false)
    if (oCL:isReturning()) then return oCL end

    local oC = self:chunk()
    oC:expressionValue()
    oC:append(oCL)
    oC:pV('#(%s)', oCL:value())
    return oC
end
-----------------------------------------------------------------------------

function CodeNode.func_emptyQ(v)
    return not(utl.is_table(v)) or not next(v)
end
-----------------------------------------------------------------------------

function CodeNode:gen_emptyQ(bIsTail)
    local oCL = self.LArgs[1]:gen(false)
    if (oCL:isReturning()) then return oCL end

    local oC  = self:chunk()
    oC:appendWithValue(oCL)
    local sTmp = oC:mergeValueAsTmpVar('emptyQ')

    oC:expressionValue()
    oC:pV('(_lal_lua_base_type(%s) ~= "table" or not _lal_lua_base_next(%s))',
          sTmp, sTmp, sTmp)
    return oC
end
-----------------------------------------------------------------------------

function CodeNode.func_at(idx, tbl) return tbl[idx + 1] end

function CodeNode:gen_at(bIsTail)
    local oIdxC = self.LArgs[1]:gen(false)
    local oTblC = self.LArgs[2]:gen(false)

    if (oIdxC:isReturning()) then return oIdxC end
    if (oTblC:isReturning()) then return oTblC end

    local oC = self:chunk()
    oC:append(oIdxC)
    oC:append(oTblC)
    oC:expressionValue()

    if (oIdxC.sValueCompileType == 'number') then
        oC:pV('((%s)[%s])', oTblC:value(), tonumber(oIdxC:value()) + 1)
    else
        oC:pV('((%s)[%s + 1])', oTblC:value(), oIdxC:value())
    end

    return oC
end
-----------------------------------------------------------------------------

function CodeNode.func_atM(idx, tbl, val) tbl[idx + 1] = val return val end
-----------------------------------------------------------------------------

function CodeNode:gen_atM(bIsTail)
    -- TODO: Refactor this together with gen_fieldAccess!

    local oIdxC = self.LArgs[1]:gen(false)
    local oTblC = self.LArgs[2]:gen(false)
    local oValC = self.LArgs[3]:gen(false)

    if (oIdxC:isReturning()) then return oIdxC end
    if (oTblC:isReturning()) then return oTblC end
    if (oValC:isReturning()) then return oValC end

    local oC = self:chunk()
    oC:append(oIdxC)
    oC:append(oTblC)
    oC:append(oValC)
    oC:expressionValue()

    local sV = oC:declTmpVar('atv', oValC:value())

    if (oIdxC.sValueCompileType == 'number') then
        oC:p('(%s)[%s] = %s;',     oTblC:value(), tonumber(oIdxC:value()) + 1, sV)
    else
        oC:p('(%s)[%s + 1] = %s;', oTblC:value(), oIdxC:value(), sV)
    end
    oC:sideeffectFreeExpressionValue()
    oC:pV('%s', sV)
    return oC
end
-----------------------------------------------------------------------------

function CodeNode.func_map(f, ...)
    local lTabs = table.pack(...)
    local lOut = {}
    if (#lTabs > 1) then
        local iMax = 0
        for i = 1, #lTabs do
            local lt = lTabs[i]
            if (iMax < #lt) then iMax = #lt end
        end
        for i = 1, iMax do
            local lArgs = {}
            for j = 1, #lTabs do lArgs[j] = lTabs[j][i] end
            lOut[i] = f(table.unpack(lArgs))
        end

    elseif (#lTabs == 0) then
        lOut[1]= f()

    else
        local lt = lTabs[1]
        for i = 1, #lt do
            lOut[i] = f(lt[i])
        end
    end
    return lOut
end
-----------------------------------------------------------------------------

function CodeNode:gen_mapF(bIsTail)
    local oRetC, LOpr = self:handleReturnedChunks(self.LArgs)
    if (oRetC) then return oRetC end

    local oCF = LOpr:shift()
    local oC = self:chunk()
    oC:append(oCF)
    local sFTmp = oC:declTmpVar('mapf', oCF:value())

    local lTabTmps = {}
    oC:appendChunks(LOpr)
    LOpr:foreach(function (oOPC)
        lTabTmps[#lTabTmps + 1] = oC:declTmpVar('maparg', oOPC:value())
    end)

    local sOutTbl
    if (#lTabTmps > 1) then
        sOutTbl = oC:declTmpVar('mapout', "{}")

        local sMAX = oC:declTmpVar('mapmaxarg', '0')
        for i = 1, #lTabTmps do
            oC:p('if (%s < #%s) then %s = #%s end;',
                 sMAX, lTabTmps[i], sMAX, lTabTmps[i])
        end

        local sI = oC:declTmpVar('mapi')
        oC:p('for %s = 1, %s do', sI, sMAX)
        oC:p('    %s[%s] = %s(%s);', sOutTbl, sI, sFTmp,
             List(lTabTmps)
             :map(function (v) return string.format("%s[%s]", v, sI) end)
             :concat(","))
        oC:p('end;')

    elseif (#lTabTmps == 0) then
        sOutTbl = oC:declTmpVar('mapout', "{ " .. sFTmp .. "() }")

    else
        local lt = lTabTmps[1]
        sOutTbl = oC:declTmpVar('mapout', "{}")
        local sI = oC:declTmpVar('mapi')
        oC:p('for %s = 1, #%s do %s[%s] = %s(%s[%s]); end;',
             sI, lt, sOutTbl, sI, sFTmp, lt, sI)
    end

    oC:sideeffectFreeExpressionValue()
    oC:pV(sOutTbl)

    return oC
end
-----------------------------------------------------------------------------

function CodeNode.func_forEach(f, ...)
    local lTabs = table.pack(...)
    if (#lTabs > 1) then
        local iMax = 0
        for i = 1, #lTabs do
            local lt = lTabs[i]
            if (iMax < #lt) then iMax = #lt end
        end
        for i = 1, iMax do
            local lArgs = {}
            for j = 1, #lTabs do lArgs[j] = lTabs[j][i] end
            f(table.unpack(lArgs))
        end

    elseif (#lTabs == 0) then
        f()

    else
        local lt = lTabs[1]
        for i = 1, #lt do
            f(lt[i])
        end
    end
    return nil
end
-----------------------------------------------------------------------------

function CodeNode:gen_forEachF(bIsTail)
    local oRetC, LOpr = self:handleReturnedChunks(self.LArgs)
    if (oRetC) then return oRetC end

    local oCF = LOpr:shift()
    local oC = self:chunk()
    oC:append(oCF)
    local sFTmp = oC:declTmpVar('forf', oCF:value())

    local lTabTmps = {}
    oC:appendChunks(LOpr)
    LOpr:foreach(function (oOPC)
        lTabTmps[#lTabTmps + 1] = oC:declTmpVar('forarg', oOPC:value())
    end)

    if (#lTabTmps > 1) then
        local sMAX = oC:declTmpVar('mapmaxarg', '0')
        for i = 1, #lTabTmps do
            oC:p('if (%s < #%s) then %s = #%s end;',
                 sMAX, lTabTmps[i], sMAX, lTabTmps[i])
        end

        local sI = oC:declTmpVar('mapi')
        oC:p('for %s = 1, %s do', sI, sMAX)
        oC:p('    %s(%s);', sFTmp,
             List(lTabTmps)
             :map(function (v) return string.format("%s[%s]", v, sI) end)
             :concat(","))
        oC:p('end;')

    elseif (#lTabTmps == 0) then
        oC:p('%s();', sFTmp)

    else
        local lt = lTabTmps[1]
        local sI = oC:declTmpVar('mapi')
        oC:p('for %s = 1, #%s do %s(%s[%s]); end;',
             sI, lt, sFTmp, lt, sI)
    end

    oC:sideeffectFreeExpressionValue()
    oC:pV('nil')

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_for(bIsTail)
    local LExpr = List()
    LExpr:push(self.LArgs[2]:gen(false))
    LExpr:push(self.LArgs[3]:gen(false))
    LExpr:push(self.LArgs[4]:gen(false))
    if (self.LArgs[5]) then
        LExpr:push(self.LArgs[5]:gen(false))
    end

    local sVar     = self.LArgs[1]
    local oStartC  = LExpr:shift()
    local oDestC   = LExpr:shift()
    local oBlockC  = LExpr:shift()
    local oIncC    = LExpr:shift()

    if (oStartC:isReturning())         then return oStartC end
    if (oDestC:isReturning())          then return oDestC end
    if (oIncC and oIncC:isReturning()) then return oIncC end

    local oC = self:chunk()
    oC:append(oDestC)
    oC:append(oStartC)

    if (oIncC) then
        oC:append(oIncC)
        oC:p('for %s = %s, %s, %s do',
             sVar, oStartC:value(), oDestC:value(), oIncC:value())
    else
        oC:p('for %s = %s, %s do',
             sVar, oStartC:value(), oDestC:value())
    end
    oBlockC:mergeUnusedValue()
    oC:append(oBlockC, 1)
    oC:p('end;')

    oC:sideeffectFreeExpressionValue()
    oC:pV('nil')
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_do_each(bIsTail)
    local LExpr = List()
    LExpr:push(self.LArgs[1]:gen(false))
    LExpr:push(self.LArgs[2]:gen(false))

    local sV = self.LArgs[3]
    local sK = self.LArgs[4]

    local oValC   = LExpr[1]
    local oBlockC = LExpr[2]

    if (oValC:isReturning()) then return oValC end

    local oC = self:chunk()
    oC:append(oValC)
    if (sK) then
        oC:p('for %s, %s in _lal_lua_base_pairs(%s) do', sK, sV, oValC:value())
    else
        oC:p('for _, %s in _lal_lua_base_ipairs(%s) do', sV, oValC:value())
    end

    oBlockC:mergeUnusedValue()
    oC:append(oBlockC, 1)
    oC:p('end;')

    oC:sideeffectFreeExpressionValue()
    oC:pV('nil')
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_op(bIsTail)
    local sOp  = self.LArgs[1]
    local oRetC, LOpr = self:handleReturnedChunks(self.LArgs[2])
    if (oRetC) then return oRetC end

    local oC = self:chunk()
    oC:expressionValue()
    oC:appendChunks(LOpr)
    oC:pV('(%s)', concatChunkValues(LOpr, string.format(" %s ", sOp)))
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_global_decl(bIsTail)
    local oC = self:chunk()

    if (self.LArgs[2]) then
        local oCVal = self.LArgs[2]:gen(false)
        if (oCVal:isReturning()) then
            oC:appendWithValue(oCVal)
            return oC
        end

        oC:append(oCVal)
        oC:p('%s = %s;', self.LArgs[1], oCVal:value())
        if (self.LArgs[3]) then
            oC:p('_LALRT_GLOB_ENV["%s"] = %s;', self.LArgs[1], self.LArgs[1])
        end
    end
    oC:sideeffectFreeExpressionValue()
    oC:pV('%s', self.LArgs[1])
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_local_decl(bIsTail)
    local oC = self:chunk()

    if (self.LArgs[4]) then
        local oCVal = self.LArgs[4]:gen(false)
        if (oCVal:isReturning()) then return oCVal end

        oC:append(oCVal)
        oC:p('local %s; %s = %s;', self.LArgs[3], self.LArgs[3], oCVal:value())
    else
        oC:p("local %s;", self.LArgs[3])
    end

    if (self.LArgs[1]) then
        oC:p('_LALRT_GLOB_ENV["%s"] = %s;', self.LArgs[3], self.LArgs[3])
    end

    oC:sideeffectFreeExpressionValue()
    oC:pV('%s', self.LArgs[3])
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_assign_var(bIsTail)
    local oCVal = self.LArgs[4]:gen(false)
    if (oCVal:isReturning()) then return oCVal end

    local oC = self:chunk()
    oC:append(oCVal)
    oC:p('%s = %s;', self.LArgs[3], oCVal:value())

    if (self.LArgs[1]) then
        oC:p('_LALRT_GLOB_ENV[%s] = %s;', self.LArgs[3], self.LArgs[3])
    end

    oC:sideeffectFreeExpressionValue()
    oC:pV('%s', self.LArgs[3])
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_var(bIsTail)
    return self:chunk(self.LArgs[1])
end
-----------------------------------------------------------------------------

function CodeNode:gen_function(bIsTail)
    local LParams = self.LArgs[1]
    local oCCode  = self.LArgs[2]:gen()
    assert(oCCode:isReturning())

    local sVarArgParam
    if (utl.is_table(LParams[#LParams])) then
        sVarArgParam = LParams:pop()[1]
        LParams:push('...')
    end

    local oC = self:chunk()
    oC:sideeffectFreeExpressionValue()
    oC:pV('(function (%s)', LParams:concat(', '))
    if (sVarArgParam) then
        oC:pV(' local %s = _lal_lua_base_table.pack(...); %s.n = nil;\n',
              sVarArgParam, sVarArgParam)
    end
    oC:pV('\n%s', oCCode:chunk(1))
    oC:pV('end)')
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_funcall(bIsTail)
    local oRetC, LArgs = self:handleReturnedChunks(self.LArgs)
    if (oRetC) then return oRetC end

    local oC = self:chunk()
    oC:statementValue()
    local oCFunc = LArgs:shift();
    oC:appendChunks(LArgs)
    oC:pV('%s(%s)', oCFunc:value(), concatChunkValues(LArgs, ","))
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_scope(bIsTail)
    local oC     = self:chunk()
    local oCCode = self.LArgs[1]:gen(bIsTail)
    if (oCCode:isReturning()) then
        oC:p('do')
        oC:appendWithValue(oCCode, 1)
        oC:p('end;')
    else
        local sOutTmp = oC:declTmpVar('s')
        oC:p('do')
        oC:append(oCCode, 1)
        oC:p('    %s = %s;', sOutTmp, oCCode:value())
        oC:p('end;')
        oC:sideeffectFreeExpressionValue()
        oC:pV('%s', sOutTmp)
    end

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_return(bIsTail)
    local oC = self.LArgs[1]:gen(true)
    if (oC:isReturning()) then return oC end
    oC:mergeValueAsReturn()
    return oC
end
-----------------------------------------------------------------------------

local function emit_if(chunk, cond_node, true_node, false_node, all_branches_return)
    chunk:append(cond_node)

    local if_tmp
    if (not all_branches_return) then
        if_tmp = chunk:declTmpVar('if')
    end

    chunk:p('if %s then', cond_node:value())

    if (true_node) then
        chunk:append(true_node, 1)

        if (not true_node:isReturning()) then
            chunk:p('    %s = %s;', if_tmp, true_node:value())
        end
    end

    if (false_node) then
        chunk:p('else')
        chunk:append(false_node, 1)

        if (not false_node:isReturning()) then
            chunk:p('    %s = %s;', if_tmp, false_node:value())
        end
    end

    chunk:p('end;')

    if (all_branches_return) then
        chunk:valueFrom(true_node) -- just inherit "isReturning" status
    else
        chunk:sideeffectFreeExpressionValue()
        chunk:pV('%s', if_tmp)
    end
end

function CodeNode:gen_if(is_tail)
    local cond_node, true_node, false_node
    if (self.LArgs[1]) then cond_node  = self.LArgs[1]:gen(false)   end
    if (self.LArgs[2]) then true_node  = self.LArgs[2]:gen(is_tail) end
    if (self.LArgs[3]) then false_node = self.LArgs[3]:gen(is_tail) end

    if ((not cond_node) or (not true_node)) then
        return self:chunk('nil')
    end

    if (cond_node:isReturning()) then
        return cond_node;
    end

    -- Make if proper tail recursive, to force return of it's values:
    if (is_tail and true_node)  then true_node:mergeValueAsReturn() end
    if (is_tail and false_node) then false_node:mergeValueAsReturn() end

    local all_branches_return = true
    if (not(true_node) or not true_node:isReturning())   then all_branches_return = false end
    if (not(false_node) or not false_node:isReturning()) then all_branches_return = false end

    local chunk = self:chunk()
    emit_if(chunk, cond_node, true_node, false_node, all_branches_return)

    return chunk
end
-----------------------------------------------------------------------------

function CodeNode:gen_or_and(bIsTail)
    local oC = self:chunk()

    local sType = self.LArgs[1]
    local sRetVal = oC:declTmpVar(sType)

    local LTerms = self.LArgs[2]

    local LEndStack = List()
    for i = 1, #LTerms do
        local oTermNode = LTerms[i]

        local bTermIsTail = bIsTail and i == #LTerms
        local oTC = oTermNode:gen(bTermIsTail)

        if (bTermIsTail and not oTC:isReturning()) then oTC:mergeValueAsReturn() end
        oC:append(oTC, 1)

        if (oTC:isReturning()) then
            break
        else
            oC:p('%s = %s;', sRetVal, oTC:value())
            if (i ~= #LTerms) then
                if (sType == 'or') then
                    oC:p('if not %s then ', sRetVal)
                else
                    oC:p('if %s then ', sRetVal)
                end
                LEndStack:push('end;')
            end
        end
    end
    oC:p('%s', LEndStack:concat(""))

    oC:sideeffectFreeExpressionValue()
    oC:pV('%s', sRetVal)
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_cond(bIsTail)
    local oC      = self:chunk()
    local cls     = self.LArgs[1]
    local else_cl = self.LArgs[2]

    local clauses = List()

    for _, cl in ipairs(cls) do
        local c_test = cl[1]:gen(false)

        if (c_test:isReturning()) then
            clauses:push { 'else', c_test }
            break

        else
            if (cl[2]) then
                local c_expr
                if (cl[3]) then -- need function invocation!
                    c_expr = cl[2]:gen(false)
                else
                    c_expr = cl[2]:gen(bIsTail)
                end
                clauses:push( { 'test', c_test, c_expr, cl[3] } )
            else
                clauses:push( { 'test', c_test } )
            end
        end
    end

    local has_else_clause = #clauses > 0 and clauses[#clauses][1] == 'else'

    if (not has_else_clause) then
        if (else_cl) then
            clauses:push { 'else', else_cl:gen(bIsTail) }
        else
            local cnilret = CodeNode('nil'):gen(bIsTail)
            clauses:push { 'else', cnilret }
        end
    end

    local ret_val  = oC:declTmpVar("cond")
    local test_var = oC:declTmpVar("cond_t")
    local open_if_count = 0
    local all_return = true

    -- TODO: when we ahve too many clauses, we should not output
    --       nested if statements, but consecutive ones with a
    --       flag that prevent further tests. But thats slower
    --       of course. But maybe we should leave this to the
    --       developer and code that in LAL directly if he needs.
    clauses:foreach(function (c)
        if (c[1] == 'test') then
            oC:append(c[2])

            local test_value_is_needed = not(c[3] and not c[4])

            if (test_value_is_needed) then
                oC:p('%s = %s;', test_var, c[2]:value())
                oC:p('if (%s) then', test_var)
            else
                oC:p('if (%s) then', c[2]:value())
            end

            if (c[3]) then
                oC:append(c[3], 1)

                if (not c[3]:isReturning()) then
                    if (c[4]) then
                        local expr_val =
                            string.format("%s(%s)", c[3]:value(), test_var)

                        if (bIsTail) then
                            oC:p('    return %s;', expr_val)
                        else
                            all_return = false
                            oC:p('    %s = %s;', ret_val, expr_val)
                        end
                    else
                        all_return = false
                        oC:p('    %s = %s;', ret_val, c[3]:value())
                    end
                end

            else
                -- return test value
                oC:p('    %s = %s;', ret_val, test_var)
            end
            oC:p('else');
            open_if_count = open_if_count + 1

        else -- else branch
            -- TODO: optimize away the last unneccessary else-branch if we
            --       don't have an else branch and are returning anyways!
            --       This is important, as we need to call everything in proper
            --       tail context!
            oC:append(c[2], 1)
            if (not c[2]:isReturning()) then
                all_return = false
                oC:p('    %s = %s;', ret_val, c[2]:value())
            end
            for i = 1, open_if_count do
                oC:p('end;')
            end
        end
    end)

    oC:sideeffectFreeExpressionValue()
    oC:pV('%s', ret_val)

    if (all_return) then
        oC:mergeUnusedValue()
        oC.bIsReturning = true
    end

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_methcall(bIsTail)
    local sCallType  = self.LArgs:shift()
    local sFieldName = utl.strip_kw(self.LArgs:shift())

    local oRetC, LArgs = self:handleReturnedChunks(self.LArgs[1])
    if (oRetC) then return oRetC end

    local oC = self:chunk()
    oC:appendChunks(LArgs)

    local oCInst = LArgs:shift()

    oC:statementValue()

    if (string.match(sFieldName, "[^A-Za-z0-9_]")) then
        sFieldName = string.format("['%s']", sFieldName)

        if (sCallType == ':') then
            local sInstVar = oC:declTmpVar("inst", oCInst:value())
            if (#LArgs > 0) then
                oC:pV('(%s)%s(%s,%s)', sInstVar, sFieldName, sInstVar, concatChunkValues(LArgs, ","))
            else
                oC:pV('(%s)%s(%s)', sInstVar, sFieldName, sInstVar)
            end
        else
            oC:pV('((%s)%s)(%s)', oCInst:value(), sFieldName, concatChunkValues(LArgs, ","))
        end
    else
        if (sCallType == ':') then
            oC:pV('(%s):%s(%s)', oCInst:value(), sFieldName, concatChunkValues(LArgs, ","))
        else
            oC:pV('(%s).%s(%s)', oCInst:value(), sFieldName, concatChunkValues(LArgs, ","))
        end
    end

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_methcall_runtime(bIsTail)
    local sCallType  = utl.strip_sym(self.LArgs:shift())

    local oRetC, LArgs = self:handleReturnedChunks(self.LArgs[1])
    if (oRetC) then return oRetC end

    local oC = self:chunk()
    oC:appendChunks(LArgs)

    local oCFName = LArgs:shift()
    local oCInst  = LArgs:shift()
    local sTVFName = oC:declTmpVar('fname', oCFName:value())
    local sTVInst  = oC:declTmpVar('inst', oCInst:value())

    oC:expressionValue()
    if (sCallType == ':') then
        oC:pV("((%s)[strip_sym(%s)](%s, %s))", sTVInst, sTVFName, sTVInst, concatChunkValues(LArgs, ","))
    else
        oC:pV("((%s)[strip_sym(%s)](%s))", sTVInst, sTVFName, concatChunkValues(LArgs, ","))
    end

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_do_loop(bIsTail)
    local oTestC = self.LArgs[1]:gen(false)
    if (oTestC:isReturning()) then return oTestC end

    local oResExprC = self.LArgs[2]:gen(bIsTail)
    local oBlockC   = self.LArgs[3]:gen(false)

    local oC = self:chunk()

    oC:append(oTestC)
    oC:p('while not(%s) do', oTestC:value())

    oBlockC:mergeUnusedValue()
    oC:append(oBlockC, 1)

    oC:p('end;')
    oC:appendWithValue(oResExprC)

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_jump_block(bIsTail)
    local sLabel  = self.LArgs[1]
    local oBlockC = self.LArgs[2]:gen(bIsTail)

    local oC = self:chunk()
    oC:p('local %s_val;', sLabel)
    if (oBlockC:isReturning()) then
        oBlockC:mergeUnusedValue()
        oC:append(oBlockC)
    else
        oC:append(oBlockC)
        oC:p('%s_val = %s;', sLabel, oBlockC:value())
    end
    oC:p('::%s::', sLabel)
    oC:sideeffectFreeExpressionValue()
    oC:pV('%s_val', sLabel)
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_return_from(bIsTail)
    local sLabel = self.LArgs[1]
    local oC     = self:chunk()
    local oCVal  = self.LArgs[2]:gen(false)
    oC:append(oCVal)
    oC:p('%s_val = %s;', sLabel, oCVal:value())
    oC:p('goto %s;', sLabel)
    oC:sideeffectFreeExpressionValue()
    oC:pV('nil')
    oC.bIsReturning = true;
    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_load_lua_libs(bIsTail)
    local mLibs   = self.LArgs[1]
    local mBltins = self.LArgs[2]
    local oC      = self:chunk()
    local oCVal   = self.LArgs[3]:gen(bIsTail)

    for k, v in pairs(mLibs) do
        local sReq = oC:declTmpVar('req', "_lal_lua_base_require '" .. k .. "'")
        for lal_name, lua_name in pairs(v) do
            oC:p('local %s = %s[%s];',
                 lua_name, sReq, utl.quote_lua_string(lal_name))
        end
    end

    local sUtlV
    for lal_name, bltin in pairs(mBltins) do
        oC:p("local %s = %s;", lal_name, bltin.name)
    end

    oC:appendWithValue(oCVal)

    return oC
end
-----------------------------------------------------------------------------

function CodeNode:gen_display_compile_output(bIsTail)
    local out_chunk = self.LArgs[2]:gen(bIsTail)
    out_chunk:print_debug_output(self.LArgs[1])
    return out_chunk
end
-----------------------------------------------------------------------------

return CodeNode
