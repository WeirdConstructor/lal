-- See Copyright Notice in lal.lua

local utl           = require 'lal.lang.util'
local Parser        = require 'lal.lang.parser'
local opt_builtins  = require 'lal.lang.opt_builtins'

if (not table.move) then
    -- Thank to the keplerproject https://github.com/keplerproject/lua-compat-5.3/blob/master/compat53/module.lua
    -- Released under:
    --      The MIT License (MIT)
    --      Copyright (c) 2015 Kepler Project.
    table.move = function (a1, f, e, t, a2)
         a2 = a2 or a1
         if e >= f then
            local m, n, d = 0, e-f, 1
            if t > f then m, n, d = n, m, -1 end
            for i = m, n, d do
               a2[t+i] = a1[f+i]
            end
         end
         return a2
    end
end

local builtins = opt_builtins.builtins
-----------------------------------------------------------------------------
-- TODO: add read/write
-- TODO: make display print all strings properly unquoted like Scheme demands
-- TODO: provide the i/o library from scheme as far as possible

local function port_write(port, str)
    if (type(port) == "userdata") then
        port:write(str)

    elseif (type(port) == "table") then
        table.insert(port, str)

    else
        io.stdout:write(str)
    end
end
-----------------------------------------------------------------------------

--[[ @io procedure (open-output-string)

Creates an output port for use everywhere in LAL where a _port_
is required. (See also `(display ...)` or `(write ...)` for example).

Inplace of a _port_ you can always pass a list (Lua table)
that will be modified by the output procedures.

    (let ((out (open-output-string)))
        (display '(x "foobar") out)
        (get-output-string out))
    ;=> "xfoobar"

    (let ((out []))
        (display '(x "foobar") out)
        (get-output-string out))
    ;=> "xfoobar"
]]
builtins["open-output-string"] = function () return {} end
-----------------------------------------------------------------------------

--[[ @io procedure (get-output-string _port_)

This method returns the complete output that was written to _port_.
_port_ must be the return value of `(open-output-string)`.

Alternatively you may pass a list, which is then concatenated
and the string of that is returned.

    (let ((out (open-output-string)))
        (display '(x "foobar") out)
        (get-output-string out))
    ;=> "(x foobar)"

    (let ((out []))
        (display '(x "foobar") out)
        (get-output-string out))
    ;=> "(x foobar)"
]]
builtins["get-output-string"] = function (port)
    if (type(port) ~= "table") then
        error("Argument to get-output-string is not a list "
              .. "or the return value of (open-output-string)!")
    end

    return table.concat(port)
end
-----------------------------------------------------------------------------

--[[ @io procedure (display _value_ [_port_])

This procedure prints a human readable representation of _value_.
In case of _value_ being a string, the string is printed directly.
Other values will be printed as if passed to `write`.

_port_ may be any Lua filehandle (for example `lua-io-stdout`)
or the result of `(open-output-string)`.

    (display "Hello World!") ;stdout=> Hello World!
    (display '(1 2 3 x))     ;stdout=> (1 2 3 x)

    (begin
        (import lua-io)
        (display '(foo bar) lua-io-stderr))
]]
builtins['display'] = function (v, port)
    local output = Parser.lal_print_string(v, nil, true)
    port_write(port, output)
    return output
end
-----------------------------------------------------------------------------

--[[ @io procedure (displayln _value_ [_port_])

Same as `display`, but with an additional `newline` afterwards.
]]
builtins['displayln'] = function (v, port)
    local output = Parser.lal_print_string(v, nil, true)
    port_write(port, output)
    port_write(port, "\n")
    return output
end
-----------------------------------------------------------------------------

--[[ @io procedure (write _value_ [_port_])

This procedure prints a serialized representation of _value_, that
can be read using `read` or `read-str` later.

_port_ may be any Lua filehandle (for example `lua-io-stdout`)
or the result of `(open-output-string)`.

    (write "Hello World!") ;stdout=> "Hello World!"
    (write '(1 2 3 x))     ;stdout=> (1 2 3 x)

    (begin
        (import lua-io)
        (write '(foo bar) lua-io-stderr))
]]
builtins['write'] = function (v, port)
    local output = Parser.lal_print_string(v)
    port_write(port, output)
    return output
end
-----------------------------------------------------------------------------

--[[ @io procedure (writeln _value_ [_port_])

Same as `write`, but with an additional `newline` afterwards.
]]
builtins['writeln'] = function (v, port)
    local output = Parser.lal_print_string(v)
    port_write(port, output)
    port_write(port, "\n")
    return output
end
-----------------------------------------------------------------------------

--[[ @io procedure (newline [_port_])

This procedure writes an end of line to the _port_.
See also `(display)`.

    (begin
      (display "Hello World!")
      (newline) ;stdout=> Hello World!\n
]]
builtins['newline'] = function (v, port)
    port_write(port, "\n")
    return "\n"
end
-----------------------------------------------------------------------------

builtins['symbol=?'] = function (...)
    local v = table.pack(...)
    local first_sym = v[1]
    for i = 1, v.n do
        if (not utl.is_sym(v[i]))  then return false end
        if (first_sym ~= v[1])     then return false end
    end
    return true
end
-----------------------------------------------------------------------------

--[[ @symbols procedure (keyword? _value_)

Returns true if _value_ is a keyword. A keyword in LAL is a special form
of symbols, which always evaluate to themself. Any symbol that ends with
a colon `:` is a keyword.

(On the Lua side these are represented by a "\xFD" prefixed string.)

    (keyword? 'foobar)      ;=> false
    (keyword? foobar:)      ;=> true
    (keyword? "foobar")     ;=> false
    (keyword? "\xFElol")    ;=> false
    (keyword? "\xFDlol")    ;=> true
]]
builtins['keyword?'] = utl.is_kw
-----------------------------------------------------------------------------

--[[ @lists procedure (nil? _value_)

Returns true if _value_ is the `nil` value.
And only then.

    (nil?   nil)     ;=> #t
    (nil?   [])      ;=> #f
    (nil?   '())     ;=> #f
    (nil?   {})      ;=> #f
    (nil?   0)       ;=> #f
    (nil?   "")      ;=> #f
]]
builtins['nil?'] = utl.is_nil
-----------------------------------------------------------------------------

builtins['list?'] = function (v)
    return utl.is_table(v) and (not(utl.is_nil(v[1])) or not next(v))
end
-----------------------------------------------------------------------------

builtins['string?'] = function (v) return type(v) == 'string' end
-----------------------------------------------------------------------------

builtins['map?'] = function (v)
    return utl.is_table(v) and utl.is_nil(v[1]) and not(not(next(v)))
end
-----------------------------------------------------------------------------

builtins['boolean?'] = function (v) return type(v) == 'boolean' end
-----------------------------------------------------------------------------

builtins['number?'] = function (v) return type(v) == 'number' end
-----------------------------------------------------------------------------

builtins['integer?'] = function (v) return type(v) == 'number' and math.type(v) == 'integer' end
-----------------------------------------------------------------------------

builtins['real?'] = function (v) return type(v) == 'number' and math.type(v) == 'float' end
-----------------------------------------------------------------------------

builtins['complex?'] = function (v) return false end
-----------------------------------------------------------------------------

builtins['rational?'] = function (v) return false end
-----------------------------------------------------------------------------

builtins['exact?'] = function (v) return type(v) == 'number' and math.type(v) == 'integer' end
-----------------------------------------------------------------------------

builtins['exact-integer?'] = builtins['exact?']
-----------------------------------------------------------------------------

builtins['inexact?'] = function (v) return type(v) == 'number' and math.type(v) == 'float' end
-----------------------------------------------------------------------------

builtins['zero?']              = function (v) return v == 0 end
builtins['positive?']          = function (v) return v >= 0 end
builtins['negative?']          = function (v) return v < 0 end
builtins['even?']              = function (v) return ((v % 2) == 0) end
builtins['odd?']               = function (v) return ((v % 2) == 1) end
-----------------------------------------------------------------------------

local function scheme_fmod(a, b)
    if ((a < 0 and b > 0) or (b < 0 and a >= 0)) then return -math.fmod(a, b)
    else                return math.fmod(a, b)
    end
end
local function scheme_truncatediv(a, b)
    local x = a / b
    return x < 0 and math.ceil(x) or math.floor(x)
end
builtins['floor/']             = function (a, b) return math.floor(a / b), scheme_fmod(a, b) end
builtins['floor-remainder']    = scheme_fmod
builtins['floor-quotient']     = function (a, b) return math.floor(a / b) end
builtins['truncate/']          = function (a, b) return scheme_truncatediv(a, b), math.fmod(a, b) end
builtins['truncate-remainder'] = math.fmod
builtins['truncate-quotient']  = scheme_truncatediv
builtins['quotient']           = builtins['truncate-quotient']
builtins['remainder']          = builtins['truncate-remainder']
builtins['modulo']             = builtins['floor-remainder']
-----------------------------------------------------------------------------

builtins['floor']              = math.floor
builtins['ceiling']            = math.ceil
builtins['truncate'] = function (x)
    return x < 0 and math.ceil(x) or math.floor(x)
end
builtins['round'] = function (x)
    return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end
-----------------------------------------------------------------------------

builtins['exp']                = math.exp
builtins['log']                = math.log
builtins['sin']                = math.sin
builtins['cos']                = math.cos
builtins['tan']                = math.tan
builtins['asin']               = math.asin
builtins['acos']               = math.acos
builtins['atan']               = math.atan
builtins['square']             = function (x) return x*x end
builtins['sqrt']               = math.sqrt
builtins['expt']               = function (a, b) return a^b end
-----------------------------------------------------------------------------

local function tostring_with_radix(n, b)
    if (not b or b == 10) then
        return tostring(n)
    end

    n = math.floor(n)

    local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end

    local digits_out = {}
    repeat
        local d = (n % b) + 1
        n       = math.floor(n / b)
        table.insert(digits_out, 1, digits:sub(d, d))
    until n == 0

    return sign .. table.concat(digits_out, "")
end
builtins['number->string'] = tostring_with_radix
builtins['string->number'] = tonumber
-----------------------------------------------------------------------------

local function gcd(a, b)
    if (not a) then a = 0 end
    if (not b) then b = 0 end

    while (b ~= 0) do
        a, b = b, a % b
    end
    return math.abs(a)
end
builtins['gcd'] = gcd
-----------------------------------------------------------------------------

builtins['lcm'] = function (a, b)
    local g = gcd(a, b)
    if (g == 0) then return 1 end
    return math.abs(a * b) / g
end
-----------------------------------------------------------------------------

builtins['concat'] = function (...)
    local v = table.pack(...); v.n = nil
    local lOut = { }
    for _, l in ipairs(v) do table.move(l, 1, #l, #lOut + 1, lOut) end
    return lOut
end
-----------------------------------------------------------------------------

builtins['concat!'] = function (...)
    local v = table.pack(...); v.n = nil
    local lOut
    for _, l in ipairs(v) do
        if (not lOut) then
            lOut = l
        else
            table.move(l, 1, #l, #lOut + 1, lOut)
        end
    end
    if (not lOut) then lOut = {} end
    return lOut
end
-----------------------------------------------------------------------------

builtins['append'] = function (...)
    local l = {}
    local v = table.pack(...);
    for i = 1, v.n do
        local e = v[i]
        if (i ~= v.n or utl.is_table(e)) then
            table.move(e, 1, #e, #l + 1, l)
        else
            table.insert(l, e)
        end
    end
    return l
end
-----------------------------------------------------------------------------

builtins['append!'] = function (l, ...)
    local v = table.pack(...);
    for i = 1, v.n do
        local e = v[i]
        if (i ~= v.n or utl.is_table(e)) then
            table.move(e, 1, #e, #l + 1, l)
        else
            table.insert(l, e)
        end
    end
    return l
end
-----------------------------------------------------------------------------

builtins['reverse'] = function (lin)
    local l = {}
    for i = 0, #lin - 1 do
        l[#lin - i] = lin[i + 1]
    end
    return l
end
-----------------------------------------------------------------------------

builtins['list-tail'] = function (l, k)
    if (#l < k) then
        error(string.format("List only has %d elements, but %d to be tailed.",
                            #l, k))
    end

    local lout = {}
    for i = k + 1, #l do
        lout[i - k] = l[i]
    end
    return lout
end
-----------------------------------------------------------------------------

--[[ @exceptions procedure (with-exception-handler _handler-func_ _func_)

Executes _func_ and catches any exception that was emitted using `(raise _value_)`
_handler-func_ is then executed using the _value_ passed to `raise`.

Please note, that no `(raise-continuable ...)` is available, due to
limitations of Lua exceptions.

    (with-exception-handler
        (lambda (err) err)
        (lambda ()
            (raise 42)
            99)) ;=> 42

See also `(error ...)`, `(raise ...)` and `(guard ...)`.
]]
builtins['with-exception-handler'] = function (handler, func)
    local bOk, val = pcall(func)
    if (not bOk) then
        if (utl.is_table(val)) then
            return handler(val[1])
        end
        return handler(val)
    end
    return val
end
-----------------------------------------------------------------------------

--[[ @exceptions procedure (error _msg_ _value_*)

This procedure works like `(raise ...)`, but it packs _msg_ and
any _value_ values into an error object which is then thrown.
You can detect error objects using `(error-object? ...)`
and catch then using `(with-exception-handler ...)` or `(guard ...)`.

    (with-exception-handler
        (lambda (err)
            (if (error-object? err)
                (display (error-object-message err))
                (display err)))
        (lambda ()
            (error "Something is wrong!" 193)))
    ;stdout=> Something is wrong!
]]
builtins['error'] = function (msg, ...)
    local irrit = table.pack(...)
    irrit.n = nil
    error { { t = "error-object", msg = msg, irritants = irrit } }
end
-----------------------------------------------------------------------------

--[[ @exceptions procedure (error-object? _value_)

Returns true if _value_ was created using `(error ...)`.

    (with-exception-handler
        (lambda (err)
            (if (error-object? err)
                (display (error-object-message err))
                (display err)))
        (lambda ()
            (error "Something is wrong!" 193)))
    ;stdout=> Something is wrong!
]]
builtins['error-object?'] = function (val)
    return utl.is_table(val) and val.t == "error-object"
end
-----------------------------------------------------------------------------

--[[ @exceptions procedure (error-object-message _value_)

If _value_ is an error object that was thrown using `(error ...)`
this procedure returns the message.
]]
builtins['error-object-message']  = function (val) return val.msg end
-----------------------------------------------------------------------------

--[[ @exceptions procedure (error-object-irritants _value_)

If _value_ is an error object that was thrown using `(error ...)`
this procedure returns the irritants or values that were passed.

    (with-exception-handler
        (lambda (err)
            (if (error-object? err)
                (error-object-irritants err)
                err))
        (lambda ()
            (error "Something is wrong!" 193)))
    ;=>(193)
]]
builtins['error-object-irritants'] = function (val) return val.irritants end
-----------------------------------------------------------------------------

--[[ @symbols procedure (symbol? _value_)

Returns true if _value_ is a symbol. A symbol is represented
as string that is prefixed with a `"\xFE"` character on the Lua
side.

Please note, that also a keyword is a symbol.

    (symbol? 'foobar)      ;=> true
    (symbol? foobar:)      ;=> false
    (symbol? "foobar")     ;=> false
    (symbol? "\xFElol:")   ;=> true
    (symbol? "\xFDlol")    ;=> false
    (symbol? "\xFEabc")    ;=> true

]]
builtins["symbol?"] = utl.is_sym

--[[ @symbols procedure (symbol->string _sym-value_)

This procedure converts the symbol _sym-value_ to a string.

    (symbol->string 'x->y) ;=> "x->y"
]]
builtins["symbol->string"] = utl.strip_sym

--[[ @symbols procedure (string->symbol _string-value_)

This procedure converts the _string-value_ into a symbol.
This might be useful for matching certain symbols or writing macros.

    (string->symbol "foo-bar") ;=> foo-bar
]]
builtins["string->symbol"] = function (str) return '\xfe' .. tostring(str) end

--[[ @symbols procedure (keyword->string _sym-value_)

This procedure converts the keyword _sym-value_ to a string.
On symbols this procedure does the same as `symbol->string`.

    (keyword->string foo:)  ;=> "foo"
]]
builtins["keyword->string"] = utl.strip_kw

--[[ @symbols procedure (string->keyword _string-value_)

This procedure converts the _string-value_ into a keyword.

    (string->keyword "foo")     ;=> foo:
    (string->keyword "foo-bar") ;=> foo-bar:
]]
builtins["string->keyword"] = function (str) return '\xfd' .. tostring(str) end

--[[ @values procedure (write-str _value_)

This procedure serializes the value it gets as it's first argument
and returns a string representation of it.
The syntax is compatible with the LAL parser and the `read-str` procedure.

    (let ((somelist [1 2 3 [1 2 3] ])
          (clone (read-str (write-str somelist))))
      clone)
    ;=> [1 2 3 [1 2 3] ]

]]
builtins["write-str"] = Parser.lal_print_string

--[[ @values procedure (read-str _string_)

This procedure parses the _string_ and returns the value as LAL data structure.
This procedure basically calls into the LAL parser to read the LAL value.
It is meant to use in conjunction with the `write` procedure and
can be useful for storing data structures in files.

    (let ((somelist (read-str "(1 2 3 4 test)")))
      somelist)
    ;=>(1 2 3 4 test)

]]
builtins["read-str"] = Parser.lal_read_string

--[[ @strings procedure (str _value_*)

This is a shorthand for `(str-join "" _value_*)`.
It basically creates a human readable representation of each value
in string form like `(display ...)` would do and concatenates the
values.

    (let ((x (+ 1 2 3)))
        (str "foo" 123  x)) ;=> "foo1236"
]]
builtins["lal-print-string"] = Parser.lal_print_string

builtins["str"] = function (...)
    local t = {}
    for _, a in ipairs(table.pack(...)) do
        table.insert(t, Parser.lal_print_string(a, nil, true))
    end
    return table.concat(t);
end

--[[ @strings procedure (str-join _separator_ _value_*)

This procedure converts all _value_ arguments to a string using
the same internal procedure that `(display ...)` uses to convert
LAL values to strings. This means: strings, symbols, keywords, lists and
maps are converted into a human readable form. Strings are directly
inserted without a change, except when they are prefixed with
a symbol char `"\xFE"` or a keyword char `"\xFD"`.

    (str-join "," "one word" another-word: 'and-a-symbol '(1 2 3))
    ;=>"one word,another-word,and-a-symbol,(1 2 3)"

If you need the Lua equivalent, you are free to `(import (lua table))`
and use `(lua-table-concat ["\xFE;123" "foobar"] ",")`:

    (begin
        (import (lua table))
        (lua-table-concat [(quote "\xFE;123") "foobar"] ","))
    ;=>123,foobar   ; notice, that we don't have quotes. Thats because the
                    ; LAL printer recognizes Lua strings that start with "\xFE"
                    ; as symbols.
]]
builtins["str-join"] = function (sep, ...)
    local t = {}
    for _, a in ipairs(table.pack(...)) do
        table.insert(t, Parser.lal_print_string(a, nil, true))
    end
    return table.concat(t, sep);
end

--[[ @lists procedure (cons _item-value_ _list-value_)

Forms a new list that contains _item-value_ followed by
the contents of _list-value_. It does a shallow copy of _list-value_.

    (cons 'a ['b 'c]) ;=> (a b c)
]]
builtins["cons"] = function (item, lst)
    local out = { item }
    table.move(lst, 1, #lst, 2, out)
    return out
end

--[[ @lists procedure (cons! _item-value_ _list-value_)

This prepends _item-value_ to _list-value_ by mutating the _list-value_.

    (let ((l ['b 'c]))
      (cons! 'a l)
      l)
    ;=> (a b c)
]]
builtins["cons!"] = function(item, lst)
    table.insert(lst, 1, item)
    return lst
end

--[[ @lists procedure (list-ref _list_ _index_)

Returns the element at _index_ in _list_.

    (list-ref [1 :lol 3] 1) ;=> :lol

]]
builtins["list-ref"] = function (l, k) return l[k + 1] end

--[[ @lists procedure (list-set! _list_ _index_ _value_)

Assigns _value_ to _index_ in _list_.

    (let ((l [4 5 6]))
      (list-set! l 3 7)
      l)
    ;=> (4 5 6 7)

]]
builtins["list-set!"] = function (l, k, v) l[k + 1] = v; return v end

--[[ @lists procedure (pop! _list_ [_num_])

Removes the last _num_ elements (at least 1 if _num_ is not given)
from _list_ and returns it.

    (let ((l [8 9 10]))
      (pop! l)  ;=> 10
      (pop! l)  ;=> 9
      (pop! l)) ;=> 8
]]
builtins["pop!"] = function (l, k)
    if (not k) then k = 1 end
    if (k == 1) then
        local v = l[#l]
        l[#l] = nil
        return v
    else
        local r = {}
        for i = 1, k do r[i] = l[#l]; l[#l] = nil end
        return r
    end
end

--[[ @lists procedure (push! _list_ _value_)

Appends the _value_ to the end of _list_.
]]
builtins["push!"] = function (l, k)
    l[#l + 1] = k
    return k
end

builtins["strip-kw"] = utl.strip_kw
builtins["strip-sym"] = utl.strip_sym

--[[ @values procedure (equal? _value-a_ _value-b_)

Compares the two values _value-a_ and _value-b_ structurally.
This means, for structured values like lists or maps it does a recursive
comparsion. And for all other values, it returns what `(eqv? _value-a_ _value-b_)`
would return.

    (equal? '((a b) { :x 10 }) '((a b) { :x 10 })) ;=> #true

Please note that `equal?` returns false once it hits a cycle in any of the
values. Thats not perfect, but at least it will terminate.  This is a
difference to R7RS Scheme, which requires `equal?` to compare the data
structures even with cycles correctly.
(R5RS did not even require it to terminate.)
]]
local function equal_q(a, b, ref_map)
    if not(utl.is_table(a) and utl.is_table(b)) then
        return a == b
    end

    local a_is_map = utl.is_nil(a[1]) and not(not(next(a)))
    local b_is_map = utl.is_nil(b[1]) and not(not(next(b)))
    if (a_is_map ~= b_is_map) then return false end

    if (not ref_map) then ref_map = { } end
    if (ref_map[a] or ref_map[b]) then return false end
    ref_map[a] = true
    ref_map[b] = true

    if (a_is_map) then
        local count = 0
        for k, v in pairs(a) do
            if (not equal_q(v, b[k], ref_map)) then
                return false
            end
            count = count + 1
        end
        for k, v in pairs(b) do
            count = count - 1
        end
        return count == 0

    else
        if (#a ~= #b) then return false end
        for i = 1, #a do
            if (not equal_q(a[i], b[i], ref_map)) then
                return false
            end
        end
        return true
    end
end

builtins["equal?"] = equal_q

--[[ @arithmetic procedure (abs _num_)

Returns the absolute value of _num_.
]]
builtins["abs"] = math.abs

--[[ @arithmetic procedure (min _num_+)

Returns the minimum value of all _num_ arguments.
]]
builtins["min"] = math.min

--[[ @arithmetic procedure (max _num_+)

Returns the maximum value of all _num_ arguments.
]]
builtins["max"] = math.max

--[[ @exceptions procedure (raise _error-value_)

With this procedure you can throw errors using the Lua exception mechanism.
_error-value_ is usually a string that describes the error. But it can also
be something else of course.

    (with-exception-handler
      (lambda (err) (display (str :Exception ": " err)))
      (lambda ()
        (when (zero? 0)
              (raise "Something is weird!"))))
    ;stdout=> Exception: Something is weird!

See also `(error ...)`, `(with-exception-handler ...)` and `(guard ...)`
]]
builtins["raise"] = function (v) error({v}) end

builtins["lal-backtrace"] = utl.lal_backtrace

-- Lua runtime specific stuff that needs to be available:
builtins["lua-table-move"] = table.move
builtins["lua-table-pack"] = table.pack
builtins["lua-type"]       = type
builtins["lua-next"]       = next
builtins["lua-ipairs"]     = ipairs
builtins["lua-pairs"]      = pairs

builtins["eval"]= function (v, env)
    local Compiler = require 'lal.lang.compiler'
    local comp = Compiler(env)
    local sRet = comp:compile_toplevel(v)
    return utl.exec_lua(sRet, "LAL-EVAL")
end

builtins['compile-to-lua'] = function (v)
    local Compiler = require 'lal.lang.compiler'
    local comp = Compiler()
    local sRet = comp:compile_toplevel(v)
    return sRet
end

--[[ @control procedure (apply _proc_ [_arg1_ ... _argN_] [...])

Calls _proc_ with the elements of the appended lists as argument.

    (apply str-join "," ["X" "Y"]) ;=> "X,Y"
]]
builtins['apply'] = function (fun, ...)
    local v = table.pack(...)

    local args;
    if (v.n > 1) then
        args = v[v.n]
        v[v.n] = nil
        local n = v.n - 1
        v.n = n + #args
        for i = 1, #args do
            v[i + n] = args[i]
        end
        args = v
    elseif (v.n == 1) then
        args = v[1]
        args.n = 1;

    else
        args = { n = 0 }
    end

    return fun(table.unpack(args))
end

return builtins
