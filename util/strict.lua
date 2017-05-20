-- See Copyright Notice in lal.lua
-- Modified version from Lua Wiki

-- strict.lua
-- checks uses of undeclared global variables
-- All global variables must be 'declared' through a regular assignment
-- (even assigning nil will do) in a main chunk before being used
-- anywhere or assigned to inside a function.
-- distributed under the Lua license: http://www.lua.org/license.html

local traceback, getinfo, error, rawset, rawget =
      debug.traceback, debug.getinfo, error, rawset, rawget
-----------------------------------------------------------------------------

local mt = getmetatable(_G)
if mt == nil then
    mt = {}
    setmetatable(_G, mt)
end

mt.__declared = {}
-----------------------------------------------------------------------------

function DECLARE(varname)
    if (type(varname) == "table") then
        for _, v in ipairs(varname) do
            -- log.trc("DECLARE: %1\n", v)
            mt.__declared[v] = true
        end
    else
        -- log.trc("DECLARE: %1\n", varname)
        mt.__declared[varname] = true
    end
end
-----------------------------------------------------------------------------

local err = function(msg)
    local coroThread, isMain = coroutine.running()
    if (isMain) then
        error(msg .. ", Traceback:\n" .. traceback(nil, 3))
    else
        error(msg .. ", Traceback:\n" .. traceback(coroThread, nil, 3))
    end
end
-----------------------------------------------------------------------------

mt.__newindex = function (t, n, v)
    if not mt.__declared[n] then
        err("assign to undeclared variable '" .. n .. "'")
    end
    rawset(t, n, v)
end
-----------------------------------------------------------------------------

mt.__index = function (t, n)
    if not mt.__declared[n] then
        err("variable '"..n.."' is not declared", 2)
    end
    return rawget(t, n)
end
