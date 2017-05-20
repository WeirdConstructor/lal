-- See Copyright Notice in lal.lua

local class = require 'lal.util.class'

local Logfile = class()

function Logfile:init(sPath)
    local fh, err = io.open(sPath, "a+")
    if (not fh) then
        print(string.format("Konnte Logfile '%s' nicht öffnen: %s\n", sPath, tostring(err)))
        return
    end
    self.h = fh
end

function Logfile:log(sFmt, ...)
    local l = table.pack(...)
    for i, v in ipairs(l) do
        if (type(v) == "table") then
            l[i] = bz.DumpStr(v)
        end
    end
    self.h:write(string.format(sFmt, table.unpack(l)))
end

function Logfile:close()
    self.h:close()
end

return Logfile
