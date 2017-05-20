-- See Copyright Notice in lal.lua

local class   = require 'lal.util.class'
local List    = require 'lal.util.list'
local Logfile = require 'lal.util.logfile'
-----------------------------------------------------------------------------

local test_case = {}

local s_current_test_case
-----------------------------------------------------------------------------

function test_case.diag(fmt, ...)
    s_current_test_case:log(fmt, ...)
end
-----------------------------------------------------------------------------

function test_case.ok(is_ok, msg)
    if (not is_ok) then
        error(string.format("not ok: %s", tostring(msg)))
    end
end
-----------------------------------------------------------------------------

function test_case.assert_match(a, b, msg)
    if (not(string.match(tostring(b), a))) then
        error(
            string.format("assert_match: %s\nExpected '%s',\nGot      '%s'",
                tostring(msg),
                tostring(a),
                tostring(b)));
    end
end
-----------------------------------------------------------------------------

function test_case.assert_eq(a, b, msg)
    if (a ~= b) then
        error(
            string.format("assert_eq: %s\nExpected '%s',\nGot      '%s'",
                tostring(msg),
                tostring(a),
                tostring(b)));
    end
end
-----------------------------------------------------------------------------

local TestCase = class()

test_case.TestCase = TestCase

local s_test_cnt     = 0
local s_test_run_cnt = 0
local s_test_ok      = 0

function TestCase:init(name, expected_cnt)
    if (not expected_cnt) then expected_cnt = 0 end

    local test_out_dir = ".\\testOutput"

    self.name           = name
    self.expected_cnt   = expected_cnt
    self.extra_los_path = test_out_dir .. "_" .. name .. ".txt"
end
-----------------------------------------------------------------------------

function TestCase:log(fmt, ...)
    print(string.format(fmt, ...))
    self.logfile:log(fmt .. "\n", ...)
end
-----------------------------------------------------------------------------

function TestCase:run(tests)
    if (tests) then
        self.expected_cnt = #tests
    end

    s_current_test_case = self

    os.remove(self.extra_los_path)
    self.logfile = Logfile(self.extra_los_path .. "_out")

    local function log(fmt, ...) self:log(fmt, ...) end

    local function format_error(error_msg)
        return string.gsub(error_msg, "([^\n]*)\r?\n?", function (line)
            return "# " .. line .. "\n"
        end)
    end

    local function runProtected(method_name, func, reaction_func)
        local is_ok, error_msg = xpcall(function ()
            func(self)
        end, function (msg)
            return method_name .. ": " .. msg .. "\nTraceback:\n" .. debug.traceback()
        end)
        if (not is_ok) then
            reaction_func(error_msg)
        else
            reaction_func()
        end
    end

    print(string.format("# next: %s", self.name))
    log("1..%d", self.expected_cnt)

    local cnt    = 0
    local ok_cnt = 0

    local is_prepared = true
    if (self.prepare) then
        runProtected("prepare", function () self:prepare() end, function (error_msg)
            if (error_msg) then log("# Prepare Failed: %s", format_error(error_msg))
                           is_prepared = false
            else           log("# Prepare ok") end
        end)
    end

    if (is_prepared) then
        local test_methods = List()

        if (tests) then
            test_methods = List(tests)
        else
            for method_name, func in pairs(self) do
                if (string.sub(method_name, 1, 4) == "test") then
                    test_methods:push(method_name)
                end
            end
        end
        test_methods:sort()
        test_methods:foreach(function (method_name)
            local func         = self[method_name]
            local test_postfix = string.sub(method_name, 5)
            local test_name    = self.name .. "." .. method_name
            cnt = cnt + 1

            local bPrepared = true
            if (self["prepare" .. test_postfix]) then
                runProtected("prepare " .. method_name, function () self["prepare" .. test_postfix](self) end, function (error_msg)
                    if (error_msg) then
                        error_msg = format_error(error_msg)
                        log("not ok %d - prepare %s\n%s", cnt, test_name, error_msg)
                        bPrepared = false
                    end
                end)
            end

            if (bPrepared) then
                local is_ok, test_err_msg = false, "unknown"
                runProtected(method_name, function () func(self) end, function (error_msg)
                    if (error_msg) then
                        is_ok        = false
                        test_err_msg = error_msg
                    else
                        is_ok = true
                    end
                end)

                if (self["cleanup" .. test_postfix]) then
                    runProtected("cleanup " .. method_name, function () self["cleanup" .. test_postfix](self) end, function (error_msg)
                        if (error_msg) then
                            is_ok          = false
                            test_err_msg = error_msg
                        end
                    end)
                end

                if (is_ok) then
                    log("ok %d - %s", cnt, test_name)
                    ok_cnt = ok_cnt + 1
                else
                    test_err_msg = format_error(test_err_msg)
                    log("not ok %d - %s\n%s", cnt, test_name, test_err_msg)
                end
            end
        end)

        if (self.cleanup) then
            local is_ok, error_msg = xpcall(function () self:cleanup() end, function (error_msg)
                if (error_msg) then
                    log("# Cleanup Failed: %s", format_error(error_msg))
                    ok_cnt = 0
                else
                    log("# Cleanup ok")
                end
            end)
        end
    end

    s_test_ok      = s_test_ok  + ok_cnt
    s_test_cnt     = s_test_cnt + self.expected_cnt
    s_test_run_cnt = s_test_run_cnt + cnt

    local lbl = "OK"
    if (ok_cnt ~= cnt) then
        lbl = "FAIL"
    end
    if (cnt ~= self.expected_cnt) then
        lbl = "FAIL"
    end

    log("# %s %s (%d OF %d OK, %d of %d were run)",
        lbl, self.name, ok_cnt, self.expected_cnt, cnt, self.expected_cnt)

    self.logfile:close()
    os.rename(self.extra_los_path .. "_out", self.extra_los_path)
end
-----------------------------------------------------------------------------

function test_case.TestCaseSummary()
    local ok_cnt  = s_test_ok
    local cnt     = s_test_cnt
    local run_cnt = s_test_run_cnt

    local lbl = "OK"
    if (ok_cnt ~= cnt) then
        lbl = "FAIL"
    end
    if (cnt ~= run_cnt) then
        lbl = "FAIL"
    end

    print(string.format("# %s (%d OF %d OK, %d of %d were run)",
                        lbl, ok_cnt, cnt, run_cnt, cnt))
end
-----------------------------------------------------------------------------

return test_case
