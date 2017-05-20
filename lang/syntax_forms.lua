-- See Copyright Notice in lal.lua

local utl      = require 'lal/lang/util'
local Parser   = require 'lal/lang/parser'
local Node     = require 'lal/lang/codegen'
local List     = require 'lal/util/list'
-----------------------------------------------------------------------------

local synforms = { }

local lua_basic_lib = {
    ['lua-assert']         = "_lal_lua_base_assert",
    ['lua-collectgarbage'] = "_lal_lua_base_collectgarbage",
    ['lua-dofile']         = "_lal_lua_base_dofile",
    ['lua-error']          = "_lal_lua_base_error",
    ['lua-getmetatable']   = "_lal_lua_base_getmetatable",
    ['lua-ipairs']         = "_lal_lua_base_ipairs",
    ['lua-load']           = "_lal_lua_base_load",
    ['lua-loadfile']       = "_lal_lua_base_loadfile",
    ['lua-next']           = "_lal_lua_base_next",
    ['lua-pairs']          = "_lal_lua_base_pairs",
    ['lua-pcall']          = "_lal_lua_base_pcall",
    ['lua-print']          = "_lal_lua_base_print",
    ['lua-rawequal']       = "_lal_lua_base_rawequal",
    ['lua-rawget']         = "_lal_lua_base_rawget",
    ['lua-rawlen']         = "_lal_lua_base_rawlen",
    ['lua-rawset']         = "_lal_lua_base_rawset",
    ['lua-require']        = "_lal_lua_base_require",
    ['lua-select']         = "_lal_lua_base_select",
    ['lua-setmetatable']   = "_lal_lua_base_setmetatable",
    ['lua-tonumber']       = "_lal_lua_base_tonumber",
    ['lua-tostring']       = "_lal_lua_base_tostring",
    ['lua-type']           = "_lal_lua_base_type",
    ['lua-xpcall']         = "_lal_lua_base_xpcall",
    ['lua-VERSION']        = "_lal_lua_base__VERSION",
    ['lua-math']           = "_lal_lua_base_math",
    ['lua-table']          = "_lal_lua_base_table",
    ['lua-string']         = "_lal_lua_base_string",
    ['lua-G']              = "_lal_lua_base__G",
    ['lua-ENV']            = "_ENV",
}
-----------------------------------------------------------------------------

local lua_aux_libs = {
    ['debug']     = debug,
    ['coroutine'] = coroutine,
    ['io']        = io,
    ['os']        = os,
    ['package']   = package,
    ['string']    = string,
    ['math']      = math,
    ['table']     = table,
    ['utf8']      = utf8,
}
-----------------------------------------------------------------------------

local syntax_compiler = {}
local lal_libs = {
    ['syntax-compiler']    = syntax_compiler,
}
-----------------------------------------------------------------------------

local s_library_cache = {}

local function gen_lib_paths(library_name, path)
    local base_path = path .. "/" .. string.gsub(library_name, "-", "/")
    local lib_subname_path     = base_path .. ".lal"
    local lib_subname_out_path = base_path .. "_out.lua"
    return lib_subname_path, lib_subname_out_path
end

local function find_and_compile_import_library(self, library_name)
    local lal_lib_path = os.getenv("LALRT_LIB") .. "/lal"

--    local sRTLib = string.match(library_name, "lal%-([^-]*)")
--    if (not sRTLib) then
--        self:err("Bad lal library name format: %s", library_name)
--    end
    local lib_subname_path, lib_subname_out_path =
        gen_lib_paths(library_name, ".");
    local fh_lal_lib = io.open(lib_subname_path, "r");
    if (fh_lal_lib) then
        fh_lal_lib:close();
    else
        lib_subname_path, lib_subname_out_path =
            gen_lib_paths(library_name, lal_lib_path);
    end

    local require_name = string.gsub(library_name, "-", ".") .. "_out"

    -- TODO: Check how old the already present file is, and compare
    --       with the lal file.
--    local fh_lua_lib = io.open(lib_subname_out_path, "r")
--    if (fh_lua_lib) then
--        fh_lua_lib:close()
--        return lib_subname_out_path, require_name, lib_subname_path
--    end

    local fh = io.open(lib_subname_path, "r")
    if (not fh) then
        self:err("Couldn't find lal library %s in %s\n",
                 library_name, lib_subname_path)
    end

    local lib_lal_code = fh:read('*a')
    if (not lib_lal_code) then
        self:err("Unable to read %s.", lib_subname_path)
    end

    fh:close()

    local lib_lua_code =
        self.compile_lal_code(lib_lal_code, nil, lib_subname_path)

    local ofh = io.open(lib_subname_out_path, "w")
    ofh:write(lib_lua_code)
    ofh:close()

    return lib_subname_out_path, require_name, lib_subname_path
end
-----------------------------------------------------------------------------

