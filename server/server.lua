local RSGCore = exports['rsg-core']:GetCoreObject()
local playersInRace = {}
local raceStarted = false
local rewardAmount = 100
local racePoints = {}
local totalLaps = 1
local raceResults = {}
local currentRaceFinishers = {}
local savedTracks = {}
local maxMarkers = 15
local loadLatestTrackOnRestart = false -- Disabled: tracks only load when chosen from menu, not auto on /racerace or restart

local function getPlayerDisplayName(Player, src)
    local charinfo = Player and Player.PlayerData and Player.PlayerData.charinfo
    local first = charinfo and charinfo.firstname
    local last = charinfo and charinfo.lastname

    -- RSG-Core normally stores firstname/lastname as strings. Never send a
    -- table/object to NUI, otherwise JavaScript renders it as [object Object].
    if type(first) == 'string' or type(last) == 'string' then
        first = type(first) == 'string' and first or ''
        last = type(last) == 'string' and last or ''
        local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
        if full ~= '' then return full end
    end

    local playerDataName = Player and Player.PlayerData and Player.PlayerData.name
    if type(playerDataName) == 'string' and playerDataName ~= '' then
        return playerDataName
    end

    local fallback = GetPlayerName(src)
    if type(fallback) == 'string' and fallback ~= '' then
        return fallback
    end

    return ('Rider #%s'):format(src)
end

local function getRacePlayerList()
    local list = {}
    for src, data in pairs(playersInRace) do
        local id = tonumber(src)
        if id and type(data) == 'table' then
            local name = type(data.name) == 'string' and data.name or ('Rider #' .. id)
            list[#list + 1] = {
                source = id,
                name = name,
                laps = tonumber(data.laps) or 0,
                passedEndPoint = data.passedEndPoint == true
            }
        end
    end
    table.sort(list, function(a, b) return a.source < b.source end)
    return list
end

local function broadcastRacePlayers()
    TriggerClientEvent('rsg-track:updatePlayers', -1, getRacePlayerList(), raceStarted)
end

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
       
        local createTableSQL = [[
            CREATE TABLE IF NOT EXISTS horse_race_tracks (
                track_id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(50) NOT NULL,
                points JSON NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ]]
        local success, error = pcall(function()
            exports['oxmysql']:executeSync(createTableSQL)
        end)
        if not success then
           
            return
        end

        
        local result = exports['oxmysql']:fetchSync('SELECT track_id, name, points FROM horse_race_tracks ORDER BY timestamp DESC')
        if not result then
           
            return
        end

        savedTracks = {}
        for _, row in ipairs(result) do
            local points = json.decode(row.points)
            if points then
                table.insert(savedTracks, {track_id = row.track_id, name = row.name, points = points})
            else
                
            end
        end
       

       
        if loadLatestTrackOnRestart and #savedTracks > 0 then
            racePoints = savedTracks[1].points
           
            TriggerClientEvent('rsg-track:syncTrack', -1, racePoints, true)
        end

       
        TriggerClientEvent('rsg-track:syncTracks', -1, savedTracks)
        TriggerClientEvent('rsg-track:syncMaxMarkers', -1, maxMarkers)
        
     end
end)

AddEventHandler('playerConnecting', function()
     local src = source
    
     TriggerClientEvent('rsg-track:syncTracks', src, savedTracks)
     TriggerClientEvent('rsg-track:syncMaxMarkers', src, maxMarkers)
     if #racePoints >= 2 then
         TriggerClientEvent('rsg-track:syncTrack', src, racePoints, true)
     end
end)


RegisterServerEvent('rsg-track:requestTracks')
AddEventHandler('rsg-track:requestTracks', function()
     local src = source
     
     TriggerClientEvent('rsg-track:syncTracks', src, savedTracks)
     TriggerClientEvent('rsg-track:syncMaxMarkers', src, maxMarkers)
     if #racePoints >= 2 then
         TriggerClientEvent('rsg-track:syncTrack', src, racePoints, true)
     end
end)

RegisterServerEvent('rsg-track:setMaxMarkers')
AddEventHandler('rsg-track:setMaxMarkers', function(count)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if raceStarted then
        return
    end
    maxMarkers = math.max(2, math.min(30, tonumber(count) or 15))
    TriggerClientEvent('rsg-track:syncMaxMarkers', -1, maxMarkers)
end)

