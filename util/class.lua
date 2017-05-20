-- See Copyright Notice in lal.lua

local function class()
    local class

    class = { }
    class.__index = class

    class = setmetatable(class, {
        __call = function (_, ...)
            local instance = setmetatable({ }, class)
            if (class.init) then instance:init(...) end
            return instance
        end
    })

    return class
end
return class
