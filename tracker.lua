-- Depth Egg Chase Tracker v2 (Event / Whirlpool / Boss + icons + boss announce)
-- Webhook URL diisi lewat GUI dan disimpan lokal (dec_settings.json), bukan di file ini.

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
    EventOn = true, WhirlpoolOn = true, BossOn = true, AntiAFK = false, ESPOn = false,
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

----------------------------------------------------------------
-- DATA
----------------------------------------------------------------
local ROLE = { event = "", whirlpool = "", boss = "" } -- contoh: "<@&123456789>"
local BOT = { event = "Event Tracker", whirlpool = "Whirlpool Tracker", boss = "Boss Tracker" }

local BOSS_NAME = {
    Boss1 = "Reef Turtle", Boss2 = "Wreck Hermit", Boss3 = "Wreck Kraken",
    Boss4 = "Abyss Angler", Boss5 = "Sunken Colossus",
}
local BOSS_IMG = {
    Boss1 = "135969045489171", Boss2 = "91541828326228", Boss3 = "108629696919919",
    Boss4 = "110716306093479", Boss5 = "73206167535657",
}

local ZONA = {
    [1]="Sweetwater River",[2]="Coral Reef",[3]="Dark Abyss",[4]="Toxic Swamps",
    [5]="Industrial Port",[6]="Oil Tank",[7]="Volcanic Pit",[8]="Electric Chasm",
    [9]="Mythic Pit",[10]="Cosmos Origin",[11]="Primal Waters",[12]="Crystal Caverns",
    [13]="Celestial Realm",[14]="Glitch Rift",[15]="Divine Throne",[16]="Eternal Ice",
    [17]="Sunken Atlantis",[18]="Shadow Realm",[19]="Star Forge",[20]="Infinity Core",
}
local ZONE_IMG = {
    [1]="96751112953590",[2]="124745314407800",[3]="99759987820688",[4]="138223515590070",
    [5]="127009423028934",[6]="101374565815446",[7]="110693852627398",[8]="101162427941327",
    [9]="129859817996825",[10]="113754142641639",[11]="125747812176467",[12]="125359547158980",
    [13]="84216613170087",[14]="83809169356358",[15]="113016186681166",[16]="139671950305375",
    [17]="113236757283093",[18]="121305240478494",[19]="107389957846847",[20]="94603751918890",
}

local EVENT_IMG = {
    Galaxy="104364450871096", Rainbow="75914146300571", Cyber="117130703313612",
    Dragon="79544478110435", Meow="121714187311045", Blizzard="113271520069988",
    SugarRush="125430530884874", StarShower="82455943848103", Party="129677202517494",
    GhostShip="124460078953936",
}
local EEMOJI = {Galaxy="🌌", Rainbow="🌈", Cyber="🤖", Dragon="🐉", Meow="🐱",
    Blizzard="❄️", SugarRush="🍭", StarShower="🌠", Party="🪩", GhostShip="👻"}
local EICON = {Galaxy="1f30c", Rainbow="1f308", Cyber="1f916", Dragon="1f409",
    Meow="1f431", Blizzard="2744", SugarRush="1f36d", StarShower="1f320",
    Party="1faa9", GhostShip="1f47b"}

----------------------------------------------------------------
-- ICONS + SENDER
----------------------------------------------------------------
local TWEMOJI = "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/%s.png"
local iconCache = {}

local function iconUrl(id)
    id = tostring(id or ""):match("%d+")
    if not id or not req then return nil end
    if iconCache[id] ~= nil then return iconCache[id] or nil end
    local pending = false
    for attempt = 1, 2 do
        local ok, res = pcall(req, {
            Url = "https://thumbnails.roblox.com/v1/assets?assetIds=" .. id .. "&size=420x420&format=Png",
            Method = "GET",
        })
        if not (ok and res and res.Body) then break end
        local ok2, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
        local e = ok2 and type(d) == "table" and d.data and d.data[1]
        if e and e.state == "Completed" and e.imageUrl and e.imageUrl ~= "" then
            iconCache[id] = e.imageUrl
            return e.imageUrl
        elseif e and e.state == "Pending" and attempt == 1 then
            pending = true
            task.wait(1.5)
        else
            pending = false
            break
        end
    end
    if not pending then iconCache[id] = false end
    return nil
