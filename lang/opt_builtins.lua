-- See Copyright Notice in lal.lua

local utl      = require 'lal/lang/util'
local Node     = require 'lal/lang/codegen'
local List     = require 'lal/util/list'
-----------------------------------------------------------------------------

local builtins = {}
local synforms = {}
-----------------------------------------------------------------------------

local function opt_builtin(name, func, compile_func)
    builtins[name] = func
    synforms[name] = compile_func
end
-----------------------------------------------------------------------------

local function compile_lua_op_builtin_func(sOp)
    return load([[
        local lArgs = table.pack(...)
        local v = lArgs[1]
        for i = 2, #lArgs do v = v ]] .. sOp .. [[ lArgs[i] end
        return v
    ]], "op " .. sOp, "t")
end
-----------------------------------------------------------------------------

local function compile_lua_binop_builtin_func(sOp)
    return load([[
        local lArgs = table.pack(...)
        return lArgs[1] ]] .. sOp .. [[ lArgs[2]
    ]], "binop " .. sOp, "t")
end
-----------------------------------------------------------------------------

local function op(sOp, fCompileFunc, sName, is_binary)
    if (not sName) then sName = sOp end
    synforms[sName] = fCompileFunc
    if (is_binary) then
        builtins[sName] = compile_lua_binop_builtin_func(sOp)
    else
        builtins[sName] = compile_lua_op_builtin_func(sOp)
    end
end
-----------------------------------------------------------------------------

