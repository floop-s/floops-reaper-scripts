-- @noindex
-- @description Floop Hunter Framework - Cache module
-- @author Floop-s
-- @license GPL-3.0
--
-- In-memory cache for analysis results and per-item profile selection.

local Cache = {}
local reaper = reaper

Cache.DB = {}
Cache.LRU_ORDER = {}
Cache.MAX_ENTRIES = 20

-- Helper to manage LRU order
local function touch_lru(guid)
    -- Remove if exists
    for i, g in ipairs(Cache.LRU_ORDER) do
        if g == guid then
            table.remove(Cache.LRU_ORDER, i)
            break
        end
    end
    -- Add to front
    table.insert(Cache.LRU_ORDER, 1, guid)
    
    -- Evict if too large
    while #Cache.LRU_ORDER > Cache.MAX_ENTRIES do
        local old_guid = table.remove(Cache.LRU_ORDER)
        Cache.DB[old_guid] = nil
    end
end

-- Cache key for analysis-critical parameters (feature extraction only).
function Cache.get_params_hash(config, hunter_name)
    local keys = { "source_profile", "window_ms", "hop_ms", "low_pass" }
    local parts = { hunter_name .. "_v2.3" }
    for _, k in ipairs(keys) do
        if config[k] ~= nil then
            table.insert(parts, k .. ":" .. tostring(config[k]))
        end
    end
    return table.concat(parts, "|")
end

function Cache.save_to_proj()
end

function Cache.get(guid, hunter_name)
    if Cache.DB[guid] and Cache.DB[guid][hunter_name] then
        touch_lru(guid)
        return Cache.DB[guid][hunter_name]
    end
    return nil
end

function Cache.set(guid, hunter_name, data)
    if not Cache.DB[guid] then Cache.DB[guid] = {} end
    Cache.DB[guid][hunter_name] = data
    touch_lru(guid)
end

function Cache.clear(guid)
    if guid then
        Cache.DB[guid] = nil
        for i, g in ipairs(Cache.LRU_ORDER) do
            if g == guid then table.remove(Cache.LRU_ORDER, i); break end
        end
    else
        Cache.DB = {}
        Cache.LRU_ORDER = {}
    end
end

function Cache.get_profile(guid)
    if Cache.DB[guid] and Cache.DB[guid].source_profile then
        return Cache.DB[guid].source_profile
    end
    return 0 -- Default
end

function Cache.set_profile(guid, profile_id)
    if not Cache.DB[guid] then Cache.DB[guid] = {} end
    Cache.DB[guid].source_profile = profile_id
end

-- Remove entries for items that no longer exist in the project.
function Cache.prune()
    local valid_guids = {}
    local cnt = reaper.CountMediaItems(0)
    for i = 0, cnt - 1 do
        local item = reaper.GetMediaItem(0, i)
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        if guid and guid ~= "" then
            valid_guids[guid] = true
        end
    end

    for guid, _ in pairs(Cache.DB) do
        if not valid_guids[guid] then
            Cache.DB[guid] = nil
        end
    end
end

return Cache