end

local MAP = {event = "Event", whirlpool = "Whirlpool", boss = "Boss"}

----------------------------------------------------------------
-- GAMBAR: gambar UI Roblox tidak tampil di Discord, jadi dipakai gambar dari GitHub.
-- Taruh PNG di folder icons/ repo, lalu isi IMG_BASE. Kosong = emoji saja.
-- Nama file: event_Galaxy.png, boss_Boss4.png, zone_9.png (huruf besar/kecil berpengaruh)
----------------------------------------------------------------
local IMG_BASE = "https://raw.githubusercontent.com/bluekidbuu/DEC-Tracker/main/icons/"
local USE_ROBLOX_IMG = false -- API thumbnail Roblox: gambar UI game rusak di Discord

local IMG_FILE = {}
for k, v in pairs(EVENT_IMG) do IMG_FILE[v] = "event_" .. k .. ".png" end
for k, v in pairs(BOSS_IMG) do IMG_FILE[v] = "boss_" .. k .. ".png" end
for k, v in pairs(ZONE_IMG) do IMG_FILE[v] = "zone_" .. k .. ".png" end

local fileOk = {}
local function hasFile(url)
    if fileOk[url] ~= nil then return fileOk[url] end
    local ok, res = pcall(req, {Url = url, Method = "GET"})
    fileOk[url] = (ok and res and res.StatusCode == 200) and true or false
    return fileOk[url]
end

local function imgFor(id)
    id = tostring(id or ""):match("%d+")
    if not id then return nil end
    if IMG_BASE ~= "" and IMG_FILE[id] then
        local url = IMG_BASE .. IMG_FILE[id]
        if hasFile(url) then return url end
    end
    if USE_ROBLOX_IMG then return iconUrl(id) end
    return nil
end

local function validUrl(u)
    return type(u) == "string" and u:find("^https://[%w%.]*discord[%w%.]*/api/webhooks/") ~= nil
end

local function serverInfo()
    local jid = game.JobId ~= "" and game.JobId:sub(1, 8) or "studio"
    return #Players:GetPlayers() .. "/" .. Players.MaxPlayers .. " players • " .. jid
end

