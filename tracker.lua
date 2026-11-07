-- Depth Egg Chase Tracker (Event / Whirlpool / Boss) + Mini GUI
-- Webhook URL diisi lewat GUI dan disimpan lokal (dec_settings.json), bukan di file ini.

-- restart-safe: hentikan instance lama jika ada
if getgenv().TRACKER_STOP then pcall(getgenv().TRACKER_STOP) end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local req = request or http_request

----------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------
local alive = true
local conns, threads, gui = {}, {}, nil
local status = {}

local function track(c) conns[#conns+1] = c return c end
local function spawnLoop(fn)
    local t = task.spawn(fn)
    threads[#threads+1] = t
    return t
end

local function stop()
    if not alive then return end
    alive = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, t in ipairs(threads) do pcall(task.cancel, t) end
    conns, threads = {}, {}
    if gui then pcall(function() gui:Destroy() end) end
    if getgenv().TRACKER_STOP == stop then getgenv().TRACKER_STOP = nil end
end
getgenv().TRACKER_STOP = stop

local function safe(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    status[name] = ok and "OK" or "FAIL"
    if not ok then warn("[Tracker:" .. name .. "] " .. tostring(err)) end
    return ok
end

local function safeRequire(path)
    local ok, m = pcall(require, path)
    if ok and type(m) == "table" then return m end
    return nil
end

local function hook(remote, fn)
    return track(remote.OnClientEvent:Connect(function(...)
        if alive then pcall(fn, ...) end
    end))
end

local function findRemotes(name)
    local list = {}
    for _, v in ipairs(RS:GetDescendants()) do
        if v:IsA("RemoteEvent") and v.Name == name then list[#list+1] = v end
    end
    return list
end

----------------------------------------------------------------
-- SETTINGS (tersimpan)
----------------------------------------------------------------
local FILE = "dec_settings.json"
local settings = {
    EventOn = true, WhirlpoolOn = true, BossOn = true, AntiAFK = false,
    EventWebhook = "", WhirlpoolWebhook = "", BossWebhook = "",
}
pcall(function()
    if isfile and isfile(FILE) then
        for k, v in pairs(HttpService:JSONDecode(readfile(FILE))) do
            if settings[k] ~= nil then settings[k] = v end
        end
    end
end)
local function save()
    pcall(function() writefile(FILE, HttpService:JSONEncode(settings)) end)
end

local ROLE = { event = "", whirlpool = "", boss = "" } -- contoh: "<@&123456789>"
local BOT = { event = "Event Tracker", whirlpool = "Whirlpool Tracker", boss = "Boss Tracker" }
local BOSS_NAME = {
    Boss1 = "Reef Turtle", Boss2 = "Anchor Crab", Boss3 = "Kraken",
    Boss4 = "Lantern Leviathan", Boss5 = "Ruin Titan",
}

----------------------------------------------------------------
-- SENDER
----------------------------------------------------------------
local MAP = {event = "Event", whirlpool = "Whirlpool", boss = "Boss"}

local function validUrl(u)
    return type(u) == "string" and u:find("^https://[%w%.]*discord[%w%.]*/api/webhooks/") ~= nil
end

local function send(cat, embed, force)
    if not alive or not req then return end
    if not force and not settings[MAP[cat] .. "On"] then return end
    local url = settings[MAP[cat] .. "Webhook"]
    if not validUrl(url) then return end
    embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    task.spawn(function()
        pcall(req, {
            Url = url, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                username = BOT[cat],
                content = (not force and ROLE[cat] ~= "") and ROLE[cat] or nil,
                embeds = {embed},
            })
        })
    end)
end

local function pretty(s) return (tostring(s):gsub("(%l)(%u)", "%1 %2")) end
local function color3(c)
    if typeof(c) ~= "Color3" then return 5793266 end
    return math.floor(c.R*255)*65536 + math.floor(c.G*255)*256 + math.floor(c.B*255)
end

----------------------------------------------------------------
-- 1) EVENTS
----------------------------------------------------------------
safe("Event", function()
    local ecfg = safeRequire(RS.Shared.Config.EventsConfig)
    assert(ecfg, "EventsConfig tidak bisa dibaca")
    local folder = RS:WaitForChild(ecfg.STATE_FOLDER_NAME, 30)
    assert(folder, "folder LiveEvents tidak ada")

    local PANTAU = {Galaxy=1, Rainbow=1, Cyber=1, Dragon=1, Meow=1,
        Blizzard=1, SugarRush=1, StarShower=1, Party=1, GhostShip=1}
    local EEMOJI = {Galaxy="🌌", Rainbow="🌈", Cyber="🤖", Dragon="🐉", Meow="🐱",
        Blizzard="❄️", SugarRush="🍭", StarShower="🌠", Party="🪩", GhostShip="👻"}

    local aktif = {}
    local function cekEvent(id)
        if not alive or not PANTAU[id] then return end
        local ends = folder:GetAttribute(id .. "EndsAt")
        local now = workspace:GetServerTimeNow()
        local on = type(ends) == "number" and ends > now
        local e = ecfg.EVENTS[id]
        local nama, emoji = pretty(id), EEMOJI[id] or "🎉"

        if on and aktif[id] ~= ends then
            aktif[id] = ends
            local unix = os.time() + math.floor(ends - now)
            local fields = {
                {name = "⏳ Ends", value = "<t:" .. unix .. ":R>", inline = true},
                {name = "⏱ Time left", value = math.floor((ends - now) / 60) .. " min", inline = true},
            }
            if e and e.Mutation then
                local m = ecfg.MUTATIONS[e.Mutation]
                fields[#fields+1] = {name = "🧬 Mutation", value = e.Mutation, inline = true}
                if m then
                    fields[#fields+1] = {name = "🎲 Chance", value = (m.Chance * 100) .. "%", inline = true}
                    fields[#fields+1] = {name = "💰 Money", value = m.MoneyMultiplier .. "x", inline = true}
                end
                fields[#fields+1] = {name = "📍 Applies", value = e.Moment == "Catch" and "When catching" or "While transporting", inline = true}
            elseif id == "Dragon" then
                fields[#fields+1] = {name = "🌍 Type", value = "World event", inline = true}
            end
            send("event", {
                title = emoji .. "  " .. nama .. " Event Started",
                description = "A live event is now active in this server.",
                color = color3(e and e.Color), fields = fields,
                footer = {text = "Live Events"},
            })
        elseif not on and aktif[id] then
            aktif[id] = nil
            send("event", {title = "⌛  " .. nama .. " Event Ended", color = 9807270,
                footer = {text = "Live Events"}})
        end
    end

    for _, id in ipairs(ecfg.EVENT_ORDER) do
        track(folder:GetAttributeChangedSignal(id .. "EndsAt"):Connect(function()
            pcall(cekEvent, id)
        end))
        pcall(cekEvent, id)
    end
    spawnLoop(function()
        while alive do
            task.wait(30)
            for _, id in ipairs(ecfg.EVENT_ORDER) do pcall(cekEvent, id) end
        end
    end)
end)

----------------------------------------------------------------
-- 2) WHIRLPOOL
----------------------------------------------------------------
local nW = 0
safe("Whirlpool", function()
    local ZONA = {
        [1]="Fresh River",[2]="Coral Reef",[3]="Dark Abyss",[4]="Toxic Swamp",
        [5]="Industrial Port",[6]="Oil Tank",[7]="Volcanic Pit",[8]="Storm Abyss",
        [9]="Mythic Pit",[10]="Cosmos Origin",[11]="Primal Waters",[12]="Crystal Caverns",
        [13]="Celestial Realm",[14]="Glitch Rift",[15]="Divine Throne",[16]="Frozen Eternity",
        [17]="Sunken Atlantis",[18]="Shadow Realm",[19]="Star Forge",[20]="Infinity Core"
    }
    local WFILTER = {Legendary = true, Mythic = true, Secret = true}
    local WCOLOR = {Legendary = 16766720, Mythic = 11141375, Secret = 16777215}
    local WEMOJI = {Legendary = "🟡", Mythic = "🟣", Secret = "⚪"}
    local WRANK = {Legendary = 1, Mythic = 2, Secret = 3}
    local lastW, lastWT = "", 0

    local function whirlpool(data)
        if type(data) ~= "table" or type(data.spots) ~= "table" then return end
        local list, key, best = {}, {}, nil
        for _, s in ipairs(data.spots) do
            if type(s) == "table" and WFILTER[s.rarity] then
                list[#list+1] = s
                key[#key+1] = s.rarity .. tostring(s.zoneId)
                if not best or WRANK[s.rarity] > WRANK[best] then best = s.rarity end
            end
        end
        if #list == 0 then return end
        local k = table.concat(key, ",")
        if k == lastW and tick() - lastWT < 60 then return end
        lastW, lastWT = k, tick()

        table.sort(list, function(a, b) return WRANK[a.rarity] > WRANK[b.rarity] end)
        local fields = {}
        for _, s in ipairs(list) do
            fields[#fields+1] = {
                name = WEMOJI[s.rarity] .. "  " .. s.rarity,
                value = "📍 **" .. (ZONA[s.zoneId] or ("Zone " .. tostring(s.zoneId))) .. "**",
                inline = true,
            }
        end
        send("whirlpool", {
            title = "🌀  Rare Whirlpool Spawned",
            description = "Resets every 5 minutes. Highest rarity: **" .. best .. "**",
            color = WCOLOR[best], fields = fields,
            footer = {text = "Whirlpool Reset"},
        })
    end

    for _, r in ipairs(findRemotes("RareSpotsSpawned")) do
        nW += 1
        hook(r, whirlpool)
    end
    assert(nW > 0, "remote RareSpotsSpawned tidak ditemukan")
end)

----------------------------------------------------------------
-- 3) BOSS
----------------------------------------------------------------
local nB = 0
safe("Boss", function()
    local bcfg = safeRequire(RS.Shared.Config.BossConfig)
    assert(bcfg, "BossConfig tidak bisa dibaca")
    local tier = {}
    for _, b in ipairs(bcfg.BOSSES) do tier[b.Id] = b.Tier end
    local BCOLOR = {Easy=5763719, Fierce=16753920, Strong=15105570, Legendary=16766720, Mythic=11141375}
    local BEMOJI = {Easy="🟢", Fierce="🟠", Strong="🔴", Legendary="🟡", Mythic="🟣"}
    local lastB = {}

    local function bossSpawn(id, src)
        id = tostring(id)
        if not alive or not tier[id] then return end
        if lastB[id] and tick() - lastB[id] < 240 then return end
        lastB[id] = tick()
        local t = tier[id]
        send("boss", {
            title = "👹  Boss Fight: " .. (BOSS_NAME[id] or id),
            description = "A boss has appeared in the Boss sea!",
            color = BCOLOR[t] or 15158332,
            fields = {
                {name = (BEMOJI[t] or "") .. " Tier", value = t, inline = true},
                {name = "🆔 ID", value = id, inline = true},
                {name = "⚔️ Fight", value = bcfg.FIGHT_SECONDS .. " sec", inline = true},
                {name = "⏳ Ends", value = "<t:" .. (os.time() + bcfg.FIGHT_SECONDS) .. ":R>", inline = true},
                {name = "🎁 Chests", value = tostring(bcfg.CHESTS_BY_TIER[t] or "?"), inline = true},
                {name = "🥚 Egg chance", value = ((bcfg.BOSS_EGG_CHANCE_BY_TIER[t] or 0) * 100) .. "%", inline = true},
            },
            footer = {text = "Boss spawns every " .. (bcfg.INTERVAL_SECONDS / 60) .. " min • via " .. src},
        })
    end

    for _, r in ipairs(findRemotes("BossAttack")) do
        nB += 1
        hook(r, function(d)
            if type(d) == "table" and d.bossId then bossSpawn(d.bossId, "BossAttack") end
        end)
    end
    for _, r in ipairs(findRemotes("BossRewarded")) do
        hook(r, function()
            send("boss", {title = "🏆  Boss Defeated", description = "Rewards have been distributed.",
                color = 9807270, footer = {text = "Boss Tracker"}})
        end)
    end

    track(workspace.DescendantAdded:Connect(function(o)
        if alive and tier[o.Name] and o:IsA("Model") then
            task.defer(bossSpawn, o.Name, "Workspace")
        end
    end))
    for _, o in ipairs(workspace:GetDescendants()) do
        if tier[o.Name] and o:IsA("Model") then bossSpawn(o.Name, "Workspace") end
    end
end)

----------------------------------------------------------------
-- 4) ANTI-AFK (terpisah, gagal tidak memengaruhi tracker)
----------------------------------------------------------------
safe("AntiAFK", function()
    local vu = game:GetService("VirtualUser") -- error bila tidak ada -> status FAIL
    track(Players.LocalPlayer.Idled:Connect(function()
        if not alive or not settings.AntiAFK then return end
        pcall(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    end))
end)

----------------------------------------------------------------
-- 5) GUI
----------------------------------------------------------------
safe("GUI", function()
    gui = Instance.new("ScreenGui")
    gui.Name = "DECMiniControl"
    gui.ResetOnSpawn = false
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local FULL_H = 345
    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(270, FULL_H)
    main.Position = UDim2.new(0.5, -135, 0.5, -FULL_H / 2)
    main.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
    main.BorderSizePixel = 0
    main.Active = true
    main.ClipsDescendants = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 9)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(65, 75, 95)
    stroke.Parent = main

    local function label(parent, text, size, pos, color, font)
        local o = Instance.new("TextLabel")
        o.BackgroundTransparency = 1
        o.Size, o.Position = size, pos
        o.Font = font or Enum.Font.Gotham
        o.Text, o.TextSize = text, 11
        o.TextColor3 = color or Color3.fromRGB(230, 230, 235)
        o.TextXAlignment = Enum.TextXAlignment.Left
        o.Parent = parent
        return o
    end

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 35)
    header.BackgroundColor3 = Color3.fromRGB(34, 39, 49)
    header.BorderSizePixel = 0
    header.Parent = main
    label(header, "DEPTH EGG CHASE", UDim2.new(1, -80, 1, 0), UDim2.fromOffset(12, 0),
        Color3.fromRGB(110, 190, 255), Enum.Font.GothamBold)

    local function headBtn(text, xOff, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(28, 28)
        b.Position = UDim2.new(1, xOff, 0, 3)
        b.Text, b.TextSize, b.Font = text, 20, Enum.Font.Gotham
        b.TextColor3 = color
        b.BackgroundTransparency = 1
        b.Parent = header
        return b
    end
    local minBtn = headBtn("–", -62, Color3.fromRGB(200, 205, 215))
    local closeBtn = headBtn("×", -33, Color3.fromRGB(255, 120, 120))

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 1, -35)
    body.Position = UDim2.fromOffset(0, 35)
    body.BackgroundTransparency = 1
    body.Parent = main

    local collapsed = false
    minBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        body.Visible = not collapsed
        main.Size = UDim2.fromOffset(270, collapsed and 35 or FULL_H)
    end)
    closeBtn.MouseButton1Click:Connect(stop) -- menghentikan SEMUA

    -- drag
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, i.Position, main.Position
        end
    end)
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))

    local function makeToggle(name, y, key)
        label(body, name, UDim2.fromOffset(150, 22), UDim2.fromOffset(12, y))
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(55, 22)
        btn.Position = UDim2.new(1, -67, 0, y)
        btn.Font, btn.TextSize = Enum.Font.GothamBold, 10
        btn.Parent = body
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local function refresh()
            local on = settings[key]
            btn.Text = on and "ON" or "OFF"
            btn.BackgroundColor3 = on and Color3.fromRGB(35, 145, 95) or Color3.fromRGB(65, 70, 80)
            btn.TextColor3 = Color3.new(1, 1, 1)
        end
        btn.MouseButton1Click:Connect(function()
            settings[key] = not settings[key]
            refresh()
            save()
        end)
        refresh()
    end

    local function mask(u)
        if not u or u == "" then return "" end
        return "••••••••" .. u:sub(-6)
    end

    local function makeInput(name, y, key)
        label(body, name, UDim2.fromOffset(240, 15), UDim2.fromOffset(12, y))
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, -24, 0, 25)
        box.Position = UDim2.fromOffset(12, y + 16)
        box.BackgroundColor3 = Color3.fromRGB(38, 43, 53)
        box.TextColor3 = Color3.fromRGB(230, 230, 235)
        box.PlaceholderColor3 = Color3.fromRGB(135, 140, 150)
        box.PlaceholderText = "Paste webhook URL..."
        box.Text = mask(settings[key])
        box.TextSize, box.Font = 10, Enum.Font.Gotham
        box.ClearTextOnFocus = false
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.Parent = body
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)

        box.Focused:Connect(function() box.Text = settings[key] or "" end)
        box.FocusLost:Connect(function()
            local t = box.Text:gsub("^%s+", ""):gsub("%s+$", "")
            if t == "" or validUrl(t) then
                settings[key] = t
                save()
            end
            box.Text = mask(settings[key])
        end)
    end

    makeToggle("Event tracker", 8, "EventOn")
    makeToggle("Whirlpool tracker", 34, "WhirlpoolOn")
    makeToggle("Boss tracker", 60, "BossOn")
    makeToggle("Anti-AFK" .. (status.AntiAFK == "FAIL" and " (unsupported)" or ""), 86, "AntiAFK")

    makeInput("EVENT WEBHOOK", 120, "EventWebhook")
    makeInput("WHIRLPOOL WEBHOOK", 172, "WhirlpoolWebhook")
    makeInput("BOSS WEBHOOK", 224, "BossWebhook")

    local test = Instance.new("TextButton")
    test.Size = UDim2.new(1, -24, 0, 26)
    test.Position = UDim2.fromOffset(12, 278)
    test.BackgroundColor3 = Color3.fromRGB(45, 90, 160)
    test.Text, test.TextSize, test.Font = "Send test", 11, Enum.Font.GothamBold
    test.TextColor3 = Color3.new(1, 1, 1)
    test.Parent = body
    Instance.new("UICorner", test).CornerRadius = UDim.new(0, 6)
    test.MouseButton1Click:Connect(function()
        for cat in pairs(MAP) do
            send(cat, {title = "✅ Test " .. cat, description = "Webhook connected.", color = 5763719}, true)
        end
        test.Text = "Sent!"
        task.delay(1.5, function() if alive then test.Text = "Send test" end end)
    end)

    label(body, "Event:" .. tostring(status.Event) .. "  Whirl:" .. tostring(status.Whirlpool)
        .. "  Boss:" .. tostring(status.Boss), UDim2.new(1, -20, 0, 14), UDim2.fromOffset(12, 308),
        Color3.fromRGB(130, 140, 155))
end)

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Tracker aktif",
        Text = "Event:" .. tostring(status.Event) .. " Whirl:" .. tostring(status.Whirlpool)
            .. " Boss:" .. tostring(status.Boss) .. " AFK:" .. tostring(status.AntiAFK),
        Duration = 8,
    })
end)