local function compile_lua_op(sOp, nArgs)
    return function (self, sF, v)
        if (nArgs and ((nArgs + 1) ~= #v)) then
            self:err("Operator %s expects %d arguments, got %d",
                     utl.strip_sym(sF), nArgs, #v - 1)
        end

        local LOpr = List()
        for i = 2, #v do LOpr:push(self:compile(v[i])) end
        return self:node('op', { sOp, LOpr })
    end
end
-----------------------------------------------------------------------------

--[[ @arithmetic procedure (+ _num-arg_+)

This procedure returns the sum of all _num-arg_ arguments.

    (let ((x 10)) (+ x 20)) ;=> 30
]]

--[[ @arithmetic procedure (- _num-expr_+)

This procedure returns the subtration of the second argument
(and following) from the first argument.

    (- 30 20 5) ;=> 5
    (- 10 20)   ;=> -10
]]

op('%',  compile_lua_op('%'))
op('+',  compile_lua_op('+'))
op('*',  compile_lua_op('*'))
op('-',  compile_lua_op('-'))
op('/',  compile_lua_op('/', 2), nil, true)
if (_VERSION == "Lua 5.3") then
    op('//', compile_lua_op('//'))
else
    op('//', compile_lua_op('/'))
end

--[[ @values procedure (= _value-a_ _value-b_ _value-x_*)

Compares all arguments, and returns true if they are equal in the
sense of `(eqv? ...)`. In Scheme this procedure only works on numbers,
but Lua doesn't have special number comparation operators, so we just
use the Lua `==`.
]]
op('==', compile_lua_op('=='), '=')
op('>',  compile_lua_op('>', 2), nil, true)
op('<',  compile_lua_op('<', 2), nil, true)
op('>=', compile_lua_op('>=', 2), nil, true)
op('<=', compile_lua_op('<=', 2), nil, true)
-----------------------------------------------------------------------------

--[[ @values procedure (eqv? _value-a_ _value-b_)

This procedure compares _value-a_ and _value-b_ using
the `==` operator from Lua. It basically returns true,
when the value's types are equal and their actual values are
equal. Only lists or maps that are stored in the same memory
location are equal.
]]
op('==', compile_lua_op('=='), 'eqv?', true)

--[[ @values procedure (eq? _value-a_ _value-b_)

This procedure is the same as `(eqv? ...)` in LAL
and not more fine grained than in Scheme.
]]
op('==', compile_lua_op('=='), 'eq?', true)
-----------------------------------------------------------------------------

--[[ @lists procedure (list _arg_+)

Returns a new list containing the values of the arguments.

    (list 1 2 3 4)   ;=> (1 2 3 4)
    (list 1 'x 3 4)  ;=> (1 x 3 4)
]]
opt_builtin('list', function (...)
    local l = table.pack(...); l.n = nil; return l

end, function (self, sF, v)
    local LE = List()
    for i = 2, #v do LE:push(self:compile(v[i])) end
    return self:node('list', LE:table())
end)
-----------------------------------------------------------------------------

--[[ @lists procedure (length _list-arg_)

Returns the length/number of items in _list-arg_.
Be aware that Lua tables can't have holes that contain `nil`.
]]
opt_builtin('length', function (v)
    return #v
end, function (self, sF, v)
    return self:node('count', { self:compile(v[2]) })
end)
-----------------------------------------------------------------------------

--[[ @lists procedure (map _function_ _list_+)

This procedure calls _function_ for each item in the _list_.
If multiple lists are passed, the _function_ is called with as many arguments
as there are lists.
The _function_ is called as long as there is still an item in any of the lists.

The return values of the _function_ are collected in a new list that
is returned.

    (let ((sum 0))
        (map (lambda (x)
                (set! sum (+ sum x)))
             '(1 2 3 4)))
    ;=> (1 3 6 10)

    (map (lambda (a b) [a b]) '(1 2) '(x y))
    ;=> ((1 x) (2 y))
]]
opt_builtin('map', Node.func_map, function (self, sF, v)
    if (#v < 3) then self:err("Bad 'map' form. Needs at least 2 arguments.") end

    local LArgs = List()
    for i = 2, #v do LArgs:push(self:compile(v[i])) end
    return self:node('mapF', LArgs:table())
end, false)
-----------------------------------------------------------------------------

--[[ @lists procedure (for-each _function_ _list_+)

This procedure calls _function_ for each item in the _list_.
If multiple lists are passed, the _function_ is called with as many arguments
as there are lists.
The _function_ is called as long as there is still an item in any of the lists.

In contrast to `map` this function does not collect the returned values
and only executed _function_ purely for it's side effects.

    (let ((sum 0))
        (for-each (lambda (x)
                (set! sum (+ sum x)))
             '(1 2 3 4)))
    ;=> 10

    (let ((out []))
      (for-each (lambda (a b) (append! out [a b])) '(1 2) '(x y))
      out)
    ;=> (1 x 2 y)
]]
opt_builtin('for-each', Node.func_forEach, function (self, sF, v)
    if (#v < 3) then self:err("Bad 'for-each' form. Needs at least 2 arguments.") end

    local LArgs = List()
    for i = 2, #v do LArgs:push(self:compile(v[i])) end
    return self:node('forEachF', LArgs:table())
end, false)
-----------------------------------------------------------------------------

--[[ @lists (empty? _list_)

Returns `#t` if _list_ is an empty list.
Same as `(null? ...)`.

    (empty?  [1 2 3]) ;=> #f
    (empty?  '())     ;=> #t
    (empty?  [])      ;=> #t
    (empty?  "")      ;=> #t
]]
opt_builtin('empty?', Node.func_emptyQ, function (self, sF, v)
    if (#v < 2) then self:err("Bad 'empty?' form, expected 1 arguments.") end
    return self:node('emptyQ', { self:compile(v[2]) })
end, true)
-----------------------------------------------------------------------------

--[[ @lists (null? _list_)

Returns `#t` if _list_ is an empty list.
Same as `(empty? ...)`.

But don't mix this up with `(nil? ...)`, which detects
the `nil` value.

    (null?  [1 2 3]) ;=> #f
    (null?  '())     ;=> #t
    (null?  [])      ;=> #t
    (null?  "")      ;=> #t
]]
opt_builtin('null?', Node.func_emptyQ, function (self, sF, v)
    if (#v < 2) then self:err("Bad 'null?' form, expected 1 arguments.") end
    return self:node('emptyQ', { self:compile(v[2]) })
end, true)
-----------------------------------------------------------------------------

opt_builtin('@', Node.func_at, function (self, sF, v)
    if (#v ~= 3) then self:err("Bad 'at' form, expected 2 arguments.") end
    return self:node('at', { self:compile(v[2]), self:compile(v[3]) })
end, true)
-----------------------------------------------------------------------------

opt_builtin('@!', Node.func_atM, function (self, sF, v)
    if (#v ~= 4) then self:err("Bad 'at' form, expected 3 arguments.") end
    return self:node('atM', { self:compile(v[2]), self:compile(v[3]), self:compile(v[4]) })
end, true)
-----------------------------------------------------------------------------

opt_builtin('$', Node.func_fld, function (self, sF, v)
    if (#v ~= 3) then self:err("Bad '$' form, expected 2 arguments.") end
    local LFields = List()
    for i = 2, #v do LFields:push(self:compile(v[i])) end
    return self:node('fieldAccess', LFields:table())
end, true)
-----------------------------------------------------------------------------

opt_builtin('$!', Node.func_fldM, function (self, sF, v)
    if (#v < 4) then self:err("Bad '$!' form, expected at least 3 arguments.") end
    local LFields = List()
    for i = 2, #v do LFields:push(self:compile(v[i])) end
    return self:node('fieldAccess', LFields:table())
end, true)
-----------------------------------------------------------------------------

local s_iGenSymCnt = 0
opt_builtin('gensym', function ()
    s_iGenSymCnt = s_iGenSymCnt + 1
    return string.format("\xfe_gs%d", s_iGenSymCnt)
end, nil, true)
-----------------------------------------------------------------------------

return { builtins = builtins, synforms = synforms }
