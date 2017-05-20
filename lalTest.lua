-- See Copyright Notice in lal.lua

local TC       = require 'lal/util/test_case'
local lal      = require 'lal/lal'
local List     = require 'lal/util/list'
local Parser   = require 'lal/lang/parser'
local Compiler = require 'lal/lang/compiler'
local lal_eval = lal.eval


local assert_eq       = TC.assert_eq
local assert_match    = TC.assert_match
local ok              = TC.ok
local diag            = TC.diag
local TestCaseSummary = TC.TestCaseSummary
local TestCase        = TC.TestCase

local function assert_error(sMatch, sData)
    local bOk, sErr = pcall(function () lal_eval(sData, sMatch) end)
    ok(not(bOk), 'Compiled without error, but should not: ' .. sData)
    if (not string.match(sErr, sMatch)) then
        ok(false, 'Compiled with wrong error (expected ' .. sMatch .. '): ' .. sErr)
    else
        ok(true, 'Compiled with error like expected')
    end
end

local function assert_lal(sLal, sData, sName)
    local info = debug.getinfo(2, "Sl")
    assert_eq(sLal, Parser.lal_print_string(lal_eval(sData, info.short_src .. ":" .. info.currentline)), sName)
end

local oT = TestCase('LAL-Compiler', 82)

--function oT:testDefM()
--    local compiler = Compiler()
--    local p        = Parser()
--    assert_eq([[local x; x = 11;
--_ENV._lal_global_env["x"] = x;
--return x;
--]],
--        compiler:compile_toplevel(p:parse_expression '(define x 11)'))
--    assert_eq([[x = 12;
--_ENV._lal_global_env["x"] = x;
--return x;
--]],
--        compiler:compile_toplevel(p:parse_expression '(set! x 12)'))
--end

function oT:testFn()
    assert_eq(20,      lal_eval '((lambda (a) a) 20)')
    assert_lal('52', [[
        (begin
            (define l (lambda (x y) (+ x y 13)))
            (l (l 0 0) (l (l 0 0) 0)))]])

    assert_error('.*Bad.*lambda.*%(lambda 10%)', [[(lambda 10)]])
    assert_error('.*Bad.*lambda', [[(begin
        (begin (begin (lambda 10))))]])
    assert_error('Bad.*lambda.*symbol.*list', [[(lambda 10 20)]])
    assert_error('Bad.*lambda', [[(lambda (x))]])
end

function oT:testLet()
    assert_eq(30, lal_eval '(let ((a 5) (b 20)) (set! a (* 2 a)) (+ a b))')
end

function oT:testDo()
    assert_eq(32, lal_eval '(begin (define x 10) (define y 20) (+ x y 2))')
    assert_eq(32, lal_eval '(begin (begin (define x 10)) (define y 20) (+ x y 2))')
    assert_eq(32, lal_eval '(begin (begin (define x 10) (define y 20) 44) (begin (+ x y 2) (+ x y 2)))')
    assert_eq(32, lal_eval '(begin (begin (define x 10) (define y (begin 44 20)) 44) (begin (+ x y 2)))')
    assert_eq(32, lal_eval '(begin (begin (define x 10) (define y 20) 44) (begin (+ x y 2)))')
end

function oT:testReturn()
    assert_eq(20, lal_eval [[
        (begin
            (define x 10)
            (return 20)
            30
        )
    ]])
end