local function send(cat, embed, force)
    if not alive or not req then return end
    if not force and not settings[MAP[cat] .. "On"] then return end
    local url = settings[MAP[cat] .. "Webhook"]
    if not validUrl(url) then return end

    task.spawn(function()
        embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        local thumb = embed.asset and imgFor(embed.asset)
        if not thumb and embed.icon then thumb = TWEMOJI:format(embed.icon) end
        if thumb then embed.thumbnail = {url = thumb} end
        local banner = embed.banner and imgFor(embed.banner)
        if banner then embed.image = {url = banner} end
        embed.asset, embed.icon, embed.banner = nil, nil, nil

        embed.author = embed.author or {name = BOT[cat]}
        local f = embed.footer and embed.footer.text or ""
        embed.footer = {text = (f ~= "" and (f .. " • ") or "") .. serverInfo()}

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
                asset = EVENT_IMG[id], icon = EICON[id],
                footer = {text = "Live Events"},
            })
        elseif not on and aktif[id] then
            aktif[id] = nil
            send("event", {
                title = "⌛  " .. nama .. " Event Ended", color = 9807270,
                asset = EVENT_IMG[id], icon = EICON[id],
                footer = {text = "Live Events"},
            })
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
-- 2) WHIRLPOOL (banner = gambar zona)
----------------------------------------------------------------
local nW = 0
safe("Whirlpool", function()
    local WFILTER = {Legendary = true, Mythic = true, Secret = true}
    local WCOLOR = {Legendary = 16766720, Mythic = 11141375, Secret = 16777215}
    local WEMOJI = {Legendary = "🟡", Mythic = "🟣", Secret = "⚪"}
    local WRANK = {Legendary = 1, Mythic = 2, Secret = 3}
    local lastW, lastWT = "", 0

    -- baca metadata spot (Tier / Dragon / ZoneId) seperti di script ESP, hanya baca
    local function spotSummary()
        local fs = workspace:FindFirstChild("FishingSpots")
        if not fs then return nil end
        local high, dragon = {}, 0
        for _, s in ipairs(fs:GetChildren()) do
            if s:GetAttribute("Dragon") == true then dragon += 1 end
            local tier = s:GetAttribute("Tier")
            if type(tier) == "string" and tier ~= "Common" and tier ~= "Rare" and tier ~= "Epic" then
                local zid = tonumber(s:GetAttribute("ZoneId"))
                local z = (zid and ZONA[zid]) or ("Zone " .. tostring(s:GetAttribute("ZoneId")))
                local k = tier .. "  ›  " .. z
                high[k] = (high[k] or 0) + 1
            end
        end
        local lines = {}
        for k, n in pairs(high) do lines[#lines+1] = k .. (n > 1 and ("  ×" .. n) or "") end
        table.sort(lines)
        if dragon > 0 then lines[#lines+1] = "🐉 Dragon spots: " .. dragon end
        if #lines == 0 then return nil end
        return table.concat(lines, "\n"):sub(1, 900)
    end

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
        local lines = {}
        for _, s in ipairs(list) do
            lines[#lines+1] = WEMOJI[s.rarity] .. " **" .. s.rarity .. "**  ›  "
                .. (ZONA[s.zoneId] or ("Zone " .. tostring(s.zoneId)))
        end
        local topZone, bestName = list[1].zoneId, best
        task.delay(1.5, function()
            if not alive then return end
            local extra = spotSummary()
            send("whirlpool", {
                title = "🌀  Rare Whirlpool",
                description = table.concat(lines, "\n") .. "\n\n*Resets every 5 minutes*",
                color = WCOLOR[bestName],
                banner = ZONE_IMG[topZone],
                icon = "1f300",
                fields = extra and {{name = "📍 Spots now", value = extra, inline = false}} or nil,
                footer = {text = "Highest: " .. bestName},
            })
        end)
    end

    for _, r in ipairs(findRemotes("RareSpotsSpawned")) do
        nW += 1
        hook(r, whirlpool)
    end
    assert(nW > 0, "remote RareSpotsSpawned tidak ditemukan")
end)

----------------------------------------------------------------
-- 3) BOSS (fight dimulai)
----------------------------------------------------------------
local nB = 0
local BCOLOR = {Easy=5763719, Fierce=16753920, Strong=15105570, Legendary=16766720, Mythic=11141375}
safe("Boss", function()
    local bcfg = safeRequire(RS.Shared.Config.BossConfig)
    assert(bcfg, "BossConfig tidak bisa dibaca")
    local tier = {}
    for _, b in ipairs(bcfg.BOSSES) do tier[b.Id] = b.Tier end
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
            description = "> **" .. (BOSS_NAME[id] or id) .. "** has appeared!\n> Tier: **" .. t .. "**",
            color = BCOLOR[t] or 15158332,
            asset = BOSS_IMG[id], icon = "1f479",
            fields = {
                {name = (BEMOJI[t] or "") .. " Tier", value = t, inline = true},
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
                color = 9807270, icon = "1f3c6", footer = {text = "Boss Tracker"}})
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
-- 3b) BOSS ANNOUNCE (fase Announced, ~1 menit sebelum)
----------------------------------------------------------------
safe("BossAnnounce", function()
    local lastKey
    local function check()
        if not alive then return end
        if workspace:GetAttribute("BossPhase") ~= "Announced" then return end
        local id = workspace:GetAttribute("BossId")
        local tier = workspace:GetAttribute("BossTier")
        local ends = workspace:GetAttribute("BossPhaseEndsAt")
        if type(id) ~= "string" or type(ends) ~= "number" then return end
        local left = ends - workspace:GetServerTimeNow()
        if left <= 0 then return end

        local key = id .. tostring(ends)
        if key == lastKey then return end
        lastKey = key

        send("boss", {
            title = "⏰  Boss incoming: " .. (BOSS_NAME[id] or id),
            description = "The fight starts <t:" .. (os.time() + math.floor(left)) .. ":R>. Get ready!",
            color = BCOLOR[tier] or 16753920,
            asset = BOSS_IMG[id], icon = "23f0",
            fields = {
                {name = "🏷 Tier", value = tostring(tier or "?"), inline = true},
                {name = "⏳ Starts in", value = math.floor(left) .. " sec", inline = true},
            },
            footer = {text = "Boss Warning"},
        })
    end

    local function later() task.delay(0.5, function() pcall(check) end) end
    track(workspace:GetAttributeChangedSignal("BossPhase"):Connect(later))
    track(workspace:GetAttributeChangedSignal("BossPhaseEndsAt"):Connect(later))
    pcall(check)
    spawnLoop(function()
        while alive do task.wait(5) pcall(check) end
    end)
end)

----------------------------------------------------------------
-- 3c) SCHEDULES (peringatan sebelum jadwal, dari atribut waktu game)
----------------------------------------------------------------
safe("Schedules", function()
    local de = RS:FindFirstChild("DragonEvent")

    -- lead = berapa detik sebelum jadwal pesan dikirim (nil = dimatikan)
    local SRC = {
        {key="Dragon", obj=de, attr="NextAutoAt", lead=60, cat="event",
         title="🐉  Dragon event starting soon", color=16737573,
         asset=EVENT_IMG.Dragon, icon="1f409"},
        {key="Whirl", find=function() return workspace:FindFirstChild("FishingSpots") end,
         attr="NextResetAt", lead=nil, cat="whirlpool",
         title="🌀  Whirlpool reset soon", color=5793266, icon="1f300"},
        {key="Boss", obj=workspace, attr="BossNextAt", lead=nil, cat="boss",
         title="⏰  Boss spawning soon", color=16753920, icon="23f0"},
    }

    local sent = {}
    spawnLoop(function()
        while alive do
            task.wait(2)
            local now = workspace:GetServerTimeNow()
            for _, s in ipairs(SRC) do
                local o = s.obj or (s.find and s.find())
                if s.lead and o then
                    local t = o:GetAttribute(s.attr)
                    if type(t) == "number" then
                        local left = t - now
                        if left > 0 and left <= s.lead and sent[s.key] ~= t then
                            sent[s.key] = t
                            send(s.cat, {
                                title = s.title,
                                description = "Starts <t:" .. (os.time() + math.floor(left)) .. ":R>",
                                color = s.color, asset = s.asset, icon = s.icon,
                                footer = {text = "Schedule"},
                            })
                        end
                    end
                end
            end
        end
    end)
end)