--[[ @environment syntax (import _import-spec_+)

Where _import-spec_ may be one of:

* _library-name_    - A list of identifiers and numbers

	(import	(lua basic))
	(import	(lua math))

	(lua-print (lua-math-floor 3.2))
	;stdout=> 3

Following (builtin) libraries are available:

* `(lua string)`
* `(lua math)`
* `(lua table)`
* `(lua package)`
* `(lua debug)`
* `(lua io)`
* `(lua utf8)`
* `(lua basic)`

See the Lua documentation for the contents of the
corresponding packages. The __(lua basic)__ package
is a special case. The contents of it is not
prefixed with `lua-basic` but directly with `lua-`.

When LAL is run within LALRT, it provides the
LALRT specific packages under the `rt` libraries:

* `(rt log)`
* `(rt utl)`
* `(rt gfx)`
* `(rt sys)`
* `(rt mp)`
* ...

Imported symbols from any of those libraries are prefixed with
their respective package name, like `mp-wait`.

Please note, that these packages (`rt`) are only meaningful inside LALRT,
other runtime environments probably provide other globally
accessible packages.
]]
synforms['import'] = function (self, sF, v)
    for i = 2, #v do
        local library_name
        if (utl.is_sym(v[i])) then
            library_name = utl.strip_sym(v[i])
        else
            local lib_name_syms = v[i]
            local lib_name_parts = {}
            for _, sym in ipairs(lib_name_syms) do
                table.insert(lib_name_parts, utl.strip_kw(tostring(sym)))
            end
            library_name = table.concat(lib_name_parts, "-")
        end

        if (library_name == 'lua-basic') then
            local mIncls = {}
            for k, v in pairs(lua_basic_lib) do
                mIncls[k] = {
                    sType = "lua_env_builtin",
                    name  = v,
                }
            end
            self:import_library(mIncls)

        elseif (string.sub(library_name, 1, 4) == 'lua-') then
            local lib_name = string.sub(library_name, 5)
            local aux_lib = lua_aux_libs[lib_name]
            if (not aux_lib) then
                self:err("Unknown Lua library to import: %s", library_name)
            end

            for k, v in pairs(aux_lib) do
                self.mGlobalEnv[library_name .. "-" .. k] = {
                    sType = "lua_env_builtin",
                    name  = "_lal_lua_base_" .. lib_name .. "." .. k,
                }
            end

        elseif (string.sub(library_name, 1, 4) == 'lal-') then
            local lib_name = string.sub(library_name, 5)
            local lal_lib = lal_libs[lib_name]

            if (not lal_lib) then
                self:err("LAL library not found: %s", lib_name)
            end
            for k, v in pairs(lal_lib) do
                self:setEnv("\xFE" .. library_name .. "-" .. k, { sType = "syntax", func = v })
            end

        elseif (string.sub(library_name, 1, 3) == 'rt-') then
            local sRTLib = string.match(library_name, "rt%-([^-]*)")
            if (not sRTLib) then
                self:err("Bad runtime library name format: %s", library_name)
            end

            if (not _ENV[sRTLib]) then
                self:err("Unknown/Unavailable runtime library: %s", library_name)
            end

            for k, v in pairs(_ENV[sRTLib]) do
                local lal_name = string.gsub(k, "Q$", "?")
                lal_name = string.gsub(lal_name, "M$", "!")
                lal_name = string.gsub(lal_name, "S$", "*")
                lal_name = string.gsub(lal_name, "([a-z])([A-Z])", function (a, b)
                    return a .. "-" .. string.lower(b)
                end)
                self.mGlobalEnv[sRTLib .. "-" .. lal_name] = {
                    sType = 'lua_env_builtin',
                    name  = '_lal_lua_base_' .. sRTLib .. '.' .. k,
                }
            end
        else
            local path, req_file, lal_file = find_and_compile_import_library(self, library_name)
            local lib = loadfile(path)()
            if (type(lib) ~= "table") then
                self:err("Couldn't load library '" .. library_name .. "' from "
                         .. lal_file ..": It doesn't return a map of symbols and functions!")
                return
            end

            for k, v in pairs(lib) do
                local id = library_name .. "-" .. k
                self.mGlobalEnv[id] = {
                    sType    = 'builtin',
                    file     = req_file,
                    in_lib_name = k,
                }

                if (type(v) == "table" and v.sType == "primitive-macro") then
                    self:setEnv("\xfe" .. id, v);
                end
            end
        end
    end
    return self:node('nil')
end
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------

