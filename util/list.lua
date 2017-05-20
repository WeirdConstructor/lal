-- See Copyright Notice in lal.lua

local class = require 'lal.util.class'
-----------------------------------------------------------------------------

local List = class()

--[[
<LListObject> = List([<lTable>])
    Creates a new List object which is either empty or has <lTable>
    as contents.

        local LList = List { 1, 2, 3, 4 }
        LList:foreach(function (nNum)
            print("Number: " .. tostring(nNum))
        end)

        local LStack = List()
        LStack:push(1)
        LStack:push(2)
        LStack:push(3)

    You can quickly get the length of the list object with the '#'
    operator and access an element using the index '[]' operator:

        for i = 1, #LList do
            print("Elem: " .. tostring(LList[i]))
        end

    You can add new elements using the '<<' operator:

        local LList = List() << 1 << 2

]]
function List:init(lList)
    if (lList) then
        self.data = lList
    else
        self.data = { }
    end
end

--[[
<nil or iIndex> = LList:idxOf(<fSearchOp: <vElem>, <iIdx> >)
    Iterates through the list and calls <fSearchOp> with the
    element as first argument and the index as second argument.
    It returns either <nil> if nothing was found, or the <iIndex>
    the element that matches first is to find at.

        List({"bla", "blubb", "foobar"):idxOf(function (sStr)
            return sStr == "foobar"
        )
]]
function List:idxOf(fOp)
    for i, v in ipairs(self.data) do
        if (fOp(v, i)) then
            return i
        end
    end
end

--[[
<nil or vValue> = LList:valOf(<fSearchOp: <vElem>, <iIdx> >)
    Iterates through the list and calls <fSearchOp> with the
    element as first argument and the index as second argument.
    It returns either <nil> if nothing was found, or the <vValue>
    the element that matches first.

        List({"bla", "blubb", "foobar"):valOf(function (_, iIdx)
            return iIdx % 2 == 0
        )
]]
function List:valOf(fOp)
    for i, v in ipairs(self.data) do
        if (fOp(v, i)) then
            return v
        end
    end
end

--[[
<LFilteredList> = LList:filter(<fFilterOp: <vElem>, <iIdx> >)
    Iterates through the list and returns a new list with the elements
    where <fFilterOp> returns true.

        local LEven = List({1, 2, 3, 4, 5, 6}):filter(function (nNum)
            return nNum % 2 == 0
        end)
]]
function List:filter(fOp)
    local lRet = { }
    for i, v in ipairs(self.data) do
        if (fOp(v, i)) then
            table.insert(lRet, v)
        end
    end
    return List(lRet)
end

--[[
<LFilteredList>, <LFilteredItems> = LList:filter2(<fFilterOp: <vElem>, <iIdx> >)
    Iterates through the list and returns a new list with the elements
    where <fFilterOp> returns true and as second return value a list with
    the elements where <fFilterOp> returned false.

        local LEven, LOdd = List({1, 2, 3, 4, 5, 6}):filter2(function (nNum)
            return nNum % 2 == 0
        end)
]]
function List:filter2(fOp)
    local lRet1 = { }
    local lRet2 = { }
    for i, v in ipairs(self.data) do
        if (fOp(v, i)) then
            table.insert(lRet1, v)
        else
            table.insert(lRet2, v)
        end
    end
    return List(lRet1), List(lRet2)
end

function List:map(fOp)
    local lRet = { }
    for i, v in ipairs(self.data) do
        local v = fOp(v, i)
        if (v ~= nil) then
            table.insert(lRet, v)
        end
    end
    return List(lRet)
end

function List:foreach(fOp)
    for i, v in ipairs(self.data) do
        fOp(v, i)
    end
    return self
end

function List:forAppend(nStart, nEnd, nStep, fOp)
    if (type(nStep) == "function") then
        fOp  = nStep
        nStep = nil
    end
    if (not nStep) then nStep = 1 end

    for i = nStart, nEnd, nStep do
        table.insert(self.data, fOp(i))
    end

    return self
end

function List:forPrepend(nStart, nEnd, nStep, fOp)
    if (type(nStep) == "function") then
        fOp  = nStep
        nStep = nil
    end
    if (not nStep) then nStep = 1 end

    for i = nStart, nEnd, nStep do
        table.insert(self.data, 1, fOp(i))
    end

    return self
end

function List:forInsert(nStart, nEnd, iIdx, nStep, fOp)
    if (type(nStep) == "function") then
        fOp  = nStep
        nStep = nil
    end
    if (not nStep) then nStep = 1 end

    for i = nStart, nEnd, nStep do
        table.insert(self.data, iIdx, fOp(i))
        iIdx = iIdx + 1
    end

    return self
end

function List:combine(fOp, vComb)
    for i, v in ipairs(self.data) do
        if (vComb == nil) then
            vComb = v
        else
            vComb = fOp(vComb, v, i)
        end
    end
    return vComb
end

function List:concat(sSep)
    return table.concat(self.data, sSep)
end

function List:insert(iIdx, oList)
    for i, v in ipairs(oList.data) do
        table.insert(self.data, iIdx + (i - 1), v)
    end
end

function List:append(oList)
    for i, v in ipairs(oList.data) do
        table.insert(self.data, v)
    end
end

function List:appendKeys(mMap)
    for k, _ in pairs(mMap) do
        self:push(k)
    end
end

function List:__shl(vValue)
    if (type(vValue) == "table") then
        if (getmetatable(self) == getmetatable(vValue)) then
            self:append(vValue)
        else
            for _, v in ipairs(vValue) do
                table.insert(self.data, v)
            end
        end
    else
        table.insert(self.data, vValue)
    end
    return self
end

function List:unshift(v)
    table.insert(self.data, 1, v)
end

function List:push(v)
    table.insert(self.data, v)
end

function List:pop()
    return table.remove(self.data)
end

function List:shift()
    local v = self.data[1]
    table.remove(self.data, 1)
    return v
end

function List:peekEnd()
    if (#(self.data) > 0) then
        return self.data[#self.data]
    end
    return nil
end

function List:table()
    return self.data
end

function List:__index(vIdx)
    if (type(vIdx) == "number") then
        return rawget(self.data, vIdx)
    else
        return rawget(getmetatable(self) or self or {}, vIdx)
    end
end

function List:__len()
    return #self.data
end

function List:subdivide(iElemCount)
    local LDivList = List()

    local LCurList = List()
    self:foreach(function (v, i)
        LCurList:push(v)
        if (#LCurList >= iElemCount) then
            LDivList:push(LCurList)
            LCurList = List()
        end
    end)
    if (#LCurList > 0) then
        LDivList:push(LCurList)
    end

    return LDivList
end

function List:divide(iPartitions)
    local iPartLen = math.floor(#self / iPartitions)
    if (iPartLen <= 0) then iPartLen = 1 end

    local LParts = List()
    for i = 1, iPartitions do
        LParts:push(List())
    end

    self:foreach(function (v, i)
        LParts[((i - 1) % iPartitions) + 1]:push(v)
    end)

    return table.unpack(LParts:table())
end

function List:sort(fComp)
    table.sort(self.data, fComp)
    return self
end

function List:takeN(iN)
    return self:filter(function(v, i) return i <= iN end)
end

function List:reverse()
    local lData = {}
    for i, v in ipairs(self.data) do
        lData[#self.data - (i - 1)] = v
    end
    return List(lData)
end

function List:LCS(LItem)
    local lM = { }

    for i = 1, #self.data + 1 do
        lM[i] = { }
        for j = 1, #LItem + 1 do
            lM[i][j] = 0
        end
    end

    for i = 1, #self.data do
        for j = 1, #LItem.data do
            if (self.data[i] == LItem.data[j]) then
                lM[i + 1][j + 1] = lM[i][j]
            else
                local nA = lM[i][j + 1] + 1
                local nB = lM[i + 1][j] + 1
                local nC = lM[i][j]     + 1
                local X = nA
                if (X > nB) then X = nB end
                if (X > nC) then X = nC end
                lM[i + 1][j + 1] = X
            end
        end
    end

    return lM[#self.data + 1][#LItem.data + 1]
end

return List
--$ return List({1, 2, 3, 5}):LCS(List({1, 2, 3, 5, 3, 3, 3, 4}))
--$ 