function oT:testReturnAnyWhere()
    assert_lal('9', [[
        { b: 20 a: (return 9) x: 22 }
    ]])
    assert_eq(10, lal_eval [[
        (list? (return 10))
    ]])
    assert_eq(11, lal_eval [[
        (empty? (return 11))
    ]])
    assert_eq(12, lal_eval [[
        (define-global ff (return 12))
    ]])
    assert_eq(12, lal_eval [[
        (define ff2 (return 12))
    ]])
    assert_eq(13, lal_eval [[
        (begin
            (define ff2 12)
            (set! ff2 (return 13)))
    ]])
    assert_eq(14, lal_eval [[
        ((return 14) 22)
    ]])
    assert_eq(16, lal_eval [[
        (begin
            (define x 2)
            ((lambda () 2) ((lambda () (set! x 16))) (return x)))
    ]])
    assert_eq(15, lal_eval [[
        (begin
            (define x 1)
            (+ ((lambda () (set! x 15))) (return x)))
    ]])
    assert_eq(31, lal_eval [[
        (begin
            (define x 1)
            (define y 2)
            (+
              ((lambda () (set! y 16)))
              (+ ((lambda () (set! x 15)))
                 (return (+ x y)))))
    ]])
    assert_eq(42, lal_eval [[
        (begin
            (let ((a 10) (b 20)) b)
            (let ((c 30))
                (let ((k 32) (j (return (+ k 10))))))
            44)
    ]])

    assert_eq(43, lal_eval [[
        (let ((x 11))
            (let ((if (= (set! x 43) (return x)))) 12)
            x)
    ]])
    assert_eq(44, lal_eval [[
        (if #t (return 44))
    ]])
    assert_eq(45, lal_eval [[
        (if #f 10 (return 45))
    ]])
    assert_eq(46, lal_eval [[
        (begin
            (import (lua basic))
            (define X 10)
            (. concat lua-table (set! X 46) (return X)))
    ]])
    assert_eq(47, lal_eval [[
        (begin
            (define X 10)
            (. (set! X 47) (return X)))
    ]])
end

function oT:testLetWOBody()
    assert_eq(nil, lal_eval [[
        (let ((i 1)))
    ]])
end

function oT:testLetEmpty()
    assert_eq(nil, lal_eval [[ (let ()) ]])
end

function oT:testReturnInLetBody()
    assert_eq(43, lal_eval [[
        (begin
            (let ((c 30))
                (return 43)
                (+ 20 30)))
    ]])
end

function oT:testReturnFromFn()
    assert_eq(44, lal_eval [[
        (begin
            (define o 10)
            (let
                ((f (lambda (a) (return (+ o a)) 99)))
                (f 34)))
    ]])
end

function oT:testIf()
    assert_eq(55, lal_eval [[
        (if (> 1 0) 55 44)
    ]])
end

function oT:testIfOneBranch()
    assert_eq(44, lal_eval [[
        (if (> 1 0) 44)
    ]])
end

function oT:testIfOneBranchFalse()
    assert_eq(nil, lal_eval [[
        (if (> 0 1) 44)
    ]])
end

function oT:testIfReturn()
    assert_eq(11, lal_eval [[
        (if (> 1 0) (return 11) 12)
    ]])
end

function oT:testIfFalseReturn()
    assert_eq(12, lal_eval [[
        (if (> 0 1) (return 11) (return 12))
    ]])
end

function oT:testLuaTOC()
    assert_eq(1000000, lal_eval [[
        (let
            ((sum (lambda (x)
                    (if (>= x 1000000)
                        (return x)
                        (return (sum (+ x 1)))))))
            (sum 0))
    ]])
end

function oT:testLuaTOCWithLetS()
    assert_eq(1000000, lal_eval [[
        (let
            ((sum (lambda (x)
                    (if (>= x 1000000)
                        (let ((y x)) (return y))
                        (let ((k x)) (return (sum (+ k 1))))))))
            (sum 0))
    ]])
end

function oT:testBool()
    assert_lal('nil', [[nil]])

    assert_eq(123,      lal_eval [[(if #t 123 321)]])
    assert_eq(321,      lal_eval [[(if #f 123 321)]])
    assert_eq(true,     lal_eval [[#t]])
end

function oT:testQuotedList()
    assert_lal('(1 2 3 4)', [[ [1 2 3 4] ]])
    assert_lal('()',        [[ [ ] ]])
    assert_lal('((1) (2))', [[ [ [1] [2] ] ]])
end

function oT:testOpsAsFn()
    assert_eq(10, lal_eval [[(let ((x +)) (x 1 2 3 4))]])
    assert_eq(24, lal_eval [[(let ((x *)) (x 2 3 4))]])
    assert_eq(2,  lal_eval [[(let ((x /)) (x 4 2))]])
    assert_eq(1,  lal_eval [[(let ((x -)) (x 4 2 1))]])
    assert_eq(-1, lal_eval [[(let ((x -)) (x 0 1))]])

    assert_eq(10, lal_eval [[(+ 1 2 3 4)]])
    assert_eq(24, lal_eval [[(* 2 3 4)]])
    assert_eq(2,  lal_eval [[(/ 4 2)]])
    assert_eq(1,  lal_eval [[(- 4 2 1)]])

    assert_eq(true,   lal_eval [[(> 4 2)]])
    assert_eq(false,  lal_eval [[(> 4 4)]])
    assert_eq(false,  lal_eval [[(> 2 4)]])
    assert_eq(false,  lal_eval [[(< 4 2)]])
    assert_eq(false,  lal_eval [[(< 4 4)]])

    assert_eq(true,    lal_eval [[(let ((k >)) (k 4 2))]])
    assert_eq(false,   lal_eval [[(let ((k <)) (k 4 2))]])
    assert_eq(true,    lal_eval [[(let ((k >=)) (k 4 2))]])
    assert_eq(false,   lal_eval [[(let ((k <=)) (k 4 2))]])
end

function oT:testOpErrors()
    assert_error('Operator %/.*expects.*2.*got.*3', '(/ 1 2 3)')
    assert_error('Operator %<.*expects.*2.*got.*3', '(< 1 2 3)')
    assert_error('Operator %>.*expects.*2.*got.*3', '(> 1 2 3)')
    assert_error('Operator %<.*expects.*2.*got.*3', '(<= 1 2 3)')
    assert_error('Operator %>.*expects.*2.*got.*3', '(>= 1 2 3)')
end

function oT:testSimpleArith()
    assert_lal('3',      [[(+ 1 2)]])
    assert_lal('11',     [[(+ 5 (* 2 3))]])
    assert_lal('8',      [[(- (+ 5 (* 2 3)) 3)]])
    if (_VERSION == "Lua 5.3") then
        assert_lal('2.0',    [[(/ (- (+ 5 (* 2 3)) 3) 4)]])
        assert_lal('2',      [[(// (- (+ 5 (* 2 3)) 3) 4)]])
        assert_lal('2565.0', [[(/ (- (+ 515 (* 222 311)) 302) 27)]])
        assert_lal('2565',   [[(// (- (+ 515 (* 222 311)) 302) 27)]])
    else
        assert_lal('2',      [[(/ (- (+ 5 (* 2 3)) 3) 4)]])
        assert_lal('2',      [[(// (- (+ 5 (* 2 3)) 3) 4)]])
        assert_lal('2565',   [[(/ (- (+ 515 (* 222 311)) 302) 27)]])
        assert_lal('2565',   [[(// (- (+ 515 (* 222 311)) 302) 27)]])
    end
end

function oT:testIfBool()
    assert_lal('10',  [[(if #true 10 20)]])
    assert_lal('20',  [[(if #false 10 20)]])
    assert_lal('nil', [[(if #false 10)]])
    assert_lal('10',  [[(if #true 10)]])
    assert_lal('nil', [[(if #false)]])
    assert_lal('nil', [[(if #true)]])
    assert_lal('7',   [[(if #true 7 8)]])
    assert_lal('8',   [[(if #false 7 8)]])
    assert_lal('8',   [[(if #true (+ 1 7) (+ 1 8))]])
    assert_lal('9',   [[(if #false (+ 1 7) (+ 1 8))]])
    assert_lal('8',   [[(if nil 7 8)]])
    assert_lal('7',   [[(if 0 7 8)]])
    assert_lal('7',   [[(if "" 7 8)]])
    assert_lal('7',   [[(if (list) 7 8)]])
    assert_lal('7',   [[(if (list 1 2 3) 7 8)]])
end

function oT:testBasicData()
    assert_lal('(1 2 3)',   [[ [1 2 (+ 1 2)] ]])
    assert_lal('{"a" 15}',  [[{a: (+ 7 8)}]])
    assert_lal('{"a" 15}',  [[{(let ((x a:)) x) (+ 7 8)}]])
    assert_lal('{"x" 15}',  [[{(quote x) (+ 7 8)}]])
end

function oT:testDef()
    assert_lal('3',  [[(define x 3)]])
    assert_lal('3',  [[(begin (define x 3) x)]])
    assert_lal('4',  [[(begin (define x 3) (define x 4) x)]])
    assert_lal('8',  [[(begin (define y (+ 1 7)) y)]])
    assert_lal('13', [[(define y 13)]])
end

function oT:testLet2()
    assert_lal('9',  [[(let ((z 9)) z)]])
    assert_lal('9',  [[(let ((x 9)) x)]])
    assert_lal('6',  [[(let ((z (+ 2 3))) (+ 1 z))]])
    assert_lal('12', [[(let ((p (+ 2 3)) (q (+ 2 p))) (+ p q))]])
    assert_lal('9',  [[(let ((q 9)) q)]])
    assert_lal('4',  [[(begin (define a 4) (let ((q 9)) a))]])
    assert_lal('4',  [[(begin (define a 4) (begin (let ((z 2)) (let ((q 9)) a))))]])
    assert_lal('12', [[(let ((p (+ 2 3)) (q (+ 2 p))) (+ p q))]])
    assert_lal('10', [[(let ((x 10)) (begin (let ((x 20)) x) x))]])
end

function oT:testLetList()
    assert_lal('(3 4 5 (6 7) 8)', [[(let ((a 5) (b 6))           [3 4 a [b 7] 8])]])
    assert_lal('(3 4 5 (6 7) 8)', [[(let ((a 5) (b 6) (lst list)) (lst 3 4 a [b 7] 8))]])
end

function oT:testKeyword()
    assert_lal('kw:',           [[kw:]])
    assert_lal('(kw: kw: kw:)', [['(kw: kw: kw:)]])
end

function oT:testList()
    assert_lal('()',               [[(list)]])
    assert_lal('(1 2 3)',          [[(list 1 2 3)]])
    assert_lal('(+ 1 2)',          [[ ['+ 1 2] ]])
    assert_lal('((3 4))',          [[ [ [3 4] ] ]])
    assert_lal('(+ 1 (+ 2 3))',    [[ ['+ 1 ['+ 2 3] ] ]])
    assert_lal('(+ 1 (+ 2 3))',    [[    [     '+     1   ['+    2 3   ]   ] ]])
end

function oT:testQuote()
    assert_lal('(+ 1 2)',          [['(+ 1 2)]])
    assert_lal('((3 4))',          [['((3 4))]])
    assert_lal('(+ 1 (+ 2 3))',    [['(+ 1 (+ 2 3))]])
    assert_lal('(+ 1 (+ 2 3))',    [[    '     ( +     1 (+  2 3 )      )]])
    assert_lal('(* 1 2)',          [['(* 1 2)]])
    assert_lal('(** 1 2)',         [['(** 1 2)]])
    assert_lal('(1 2 3)',          [['(1 2 3)]])
    assert_lal('(quote 1)',        [[''1]])
    assert_lal('(quote (1 2 3))',  [[''(1 2 3)]])
    assert_lal('7',                [[(quote 7)]])
    assert_lal('7',                [['7]])
    assert_lal('(1 2 3)',          [[(quote (1 2 3))]])
    assert_lal('(1 2 3)',          [['(1 2 3)]])
    assert_lal('(1 2 (3 4))',      [[(quote (1 2 (3 4)))]])
    assert_lal('(1 2 (3 4))',      [['(1 2 (3 4))]])
    assert_lal('(10)',             [[(quote (10))]])
end

function oT:testLength()
    assert_error('attempt.*length.*nil',
                                    [[(length nil)]]) -- does not work, nil != {}
    assert_lal('3',                [[(length (list 1 2 3))]])
    assert_lal('0',                [[(length (list))]])
    assert_lal('"no"',             [[(if (>  (length (list 1 2 3)) 3) "yes" "no")]])
    assert_lal('"yes"',            [[(if (>= (length (list 1 2 3)) 3) "yes" "no")]])
    assert_lal('4',                '(begin (let ((c length)) (c [1 2 3 (define x 20)])))')
end

function oT:testUnusedRetValsAndBuiltins()
    assert_lal('20',  '(begin (length [1 2 3 (define x 20)]) x)')
    assert_lal('20',  '(begin [1 2 3 (define x 20)] x)')
end


function oT:testPredicates1()
    assert_lal('#true',    [[(list? (list))]])
    assert_lal('#true',    [[(let ((x list?)) (x (list)))]])
    assert_lal('#false',   [[(list? { a: 1 })]])
    assert_lal('#false',   [[(let ((x list?)) (x { a: 1 }))]])

    assert_lal('#true',   [[(empty? (list))]])
    assert_lal('#false',  [[(empty? (list 1))]])
    assert_lal('#true',   [[(empty? {})]])
    assert_lal('#false',  [[(empty? {a: 1})]])
    assert_lal('#true',   [[(let ((x empty?)) (x (list)))]])
    assert_lal('#false',  [[(let ((x empty?)) (x (list 1)))]])
    assert_lal('#true',   [[(let ((x empty?)) (x {}))]])
    assert_lal('#false',  [[(let ((x empty?)) (x {a: 1}))]])
--    assert_lal('#false',  [[(= (list) nil)]])
end

function oT:testPrStrRdStr()
    assert_eq('(1 2 3)',                 lal_eval [[(write-str (list 1 2 3))]])
    assert_eq('{\"a\" 1}',               lal_eval [[(write-str {a: 1})]])
    assert_eq('{\"a\" 1}',               lal_eval [[(write-str {"a" 1})]])
    assert_eq('{\"a:\" 1}',              lal_eval [[(write-str {"a:" 1})]])
    assert_eq('{(1 2 3) (4 5 6)}',       lal_eval [[(write-str {'(1 2 3) '(4 5 6)})]])
    assert_eq('(1.1 2.02 3.003)',        lal_eval [[(write-str '(1.1 2.02 3.003))]])
    assert_eq('3.003',                   lal_eval [[(write-str 3.003)]])
    assert_eq('\"foo\"',                 lal_eval [[(write-str "foo")]])

    assert_lal('(1 2 3)',               [[(read-str (write-str (list 1 2 3)))]])
    assert_lal('{\"a\" 1}',             [[(read-str (write-str {a: 1}))]])
    assert_lal('{\"a\" 1}',             [[(read-str (write-str {"a" 1}))]])
    assert_lal('{\"a:\" 1}',            [[(read-str (write-str {"a:" 1}))]])
    assert_lal('{(1 2 3) (4 5 6)}',     [[(read-str (write-str {'(1 2 3) '(4 5 6)}))]])
    assert_lal('(1.1 2.02 3.003)',      [[(read-str (write-str '(1.1 2.02 3.003)))]])
    assert_lal('3.003',                 [[(read-str (write-str 3.003))]])
    assert_lal('\"foo\"',               [[(read-str (write-str "foo"))]])
    assert_lal('5',                     [[(eval (read-str "(+ 2 3)"))]])
end

function oT:testEval()
    assert_lal('(1 2 3)',  [[(eval '(list 1 2 3))]])
    assert_lal('(33 x:)',  [[(eval '(let ((a 33) (b x:)) (list a b)))]])
end

function oT:testEQ()
    assert_lal('#true',   [[(= 1 1)]])
    assert_lal('#true',   [[(= 'abc 'abc)]])
    assert_lal('#false',  [[(= 'abc 'abcd)]])
    assert_lal('#false',  [[(= 'abc "abc")]])
    assert_lal('#false',  [[(= "abc" 'abc)]])
end

function oT:testFunctionDef()
    assert_lal('12',  [[
        ((
            (lambda (a)
                (lambda (b) (+ a b)))
            5)
         7)]])
    assert_lal('12',  [[
        (begin
            (define gen-plus5
                (lambda () (lambda (b) (+ 5 b))))
            (define plus5 (gen-plus5))
            (plus5 7))]])
    assert_lal('15',  [[
        (begin
            (define gen-plusX (lambda (x) (lambda (b) (+ x b))))
            (define plus7 (gen-plusX 7))
            (plus7 8))]])

    -- recursion:
    assert_lal('(1 3 21)',  [[
        (begin
            (define sumdown
                (lambda (N) (if (> N 0) (+ N (sumdown  (- N 1))) 0)))
            [ (sumdown 1) (sumdown 2) (sumdown 6) ])]])

end

function oT:testTailIf()
    assert_lal('49',  [[ (if (return 49) 10 11) ]])

    assert_lal('50',  [[ (begin (define x 50) (return x)) ]])
    assert_lal('51',  [[ (begin (define x 51) x) ]])
    assert_lal('51',  [[ (begin (define x 51) (if #true (return x))) ]])
    assert_lal('51',  [[ (begin (define x 51) (if #true x)) ]])
    assert_lal('51',  [[ (begin (define x 51) (if #false #false (return x))) ]])
    assert_lal('51',  [[ (begin (define x 51) (if #false #false x)) ]])
    assert_lal('51',  [[ (begin (define x 51) (return (if #false #false (return x)))) ]])
    assert_lal('51',  [[ (begin (define x 51) (return (if #false #false x))) ]])

    -- testing effect of outer return:
    assert_lal('51',  [[ (return (begin (define x 51) (if #true (return x)))) ]])
    assert_lal('51',  [[ (return (begin (define x 51) (if #true x))) ]])
    assert_lal('51',  [[ (return (begin (define x 51) (return (if #f #f (return x))))) ]])
    assert_lal('51',  [[ (return (begin (define x 51) (return (if #f #f x)))) ]])

    -- testing proper output ignore & TCO creation by (return ...):
    assert_lal('51',  [[ (return (begin (define x 51) (return (if #f #f (return x))) 55)) ]])
    assert_lal('51',  [[ (return (begin (define x 51) (return (if #f #f x)) 55)) ]])

    -- testing let TCO:
    assert_lal('61',  [[ (let         ((a (lambda (x) (+ x 10))         ) (b 51)) (a b)) ]])
    assert_lal('61',  [[ (let         ((a (lambda (x) (return (+ x 10)))) (b 51)) (a b)) ]])
    assert_lal('61',  [[ (let         ((a (lambda (x) (+ x 10))         ) (b 51)) (return (a b))) ]])
    assert_lal('61',  [[ (let         ((a (lambda (x) (return (+ x 10)))) (b 51)) (return (a b))) ]])
    assert_lal('61',  [[ (return (let ((a (lambda (x) (+ x 10))         ) (b 51)) (a b))) ]])
    assert_lal('61',  [[ (return (let ((a (lambda (x) (return (+ x 10)))) (b 51)) (a b))) ]])
    assert_lal('61',  [[ (return (let ((a (lambda (x) (+ x 10))         ) (b 51)) (return (a b)))) ]])
    assert_lal('61',  [[ (return (let ((a (lambda (x) (return (+ x 10)))) (b 51)) (return (a b)))) ]])

    -- testing recursive algorithm definition:
    assert_lal('500000500000',  [[
        (begin
            (define sum2
                (lambda (n acc)
                    (if (= n 0)
                        (return acc)
                        (return (sum2 (- n 1) (+ n acc))))))
            (define res2 (sum2 1000000 0))
            res2)]])

    -- testing tail of (begin ...)
    assert_lal('500000500000',  [[
        (begin
            (define sum2
                (lambda (n acc)
                    (if (= n 0)
                        (return (begin acc))
                        (return (begin (sum2 (- n 1) (+ n acc)))))))
            (define res2 (sum2 1000000 0))
            res2)]])

    -- testing implicit tail of (if ...)
    assert_lal('500000500000',  [[
        (begin
            (define sum2
                (lambda (n acc)
                    (if (= n 0)
                        acc
                        (sum2 (- n 1) (+ n acc)))))
            (define res2 (sum2 1000000 0))
            res2)]])
end

function oT:testConsConcat()
    assert_lal('(1)',            [[(cons 1 (list))]])
    assert_lal('(1 2)',          [[(cons 1 (list 2))]])
    assert_lal('(1 2 3)',        [[(cons 1 (list 2 3))]])
    assert_lal('((1) 2 3)',      [[(cons (list 1) (list 2 3))]])
    assert_lal('()',             [[(concat)]])
    assert_lal('(1 2)',          [[(concat (list 1 2))]])
    assert_lal('(1 2 3 4)',      [[(concat (list 1 2) (list 3 4))]])
    assert_lal('(1 2 3 4 5 6)',  [[(concat (list 1 2) (list 3 4) (list 5 6))]])
    assert_lal('()',             [[(concat (concat))]])

    assert_lal('(1 2 3)',        [[(cons! 1 (list 2 3))]])
    assert_lal('((1) 2 3)',      [[(cons! (list 1) (list 2 3))]])
    assert_lal('()',             [[(concat!)]])
    assert_lal('(1 2 3 4 5 6)',  [[(concat! (list 1 2) (list 3 4) (list 5 6))]])
    assert_lal('(2 3)',          [[(let ((x (list 2 3))) (cons 1 x)  x)]])
    assert_lal('(1 2 3)',        [[(let ((x (list 2 3))) (cons! 1 x) x)]])
    assert_lal('(2 3)',          [[(let ((x (list 2 3))) (concat x '(1))  x)]])
    assert_lal('(2 3 1)',        [[(let ((x (list 2 3))) (concat! x '(1)) x)]])
end

function oT:testDefGlobal()
    assert_eq(table,        lal_eval [[(begin (import (lua basic)) lua-table)]])
    assert_lal('(1 2 3)',  [[(concat! (let ((x 1)) (define-global y 2) [x]) [y 3])]])
-- TODO!
--    assert_eq(table, lal_eval([[t]], { t = table }))
end

function oT:testDotSyntax()
    assert_lal('"foo"',  [[
        (begin
            (import (lua string))
            (lua-string-sub "foobar" (+ 0 1) 3))]])
    assert_lal('"foo"',  [[
        (begin
            (import (lua basic))
            (let ((y 'sub))
                (.(begin y) lua-string "foobar" (+ 0 1) 3)))]])

    assert_lal('(1 2 3)',  [[
        (begin
            (import lua-basic)
            (let ((List (lua-require "lal.util.list")))
                (let ((L (List)))
                    (..push L 1)
                    (..push L 2)
                    (..push L 3)
                    (..table L))))]])
    assert_lal('(1 2 3)',  [[
        (begin
            (import lua-basic)
            (let ((List (lua-require "lal.util.list")))
                (let ((L (List)))
                    (..(begin 'push)  L 1)
                    (..(begin 'push)  L 2)
                    (..(begin 'push)  L 3)
                    (..table L))))]])

    assert_lal('(10 (1 9 4))',  [[
        (let ((x ())) ($!a: x 10) ($!b: x [1 (* 3 3) 4]) [($a: x) ($b: x)])
    ]])
    assert_lal('(1 9 4)',  [[
        (let ((y (let ((x ())) ($!a: x 10) ($!b: x [1 (* 3 3) 4])))) y)
    ]])
    assert_lal('("x" "y" "m")',  [[
        (let ((m {a:: "m" a: "x" 'b "y"})) [($a: m) ($b: m) ($a:: m)])
    ]])
    assert_lal('("x" "y" "m")',  [[
        (let ((K $))
            (let ((m {a:: "m" a: "x" 'b "y"}))
                [(K a: m) (K b: m) (K a:: m)]))
    ]])
    assert_lal('("x" "y" "m")',  [[
        (let ((m {a:: "m" a: "x" 'b "y"}) (oop b:)) [($(begin (when #t "a")) m) ($oop m) ($a:: m)])
    ]])
    assert_lal('("x" "y" "m")',  [[
        (let ((m {a:: "m" a: "x" 'b "y"}) (oop b:)) [($(begin (when #t a:)) m) ($oop m) ($a:: m)])
    ]])
    assert_lal('("x" "y" "m")',  [[
        (let ((m {a:: "m" a: "x" 'b "y"}) (oop b:)) [($(begin a:) m) ($oop m) ($a:: m)])
    ]])

    assert_lal('942', [[
        (let ((obj { print-hello: (lambda (a) (+ 932 a)) }))
            (.print-hello obj 10))
    ]])

    assert_lal('943', [[
        (let ((obj { print-hello: (lambda (self a) (+ 933 a)) }))
            (..print-hello obj 10))
    ]])

    assert_lal('944', [[
        (let ((obj { "print hello" (lambda (a) (+ 934 a)) }))
            (. "print hello" obj 10))
    ]])

    assert_lal('945', [[
        (let ((obj { "print hello" (lambda (self a) (+ 935 a)) }))
            (.. "print hello" obj 10))
    ]])
end

function oT:testSideeffectIgnore()
    assert_lal('0',  [[ (begin '1 0) ]])
    assert_lal('0',  [[ (begin (lambda (x) x) 0) ]])
    assert_lal('0',  [[ (begin (+ 1 2) 0) ]])
    assert_lal('0',  [[ (begin (list? []) 0) ]])
    assert_lal('0',  [[
        (begin
            (begin ($x: {x: 10}) y:)
            (list? [])
            0)
    ]])
    assert_lal('(1 2 3 4)',  [[
        (begin
            (import (lua basic))
            (define x [1 2 3])
            [(let ((m 10)) (list? (.insert lua-table x 4)) (define y m))]
            x)
    ]])
end

function oT:testValueEvaluation()
    assert_lal('10',                    [[10]])
    assert_lal('nil',                   [[nil]])
    assert_lal('#true',                 [[#t]])
    assert_lal('#true',                 [[#true]])
    assert_lal('#false',                [[#false]])
    assert_lal('#false',                [[#f]])
    assert_lal('1',                     [[1]])
    assert_lal('7',                     [[7]])
    assert_lal('7',                     [[   7]])
    assert_lal('+',                     [['+]])
    assert_lal('abc',                   [['abc]])
    assert_lal('abc',                   [[   'abc]])
    assert_lal('abc5',                  [['abc5]])
    assert_lal('abc-def',               [['abc-def]])
    assert_lal('"abc"',                 [["abc"]])
    assert_lal('"abc"',                 [[    "abc"]])
    assert_lal('"abc (with parens)"',   [["abc (with parens)"]])
    assert_lal('"abc\\"def"',           [["abc\"def"]])
    assert_lal('""',                    [[""]])
    assert_lal('{"abc" 1}',             [[{"abc" 1}]])
    assert_lal('{"a" {"b" 2}}',         [[{"a" {"b" 2}}]])
    assert_lal('{"a" {"b" {"c" 3}}}',   [[{"a" {"b" {"c" 3}}}]])
    assert_lal('{"a" {"b" {"cde" 3}}}', [[{    "a"   {"b"    { "cde"       3 }   }}]])
    assert_lal('{"a" {"b" {"cde" 3}}}', [[{    a:   {b:    {    cde:       3 }   }}]])
    assert_lal('{"f" f:}',              [[{ 'f f: }]])
end

function oT:testQuasiquote()
    assert_lal('7',           [[(quasiquote 7)]])
    assert_lal('7',           [[`7]])
    assert_lal('(1 2 3)',     [[(quasiquote (1 2 3))]])
    assert_lal('(1 2 3)',     [[`(1 2 3)]])
    assert_lal('(1 2 (3 4))', [[(quasiquote (1 2 (3 4)))]])
    assert_lal('(1 2 (3 4))', [[`(1 2 (3 4))]])
    assert_lal('7',           [[`,7]])
    assert_lal('(a 8)',       [[(begin (define a 8) [`a `,a])]])
    assert_lal('(1 (1 2 4 9 8 7 3) 2 3 4 (101 200 201) 90 100 101 x)', [[
        (begin
            (define x 101)
            `(1
              `(1 2 ,(+ 2 2) ,@(list 9 8 7) 3)
              ,@(list 2 3 (+ 1 3))
              ,[x 200 201]
              90
              100
              ,x
              x))
    ]])

    assert_lal('(1 a 3)',           [[(let ((a 8)) `(1 a 3))]])
    assert_lal('(1 8 3)',           [[(let ((a 8)) `(1 ,a 3))]])
    assert_lal('(1 "b" "d")',       [[(define b '(1 "b" "d"))]])
    assert_lal('(1 b 3)',           [[`(1 b 3)]])
    assert_lal('(1 (1 "b" "d") 3)', [[
        (begin
            (define b '(1 "b" "d"))
            `(1 ,b 3))
    ]])
    assert_lal('(1 c 3)', [[
        (begin
            (define c '(1 "b" "d"))
            `(1 c 3))]])
    assert_lal('(1 1 "b" "d" 3)', [[
        (begin
            (define c '(1 "b" "d"))
            `(1 ,@c 3))
    ]])

    assert_lal('(6 21 6)', [[
        (begin
            (define l (lambda (x) (+ x 1)))
            (define k (l 5))
            (define m `(begin (define k 20) (+ 1 k)))
            [k (eval m) k])
    ]])
    assert_lal('(12 13)', [[
        (begin
            (define F 12)
            (define L (let ((x 10) (y 23)) (begin (define F 13) x F)))
            `(,F ,L))]])

    -- Following test are taken from R4RS-Tests of SCM:
    assert_lal('(list 3 4)',      '`(list ,(+ 1 2) 4)')
    assert_lal('(list a (quote a))', [[(let ((name 'a)) `(list ,name ',name))]])
    assert_lal('(a 3 4 5 6 b)',   [[
        (begin
            (import lua-math)
            `(a ,(+ 1 2) ,@(map lua-math-abs '(4 -5 6)) b))
    ]])
    assert_lal('5', "`,(+ 2 3)")
    assert_lal('(quasiquote (list (unquote (+ 1 2)) 4))',
                "'(quasiquote (list (unquote (+ 1 2)) 4))")

--(test '#(10 5 2 4 3 8) 'quasiquote `#(10 5 ,(sqt 4) ,@(map sqt '(16 9)) 8))
--(test '(a `(b ,(+ 1 2) ,(foo 4 d) e) f)
--      'quasiquote `(a `(b ,(+ 1 2) ,(foo ,(+ 1 3) d) e) f))
--(test '(a `(b ,x ,'y d) e) 'quasiquote
--	(let ((name1 'x) (name2 'y)) `(a `(b ,,name1 ,',name2 d) e)))
--(test '(list 3 4) 'quasiquote (quasiquote (list (unquote (+ 1 2)) 4)))
end

function oT:testMap()
    assert_lal('("1" "2" "3" "4")', [[
        (begin
            (import lua-basic)
            (define str lua-tostring)
            (map str '(1 2 3 4)))]])

    -- compiled map variants:
    assert_lal('((1 1 1) (2 2 2) (3 3 3) (4 4) (5))', [[
        (map
            (lambda (a b c) [a b c])
            [1 2 3 4 5]
            [1 2 3 4]
            [1 2 3])
    ]])
    assert_lal('((2) (4) (6) (8) (10))', [[
        (map (lambda (a) [(* 2 a)]) [1 2 3 4 5])
    ]])
    assert_lal('(1)', [[(map (lambda () 1) '(2))]])

    -- next test the function variants of map:
    assert_lal('((1 1 1) (2 2 2) (3 3 3) (4 4) (5))', [[
        (let ((x map)) (x
            (lambda (a b c) [a b c])
            [1 2 3 4 5]
            [1 2 3 4]
            [1 2 3]))
    ]])
    assert_lal('((2) (4) (6) (8) (10))', [[
        (let ((x map)) (x (lambda (a) [(* 2 a)]) [1 2 3 4 5]))
    ]])
    assert_error('Bad.*2 argum', [[ (map) ]])
    assert_error('Bad.*2 argum', [[ (map (lambda () 10)) ]])

    -- Map as function has no error checking yet, handled by lua:
    assert_lal('(1)', [[ (let ((x map)) (x (lambda () 1))) ]])

    assert_lal('(1 3 6 10)', [[
        (let ((sum 0))
            (map (lambda (x) (set! sum (+ sum x))) '(1 2 3 4)))
    ]])

    assert_lal('((1 x) (2 y))', [[
        (map (lambda (a b) [a b]) '(1 2) '(x y))
    ]])
end

function oT:testForEach()
    -- compiled for-each variants:
    assert_lal('(1 1 1 2 2 2 3 3 3 4 4 5)', [[
        (let ((out []))
          (for-each
           (lambda (a b c) (append! out [a b c]))
           [1 2 3 4 5]
           [1 2 3 4]
           [1 2 3])
          out)
    ]])

    -- next test the function variants of for-each:
    assert_lal('(15 24 6)', [[
        (for-each (lambda (a) [(* 2 a)]) [1 2 3 4 5])
        (let ((y  0)
              (y2 0)
              (y3 0)
              (f  (lambda (x) (set! y (+ x y))))
              (f2 (lambda (x) (set! y2 (+ x y2))))
              (f3 (lambda (x) (set! y3 (+ x y3)))))
          (for-each for-each [f f2 f3] [[4 5 6] [8 8 8] [1 2 3] ])
          [y y2 y3])
    ]])
    assert_lal('nil', [[(for-each (lambda () 1) '(2))]])

    assert_lal('29', [[
        (let ((x for-each) (y 0))
            (x (lambda (a) (set! y a)) [29])
            y)
    ]])

    assert_error('Bad.*2 argum', [[ (for-each) ]])
    assert_error('Bad.*2 argum', [[ (for-each (lambda () 10)) ]])

    assert_lal('10', [[
        (let ((sum 0))
            (for-each (lambda (x) (set! sum (+ sum x))) '(1 2 3 4))
            sum)
    ]])

    assert_lal('(1 x 2 y)', [[
        (let ((out []))
          (for-each (lambda (a b) (append! out [a b])) '(1 2) '(x y))
          out)
    ]])
end

function oT:testAt()
    assert_lal('1', [[ (@0 [1 2 3 4]) ]])
    assert_lal('3', [[ (@2 [1 2 3 4]) ]])
    assert_lal('(1 5 3)', [[
        (let ((x [1 2 3]))
            (@!1 x 5)
            [(@0 x) (@1 x) (@2 x)])
    ]])
    assert_lal('(1 5 3)', [[
        (let ((x [1 2 3])
              (i 1))
            (@!i x 5)
            [(@0 x) (@i x) (@2 x)])
    ]])
    assert_lal('(1 2)', [[ (let ((x [])) (@! 0 x 1) (@! 1 x 2) x) ]])

    assert_lal('13', [[ (@ (return 13) [1 2 3]) ]])
    assert_lal('14', [[ (@1 (return 14)) ]])
    assert_lal('15', [[ (@13 [1 2 (return 15)]) ]])
    assert_lal('16', [[ (@! (return 16) [1 2 3] 99) ]])
    assert_lal('17', [[ (@!1 (return 17) 99)]])
    assert_lal('18', [[ (@! 13 [1 2 (return 18)] 99) ]])

    assert_lal('22', [[ (@!4 [] 22) ]])

    -- Weird case, due to Luas braindamaged Tables:
    assert_lal('{5 22}', [[ (let ((x [])) (@!4 x 22) x) ]])
end

function oT:testDefineFun()
    assert_lal('213', [[
        (begin
            (define (x a b)
                (define y 100)
                (+ (* y a) b))
            (x 2 13))
    ]])

    -- and some other minor lambda syntaxes:
    assert_lal('4000', [[ ((lambda x       (* 200 (@1 x))) #t 20) ]])
    assert_lal('4000', [[ ((lambda (a . x) (* 200 (@0 x))) #t 20) ]])
    assert_lal('4000', [[ ((lambda (x)     (* 200 x))      20) ]])

    assert_lal('5000', [[
        (begin
            (define (a . x) (@1 x))
            (a 1 5000 3))
    ]])
    assert_lal('(1 5001)', [[
        (begin
            (define (a l . x) [ l (@1 x) ])
            (a 1 2 5001 3))
    ]])
end

function oT:testWhenUnlessNot()
    assert_lal('11',     [[ (let ((x 0)) (set! x 2) (when   (> x 1) (set! x 11) x)) ]])
    assert_lal('12',     [[ (let ((x 0)) (set! x 2) (unless (< x 1) (set! x 12) x)) ]])
    assert_lal('nil',    [[ (let ((x 0)) (set! x 2) (when   (< x 1) (set! x 11) x)) ]])
    assert_lal('nil',    [[ (let ((x 0)) (set! x 2) (unless (> x 1) (set! x 12) x)) ]])
    assert_lal('#false', [[ (not #true) ]])
    assert_lal('4613732', [[
        (begin
            (define (fibonacci-seq prev-1 prev-2 func)
                    (let ((fib-num (+ prev-1 prev-2)))
                        (unless (func fib-num)
                            (return fib-num))
                        (fibonacci-seq prev-2 fib-num func)))
            (let ((sum 0))
                (fibonacci-seq 1 1
                            (lambda (fib-num)
                                (when (= (% fib-num 2) 0)
                                    (set! sum (+ sum fib-num)))
                                (< fib-num 4000000)))
                sum))
    ]])
end

function oT:testFor()
    assert_lal('(1 2 3 4)', [[
        (let ((l (list)))
            (for (x 1 4) (concat! l [x]))
            l)
    ]])
    assert_lal('(1 3 5 7)', [[
        (let ((l (list)))
            (for (x 1 8 2) (concat! l [x]))
            l)
    ]])
    assert_lal('123', [[
        (let ((l (list)))
            (for (x 123 333 2) (return x))
            l)
    ]])
    assert_lal('11', [[
        (let ((l (list)))
            (for (x (return 11) 8 2) (return x))
            l)
    ]])
end

function oT:testDoEach()
    assert_lal('11', [[
        (let ((x 0))
            (do-each (v '(2 2 3 4))
                (set! x (+ x v)))
            x)
    ]])
    assert_lal('22', [[
        (let ((x 0))
            (do-each (k v { a: 10 b: 12 })
                (set! x (+ x v)))
            x)
    ]])
    assert_lal('("a" 10)', [[
        (do-each (k v { a: 10 })
            (return [k v]))
    ]])
    assert_lal('23', [[
        (do-each (k v { a: (return 23) b: 12 })
            (return [k v]))
    ]])
end

function oT:testPredicates2()
    assert_lal('#true',  [[ (symbol? 'x) ]])
    assert_lal('#false', [[ (symbol? x:) ]])
    assert_lal('#false', [[ (symbol? [1 2 3]) ]])
    assert_lal('#false', [[ (symbol? { a: 1 b: 2 }) ]])
    assert_lal('#false', [[ (symbol? []) ]])
    assert_lal('#false', [[ (symbol? {}) ]])
    assert_lal('#false', [[ (symbol? #true) ]])
    assert_lal('#false', [[ (symbol? #false) ]])
    assert_lal('#false', [[ (symbol? nil) ]])
    assert_lal('#false', [[ (symbol? 1) ]])
    assert_lal('#false', [[ (symbol? "abc") ]])

    assert_lal('#false', [[ (keyword? 'x) ]])
    assert_lal('#true',  [[ (keyword? x:) ]])
    assert_lal('#false', [[ (keyword? [1 2 3]) ]])
    assert_lal('#false', [[ (keyword? { a: 1 b: 2 }) ]])
    assert_lal('#false', [[ (keyword? {}) ]])
    assert_lal('#false', [[ (keyword? []) ]])
    assert_lal('#false', [[ (keyword? #true) ]])
    assert_lal('#false', [[ (keyword? #false) ]])
    assert_lal('#false', [[ (keyword? nil) ]])
    assert_lal('#false', [[ (keyword? 1) ]])
    assert_lal('#false', [[ (keyword? "abc") ]])

    assert_lal('#false', [[ (list? 'x) ]])
    assert_lal('#false', [[ (list? x:) ]])
    assert_lal('#true',  [[ (list? [1 2 3]) ]])
    assert_lal('#false', [[ (list? { a: 1 b: 2 }) ]])
    assert_lal('#true',  [[ (list? []) ]])
    assert_lal('#true',  [[ (list? {}) ]])
    assert_lal('#false', [[ (list? #true) ]])
    assert_lal('#false', [[ (list? #false) ]])
    assert_lal('#false', [[ (list? nil) ]])
    assert_lal('#false', [[ (list? 1) ]])
    assert_lal('#false', [[ (list? "abc") ]])

    assert_lal('#false', [[ (map? 'x) ]])
    assert_lal('#false', [[ (map? x:) ]])
    assert_lal('#false', [[ (map? [1 2 3]) ]])
    assert_lal('#true',  [[ (map? { a: 1 b: 2 }) ]])
    assert_lal('#false', [[ (map? []) ]])
    assert_lal('#false', [[ (map? {}) ]])
    assert_lal('#false', [[ (map? #true) ]])
    assert_lal('#false', [[ (map? #false) ]])
    assert_lal('#false', [[ (map? nil) ]])
    assert_lal('#false', [[ (map? 1) ]])
    assert_lal('#false', [[ (map? "abc") ]])

    assert_lal('#true',  [[ (string? 'x) ]])
    assert_lal('#true',  [[ (string? x:) ]])
    assert_lal('#false', [[ (string? [1 2 3]) ]])
    assert_lal('#false', [[ (string? { a: 1 b: 2 }) ]])
    assert_lal('#false', [[ (string? []) ]])
    assert_lal('#false', [[ (string? {}) ]])
    assert_lal('#false', [[ (string? #true) ]])
    assert_lal('#false', [[ (string? #false) ]])
    assert_lal('#false', [[ (string? nil) ]])
    assert_lal('#false', [[ (string? 1) ]])
    assert_lal('#true',  [[ (string? "abc") ]])

    assert_lal('#false', [[ (number? 'x) ]])
    assert_lal('#false', [[ (number? x:) ]])
    assert_lal('#false', [[ (number? [1 2 3]) ]])
    assert_lal('#false', [[ (number? { a: 1 b: 2 }) ]])
    assert_lal('#false', [[ (number? []) ]])
    assert_lal('#false', [[ (number? {}) ]])
    assert_lal('#false', [[ (number? #true) ]])
    assert_lal('#false', [[ (number? #false) ]])
    assert_lal('#false', [[ (number? nil) ]])
    assert_lal('#true',  [[ (number? 1) ]])
    assert_lal('#false', [[ (number? "abc") ]])

    assert_lal('#false', [[ (boolean? 'x) ]])
    assert_lal('#false', [[ (boolean? x:) ]])
    assert_lal('#false', [[ (boolean? [1 2 3]) ]])
    assert_lal('#false', [[ (boolean? { a: 1 b: 2 }) ]])
    assert_lal('#false', [[ (boolean? []) ]])
    assert_lal('#false', [[ (boolean? {}) ]])
    assert_lal('#true',  [[ (boolean? #true) ]])
    assert_lal('#true',  [[ (boolean? #false) ]])
    assert_lal('#false', [[ (boolean? nil) ]])
    assert_lal('#false', [[ (boolean? 1) ]])
    assert_lal('#false', [[ (boolean? "abc") ]])

    assert_lal('#false', [[ (nil? 'x) ]])
    assert_lal('#false', [[ (nil? x:) ]])
    assert_lal('#false', [[ (nil? [1 2 3]) ]])
    assert_lal('#false', [[ (nil? { a: 1 b: 2 }) ]])
    assert_lal('#false', [[ (nil? []) ]])
    assert_lal('#false', [[ (nil? {}) ]])
    assert_lal('#false', [[ (nil? #true) ]])
    assert_lal('#false', [[ (nil? #false) ]])
    assert_lal('#true',  [[ (nil? nil) ]])
    assert_lal('#false', [[ (nil? 1) ]])
    assert_lal('#false', [[ (nil? "abc") ]])
end

function oT:testDoLoop()
    assert_lal('(1 2 3 4 5 6)', [[
        (do ((l (list))
             (x 1 (+ x 1)))
            ((> x 6) l)
            (concat! l [x]))
    ]])

    assert_lal('10', [[
        (do ((l (list))
             (y 1 (+ y (return 10)))
             (x 1 (+ x 1)))
            ((> x 6) l)
            (concat! l [x]))
    ]])

    assert_lal('()', [[
        (do ((l (list))
             (y 1 (+ y (return 10)))
             (x 7 (+ x 1)))
            ((> x 6) l)
            (concat! l [x]))
    ]])

    assert_lal('7', [[
        (do ((l (list))
             (y 1 (+ y (return 10)))
             (x (return 7) (+ x 1)))
            ((> x 6) l)
            (concat! l [x]))
    ]])

    assert_lal('8', [[
        (do ((l (list))
             (y (return 8) (+ y (return 10)))
             (x (return 7) (+ x 1)))
            ((> x 6) l)
            (concat! l [x]))
    ]])
    assert_lal('11', [[
        (do ((x 1 (+ x 1)))
            (#t 11)
            (return 11))
    ]])
    assert_lal('12', [[
        (do ((x 1 (+ x 1)))
            (#t 12)
            (return 11))
    ]])

    -- just for checking output manually for TCO:
    assert_lal('17', [[
        (do ((f (lambda (k) (if (> k 1000) (return 17) (f (+ k 1)))))
             (x 1 (+ x 1)))
            (#t (f 0))
            #true)
    ]])

    assert_lal('100', [[
        (let ((y (do ((x 1 (+ x 1))) (#t 100) #true)))
            y)
    ]])
    assert_lal('101', [[
        (let ((y (do ((x 1 (+ x 1))) (#t (return 101)) #true)))
            y)
    ]])
    assert_lal('102', [[
        (let ((y (do ((x 1 (+ x 1))) (#f (return 101)) (return 102))))
            y)
    ]])
    assert_lal('102', [[
        (let ((y (do ((x 1 (+ x 1))) (#f 112) (return 102))))
            y)
    ]])
end

function oT:testCompToLua()
    local sChunk = lal_eval [[
        (compile-to-lua '(let ((x 10)) (+ x 10)))
    ]]
    local x = load(sChunk)
    assert_eq(20, x())

    assert_match([[.*return %(x %+ 10%);.*]],
    lal_eval [[
        (compile-to-lua '(let ((x 10)) (+ x 10)))
    ]])
end

function oT:testBlock()
    assert_lal('13', [[
        (let ((l (block moep
                 (do ((x 1)) ((>= x 16) x)
                     (set! x (+ x 1))
                     (when (= x 13)
                         (return-from moep x))
                 ))))
            l)
    ]])
    assert_lal('16', [[
        (let ((l (block moep
                 (do ((x 1)) ((>= x 16) x)
                     (set! x (+ x 1))
                     (when (= x 19)
                         (return-from moep x))
                 ))))
            l)
    ]])

    assert_lal('45', [[
        (let ((l (block moep
                  (let ((y 0))
                    (for (x 1 10)
                      (set! y (+ y x))
                      (when (> y 40) (return-from moep y)))))))
            l)
    ]])
end

function oT:testCompileErrors()
    assert_error('.*such.*symbol.*%(let', [[(let ((x 10)) y)]])
end

function oT:testInclude()
    local f = io.open("lalTestIncl1.lal", "w")
    f:write([[
    (begin
        (define G 102))
]])
    f:close()
    local f = io.open("lalTestIncl2.lal", "w")
    f:write([[
    (begin
        (define G2 103)
        109)
]])
    f:close()
    local f = io.open("lalTest/lalTestIncl3.lal", "w")
    f:write([[
    (begin
        (include lalTestIncl4)
        108)
]])
    f:close()
    local f = io.open("lalTest/lalTestIncl4.lal", "w")
    f:write([[(define G3 104)]])
    f:close()

    assert_lal('102', [[ (include "lalTestIncl1.lal") ]])
    assert_lal('109', [[ (include lalTestIncl2) ]])
    assert_lal('207', [[
        (begin
            (include "/lalTest/lalTestIncl3.lal" "lalTestIncl2.lal")
            (+ G2 G3))]])

    assert_error('Expected.*1 arg', [[(include)]])
    assert_error('not a string or symbol', [[(include (123))]])
end

function oT:testComments()
    assert_lal('99', [[
            ; fooo
            99 ]])
    assert_lal('99', [[; fofoewofwofwe
        (begin
            99) ]])

    assert_lal('99', [[; fofoewofwofwe
        (begin
            99)
; fofoewofwofwe
]])
    assert_lal('99', [[
        (begin
            ; fooo
            99) ]])
    assert_lal('(foo 323 11)',
        [[ ['foo #;bar #;399 323 #;(* 2 2 3 4) 11] ]])
    assert_lal('(1)', [[
        [
            #| foofeo |#
            1
        ]
    ]])
    assert_lal('(list |# 144)', [[
        '[
        #| FEWO FWPO WOPF W
                    FOIEWJFEIWOWE
                    #' feowfeo feo e
                    |#

        |#
            ; fooo
            144] ]])
    assert_lal('(list 144)', [[
        '[
        #| FEWO FWPO WOPF W
                    FOIEWJFEIWOWE
                    #| feowfeo feo e
                    |#

        |#
            ; fooo
            144] ]])

    assert_lal('(12 224 32543 42)', [[
(list
12
224
32543
42
;
)
]])
    assert_lal('(12 224 32543 42)', [[
;feo
[
12
224
32543
42
;
]
]])

    assert_lal('{"f" 234}', [[
{
;fewo
f: ;feofwfwe
;fewgree
234
;ogore
}
]])
end

function oT:testString()
    assert_eq('\xFF\xFE',        lal_eval [[ "\xFF;\xFE;" ]])
    assert_eq('\r\n\"\a\t\b',    lal_eval [[ "\r\n\"\a\t\b" ]])
    assert_eq('|\\\r\n\"\a\t\b', lal_eval [[ "\|\\\r\n\"\a\t\b" ]])
    assert_eq('   fewfew f ewufi wfew ', lal_eval [[ "   fewfew \
    f ewufi wfew \
        " ]])
    assert_error('values bigger than 0xFF', [[ "\xFFFF;\xFE;" ]])

end

function oT:testMultiLineString()
    assert_eq([[FOO
    BAR]],
        lal_eval [[
        #<<EOS
FOO
    BAR
EOS]])

    assert_eq([[#
FOO42
    BAR]],
        lal_eval [[
        #<#EOS
##
FOO#(+ 2 40)
    BAR
EOS]])
end

function oT:testMacro()
    assert_lal('(1 2 3)', [[
        (begin
            (define-macro (testmak a) `[,a (+ 1 ,a) (+ 2 ,a)])
            (testmak 1))
    ]])
    assert_lal('((list 1 (+ 1 1) (+ 2 1)) (1 2 3))', [[
        (begin
            (define-macro (testmak a)
                `[,a (+ 1 ,a) (+ 2 ,a)])
            [
                (macroexpand (testmak 1))
                (testmak 1)
            ])
    ]])
    assert_lal('((1 2 3) 2 3)', [[
        (begin
            (define-macro (testmak a . x)
                `[ '(,a ,@x) ,(@0 x) ,(@1 x) ])
            (testmak 1 2 3))
    ]])

    assert_lal('13', [[
        (let ((j 10))
            (define-macro (testmak a)
                `(+ j ,a))
            (testmak 3))
    ]])
    assert_lal('50', [[
        (let ((j 10))
            (define-macro (testmak a)
                `(let ((j 20))
                    (+ j ,a)))
            (testmak (+ j 10)))
    ]])
    assert_lal('30', [[
        (let ((j 10))
            (define-macro (testmak a)
                (let ((j (gensym)))
                    `(let ((,j 20))
                        (+ j ,a)))) ; error here, not unquoted j
            (testmak (+ j 10)))
    ]])

    assert_lal('40', [[
        (let ((j 10))
            (define-macro (testmak a)
                (let ((j (gensym)))
                    `(let ((,j 20))
                        (+ ,j ,a))))
            (testmak (+ j 10)))
    ]])
end

function oT:testImport()
    local fh = io.open("test_output_macro_def.lal", "w")
    os.remove("test_output_macro_def_out.lua")
    fh:write([[{
        macro-add: (define-macro (macro-add a b) `(+ ,a ,@b))
        func-mul: (lambda (a b) (* a b 10))
    }]])
    fh:close()
    assert_lal('44', [[
        (import (test_output_macro_def))
        (test_output_macro_def-macro-add 12 32)
    ]]);
    assert_lal('3630', [[
        (import (test_output_macro_def))
        (test_output_macro_def-func-mul 11 33)
    ]]);
end

function oT:testAndOr()
    assert_lal('93', [[
        (let ((x 10))
            (or #f
                (begin (set! x 22) #f)
                (+ x 71)
                (set! x 32)))
    ]])
    assert_lal('99', [[
        (let ((x 10))
            (or #f
                (begin (set! x 22) #f)
                (return 99)
                (+ x 71)
                (set! x 32)))
    ]])
    assert_lal('10', [[
        (let ((x 12)
              (f (lambda () 10)))
            (or #f
                (begin (set! x 22) #f)
                (f)))
    ]])
    assert_lal('22', [[
        (let ((x 12)
              (f (lambda () 10)))
            (or #f
                (begin (set! x 22) #f)
                (f))
            22)
    ]])
    assert_lal('44', [[
        (let ((x 44)
              (f (lambda () 30)))
            (and #f
                (begin (set! x 33) #f)
                (f))
            x)
    ]])
    assert_lal('33', [[
        (let ((x 44)
              (f (lambda () x)))
            (and #t
                (begin (set! x 33) #f)
                (f))
            x)
    ]])
    assert_lal('32', [[
        (let ((x 44)
              (f (lambda () x)))
            (and #t
                (begin (set! x 32) #t)
                (f)))
    ]])
    assert_lal('#false', [[(and 1 3 #f 99)]])
    assert_lal('99', [[(and 1 3 #t 99)]])
    assert_lal('#true', [[(and 1 3 3432 #t)]])
    assert_lal('1', [[(or #f 1 3 3432 #t)]])
    assert_lal('#false', [[(or #f #f ((lambda () #f)) #f)]])
end

function oT:testMagicSquares()
    assert_lal('(#false #true)', [[
        (begin
            (define T2 [ 8 1 6 3 5 7 4 9 2 ])
            (define T1 [ 3 5 7 8 1 6 4 9 2 ])
            ; [8, 1, 6, 3, 5, 7, 4, 9, 2] => true
            ; [2, 7, 6, 9, 5, 1, 4, 3, 8] => true
            ; [3, 5, 7, 8, 1, 6, 4, 9, 2] => false
            ; [8, 1, 6, 7, 5, 3, 4, 9, 2] => false

            (define (cell table x y)
                (@(+ (* x 3) y) table))

            (define (sum-direction table start dir)
                (let ((cx (@0 start))
                      (cy (@1 start))
                      (sum 0))
                    (for (i 0 2)
                        (set! sum (+ sum (cell table cx cy)))
                        (set! cx  (+ cx (@0 dir)))
                        (set! cy  (+ cy (@1 dir))))
                    sum))

            (define (all-eq-to list item)
                (do-each (l list)
                    (when (not (eqv? l item))
                        (return #false)))
                #t)

            (define (test-all-dirs table)
                (let ((d1 (sum-direction table [0 0] [0 1]))
                      (d2 (sum-direction table [1 0] [0 1]))
                      (d3 (sum-direction table [2 0] [0 1]))

                      (d4 (sum-direction table [0 0] [1 1]))
                      (d5 (sum-direction table [0 2] [1 -1]))

                      (d6 (sum-direction table [0 0] [1 0]))
                      (d7 (sum-direction table [0 1] [1 0]))
                      (d8 (sum-direction table [0 2] [1 0])))
                    (all-eq-to [d1 d2 d3 d4 d5 d6 d7 d8] 15)))
            [ (test-all-dirs T1) (test-all-dirs T2) ])
    ]])
end

function oT:testMacroManip()

    assert_lal('1', [[
        (begin
            (define-macro (print-lua-code x)
                (compile-to-lua x)
                x)

            (print-lua-code
                (define (cell lst x y)
                    (@(+ (* x 3) y) lst)))

            (cell [1 2 3] 0 0))
    ]])
end

function oT:testRuntimeError()
    assert_error('.*perform arithmetic', [[
        (begin
            (define (y f)
                (+ f 10))
            (define (x) (y) 100)
            (x)
            102)
    ]])
end

function oT:testOverFldAcc()
    assert_error('symbol argument.*list as sec', [[($^! _ _)]])
    assert_error('basic form.*list as second', [[($^! 23 _)]])
    assert_error('at least 2 arguments', [[($^! (x: m))]])
    assert_lal('219', [[
        (let ((m { x: 120 }))
            ($^! (x: m)
                (+ _ 99))
            ($x: m))
    ]])

    assert_lal('217', [[
        (let ((m { x: 120 }))
            ($^! ("x" m)
                (+ _ 97))
            ($x: m))
    ]])
    assert_lal('218', [[
        (let ((fld x:) (m { x: 120 }))
            ($^! (fld m)
                (+ _ 98))
            ($x: m))
    ]])
    assert_lal('219', [[
        (let ((m { x: 120 }))
            ($^! K (x: m)
                (+ K 99))
            ($x: m))
    ]])

    assert_lal('217', [[
        (let ((m { x: 120 }))
            ($^! K ("x" m)
                (+ K 97))
            ($x: m))
    ]])
    assert_lal('218', [[
        (let ((fld x:) (m { x: 120 }))
            ($^! K (fld m)
                (+ K 98))
            ($x: m))
    ]])
    assert_lal('211', [[
        (let ((fld x:) (m { x: 120 }))
            ($^! ((return 211) m)
                (+ _ 99))
            ($x: m))
    ]])
    assert_lal('200', [[
        (let ((fld x:) (m { x: 120 }))
            ($^! ((set! fld 200) m)
                (return fld)
                (+ _ 99))
            ($x: m))
    ]])


    assert_error('symbol argument.*list as sec', [[(@^! _ _)]])
    assert_error('basic form.*list as second', [[(@^! 23 _)]])
    assert_error('at least 2 arguments', [[(@^! (x: m))]])
    assert_lal('219', [[
        (let ((m [ 22 120 ]))
            (@^! (1 m)
                (+ _ 99))
            (@1 m))
    ]])

    assert_lal('218', [[
        (let ((fld 1) (m [ 292 120 ]))
            (@^! (fld m)
                (+ _ 98))
            (@1 m))
    ]])

    assert_lal('217', [[
        (let ((m [ 120 ]))
            (@^! K (0 m)
                (+ K 97))
            (@0 m))
    ]])
    assert_lal('218', [[
        (let ((fld 1) (m [ x: 120 ]))
            (@^! K (fld m)
                (+ K 98))
            (@1 m))
    ]])
    assert_lal('211', [[
        (let ((fld 0) (m [ 120 ]))
            (@^! ((return 211) m)
                (+ _ 99))
            (@0 m))
    ]])
    assert_lal('200', [[
        (let ((fld 0) (m [ 120 ]))
            (@^! ((set! fld 200) m)
                (return fld)
                (+ _ 99))
            (@0 m))
    ]])
    assert_lal('(1 4)', [[
        (let ((ref @))
            [
                (ref 0 '(1 2 3 4 5))
                (ref 3 '(1 2 3 4 5))
            ])
    ]])
    assert_lal('(5 2 3 4 5)', [[
        (let ((ref! @!) (l '(1 2 3 4 5)))
            (ref! 0 l 5)
            l)
    ]])
end

function oT:testSymbol()
    assert_lal('"t"',    [[(symbol->string 't)]])
    assert_lal('t:',     [[(symbol->string 't:)]])
    assert_lal('t:',     [[(symbol->string t:)]])
    assert_lal('x:',     [[(string->symbol "x:")]])
    assert_lal('#true',  [[(symbol=? 'a (begin 'a) (string->symbol "a"))]])
    assert_lal('#false', [[(symbol=? a: (string->symbol "a:"))]])
end

function oT:testNumeric()
    assert_lal('#false', [[(number? #true)]])
    assert_lal('#true',  [[(number? 1.2)]])
    assert_lal('#true',  [[(number? 1)]])
    if (_VERSION == "Lua 5.3") then
        assert_lal('#true',  [[(integer? 1)]])
    end
    assert_lal('#false', [[(complex? 1)]])
    assert_lal('#false', [[(rational? 1)]])

    if (_VERSION == "Lua 5.3") then
        assert_lal('#true',  [[(exact? 1)]])
        assert_lal('#true',  [[(exact-integer? 1)]])
        assert_lal('#false', [[(exact-integer? 1.2)]])
        assert_lal('#false', [[(exact? 1.1)]])
        assert_lal('#false', [[(exact? 1.0)]])
        assert_lal('#true',  [[(inexact? 1.0)]])
        assert_lal('#true',  [[(inexact? 1.2)]])
        assert_lal('#false', [[(inexact? 1)]])
    end

    assert_lal('#true',  [[(zero? 0)]])
    assert_lal('#true',  [[(zero? 0.0)]])
    assert_lal('#false', [[(zero? 1)]])
    assert_lal('#false', [[(zero? 0.1)]])
    assert_lal('#true',  [[(positive? 0.0)]])
    assert_lal('#true',  [[(positive? 0.1)]])
    assert_lal('#true',  [[(positive? 1)]])
    assert_lal('#false', [[(positive? -0.1)]])
    assert_lal('#false', [[(positive? -1)]])
    assert_lal('#false', [[(negative? 0.0)]])
    assert_lal('#false', [[(negative? 0.1)]])
    assert_lal('#false', [[(negative? 1)]])
    assert_lal('#true',  [[(negative? -0.1)]])
    assert_lal('#true',  [[(negative? -1)]])

    assert_lal('#true',  [[(odd? 1)]])
    assert_lal('#false', [[(odd? 2)]])
    assert_lal('#false', [[(even? 1)]])
    assert_lal('#true',  [[(even? 2)]])

    assert_lal('7',      [[(abs -7)]])
    assert_lal('7.4',    [[(abs -7.4)]])

    assert_lal('4',      [[(max 3 4)]])
    if (_VERSION == "Lua 5.3") then
        assert_lal('4.0',    [[(max 3.9 4.0)]])
    else
        assert_lal('4',      [[(max 3.9 4.0)]])
    end

    assert_lal('3.2',    [[(min 3.2 4.2)]])
    assert_lal('-3',     [[(min -3 4.2)]])

    assert_lal('2',      [[(floor/             5 2)]])
    assert_lal('2',      [[(floor-quotient     5 2)]])
    assert_lal('1',      [[(floor-remainder    5 2)]])

    assert_lal('-3',     [[(floor/             -5 2)]])
    assert_lal('-3',     [[(floor-quotient     -5 2)]])
    assert_lal('1',      [[(floor-remainder    -5 2)]])

    assert_lal('-3',     [[(floor/             5 -2)]])
    assert_lal('-3',     [[(floor-quotient     5 -2)]])
    assert_lal('-1',     [[(floor-remainder    5 -2)]])

    assert_lal('2',      [[(floor/             -5 -2)]])
    assert_lal('2',      [[(floor-quotient     -5 -2)]])
    assert_lal('-1',     [[(floor-remainder    -5 -2)]])

    assert_lal('2',      [[(truncate/           5 2)]])
    assert_lal('2',      [[(truncate-quotient   5 2)]])
    assert_lal('1',      [[(truncate-remainder  5 2)]])

    assert_lal('-2',     [[(truncate/          -5 2)]])
    assert_lal('-2',     [[(truncate-quotient  -5 2)]])
    assert_lal('-1',     [[(truncate-remainder -5 2)]])

    assert_lal('-2',     [[(truncate/           5 -2)]])
    assert_lal('-2',     [[(truncate-quotient   5 -2)]])
    assert_lal('1',      [[(truncate-remainder  5 -2)]])

    assert_lal('2',      [[(truncate/           -5 -2)]])
    assert_lal('2',      [[(truncate-quotient   -5 -2)]])
    assert_lal('-1',     [[(truncate-remainder  -5 -2)]])

    assert_lal('#true',  [[(= truncate-remainder remainder)]])
    assert_lal('#true',  [[(= truncate-quotient quotient)]])
    assert_lal('#true',  [[(= modulo floor-remainder)]])

    assert_lal('4',      [[(gcd 32 -36)]])
    assert_lal('4',      [[(gcd 32 36)]])
    assert_lal('0',      [[(gcd)]])
    assert_lal('1',      [[(lcm)]])
    if (_VERSION == "Lua 5.3") then
        assert_lal('288.0',  [[(lcm 32 -36)]]) -- difference to scheme, which returns exact num
        assert_lal('288.0',  [[(lcm 32.0 -36)]])
    else
        assert_lal('288',    [[(lcm 32 -36)]]) -- difference to scheme, which returns exact num
        assert_lal('288',    [[(lcm 32.0 -36)]])
    end

    assert_lal('-5',     [[(floor -4.3)]]) -- diff to scheme -5.0
    assert_lal('-4',     [[(truncate -4.3)]])
    assert_lal('-4',     [[(ceiling -4.3)]])
    assert_lal('-4',     [[(round -4.3)]])

    assert_lal('3',      [[(floor 3.5)]])
    assert_lal('3',      [[(truncate 3.5)]])
    assert_lal('4',      [[(ceiling 3.5)]])
    assert_lal('4',      [[(round 3.5)]])

    assert_lal('#true',  [[(and (< (exp 1) 2.72) (> (exp 1) 2.718))]])
    if (_VERSION == "Lua 5.3") then
        assert_lal('1.0',    [[(exp 0)]])
    else
        assert_lal('1',      [[(exp 0)]])
    end

    assert_lal('"4.5"',  [[(number->string 4.5)]])
    assert_lal('"4"',    [[(number->string 4)]])
    assert_lal('"10"',   [[(number->string 16 16)]])
    assert_lal('"21"',   [[(number->string 33 16)]])

    assert_lal('33',     [[(string->number "21" 16)]])
    assert_lal('17',     [[(string->number "21" 8)]])
    assert_lal('100',    [[(string->number "100")]])
    assert_lal('256',    [[(string->number "100" 16)]])
    if (_VERSION == "Lua 5.3") then
        assert_lal('100.0',  [[(string->number "1e2")]])
    else
        assert_lal('100',    [[(string->number "1e2")]])
    end

    -- TODO: Rational/Complex parser syntax!?
    -- TODO: Complete Float parser syntax!?
end

function oT:testListOps()
    assert_lal('(1 2 3 x:)',       [[(append  '(1 2 3) x:)]])
    assert_lal('(1 2 3 x:)',       [[(append  '(1 2 3) [x:])]])
    assert_lal('(1 2 3 x:)',       [[(append! '(1 2 3) x:)]])
    assert_lal('(1 2 3 x:)',       [[(let ((l '(1 2 3))) (append! l x:) l)]])
    assert_lal('(1 2 3 x:)',       [[(let ((l '(1 2 3))) (append! l '(x:)) l)]])
    assert_lal('(1 2 3 (x:))',     [[(let ((l '(1 2 3))) (append! l ['(x:)]) l)]])
    assert_lal('(1 2 3)',          [[(let ((l '(1 2 3))) (append l x:) l)]])
    assert_lal('0',                [[(length '())]])
    assert_lal('0',                [[(let ((l length)) (l '()))]])
    assert_lal('0',                [[(length [])]])
    assert_lal('3',                [[(length '(a b c))]])
    assert_lal('3',                [[(let ((l length)) (l '(a b c)))]])
    assert_lal('3',                [[(length '(a (b) (c d e)))]])
    assert_lal('(e d c b a)',      [[(reverse '(a b c d e))]])
    assert_lal('(a b c d e)',      [[(list-tail '(a b c d e) 0)]])
    assert_lal('(d e)',            [[(list-tail '(a b c d e) 3)]])
    assert_lal('()',               [[(list-tail '(a b c d e) 5)]])
    assert_lal('c',                [[(list-ref  '(a b c d e) 2)]])
    assert_lal('(a b 99 d e)',     [[(let ((x '(a b c d e))) (list-set! x 2 99) x)]])
    assert_lal('((e d) (a b c))',  [[(let ((x '(a b c d e)) (y (pop! x 2))) [y x])]])
    assert_lal('(e (a b c d))',    [[(let ((x '(a b c d e)) (y (pop! x 1))) [y x])]])
    assert_lal('(e (a b c d))',    [[(let ((x '(a b c d e)) (y (pop! x))) [y x])]])
end

function oT:testEquality()
    assert_lal('#true',   [[(eqv? #t #t)]])
    assert_lal('#true',   [[(eqv? #f #f)]])
    assert_lal('#true',   [[(eqv? 't (string->symbol "t"))]])
    assert_lal('#true',   [[(eqv? t: (string->keyword "t"))]])
    assert_lal('#true',   [[(eqv? 2 (/ 4 2))]])
    assert_lal('#true',   [[(eqv? 2 (/ 4.0 2.0))]]) -- diff to scheme
    assert_lal('#true',   [[(eqv? 2.0 (/ 4.0 2.0))]])
    assert_lal('#false',  [[(eqv? [] [])]]) -- diff to scheme
    assert_lal('#false',  [[(eqv? {} {})]]) -- diff to scheme
    assert_lal('#true',   [[(eqv? "foo" (symbol->string 'foo))]])
    assert_lal('#true',   [[(eqv? + (let ((y +)) y))]])
    assert_lal('#true',   [[(let ((m { x: 11 }) (l #f)) (set! l m) (eqv? m l))]])
    assert_lal('#true',   [[(let ((p (lambda (x) x))) (eqv? p p))]])
    assert_lal('#false',  [[(eqv? { x: 11 } { x: 10 })]])
    assert_lal('#false',  [[(eqv? 2 (/ 5 2))]])
    assert_lal('#false',  [[(eqv? t: (string->symbol "t"))]])
    assert_lal('#false',  [[(eqv? #f #t)]])
    assert_lal('#false',  [[(eqv? #f 0)]])
    assert_lal('#false',  [[(eqv? #f [])]])
    assert_lal('#true',   [[(eqv? 2.0 2)]]) -- another diff to scheme

    assert_lal('#true',   [[(eq? #t #t)]])
    assert_lal('#true',   [[(eq? #f #f)]])
    assert_lal('#true',   [[(eq? 't (string->symbol "t"))]])
    assert_lal('#true',   [[(eq? t: (string->keyword "t"))]])
    assert_lal('#true',   [[(eq? t:: (string->keyword "t:"))]])
    assert_lal('#true',   [[(eq? 2 (/ 4 2))]])
    assert_lal('#true',   [[(eq? 2 (/ 4.0 2.0))]]) -- diff to scheme
    assert_lal('#true',   [[(eq? 2.0 (/ 4.0 2.0))]])
    assert_lal('#false',  [[(eq? [] [])]]) -- diff to scheme
    assert_lal('#false',  [[(eq? {} {})]]) -- diff to scheme
    assert_lal('#true',   [[(eq? "foo" (symbol->string 'foo))]])
    assert_lal('#true',   [[(eq? + (let ((y +)) y))]])
    assert_lal('#true',   [[(let ((m { x: 11 }) (l #f)) (set! l m) (eq? m l))]])
    assert_lal('#true',   [[(let ((p (lambda (x) x))) (eq? p p))]])
    assert_lal('#false',  [[(eq? { x: 11 } { x: 10 })]])
    assert_lal('#false',  [[(eq? 2 (/ 5 2))]])
    assert_lal('#false',  [[(eq? t: (string->symbol "t"))]])
    assert_lal('#false',  [[(eq? #f #t)]])
    assert_lal('#false',  [[(eq? #f 0)]])
    assert_lal('#false',  [[(eq? #f [])]])
    assert_lal('#true',   [[(eq? 2.0 2)]]) -- another diff to scheme

    assert_lal('#true',   [[(let ((x eqv?)) (x #t #t))]])
    assert_lal('#false',  [[(let ((x eqv?)) (x #t #f))]])
end

function oT:testCyclicStructs()
    assert_lal('"#0=(1 2 3 4 #0#)"',
               [[ (write-str (read-str "#0=(1 2 3 4 #0#)")) ]])
    assert_lal('"#0=(1 #1={x: (list #0# #1#)} 3 4 #0#)"',
               [[ (write-str (read-str "#2=(1 #4={ x: [#2# #4#] } 3 4 #2#)")) ]])
end

function oT:testEqual()
    assert_lal('#true',   [[(equal? 'a 'a)]])
    assert_lal('#false',  [[(equal? 'a 'b)]])
    assert_lal('#false',  [[(equal? '(a) '(a b))]])
    assert_lal('#false',  [[(equal? '(a) '(a b))]])
    assert_lal('#false',  [[(equal? '(a a) '(a b))]])
    assert_lal('#true',   [[(equal? '(a a) '(a a))]])
    assert_lal('#true',   [[(equal? ['a 'b [1 2 3 ] ] ['a 'b [1 2 3] ])]])
    assert_lal('#true',   [[(equal? "abc" "abc")]])
    assert_lal('#true',   [[(equal? 2 2)]])
    assert_lal('#true',   [[(equal? { a: 10 b: 20 } { b: 20 a: 10 })]])
    assert_lal('#false',  [[(equal? { a: 10 b: 20 } { b: 20 a: 11 })]])
    assert_lal('#true',   [[(equal? { a: [1 2 3] b: 20 } { b: 20 a: [1 2 3] })]])
    assert_lal('#false',  [[(equal? (read-str "#0=('a 'b #0#)") (read-str "#1=('a 'b #1#)"))]])
        -- diff to scheme, but it terminates at least
end

function oT:testNilSentinel()
    assert_lal('nil',     [[nil]])
    assert_error('Expected not nil', [[(nil)]])
    assert_error('Expected not nil', [[(nil nil)]])
    assert_lal('()',      [[ [nil] ]])
    assert_lal('()',      [[ [nil nil] ]])
    assert_lal('(1 2)', [[
        (let ((l [1 2 3]))
            (@!2 l nil)
            l)
    ]])
    assert_lal('#true',  [[(nil?  nil)]])
    assert_lal('#false', [[(list? nil)]])
    assert_lal('#false', [[(map?  nil)]])
    assert_lal('#true',  [[(nil?  'nil)]])
    assert_lal('#false', [[(list? 'nil)]])
    assert_lal('#false', [[(map?  'nil)]])
end

function oT:testParser()
    assert_lal('(1 2 3)', [[ (let((x[1 2 3]))x) ]])
end

function oT:testWriteReadCyclic()
    assert_lal('"#0=(1 2 #0#)"', [[
        (let ((x [1 2]))
            (push! x x)
            (write-str x))
    ]])
    assert_lal('"#0=(1 #0# #1={\\"a\\" #1#})"', [[
        (let ((x [1]) (m { }))
            ($!a: m m)
            (push! x x)
            (push! x m)
            (write-str x))
    ]])
    assert_lal('"(#0=(1 #0#) #0# #1={\\"a\\" #0#} #1#)"', [[
        (let ((x [1]) (k {a: x}) (y [x x k k]))
            (push! x x)
            (write-str y))
    ]])
    assert_lal('"(#0=() #0# ())"', [[
        (let ((x []) (k [x x [] ]))
            (write-str k))
    ]])
end

function oT:testDisplay()
    assert_lal('"(foo foo foo {a hallo da})10"', [[
        (let ((o []))
            (import lua-table)
            (display '("foo" foo foo: { a: "hallo da" }) o)
            (display ($a: { a: 10 }) o)
            (lua-table-concat o))
    ]])

    assert_lal('"(x foobar)"', [[
        (let ((out (open-output-string)))
            (display '(x "foobar") out)
            (get-output-string out))
        ;=> "xfoobar"
    ]])

    assert_lal('"(x foobar)"', [[
        (let ((out []))
            (display '(x "foobar") out)
            (get-output-string out))
        ;=> "xfoobar"
    ]])

end

function oT:testStr()
    assert_lal('"foobar test123x"',
               [[(str "foobar" " " test: 1 2 3 'x)]])
    assert_lal('"foobar, ,test,1,2,3,x"',
               [[(str-join "," "foobar" " " test: 1 2 3 'x)]])
    assert_lal('"one word,another-word,and-a-symbol,(1 2 3)"',
               [[(str-join "," "one word" another-word: 'and-a-symbol '(1 2 3))]])

    assert_lal('123,foobar', [[
        (begin
            (import (lua table))
            (lua-table-concat ['"\xFE;123" "foobar"] ","))
    ]])

    assert_lal('"foo1236"', [[
        (let ((x (+ 1 2 3)))
            (str "foo" 123 x)) ;=> "foo1236"
    ]])
end

function oT:testExceptions()
    assert_lal('"Exception: Something is weird!"', [[
        (with-exception-handler
            (lambda (err) (str Exception: ": " err))
            (lambda ()
                (when (zero? 0)
                    (raise "Something is weird!"))))
    ]])
    assert_lal('"Exception: Something is weird!"', [[
        (with-exception-handler
            (lambda (err) (str Exception: ": " (error-object-message err)))
            (lambda ()
                (when (zero? 0)
                    (error "Something is weird!" 192))))
    ]])
    assert_lal('#true', [[
        (with-exception-handler
            (lambda (err) (error-object? err))
            (lambda () (error 123)))
    ]])
    assert_lal('(1 2 3)', [[
        (with-exception-handler
            (lambda (err) (error-object-irritants err))
            (lambda () (error 123 1 2 3)))
    ]])
    assert_lal('"[string \\"*LAL*"', [[
        (begin
            (import (lua basic))
            (import (lua string))
            (with-exception-handler
                (lambda (err) (lua-string-sub err 1 14))
                (lambda () (lua-error "FOOBAR"))))
    ]])

    -- TODO: add (guard ...)
end

function oT:testCurrentLine()
    assert_match([[<eval>:4]],
                 lal_eval [[
                     (begin
                         (import (lal syntax compiler))
                         2130
                         (lal-syntax-compiler-current-source-pos))
                 ]])
end

--function oT:testLetrecSDefine()
--    assert_lal('19', [[
--        (define (x) y)
--        (define y 19)
--        x
--    ]])
--
--    assert_lal('(24 23)', [[
--        (define (x) y)
--        (begin
--            (set! g 23)
--            (define y 24))
--        (define g 22)
--        [x g]
--    ]])
--end

-- TODO: (define-values ...) (let-values ...) and so on

-- TODO: add (cond ...)
function oT:testCond()
    assert_lal('none', [[
        ((lambda () (cond ((> 3 3) 'greater)
              ((< 3 3) 'less)
              (else   'none))))
    ]])
    assert_lal('3492', [[
        (cond (else (+ 3491 1)))
    ]])
    assert_lal('greater', [[
        (cond ((> 3 2) 'greater)
              ((< 3 2) 'less))
    ]])
    assert_lal('less', [[
        (cond ((> 2 3) 'greater)
              ((< 2 3) 'less))
    ]])
    assert_lal('nil', [[
        (cond ((> 3 3) 'greater))
    ]])
    assert_lal('#true', [[
        (cond ((eqv? 3 3)))
    ]])
    assert_lal('333', [[
        (cond ((eqv? 3 3) => (lambda (x) 333)))
    ]])
    assert_lal('333', [[
        (let ((x (cond ((eqv? 3 3)
                        => (lambda (x) 333)))))
          (+ x 1)
          x)
    ]])
    assert_lal('623', [[
        (cond ((return 623)))
    ]])
    assert_lal('73', [[
        (let ((x 10))
            (cond ((not (set! x (+ x 1)) 20))
                  ((return (+ 62 x)))))
    ]])
    assert_lal('73', [[
        (let ((x 10))
            (cond ((not (set! x (+ x 1)) 20))
                  ((return (+ 62 x)))
                  (else 32)))
    ]])
    assert_lal('444', [[
        (let ((x 10))
            (cond ((not (set! x (+ x 1)) 20))
                  (23 => (return 444))
                  ((return 623))))
    ]])
    assert_lal('623', [[
        (+ 1 (cond ((return 623))))
    ]])
    assert_lal('73', [[
        (+ 1 (let ((x 10))
            (cond ((not (set! x (+ x 1)) 20))
                  ((return (+ 62 x))))))
    ]])
    assert_lal('73', [[
        (+ 1 (let ((x 10))
            (cond ((not (set! x (+ x 1)) 20))
                  ((return (+ 62 x)))
                  (else 32))))
    ]])
    assert_lal('444', [[
        (+ 1 (let ((x 10))
            (cond ((not (set! x (+ x 1)) 20))
                  (23 => (return 444))
                  ((return 623)))))
    ]])
    -- TODO: Test returning tests!
end

function oT:testApply()
    assert_lal('6',     [[(apply + 1 2 3 [])]])
    assert_lal('6',     [[(apply + 1 2 3 (list))]])
    assert_lal('-1',    [[(apply - 0 (list 1))]])
    assert_lal('-1',    [[(apply - (list 0 1))]])
    assert_lal('"X,Y"', [[(apply str-join "," (list X: Y:))]])
end

function oT:testAltStringQuote()
    assert_lal('"foobar"', [[#q'foobar']])
    assert_lal('"X\\"X"', [[#q'X"X']])
    assert_lal('"X\'\\"X"', [[#q'X''"X']])
    assert_lal('"X\\\\\\"X"', [[#q'X\"X']])
    assert_lal('"X\\nX"', [[#q'X
X']])
end

-- TODO
--function oT:testMacroUsesFunction()
--    assert_lal('120', [[
--        (begin
--            (define (x a b) [+ a b])
--            (define-macro (l m a) (x m 10))
--            (l 2 4))
--    ]])
--
--end
--
-- TODO: add test for (str ....)

--
-- TODO: make most of the following tests work:
--    assert_lal('; BukaLisp Exception at Line -1: First symbol '$:abc' of (abc 1 2 3) not found in env!',  [[(abc 1 2 3)]])
--    assert_lal('; BukaLisp Exception at Line -1: Symbol '$:undefvar' not found in env!',  [[undefvar]])
--    assert_lal('; "B" nil 10
--    ; "A"
--    ; "OOO" (#<prim:+> 2 3) 5
--    ;=>nil', lal_eval [[(begin (prn "A") (when-compile :eval (define y 10)) (let* (x 20) (begin (when-compile :eval (begin (define o (list + 2 3)) (prn "B" x y))) (define k (when-compile :eval-compile o)) (prn "OOO" o k))))]])
--    assert_lal('("1" "2" "3" "4")',  [[(begin (map str '(1 2 3 4)))]])
--    assert_lal('("1" "2" "3" "4")',  [[(begin (map str [1 2 3 4]))]])
--    assert_lal('(":l1")',  [[(begin (map str '{:l 1}))]])
--    assert_lal('"x"',  [[(begin (map str 'x))]])
--    assert_lal('(2 4 6 8)',  [[(begin (map (lambda* (x) (* 2 x)) '(1 2 3 4)))]])
--    assert_lal('(2 4 6 8)',  [[(begin (map (lambda* (x) (* 2 x)) [1 2 3 4]))]])
--    assert_lal('(2)',  [[(begin (map (lambda* (k x) (* 2 x)) '{:l 1}))]])
--    assert_lal('20',  [[(begin (map (lambda* (x) (* 2 x)) 10))]])
--    assert_lal('; 203
--    ; 424
--    ;=>30', lal_eval [[(let* (x 10 y 20) (prn (* 20.3 x)) (prn (* 21.2 y)) (+ x y))]])
--    assert_lal('; A
--    ; B
--    ;=>10', lal_eval [[(begin (prn 'A) (prn 'B) 10)]])
--    assert_lal('; 21 22
--    ;=>53', lal_eval [[(begin (define x (lambda* (x y) (prn x y) (+ x y 10))) (x 21 22))]])
--    assert_lal('; A
--    ; B
--    ; X
--    ; Y
--    ;=>21', lal_eval [[(begin (prn 'X) (let* (l (when-compile :eval (prn 'A) (prn 'B) 21)) (prn 'Y) l))]])
--    assert_lal('2',  [[(at '(1 2 3) 1)]])
--    assert_lal(':foo',  [[(at {:a 43 :x :foo :b "bar"} :x)]])
--    assert_lal('foo',  [[(at ['foo 'bar 'x] 0)]])
--    assert_lal('(1 2 4)',  [[(begin (define x '(1 2 3)) (set-at! x 2 4) x)]])
--    assert_lal('[1 2 (1 2 3)]',  [[(begin (define x [1 2 3]) (set-at! x 2 '(1 2 3)) x)]])
--    assert_lal('(f :f)',  [[(begin (define x { }) (set-at! x 'f :f) (set-at! x :f 'f) (list (at x :f) (at x 'f)))]])
--    assert_lal('; BukaLisp Exception at Line -1: Can't set undefined variable '$:XXX'',  [[(let (y 12) (set! XXX 20) XXX)]])
--    assert_lal('13',  [[(let (y 12) (set! y 13) y)]])
--    assert_lal('10',  [[(begin (define X (lambda () (return 10) 20)) (define Y (lambda () (define Y (X)) (return Y) 32)) (Y))]])
--    assert_lal('; A 20
--    ; B 11
--    ;=>30', lal_eval [[(begin
--        (define X (lambda (a)
--            (if (> a 10)
--                (+ 400 (begin
--                    (println "A" a)
--                    (+ 10 (return 20))
--                    (println "NOREACH")))
--                (begin
--                    (println "B" (+ a 10))
--                    (return 30)))))
--    (X 20)
--    (X 1))]])
--    assert_lal('420',  [[(let (f 40) (try (let (f 3) (+ (throw 10) 3 f)) (catch x (* x (i+ 2 f)))))]])
--    assert_lal('; "A"
--    ; Got: :C
--    ;=>133', lal_eval [[(begin (define X (lambda () (prn "A") (throw :C) (prn "B"))) (let (o 33) (+ o (try (X) (catch L (println "Got:" L) 100)))))]])
--    assert_lal('; "FOOBAR"
--    ; "FINALLY!" 100
--    ; your-mom "was thrown" 200
--    ;=>your-mom', lal_eval [[(let (fooo 200)
--        (try
--           (let (fooo 100)
--              (with-final
--                 (begin
--                    (prn "FOOBAR")
--                    (throw 'your-mom)
--                    (prn "FOOBAR2"))
--                 (prn "FINALLY!" fooo)))
--           (catch x (prn x "was thrown" fooo) x)))]])
--    assert_lal('; "FOOBAR"
--    ; "FOOBAR2"
--    ; "FINALLY!" 100
--    ;=>nil', lal_eval [[(let (fooo 200)
--        (try
--           (let (fooo 100)
--              (with-final
--                 (begin
--                    (prn "FOOBAR")
--                    (prn "FOOBAR2"))
--                 (prn "FINALLY!" fooo)))
--           (catch x (prn x "was thrown" fooo) x)))]])
--    assert_lal('; "FINAL-X-THROW"
--    ; "FINAL-TRY"
--    ; "caught" 10
--    ;=>10', lal_eval [[(begin
--        (define Y (lambda (a) (throw a)))
--        (define X (lambda () (with-final (Y 10) (try (throw :l) (catch l (prn "FINAL-X-THROW"))))))
--        (try
--            (with-final (X) (prn "FINAL-TRY"))
--            (catch y (prn "caught" y) y))
--    )]])
--    assert_lal('; "FIN"
--    ; "caught" 1
--    ;=>1', lal_eval [[(begin
--        (try
--            (with-final (map throw (list 1 2)) (prn "FIN"))
--            (catch y
--                (prn "caught" y)
--                y))
--    )]])
--    assert_lal('; "FIN"
--    ; "INNER"
--    ;=>2', lal_eval [[(try (with-final (throw :x) (begin (prn "FIN") (with-final (throw 2) (prn "INNER"))))
--         (catch y y))]])
--    assert_lal('; "A"
--    ; "B"
--    ; "C"
--    ;=>:y', lal_eval [[(begin
--        (with-final (begin (prn "A") (return :x) (prn "0"))
--            (prn "B") (with-final (return :y) (prn "C"))) (prn "D"))]])
--    assert_lal('; "A"
--    ; "B"
--    ;=>:bla', lal_eval [[(begin (try
--        (with-final (begin (prn "A") (return :x) (prn "0"))
--            (prn "B")
--            (with-final (return :y)
--                (throw :bla)
--                (prn "C")))
--        (catch l l)))]])
--    assert_lal('; 0
--    ; 1
--    ; 2
--    ; 3
--    ; 4
--    ; 5
--    ; 6
--    ; 7
--    ; 8
--    ; 9
--    ;=>90', lal_eval [[(loop for (i 0 (< i 10) (i+ i 1))
--         (prn i)
--         (* i 10))]])
--    assert_lal('; :A
--    ; :B
--    ; :1-X
--    ;=>50', lal_eval [[(block 'x
--       (prn :A) 
--       (block 'y
--           4
--          (return-from 'y 30)
--          (prn :D))
--       (prn :B)
--       (block 'y
--           (prn :1-X)
--           (return-from 'x 50)
--           (prn :2-X))
--       (prn :C))]])
--    assert_lal('; :A
--    ;=>:GOGO', lal_eval [[(begin
--        (define X (lambda () (prn :A) (return-from 'GOGO :GOGO) (prn :B)))
--        (X))]])
--    assert_lal('; :A-X
--    ; :GOGO
--    ;=>nil', lal_eval [[(begin
--        (define X (lambda () (prn :A-X) (return-from 'GOGO :GOGO)))
--        (define L (lambda (f) (block 'GOGO (f))))
--        (prn (L X)))]])
--    assert_lal('; :X
--    ;=>:A', lal_eval [[(block 'A ((lambda () (prn :X) (return :A))))]])
--    assert_lal('; :A-X
--    ; :A-Y
--    ; :GOGO 30
--    ;=>nil', lal_eval [[(begin
--        (define X (lambda () (prn :A-X) (return-from 'GOGO :GOGO)))
--        (define L (lambda (f) (block 'GOGO (f))))
--        (define Y (lambda () (prn :A-Y) (return 30)))
--        (println (L X) (L Y)))]])
--    assert_lal('; :ef
--    ;=>nil', lal_eval [[(begin
--        (define X (lambda () (return-from 'GOGO :ef)))
--        (define L (lambda () (block 'GOGO (X))))
--        (println (L)))]])
--    assert_lal('100',  [[(begin
--        (ns $O [$] ($:when-compile :eval ($:define $:define $:define)) (define L 100))
--        (ns $X [$ $O:] (define OOO L))
--        $X:OOO)]])
--    assert_lal('; 10
--    ; 20
--    ; 30
--    ;=>nil', lal_eval [[(begin
--        (ns pman [$:]
--            (define x 10)
--            (define print (lambda (y) (println y)))
--            (ns XXX [] (define O print)))
--        ($:pman:print 10)
--        (ns pman []
--            (print 20))
--        ($:pman:XXX:O 30))]])
--    assert_lal('[:A :X :E :B]',  [[(begin
--        (ns $foo [$:define]
--            (define a :A)
--            (define b :B)
--            (define c :C)
--            (define d :D))
--        (ns $bar [$:define] (define e :E) (define b :X))
--        (ns user [$foo:a $bar:]
--            [a b e $foo:b]))]])
--    assert_lal('10',  [[(begin (ns $ [] ($:define FO 10)) FO)]])
--    assert_lal('[20 10 20]',  [[(begin
--        (define $foox:X 10)
--        [(ns $foox [] ($:define Y X) ($:set! X 20)) $foox:Y X])]])
--    assert_lal('33',  [[(begin
--        (ns fooER [] ($:define X 20))
--        (set! $:fooER:X 33)
--        (ns fooER [] X))]])
--    assert_lal('(quasiquote 1)',  [['`1]])
--    assert_lal('(quasiquote (1 2 3))',  [['`(1 2 3)]])
--    assert_lal('(unquote 1)',  [[',1]])
--    assert_lal('(splice-unquote (1 2 3))',  [[',@(1 2 3)]])
--    assert_lal('; BukaLisp Exception at Line 1: Expected ')', got: T_EOF@1',  [[(1 2]])
--    assert_lal('; BukaLisp Exception at Line 1: Expected ']', got: T_EOF@1',  [[[1 2]])
--    assert_lal('; BukaLisp Exception at Line 1: Expected '"', got: T_EOF@1',  [["abc]])
--    assert_lal('(with-meta [1 2 3] {"a" 1})',  [['^{"a" 1} [1 2 3] ;; Comment test]])
--    assert_lal('(deref a)',  [['@a ; comment test]])

-----------------------------------------------------------------------------

-- WITH ERROR CHECKING:
--oT:run { 'testFn' }
--oT:run { 'testCompileErrors' }
--oT:run { 'testOpsAsFn' }
--oT:run { 'testOpErrors' }
--oT:run { 'testLength' }
--oT:run { 'testMap' }
--oT:run { 'testInclude' }
--oT:run { 'testComments' }
--oT:run { 'testString' }
--oT:run { 'testMultiLineString' }
--oT:run { 'testStr' }
--oT:run { 'testMacro' }
--oT:run { 'testAndOr' }
--oT:run { 'testMagicSquares' }
--oT:run { 'testMacroManip' }
--oT:run { 'testRuntimeError' }
--oT:run { 'testOverFldAcc' }
--oT:run { 'testParser' }

--oT:run { 'testCond' }
--oT:run { 'testEquality' }
--oT:run { 'testEqual' }
--oT:run { 'testSymbol' }
--oT:run { 'testNumeric' }
--oT:run { 'testListOps' }
--oT:run { 'testNilSentinel' }
--oT:run { 'testDisplay' }
--oT:run { 'testExceptions' }
--oT:run { 'testDefBuiltin' }
--oT:run { 'testCyclicStructs' }

--oT:run { 'testImport' }

-- WITHOUT ERROR CHECKING:
--oT:run { 'testSideeffectIgnore' }
--oT:run { 'testDo' }
--oT:run { 'testBool' }
--oT:run { 'testLet' }
--oT:run { 'testReturn' }
--oT:run { 'testReturnAnyWhere' }
--oT:run { 'testLetWOBody' }
--oT:run { 'testLetEmpty' }
--oT:run { 'testReturnInLetBody' }
--oT:run { 'testReturnFromFn' }
--oT:run { 'testIf' }
--oT:run { 'testIfOneBranchFalse' }
--oT:run { 'testIfReturn' }
--oT:run { 'testIfFalseReturn' }
--oT:run { 'testLuaTOC' }
--oT:run { 'testLuaTOCWithLetS' }
--oT:run { 'testQuotedList' }
--oT:run { 'testSimpleArith' }
--oT:run { 'testIfBool' }
--oT:run { 'testBasicData' }
--oT:run { 'testDef' }
--oT:run { 'testLet2' }
--oT:run { 'testLetList' }
--oT:run { 'testKeyword' }
--oT:run { 'testQuote' }
--oT:run { 'testUnusedRetValsAndBuiltins' }
--oT:run { 'testPredicates1' }
--oT:run { 'testPrStrRdStr' }
--oT:run { 'testEval' }
--oT:run { 'testEQ' }
--oT:run { 'testFunctionDef' }
--oT:run { 'testTailIf' }
--oT:run { 'testConsConcat' }
--oT:run { 'testDefGlobal' }
--oT:run { 'testDotSyntax' }
--oT:run { 'testSideeffectIgnore' }
--oT:run { 'testValueEvaluation' }
--oT:run { 'testQuasiquote' }

--oT:run { 'testAt' }
--oT:run { 'testDefineFun' }

--oT:run { 'testWhenUnlessNot' }
--oT:run { 'testFor' }
--oT:run { 'testDoEach' }
--oT:run { 'testPredicates2' }
--oT:run { 'testDoLoop' }
--oT:run { 'testCompToLua' }
--oT:run { 'testBlock' }
--oT:run { 'testWriteReadCyclic' }
--oT:run { 'testDefineSyntax' }
--oT:run { 'testApply' }
--oT:run { 'testForEach' }
--oT:run { 'testAltStringQuote' }
-- TODO oT:run { 'testMacroUsesFunction' }

oT:run()
