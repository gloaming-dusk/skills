-- Template scenario for templates/headless-test.sh. Copy to
-- tests/headless-<name>-init.lua and replace the steps.
--
-- Steps run one after another, each after the previous one settled. A failed
-- check logs the reason and quits, so the test fails at once instead of
-- waiting for its timeout. The last step logs "<name>: PASS".

local NAME = "example"
local A = shady.automation
local probe = assert(os.getenv("SHADY_AUTOMATION_PROBE"), "SHADY_AUTOMATION_PROBE is not set")

local function check(cond, message)
    if not cond then error(NAME .. ": " .. message, 2) end
end

local function window(app_id)
    for _, w in ipairs(shady.windows()) do
        if w.app_id == app_id then return w end
    end
end

-- Delays of at least 1 ms keep this working on Shady builds before 53537a7,
-- where shady.automation.after(0, fn) never fires.
local steps = {}
local function step(ms, fn) steps[#steps + 1] = { ms, fn } end
local function run(i)
    local s = steps[i]
    if not s then
        shady.log(NAME .. ": PASS")
        shady.quit()
        return
    end
    A.after(s[1], function()
        local ok, err = pcall(s[2])
        if not ok then
            shady.log(tostring(err))
            shady.quit()
            return
        end
        run(i + 1)
    end)
end

-- What the test exercises: a binding of its own, driven like a real key.
shady.bind("Super+m", function()
    local w = shady.focused_window()
    if w then w:maximize() end
end)

step(100, function()
    check(window("probe-a"), "the probe did not map")
    check(shady.focused_window().app_id == "probe-a", "the probe is not focused")
end)
step(50, function()
    check(A.key("Super+m"), "Super+m was not handled")
end)
step(300, function()
    check(window("probe-a").maximized, "Super+m did not maximize the window")
end)
step(50, function()
    A.key("Super+m")
end)
step(300, function()
    check(not window("probe-a").maximized, "a second Super+m did not restore the window")
end)

-- Start once the probe is on screen; a fixed sleep would be flaky.
local started = false
shady.on("window.mapped", function(w)
    if started or w.app_id ~= "probe-a" then return end
    started = true
    run(1)
end)

-- A safety net: never hang the suite if the probe never maps.
A.after(10000, function()
    if not started then
        shady.log(NAME .. ": the probe never mapped")
        shady.quit()
    end
end)

shady.spawn(string.format("SHADY_AUTOMATION_PROBE_APP_ID=probe-a %q", probe))
