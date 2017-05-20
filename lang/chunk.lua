-- See Copyright Notice in lal.lua

local utl   = require 'lal.lang.util'
local class = require 'lal.util.class'

-----------------------------------------------------------------------------

local CodeChunk = class()
-----------------------------------------------------------------------------

function CodeChunk:init(expr_value)
    self.lOut               = {}
    self.lValueOut          = {}
    self.sValueType         = ''
    self.sValueCompileType  = 'unknown'
    self.sRawStringValue    = nil

    if (expr_value) then
        self:sideeffectFreeExpressionValue()
        self:pV('%s', expr_value)
    end
end
-----------------------------------------------------------------------------

function CodeChunk:print_debug_output(tag)
    local ret = ""
    if (self.isReturning) then
        ret = "returning"
    end
    print(string.format("LAL-COMPILE-OUT[%s] CHUNK{{{\n%s}}} VALUE[%s:%s:%s:%s]{{{ %s }}}",
                        tag,
                        self:chunk(1),
                        self.sValueType,
                        self.sValueCompileType,
                        self.sRawStringValue,
                        ret,
                        table.concat(self.lValueOut, "")))
end
-----------------------------------------------------------------------------

function CodeChunk:p_if_has_output(sFmt, ...)
    self.sPrepOut = string.format(sFmt, ...)
end
-----------------------------------------------------------------------------

function CodeChunk:p(sFmt, ...)
    table.insert(self.lOut, string.format(sFmt, ...))
end
-----------------------------------------------------------------------------

function CodeChunk:pV(sFmt, ...)
    table.insert(self.lValueOut, string.format(sFmt, ...))
end
-----------------------------------------------------------------------------

function CodeChunk:append(v, iIndent)
    local sIndent = ""
    if (iIndent) then
        sIndent = string.rep('    ', iIndent)
    end

    local prev_prep_out
    if (v.sPrepOut and #v.lOut > 0) then
        prev_prep_out = v.sPrepOut
        string.gsub(sIndent .. v.sPrepOut, '\n', '\n' .. sIndent)
        table.insert(self.lOut, v.sPrepOut)
    end

    for _, l in ipairs(v.lOut) do
        local sTxt =
            string.gsub(sIndent .. l, '\n', '\n' .. sIndent)
        table.insert(self.lOut, sTxt)
    end
end
-----------------------------------------------------------------------------

function CodeChunk:appendWithValue(oC, iIndent)
    self:append(oC, iIndent)
    self:valueFrom(oC)
end
-----------------------------------------------------------------------------

function CodeChunk:appendChunks(LChunks, iIndent)
    LChunks:foreach(function (oC)
        self:append(oC, iIndent)
    end)
end
-----------------------------------------------------------------------------

function CodeChunk:chunk(iIndent)
    local sIndent = ""
    if (iIndent) then
        sIndent = string.rep('    ', iIndent)
    end
    local lOut = {}
    if (self.sPrepOut) then
        table.insert(self.lOut, self.sPrepOut)
    end
    for i = 1, #self.lOut do
        lOut[i] = sIndent .. self.lOut[i]
    end
    table.insert(lOut, "") -- for extra newline
    return table.concat(lOut, "\n")
end
-----------------------------------------------------------------------------

function CodeChunk:value()
    if (#self.lValueOut <= 0) then
        return nil
    end

    if (self.sValueOutCache) then
        return self.sValueOutCache
    else
        self.sValueOutCache = table.concat(self.lValueOut)
        return self.sValueOutCache
    end
end
-----------------------------------------------------------------------------

function CodeChunk:compileType(sT, sRawString)
    self.sValueCompileType = sT
    self.sRawStringValue   = sRawString
    return self
end
-----------------------------------------------------------------------------

function CodeChunk:resetValue()
    self.lValueOut         = {}
    self.sValueType        = ''
    self.sValueOutCache    = nil
    self.sValueCompileType = 'unknown'
    self.sRawStringValue   = nil
end
-----------------------------------------------------------------------------

function CodeChunk:valueFrom(oC)
    self:resetValue()
    self.lValueOut         = oC.lValueOut
    self.sValueType        = oC.sValueType
    self.bIsReturning      = oC.bIsReturning
    self.sValueCompileType = oC.sValueCompileType
    self.sRawStringValue   = oC.sRawStringValue
end
-----------------------------------------------------------------------------

function CodeChunk:statementValue()
    self.sValueType = 'stmt'
end
-----------------------------------------------------------------------------

function CodeChunk:expressionValue()
    self.sValueType = 'expr'
end
-----------------------------------------------------------------------------

function CodeChunk:sideeffectFreeExpressionValue()
    self.sValueType = 'sideeffectFree'
end
-----------------------------------------------------------------------------

function CodeChunk:mergeUnusedValue()
    if (self.sValueType == 'stmt') then
        self:p('%s;', self:value())

    elseif (self.sValueType == 'expr') then
        self:p('local %s = %s;', utl.tmpvar('expr'), self:value())

    elseif (self.sValueType == 'sideeffectFree') then
        -- ignore it!
    elseif (self.bIsReturning) then
        -- ignore it too!
    else
        assert(false)
    end

    self:resetValue()
end
-----------------------------------------------------------------------------

function CodeChunk:mergeValueAsReturn()
    if (self:value()) then
        self:p('return %s;', self:value())
        self.bIsReturning = true
    end

    self:resetValue()
end
-----------------------------------------------------------------------------

function CodeChunk:isReturning()
    return self.bIsReturning
end
-----------------------------------------------------------------------------

function CodeChunk:mergeValueAsTmpVar(sPref)
    local sTmp = self:declTmpVar(sPref, self:value())
    self:resetValue()
    return sTmp
end
-----------------------------------------------------------------------------

function CodeChunk:declTmpVar(sPref, sVal)
    local sTV = utl.tmpvar(sPref)
    if (sVal) then self:p('local %s = %s;', sTV, sVal)
    else           self:p('local %s;',      sTV) end
    return sTV
end
-----------------------------------------------------------------------------

return CodeChunk