----------------------------------------------------------------
-- 3d) ESP SPOT WHIRLPOOL (toggle di GUI, hanya membaca atribut spot)
----------------------------------------------------------------
safe("ESP", function()
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local spots = workspace:WaitForChild("FishingSpots", 10)
    assert(spots, "FishingSpots tidak ada")

    -- 1 = semua, 2 = Rare+, 3 = Epic+, 4 = Legendary+, 5 = Mythic+
    local MIN_RANK, MAX_LABELS, MAX_RANGE = 2, 36, 1200
    local ranks = {Common=1, Rare=2, Epic=3, Legendary=4, Mythic=5, Secret=6}
    local colors = {
        Common = Color3.fromRGB(205,215,225), Rare = Color3.fromRGB(95,177,255),
        Epic = Color3.fromRGB(198,112,255), Legendary = Color3.fromRGB(255,205,82),
        Mythic = Color3.fromRGB(255,90,220), Secret = Color3.fromRGB(255,255,255),
    }
    local labels = {}

    local function anchorOf(spot)
        local c = spot:FindFirstChild("Centre")
        if c and (c:IsA("BasePart") or c:IsA("Attachment")) then return c end
        local p = spot:FindFirstChild("FishPrompt", true)
        if p and p.Parent and (p.Parent:IsA("BasePart") or p.Parent:IsA("Attachment")) then return p.Parent end
        return spot:FindFirstChildWhichIsA("BasePart", true)
    end
    local function posOf(a) return a:IsA("Attachment") and a.WorldPosition or a.Position end

    local function clear(spot)
        local ui = labels[spot]
        if ui then labels[spot] = nil pcall(function() ui:Destroy() end) end
    end
    local function clearAll()
        for sp in pairs(labels) do clear(sp) end
    end

    local function make(anchor)
        local bill = Instance.new("BillboardGui")
        bill.Name = "DEC_SpotLabel"
        bill.Adornee = anchor
        bill.Size = UDim2.fromOffset(190, 48)
        bill.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        bill.AlwaysOnTop = true
        bill.ResetOnSpawn = false
        bill.Parent = pg
        local t = Instance.new("TextLabel")
        t.Name = "T"
        t.Size = UDim2.fromScale(1, 1)
        t.BackgroundColor3 = Color3.fromRGB(18, 25, 36)
        t.BackgroundTransparency = 0.15
        t.BorderSizePixel = 0
        t.TextSize = 13
        t.Font = Enum.Font.GothamBold
        t.TextWrapped = true
        t.Parent = bill
        Instance.new("UICorner", t).CornerRadius = UDim.new(0, 6)
        return bill
    end

    local function refresh()
        local char = Players.LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local chosen = {}
        for _, spot in ipairs(spots:GetChildren()) do
            local tier = spot:GetAttribute("Tier")
            if type(tier) == "string" then
                local dragon = spot:GetAttribute("Dragon") == true
                local rank = ranks[tier] or 5
                if dragon or rank >= MIN_RANK then
                    local a = anchorOf(spot)
                    if a then
                        local d = (posOf(a) - root.Position).Magnitude
                        if d <= MAX_RANGE then
                            chosen[#chosen+1] = {spot=spot, a=a, d=d, tier=tier, dragon=dragon}
                        end
                    end
                end
            end
        end
        table.sort(chosen, function(x, y) return x.d < y.d end)

        local keep = {}
        for i = 1, math.min(#chosen, MAX_LABELS) do
            local c = chosen[i]
            keep[c.spot] = true
            local bill = labels[c.spot]
            if not bill then bill = make(c.a) labels[c.spot] = bill end
            bill.Adornee = c.a
            local t = bill:FindFirstChild("T")
            if t then
                local zid = tonumber(c.spot:GetAttribute("ZoneId"))
                t.Text = (c.dragon and "DRAGON | " or "") .. c.tier
                    .. "\n" .. (ZONA[zid] or ("Zone " .. tostring(zid))) .. " | " .. math.floor(c.d + 0.5) .. " studs"
                t.TextColor3 = c.dragon and Color3.fromRGB(255, 113, 117) or (colors[c.tier] or colors.Mythic)
            end
        end
        for spot in pairs(labels) do
            if not keep[spot] then clear(spot) end
        end
    end

    track({Disconnect = clearAll}) -- dibersihkan saat stop()
    track(spots.ChildRemoved:Connect(clear))
    spawnLoop(function()
        while alive do
            if settings.ESPOn then pcall(refresh) else clearAll() end
            task.wait(0.85)
        end
    end)
end)

----------------------------------------------------------------
-- 4) ANTI-AFK
----------------------------------------------------------------
safe("AntiAFK", function()
    local vu = game:GetService("VirtualUser")
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

    local FULL_H = 371
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
    closeBtn.MouseButton1Click:Connect(stop)

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
    makeToggle("ESP spot tier" .. (status.ESP == "FAIL" and " (error)" or ""), 112, "ESPOn")

    makeInput("EVENT WEBHOOK", 146, "EventWebhook")
    makeInput("WHIRLPOOL WEBHOOK", 198, "WhirlpoolWebhook")
    makeInput("BOSS WEBHOOK", 250, "BossWebhook")

    local test = Instance.new("TextButton")
    test.Size = UDim2.new(0.5, -18, 0, 26)
    test.Position = UDim2.fromOffset(12, 304)
    test.BackgroundColor3 = Color3.fromRGB(45, 90, 160)
    test.Text, test.TextSize, test.Font = "Send test", 11, Enum.Font.GothamBold
    test.TextColor3 = Color3.new(1, 1, 1)
    test.Parent = body
    Instance.new("UICorner", test).CornerRadius = UDim.new(0, 6)
    test.MouseButton1Click:Connect(function()
        send("event", {title = "✅ Test Event: Galaxy", description = "Webhook connected.",
            color = 5763719, asset = EVENT_IMG.Galaxy, icon = "1f30c"}, true)
        send("whirlpool", {title = "✅ Test Whirlpool", description = "🟡 **Legendary**  ›  " .. ZONA[9],
            color = 16766720, banner = ZONE_IMG[9], icon = "1f300"}, true)
        send("boss", {title = "✅ Test Boss: " .. BOSS_NAME.Boss4, description = "Webhook connected.",
            color = 16766720, asset = BOSS_IMG.Boss4, icon = "1f479"}, true)
        test.Text = "Sent!"
        task.delay(1.5, function() if alive then test.Text = "Send test" end end)
    end)

    local full = Instance.new("TextButton")
    full.Size = UDim2.new(0.5, -18, 0, 26)
    full.Position = UDim2.new(0.5, 6, 0, 304)
    full.BackgroundColor3 = Color3.fromRGB(95, 70, 160)
    full.Text, full.TextSize, full.Font = "Full test", 11, Enum.Font.GothamBold
    full.TextColor3 = Color3.new(1, 1, 1)
    full.Parent = body
    Instance.new("UICorner", full).CornerRadius = UDim.new(0, 6)
    full.MouseButton1Click:Connect(function()
        task.spawn(function()
            -- Boss incoming (1 menit sebelum)
            send("boss", {
                title = "⏰  Test Boss incoming: " .. BOSS_NAME.Boss4,
                description = "The fight starts <t:" .. (os.time() + 60) .. ":R>. Get ready!",
                color = BCOLOR.Legendary, asset = BOSS_IMG.Boss4, icon = "23f0",
                fields = {
                    {name = "🏷 Tier", value = "Legendary", inline = true},
                    {name = "⏳ Starts in", value = "60 sec", inline = true},
                },
                footer = {text = "Boss Warning"},
            }, true)
            task.wait(0.6)
            -- Whirlpool dengan beberapa rarity
            send("whirlpool", {
                title = "🌀  Test Rare Whirlpool",
                description = "⚪ **Secret**  ›  " .. ZONA[19] .. "\n🟣 **Mythic**  ›  " .. ZONA[10]
                    .. "\n🟡 **Legendary**  ›  " .. ZONA[9] .. "\n\n*Resets every 5 minutes*",
                color = 16777215, banner = ZONE_IMG[19], icon = "1f300",
                footer = {text = "Highest: Secret"},
            }, true)
            task.wait(0.6)
            -- Dragon segera mulai
            send("event", {
                title = "🐉  Test Dragon event starting soon",
                description = "Starts <t:" .. (os.time() + 60) .. ":R>",
                color = 16737573, asset = EVENT_IMG.Dragon, icon = "1f409",
                footer = {text = "Schedule"},
            }, true)
            task.wait(0.6)
            -- Event berakhir
            send("event", {
                title = "⌛  Test Galaxy Event Ended", color = 9807270,
                asset = EVENT_IMG.Galaxy, icon = EICON.Galaxy,
                footer = {text = "Live Events"},
            }, true)
        end)
        full.Text = "Sent!"
        task.delay(1.5, function() if alive then full.Text = "Full test" end end)
    end)

    label(body, "Event:" .. tostring(status.Event) .. "  Whirl:" .. tostring(status.Whirlpool)
        .. "  Boss:" .. tostring(status.Boss), UDim2.new(1, -20, 0, 14), UDim2.fromOffset(12, 334),
        Color3.fromRGB(130, 140, 155))
end)

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Tracker aktif",
        Text = "Event:" .. tostring(status.Event) .. " Whirl:" .. tostring(status.Whirlpool)
            .. " Boss:" .. tostring(status.Boss) .. " Announce:" .. tostring(status.BossAnnounce)
            .. " AFK:" .. tostring(status.AntiAFK),
        Duration = 8,
    })
end)