synforms['define-library'] = function (self, sF, v)
    local lib_name      = List()
    local lib_name_node = List()
    for _, n in ipairs(v[2]) do
        lib_name:push(n)
        lib_name_node:push(self:compile(n))
    end

    --[[
        TODO

        (define-library (lal srfi 132)
          (export list-sort list-stable-sort list-sort! list-stable-sort!)
          (begin
            (define (list-sort o l)
              #;(...)))
            (define (list-sort! o l)
              #;(...)))
          (include "stable-sort-impl.lal"))

        stable-sort-impl.lal=============== START

        (define (list-stable-sort o l) #;(...))
        (define (list-stable-sort! o l) #;(...))

        =================================== END


        =>

        begin -- scope
            -- (begin ...) block:
            local list_sort;  list_sort = function () ... end
            local list_sort!; list_sort! = function () ... end
            -- (include ...) stuff:
            local list_stable_sort;  list_stable_sort = function () ... end
            local list_stable_sort!; list_stable_sort! = function () ... end

            -- We need to walk the current mEnv at this point
            -- and generate the following library "declaration":
            return {
                ["list-sort"]  = list_sort,
                ["list-sort!"] = list_sortQ,
                ["list-stable-sort"]  = list_sort,
                ["list-stable-sort!"] = list_sortQ,
            }
        end


        (import (lal srfi 132))
        ; 1. search for some filename and evaluate the contents
        ; 2. store the return value in parallel to the environment
        ;    (it contains the return {...} value of the above begin-end block.
        ; 3. plug the corresponding entries of that library into the
        ;    global environment while compiling the (import ...) directive.
        ;    It's possible to exclude and include and rename stuff from the
        ;    library at this point.
        ; This way importing a library is absolutely no runtime overhead.
    ]]

--    local oLet = self:node('scope', { self:node('block', LStmts:table()) })

    local lib_name_gen = self:node('list', lib_name_node)
end
-----------------------------------------------------------------------------

--[[ @values syntax (quasiquote _value_) reader-syntax: ``_value_

This is LALs quasiquotation. It quotes the _value_ in such a way,
that it evaluates to itself. If the _value_ is a list, then the
special quasiquote syntaxes `(unquote ...)` and `(unquote-splicing ...)`
are evaluated and expanded properly.

This syntax is usually very helpful when defining macros with `(define-macro ...)`:

    (define-macro (macro-add a b)
        `(+ ,a ,@b))
	(macro-add 30 (1 3 4 5)) ;=> 43
]]

--[[ @values syntax (unquote _value_) reader-syntax: ,_value_

Useful only inside a quasiquotation. It unquotes the _value_ and
inserts the evaluated value inside the quasioquoted result.

	`(1 2 ,(+ 1 2)) ;=> (1 2 3)
]]

--[[ @values syntax (unquote-splicing _value_) reader-syntax: ,@_value_

Useful only insode a quasiquotation. It unquotes the _value_,
evaluates it, and inserts the value into the quasiquoted list.
If the _value_ evaluates to a list, the items are directly
inserted into the resulting list.

	`(1 2 ,@(list 3 4)) ;=> (1 2 3 4)

Compared with `(unquote ...)`:

	`(1 2 ,(list 3 4))  ;=> (1 2 (3 4))
]]
synforms['quasiquote'] = function (self, sF, v)
    return self:compileQuasiQuote(v[2])
end
-----------------------------------------------------------------------------

--[[ @values syntax (quote _value_) reader-syntax: '_value_

Quotes the _value_ in that way, that it evaluates to itself:

    (symbol->string 'a)     ;=> "a"
    '(a b c d)              ;=> (a b c d)
    ['a 'b 'c 'd]           ;=> (a b c d)
]]
synforms['quote'] = function (self, sF, v)
    return self:compileQuote(v[2])
end
-----------------------------------------------------------------------------

--[[ @scope syntax (define-global _symbol_ [_value_])

Defines a global variable _symbol_. And optionally assigns _value_.

    (begin
        (let ((x 10))
            (define-global y (* x 2)))
        y)
    ;=> 20
]]
synforms['define-global'] = function (self, sF, v)
    local var_name = utl.uservar(v[2])
    self.mGlobalEnv[utl.strip_sym(v[2])] = false;

    if (utl.is_nil(v[3])) then
        return self:node('global_decl', { var_name })
    else
        return self:node('global_decl', { var_name, self:compile(v[3]), self.assign_to_global_env })
    end
end
-----------------------------------------------------------------------------

--[[ @scope syntax (define _symbol_ _expression_)

Binds the _symbol_ inside the current lexical scope to the
evaluated value of _expression_.

    (let ((x 10))
        (define y 30)
        (+ x y))
    ;=> 40
]]
--[[ @scope syntax (define (_symbol_ [_parameters_]) _sequence_)

Binds the _symbol_ inside the current lexical scope to a function.
It's syntactic sugar for:

    (define _symbol_
        (lambda ([_parameters_]) _sequence_))

To define the equivalent of `(lambda arglist ...)` use
`(define (funcname . arglist) ...)`.
]]
synforms['define'] = function (self, sF, v)
    local do_glob_assign = self.mEnv == self.mGlobalEnv
    do_glob_assign = do_glob_assign and self.assign_to_global_env

    if (utl.is_table(v[2])) then
        local LArgs = List(v[2])
        local lal_var = LArgs[1]

        local LLambdaArgs = List()
        LLambdaArgs:forAppend(2, #LArgs, 1, function (i) return LArgs[i] end)

        local lua_var = self:touchVar(lal_var)
        local LLambda = List()
        LLambda:push('\xfelambda')
        LLambda:push(LLambdaArgs:table())
        if (#v > 2) then
            for i = 3, #v do LLambda:push(v[i]) end
        end

        return self:node('local_decl', { do_glob_assign, lal_var, lua_var, self:compile(LLambda:table()) })

    else
        local lal_var = v[2]
        local lua_var = self:touchVar(v[2])

        if (utl.is_nil(v[3])) then
            return self:node('local_decl', { do_glob_assign, lal_var, lua_var })
        else
            return self:node('local_decl', { do_glob_assign, lal_var, lua_var, self:compile(v[3]) })
        end
    end
end
-----------------------------------------------------------------------------

synforms['set!'] = function (self, sF, v)
    self:lookupInEnv(v[2])
    local do_glob_assign = self.mEnv == self.mGlobalEnv
    do_glob_assign = do_glob_assign and self.assign_to_global_env
    return self:node('assign_var', { do_glob_assign, v[2], utl.uservar(v[2]), self:compile(v[3]) })
end
-----------------------------------------------------------------------------

synforms['lambda'] = function (self, sF, v)
    if (#v < 3) then
        self:err('Bad lambda form, missing parameter and/or block definition')
    end

    if (utl.is_nil(v[2]) or type(v[2]) ~= 'table') then
        if (not utl.is_sym(v[2])) then
            self:err('Bad lambda form, expected symbol or list as first form argument')
        end

        v[2] = { "\xfe.", v[2] } -- (lambda x ...) => (lambda (x) ...)
    end

    self:pushEnv()
    local LParams = List()
    for i = 1, #v[2] do
        local sV = v[2][i]
        if (utl.strip_sym(sV) == '.') then
            if (utl.is_nil(v[2][i + 1])) then
                self:err('Bad lambda parameter form. Expected symbol after \'.\'.')
            elseif (utl.is_not_nil(v[2][i + 2])) then
                self:err('Bad lambda parameter form. Expected only one more symbol after \'.\', but got more.')
            end
            LParams:push({ self:mkUservar(v[2][i + 1]) })
            break

        else
            LParams:push(self:mkUservar(sV))
        end
    end

    self:pushJumpEnv()
    local oNode =
        self:node('function', {
            LParams,
            self:node('tailContext', {
                self:compile_block(v, 3) }) })
    self:popJumpEnv()

    self:popEnv()
    return oNode
end
-----------------------------------------------------------------------------

--[[ @iterative syntax (for (_count-var-symbol_ _start-idx_ _end-idx_ [_increment-num_]) _sequence_)

This form represents a simple counting loop. It counts by _increment-num_ from _start-idx_
until _end-idx_ is reached. The index is bound to _count-var-symbol_.

    (let ((nums []))
      (for (i 0 4)
        (push! nums i))
      nums)
    ;=> (0 1 2 3 4)
]]
synforms['for'] = function (self, sF, v)
    assert(utl.is_table(v[2]))
    assert(#v[2] > 2)

    local oStartVal = self:compile(v[2][2])
    local oDestVal  = self:compile(v[2][3])
    local oIncrement
    if (utl.is_not_nil(v[2][4])) then oIncrement = self:compile(v[2][4]) end

    self:pushEnv()
    local sVarTmp = self:mkUservar(v[2][1])

    local oBlock = self:compile_block(v, 3)
    self:popEnv()

    return self:node('for', { sVarTmp, oStartVal, oDestVal, oBlock, oIncrement })
end
-----------------------------------------------------------------------------

--[[ @controlflow syntax (if _condition-expr_ [_true-branch_ [_false-branch_] ])

The most basic control flow operation. If _condition-expr_ evaluates to a
true value the _true-branch_ is evaluated. Otherwise the _false-branch_ is
evaluated if it is present.

    (if #t 10 20) ;=> 10
    (if #f 10 20) ;=> 20
    (if #t 10)    ;=> 10
    (if #f 10)    ;=> nil
    (if #t)       ;=> nil
    (if #f)       ;=> nil

    (let ((x 100))
      (if (> x 50)
        (set! x 11))
      x)
    ;=> 11
]]
synforms["if"] = function (self, sF, v)
    local condition, true_branch, false_branch = nil, nil, nil
    if (#v > 1) then condition = self:compile(v[2]) end
    if (#v > 2) then true_branch = self:compile(v[3]) end
    if (#v > 3) then false_branch = self:compile(v[4]) end
    return self:node('if', { condition, true_branch, false_branch })
end

--[[ @controlflow syntax (case _key-value_ ((_datum_ ...) _result_) ...)

Alternative forms:

* (case ((_datum_ ...) _result_) ... (else _result_))
* (case ((_datum_ ...) _result_) ... (else => _result_))

This is a dispatch based on the `eqv?` operator. _key-value_ is evaluated
and the result is compared against each _datum_ of the `case` clauses.
The matching clause _result_ is evaluated then and it's value returned.
Alternatively there is the `else` branch, which is executed when nothing
matches.
If a `=>` is present in the _result_ of a `case` branch or `else`,
then the _result_ should evaluated to a function, which is then called
with the _key-value_ as argument.
]]
synforms['case'] = function (self, sF, v)
    if (#v <= 1) then
        self:err('Bad case form, has not branches.')
    end
    -- TODO

    return self:node('case', { cases })
end

--[[ @controlflow syntax (cond (_condition-expr_ _result_) ...)
* (cond (_condition-expr_ _result_) ... (else _result_))

Simple multi-if statement that tests multiple _condition-expr_ and then
evaluated the corresponding _result_.
If there is an `else` branch, the branch will be evaluated when no condition
evaluates to `#t`.

    (cond ((> 3 2) 'greater)
          ((< 3 2) 'less))
    ;=> greater

    (cond ((> 3 3) 'greater)
          ((< 3 3) 'less)
          (else 'equal))
    ;=> equal
]]
synforms['cond'] = function (self, sF, v)
    if (#v <= 1) then
        self:err('Bad cond form, has not branches.')
    end

    local clauses = List()
    local else_clause
    for i = 2, #v do
        if (not utl.is_table(v[i])) then
            self:err("Badly formed cond element at position %d.", i - 2)
        end
        if (v[i][1] == "\xfeelse") then
            if (else_clause) then
                self:err("Badly formed cond element, "
                         .. "has multiple else clauses at pos %d.",
                         i - 2)
            end
            else_clause = v[i]
        else
            clauses:push(v[i])
        end
    end

    clauses = clauses:map(function (clause)
        self:pushDebugPos(clause)
        local c, b, t
        c = self:compile(clause[1])
        if (clause[2] == "\xfe=>") then
            b = self:compile_block(clause, 3)
            t = true
        elseif (clause[2]) then
            b = self:compile_block(clause, 2)
        end
        self:popDebugPos()
        return { c, b, t }
    end)

    if (else_clause) then
        self:pushDebugPos(else_clause)
        else_clause = self:compile_block(else_clause, 2)
        self:popDebugPos()
    end

    return self:node('cond', { clauses:table(), else_clause })
end

--[[ @controlflow syntax (when _condition-expr_ _block_)

When _condition-expr_ evaluates to a non false (true) value,
the _block_ is executed.

    (let ((something 0))
      (when (zero? something)
        (display "Something is zero!")
        (set! something 1))
      something)
    ;=>1
]]
synforms["when"] = function (self, sF, v)
    local condition = self:compile(v[2])
    local block     = self:compile_block(v, 3)
    return self:node('if', { condition, block })
end

--[[ @controlflow syntax (when _condition-expr_ _block_)

When _condition-expr_ evaluates to a false value, the _block_ is executed.

    (let ((something 1))
      (unless (zero? something)
        (display "Something is zero!")
        (set! something 0))
      something)
    ;=>0
]]
synforms["unless"] = function (self, sF, v)
    local condition = self:compile(v[2])
    local block     = self:compile_block(v, 3)
    return self:node('if', { self:node('not', { condition }), block })
end

--[[ @iterative syntax (do-each (_val-sym_ _list-expr_) _sequence_)

Iterates over the value of _list-expr_, binding the variable _val-sym_ to the
current item of the list and executing _sequence_ for each item.

    (let ((non-zero-vals []))
        (do-each (v [ 0 322 0 493 0 12 212 3 40 ])
            (when (not (zero? v))
                (push! non-zero-vals v)))
        non-zero-vals)
    ;=> (322 493 12 212 3 40)
]]

--[[ @iterative syntax (do-each (_key-sym_ _value-sym_ _map-expr_) _sequence_)

Iterates over the value of _map-expr_, binding the variables _key-sym_ and _value-sym_ to the
corresponding key/value pair and executing _sequence_ for each pair.

    (let ((keys []) (vals []))
        (do-each (k v { :a 10 :b 20 :c 30 })
            (push! keys k)
            (push! vals v))
        keys)
    ;=> (:a :b :c)
]]
synforms['do-each'] = function (self, sF, v)
    assert(utl.is_table(v[2]))
    assert(#v[2] > 1)

    local oValue
    local sV
    local sK
    if (#v[2] > 2) then
        oValue = self:compile(v[2][3])
        sV = v[2][2]
        sK = v[2][1]
    else
        oValue = self:compile(v[2][2])
        sV = v[2][1]
    end

    self:pushEnv()
    if (utl.is_not_nil(sK)) then
        local sVarTmp = self:mkUservar(sK)
        sK = sVarTmp
    end
    local sVarTmp = self:mkUservar(sV)
    sV = sVarTmp

    local oBlock = self:compile_block(v, 3)
    self:popEnv()

    return self:node('do_each', { oValue, oBlock, sV, sK })
end
-----------------------------------------------------------------------------

synforms['let'] = function (self, sF, v)
    if (not(utl.is_table(v[2]))) then
        self:err('Bad let form, has not a list as first argument.')
    end

    self:pushEnv()

    local LVars = List()
    for i = 1, #v[2] do
        local lBinding = v[2][i]
        if (not(utl.is_table(lBinding))) then
            self:err('Bad let binding spec, element '
                     .. tostring(i) .. ' is not a list.')
        end

        if (not(utl.is_sym(lBinding[1]))) then
            self:err(
                'Bad let binding spec, contains a non-symbol as first element: '
                .. Parser.lal_print_string(lBinding))
        end

        if (#lBinding ~= 2)  then
            self:err(
                'Bad let binding spec, does not contain exactly 2 elements.')
        end

        LVars:push(self:mkUservar(lBinding[1]))
    end

    local LStmts = List()
    for i = 1, #v[2] do
        local lBinding = v[2][i]
        LStmts:push(self:node('local_decl', { false, lBinding[1], LVars[i], self:compile(lBinding[2]) }))
    end

    LStmts:push(self:compile_block(v, 3))
    local oLet = self:node('scope', { self:node('block', LStmts:table()) })

    self:popEnv()

    return oLet
end
-----------------------------------------------------------------------------

-- (do (<inits>) (test) <block>)
synforms['do'] = function (self, sF, v)
    assert(utl.is_table(v[2]))
    assert(utl.is_table(v[3]))
    assert(#v[3] == 2)

    local LScopeStmts = List()
    local LIncrements = List()

    self:pushEnv()

    List(v[2]):foreach(function (vb)
        assert(vb[1])
        local sVarTmp = self:mkUservar(vb[1])
        LScopeStmts:push(self:node('local_decl', { false, vb[1], sVarTmp, self:compile(vb[2]) }))
        if (#vb > 2) then
            LIncrements:push(
                self:node('assign_var', { false, vb[1], sVarTmp, self:compile(vb[3]) }))
        end
    end)

    local oTest    = self:compile(v[3][1])
    local oResExpr = self:compile(v[3][2])
    local oBlock   = self:compile_block(v, 4, LIncrements:table())

    LScopeStmts:push(self:node('do_loop', {
        oTest,
        oResExpr,
        oBlock
    }))

    self:popEnv()

    return self:node('scope', { self:node('block', LScopeStmts:table()) })
end
-----------------------------------------------------------------------------

synforms['or'] = function (self, sF, v)
    local LTerms = List()
    for i = 2, #v do LTerms:push(self:compile(v[i])) end
    return self:node('or_and', { 'or', LTerms })
end
-----------------------------------------------------------------------------

synforms['and'] = function (self, sF, v)
    local LTerms = List()
    for i = 2, #v do LTerms:push(self:compile(v[i])) end
    return self:node('or_and', { 'and', LTerms })
end
-----------------------------------------------------------------------------

synforms['not'] = function (self, sF, v)
    return self:node('not', { self:compile(v[2]) })
end
-----------------------------------------------------------------------------

synforms['begin'] = function (self, sF, v)
    return self:compile_block(v, 2)
end
-----------------------------------------------------------------------------

synforms['return'] = function (self, sF, v)
    return self:node('return', { self:compile(v[2]) })
end
-----------------------------------------------------------------------------

--[[ @controlflow syntax (return-from _label-symbol_ _expression_)

This syntax is to be used in conjunction with `(block ...)`.
It returns the value of _expression_ from the corresponding `block`.

    (block break
        (for (i 1 10000)
            (when (is-done? i)
                (return-from break i))))
]]
synforms['return-from'] = function (self, sF, v)
    assert(self.mJumpLabels[v[2]])
    return self:node('return_from', { self.mJumpLabels[v[2]], self:compile(v[3]) })
end
-----------------------------------------------------------------------------

--[[ @controlflow syntax (block _label-symbol_ _sequence_)

This syntax allows to break out of loops in conjunction with `(return-from ...)`.
It internally binds the _label-symbol_ for `return-from` to refer to.
When `return-from` is called the execution continues after the `block` expression
with the return value given to `return-from`.

    (block outer
        (for (i 1 10)
            (when (= i 5)
                (return-from outer 99)))
        20)
    ;=> 99

Please note, that the internal binding of _label-symbol_ is dynamic and not
lexically scoped. This means, you can not use it in a lambda closure to jump
up/down the call stack. LAL does not support continuations. (You can however
use the coroutine capabilities provided by Lua).

]]
synforms['block'] = function (self, sF, v)
    assert(utl.is_sym(v[2]))
    assert(not self.mJumpLabels[v[2]])
    local sLbl = utl.uservar(v[2])
    self.mJumpLabels[v[2]] = sLbl
    return self:node('jump_block', { sLbl, self:compile_block(v, 3) })
end
-----------------------------------------------------------------------------

--[[ @interop syntax (. _method-symbol_ _object-value_ _arg-expr_*)

This special syntax allows you to use the Lua method call syntax.
It is basically a shorthand for: `(($_method-symbol_ _object-value_) _arg-expr_*)`
and is compiled a bit more neatly down to Lua.
You may use it if you ever get some Lua object returned or you want to define your own.

	(import (lua basic))

	(let ((obj { :print_hello
			     (lambda (astr) (lua-print "Hello World! " astr)) }))
		(.print_hello obj "Welcome!"))
		; Generated Lua:  obj.print_hello("Welcome!")

	;stdout=> Hello World! Welcome!

The syntax is inspired from Clojure. Please be aware, that if you use
keywords like `print_hello:` the `:` is removed from the symbol before
it is used as map key.
]]
--[[ @interop procedure (.. _method-symbol_ _object-value_ _arg-expr_*)

This is equivalent to `(. _method-symbol_ _object-value_ _arg-expr_*)` but
it calls the method _method-symbol_ using the `:` Lua syntax. This passes
the object table as first argument to the function.

	(import (lua basic))

	(let ((obj { :print_hello
				 (lambda (self, astr) (lua-print "Hello World! " astr)) }))
		(..print_hello obj "Welcome!"))
		; Generated Lua:  obj:print_hello("Welcome!")
		; Equivalent to:  obj.print_hello(obj, "Welcome!")

	;stdout=> Hello World! Welcome!
]]
synforms['.'] = function (self, sF, v)
    local bColonSyn = (utl.strip_sym(v[1]) == '..')

    if (#v < 3) then
        self:err('Bad ' .. utl.strip_sym(sF) .. ' form. Expected at least 2 arguments.')
    end
    local LArgs = List()
    for i = 3, #v do LArgs:push(self:compile(v[i])) end

    local sCode
    if (utl.is_sym(v[2])) then
        if (bColonSyn) then return self:node('methcall', { ':', v[2], LArgs })
        else                return self:node('methcall', { '.', v[2], LArgs }) end

    else
        -- runtime function application
        local oField = self:compile(v[2])
        LArgs:unshift(oField)
        if (bColonSyn) then
            return self:node('methcall_runtime', { ':', LArgs })
        else
            return self:node('methcall_runtime', { '.', LArgs })
        end
    end
end
synforms['..']  = synforms['.']
-----------------------------------------------------------------------------

synforms['include'] = function (self, sF, v)
    if (#v < 2) then self:err('Bad ' .. utl.strip_sym(sF) .. ' form. Expected at least 1 arguments.') end

    local LExpr = List { '\xfebegin' }

    local p = Parser()
    for i = 2, #v do
        if (type(v[i]) ~= 'string') then
            self:err('Bad ' .. utl.strip_sym(sF) .. ' form. Argument '
                     .. tostring(i - 1) .. ' is not a string or symbol.')
        end

        local sInclPath
        local sLocalPath
        if (utl.is_sym(v[i])) then
            sLocalPath = utl.strip_kw(v[i]) .. ".lal"
        else
            sLocalPath = v[i]
        end

        if (not string.match(sLocalPath, "^%s*/")) then
            sLocalPath = "/" .. sLocalPath
        end

        sInclPath = self.sInputPath .. sLocalPath

        local f, sErr = io.open(sInclPath, 'r')
        if (not f) then
            sInclPath = "." .. sLocalPath
        end
        f, sErr = io.open(sInclPath, 'r')
        if (not f) then
            self:err("Couldn't include '" .. sInclPath .. "': " .. sErr)
        end

        local sContent = f:read('*a')

        local vData, mTblPos = p:parse_program(sContent, sInclPath)
        LExpr:push(vData)

        for k, v in pairs(mTblPos) do
            self.m_mTablePos[k] = v
        end
    end

    return self:compile(LExpr:table())
end
-----------------------------------------------------------------------------

--[[ @compiler syntax (macroexpand _form_)

This function expands the macros found in _form_ and returns the
expanded form as quoted LAL value.

    (define-macro (head-of-syntax-list foo)
      (@0 foo))

    (lua-print
     (write-str
      (macroexpand
       (head-of-syntax-list
        ((let (x a) x) 2 3)))))
    ;stdout=>(let (x a) x)

]]
synforms["macroexpand"] = function (self, sF, v)
    return self:compileQuote(self:macroexpand(v[2]))
end
-----------------------------------------------------------------------------

synforms['define-macro'] = function (self, sF, vMacroDef)
    local LArgs  = List(vMacroDef[2])
    local sFName = LArgs[1]

    local LLambdaArgs = List()
    LLambdaArgs:forAppend(2, #LArgs, 1, function (i) return LArgs[i] end)

    local LLambda = List({ "\xfelambda", LLambdaArgs:table() })
    if (#vMacroDef > 2) then
        for i = 3, #vMacroDef do LLambda:push(vMacroDef[i]) end
    end

    local lDefine = { "\xfedefine", sFName, {
        ["\xfdsType"] = "primitive-macro",
        ["\xfdfunc"]  = LLambda:table()
    } };

    local sCode, oDefMacroNode = self:compile_internal_code(lDefine)
    local f = load(sCode, "macro: " .. utl.strip_sym(sFName), "t")

    self:setEnv(sFName, f());

    return oDefMacroNode
end
-----------------------------------------------------------------------------

synforms['$^!'] = function (self, sF, v)
    if (#v < 3) then self:err("Bad '%s' form, expected at least 2 arguments.", utl.strip_sym(sF)) end

    if (utl.is_sym(v[2]) and not(utl.is_table(v[3]))) then
        self:err("Bad '%s' form, symbol argument form requires list as second argument.", utl.strip_sym(sF))

    elseif ((not utl.is_sym(v[2])) and not(utl.is_table(v[2]))) then
        self:err("Bad '%s' form, basic form requires list as second argument.", utl.strip_sym(sF))

    elseif (utl.is_sym(v[2]) and #v[2] ~= 2) then
        self:err("Bad '%s' form, symbol argument form requires list with "
                 .. "exactly 2 elements as second argument.", utl.strip_sym(sF))
    end

    local i = 1
    local sVarSym = '\xfe_'
    if (utl.is_sym(v[2])) then
        i       = 2
        sVarSym = v[2]
    end

    self:pushEnv()
    local sVar = self:mkUservar(sVarSym)
    local oBlock = self:compile_block(v, i + 2)
    self:popEnv()
    return self:node('fieldOverAccess', {
                utl.strip_sym(sF) == '@^!',
                sVar, self:compile(v[i + 1][1]), self:compile(v[i + 1][2]), oBlock })
end
synforms['@^!'] = synforms['$^!']
-----------------------------------------------------------------------------

--[[ @syntax-compiler syntax (current-source-pos)

Returns a string that identifies the current position in the source code.
Example:

    (import (lal syntax-compiler))

    (begin
         (display A:)
         (display (lal-syntax-compiler-current-source-pos))
         (display B:))
]]
syntax_compiler['current-source-pos'] = function (self, sF, v)
    return self:node('string', {
        string.format("%s:%d", self.sInputName, self.iCurLine) })
end
-----------------------------------------------------------------------------

--[[ @syntax-compiler syntax (debug-print-output)

This method sets a flag in the compiler, so that it will print out the generated
Lua code after compilation together with the line and file in which this
form is used.

    (import (lal syntax-compiler))

    (begin
         (displayln A:)
         (lal-syntax-compiler-debug-print-output)
         (displayln B:))

    ;stdout=>
        DEBUG-PRINT-OUTPUT testdeb.lal:5> [
        if (os.getenv("LALRT_LIB")) then package.path = package.path .. ";" .. os.getenv("LALRT_LIB") .. '/lal/?.lua'; end
        ;
        local _ENV = { _lal_lua_base_ENV = _ENV, _lal_lua_base_pairs = pairs };
        for k, v in _lal_lua_base_pairs(_lal_lua_base_ENV) do _ENV["_lal_lua_base_" .. k] = v end;
        local _lal_req1 = _lal_lua_base_require 'lal.lang.builtins';
        local strip_kw = _lal_req1["strip-kw"];
        local strip_sym = _lal_req1["strip-sym"];
        local display = _lal_req1["display"];
        --[[testdeb.lal:1] ]
        --[[testdeb.lal:3] ]
        --[[testdeb.lal:4] ]
        display("\xFDA");
        return display("\xFDB");
        --[[testdeb.lal:1] ]
        ]

Please note, that the actual output is compiler dependent and may differs
between versions.
]]
syntax_compiler['debug-print-output'] = function (self, sF, v)
    self.do_print_output = string.format("%s:%d", self.sInputName, self.iCurLine)
end
-----------------------------------------------------------------------------

--[[ @syntax-compiler syntax (display-compile-output [_tag_] _expression_)

This syntax will print out the compilation output of _expression_ to
standard output. It will be marked using _tag_. This form is very handy for
debugging problems in the code generation and/or the compiler itself.

    (import (lal syntax-compiler))
    (lal-syntax-compiler-display-compile-output "test out" (+ 10 20))
    ;stdout=> LAL-COMPILE-OUT[test out] CHUNK{{{
    ;         }}} VALUE[expr:unknown:nil:returning]{{{ (10 + 20) }}}

A __CHUNK__ contains usually only code that has side effects and does not directly
provide a value for the next expression which uses the value of the currently compiled
expression. The __VALUE__ is the actual Lua code that returns an expression.
This can be a full expression like `(10 + 20)` or also a function like
`function (a, b) ... end`. Often it is just some temporary variable name that
was declared in/before the __CHUNK__.

Meaning of the fields in `[ ... ]`:
    expression-type         - type of the expression, used by the code generator
                              to determine how to handle the VALUE of the chunk.
                              Lua does make a difference between statements and expressions,
                              so we need to explictly assign some expressions
                              to some temporary if the VALUE has sideeffects.
                              Types:
                                "sideeffectFree"
                                "expr"
                                "stmt"
    compile-type            - the type of the value returned by the generated code
                              generator node. Used for primitive data literals
                              to apply some optimizations. For example when accessing
                              fields in tables. Some possible values:
                                "string"
                                "number"
                                "boolean"
                                "keyword"
                                "symbol"
                                "nil"
    raw-string-val          - the raw value as string. useful in case some optimizations
                              based on compile-type are done. Usually only filled for
                              "keyword", "symbol" or "string".
    is-returning            - shows "returning" if the expression is located in a
                              returning branch or whether it actually returns due to
                              a `(return ...)`. This helps the LAL compiler to eliminate
                              dead code after a return, so that the Lua compiler
                              does not complain.
]]
syntax_compiler["display-compile-output"] = function (self, sF, v)
    if (#v > 3) then
        self:err("display-compile-output needs 1 or 2 arguments: "
                 .. "tag and expression or just expression.")
    end
    if (#v == 2) then
        v[3] = v[2]
        v[2] = "\xFE:"
    end

    return self:node('display_compile_output', { utl.strip_kw(v[2]), self:compile(v[3]) })
end
-----------------------------------------------------------------------------
-- TODO: implement these special forms maybe more clean with:
--          (with-compiler-opt (:print-generated) codeblock)
--       Of course :print-generatd needs code-gen support!
-----------------------------------------------------------------------------

return synforms