RegisterServerEvent('rsg-track:setLaps')
AddEventHandler('rsg-track:setLaps', function(laps)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    totalLaps = math.max(1, math.min(5, laps))
    TriggerClientEvent('rsg-track:syncLaps', -1, totalLaps)
end)

RegisterServerEvent('rsg-track:deleteTrack')
AddEventHandler('rsg-track:deleteTrack', function(trackId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local result = exports['oxmysql']:executeSync('DELETE FROM horse_race_tracks WHERE track_id = :track_id', {track_id = trackId})
    if result.affectedRows > 0 then
        savedTracks = {}
        local tracks = exports['oxmysql']:fetchSync('SELECT track_id, name, points FROM horse_race_tracks ORDER BY timestamp DESC')
        if tracks then
            for _, row in ipairs(tracks) do
                local points = json.decode(row.points)
                if points then
                    table.insert(savedTracks, {track_id = row.track_id, name = row.name, points = points})
                end
            end
        end
        
        TriggerClientEvent('rsg-track:syncTracks', -1, savedTracks)
        TriggerClientEvent('rsg-track:toast', src, {
            title = Locale('title'),
            description = Locale('notify_track_deleted'),
            type = 'success'
        })
        
        if #racePoints > 0 then
            for _, track in ipairs(savedTracks) do
                if track.track_id == trackId then
                    racePoints = {}
                    TriggerClientEvent('rsg-track:syncTrack', -1, {}, false)
                    break
                end
            end
        end
    else
        TriggerClientEvent('rsg-track:toast', src, {
            title = Locale('title'),
            description = Locale('notify_track_delete_fail'),
            type = 'error'
        })
    end
end)

RegisterServerEvent('rsg-track:joinRace')
AddEventHandler('rsg-track:joinRace', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if #racePoints < 2 then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_no_track_yet'), type = 'error'})
        return
    end
    
    if raceStarted then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_race_already_started'), type = 'error'})
        return
    end
    
    if playersInRace[src] then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_already_in_race'), type = 'error'})
        return
    end
    
    local playerName = getPlayerDisplayName(Player, src)
    playersInRace[src] = { name = playerName, laps = 0, passedEndPoint = false }
    TriggerClientEvent('rsg-track:joinedRace', src)
    broadcastRacePlayers()
end)

RegisterServerEvent('horse_race:trackCreated')
AddEventHandler('horse_race:trackCreated', function(points, trackName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if #points < 2 or #points > maxMarkers then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_invalid_points', maxMarkers), type = 'error'})
        return
    end
    
    local pointsJson = json.encode(points)
    local success, error = pcall(function()
        exports['oxmysql']:executeSync('INSERT INTO horse_race_tracks (name, points) VALUES (:name, :points)', {
            name = trackName or ('Track ' .. (#savedTracks + 1)),
            points = pointsJson
        })
    end)
    if not success then
       
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_save_failed'), type = 'error'})
        return
    end
    
    local result = exports['oxmysql']:fetchSync('SELECT track_id, name, points FROM horse_race_tracks ORDER BY timestamp DESC')
    if result then
        savedTracks = {}
        for _, row in ipairs(result) do
            local points = json.decode(row.points)
            if points then
                table.insert(savedTracks, {track_id = row.track_id, name = row.name, points = points})
            end
        end
        
    else
        
    end
    
    racePoints = points
    TriggerClientEvent('rsg-track:syncTrack', -1, points, true)
    TriggerClientEvent('rsg-track:syncTracks', -1, savedTracks)
end)

RegisterServerEvent('rsg-track:loadTrack')
AddEventHandler('rsg-track:loadTrack', function(trackId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if raceStarted then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_cannot_load_during_race'), type = 'error'})
        return
    end
    
    for _, track in ipairs(savedTracks) do
        if track.track_id == trackId then
            racePoints = track.points
            TriggerClientEvent('rsg-track:syncTrack', -1, track.points, true)
            return
        end
    end
    TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_track_not_found'), type = 'error'})
end)

RegisterServerEvent('rsg-track:leaveRace')
AddEventHandler('rsg-track:leaveRace', function()
    local src = source
    if playersInRace[src] then
        playersInRace[src] = nil
        TriggerClientEvent('rsg-track:leftRace', src)
        broadcastRacePlayers()
    end
end)

-- Clean up ghost riders: without this, anyone who disconnects mid-race
-- (crash, alt-F4, reconnect) stays in playersInRace forever, since a new
-- connection gets a new src and never matches the stale entry.
AddEventHandler('playerDropped', function(reason)
    local src = source
    if playersInRace[src] then
        playersInRace[src] = nil
        broadcastRacePlayers()
    end
end)

RegisterServerEvent('rsg-track:startRace')
AddEventHandler('rsg-track:startRace', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_player_data_not_found'), type = 'error'})
        return
    end
    
    if #racePoints < 2 then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_no_track'), type = 'error'})
        return
    end
    
    local playerCount = 0
    for _ in pairs(playersInRace) do playerCount = playerCount + 1 end
    if playerCount < 1 then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_min_players'), type = 'error'})
        return
    end
    
    if raceStarted then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_race_in_progress'), type = 'error'})
        return
    end
    
    raceStarted = true
    broadcastRacePlayers()
    TriggerClientEvent('rsg-track:startRace', -1)
end)

RegisterServerEvent('horse_race:finishRace')
AddEventHandler('horse_race:finishRace', function(playerLaps)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
   
    
    if not Player then
        
        return
    end
    if not playersInRace[src] then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_not_in_race'), type = 'error'})
        return
    end
    if playerLaps < totalLaps then
        TriggerClientEvent('rsg-track:toast', src, {title = Locale('title'), description = Locale('notify_incomplete_laps'), type = 'error'})
        return
    end
    
    local playerName = getPlayerDisplayName(Player, src)
    local position = #currentRaceFinishers + 1
    table.insert(currentRaceFinishers, {name = playerName, position = position, laps = totalLaps})
    
    TriggerClientEvent('rsg-track:showFinisherNotification', -1, playerName, position)
    
    if position == 1 then
        Player.Functions.AddMoney('cash', rewardAmount)
        TriggerClientEvent('rsg-track:rewardReceived', src, rewardAmount)
    end
    
    playersInRace[src] = nil
    TriggerClientEvent('rsg-track:syncResults', -1, currentRaceFinishers)
    -- Ensure stragglers who missed checkpoint still clear markers: broadcast force clear on first finisher
    if position == 1 then
        TriggerClientEvent('rsg-track:finishRace', -1)
        -- Keep raceStarted handling to allow forced visuals clear; actual reset waits for last player or timeout
        Citizen.SetTimeout(12000, function()
            if raceStarted then
                -- Force end for missed-checkpoint stragglers
                for pid,_ in pairs(playersInRace) do
                    TriggerClientEvent('rsg-track:toast', pid, {title=Locale('title'), description=Locale('notify_ended_missed_checkpoint'), type='inform'})
                end
                TriggerClientEvent('rsg-track:finishRace', -1)
                TriggerClientEvent('rsg-track:resetRace', -1, false)
                raceStarted = false
                racePoints = {}
                playersInRace = {}
                currentRaceFinishers = {}
                totalLaps = 1
                broadcastRacePlayers()
                TriggerClientEvent('rsg-track:syncResults', -1, {})
            end
        end)
    end
    
    local playerCount = 0
    for _ in pairs(playersInRace) do playerCount = playerCount + 1 end
    
    if playerCount == 0 then
        table.insert(raceResults, {finishers = currentRaceFinishers, raceId = #raceResults + 1})
        if #raceResults > 5 then table.remove(raceResults, 1) end
        
        TriggerClientEvent('rsg-track:syncRaceResults', -1, raceResults)
        TriggerClientEvent('rsg-track:finishRace', -1)
        raceStarted = false
        racePoints = {}
        playersInRace = {}
        currentRaceFinishers = {}
        totalLaps = 1
        TriggerClientEvent('rsg-track:resetRace', -1, false)
        broadcastRacePlayers()
        TriggerClientEvent('rsg-track:syncResults', -1, {})
    end
end)

RegisterServerEvent('horse_race:countdownFinished')
AddEventHandler('horse_race:countdownFinished', function()
    TriggerClientEvent('rsg-track:raceStarted', -1)
end)

RegisterServerEvent('rsg-track:resetRace')
AddEventHandler('rsg-track:resetRace', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    racePoints = {}
    playersInRace = {}
    raceStarted = false
    totalLaps = 1
    raceResults = {}
    currentRaceFinishers = {}
    TriggerClientEvent('rsg-track:syncRaceResults', -1, raceResults)
    TriggerClientEvent('rsg-track:resetRace', -1, true)
end)