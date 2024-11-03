local config = require 'config.client'
local playerStatus = {}
local casings = {}
local currentCasing = nil
local bloodDrops = {}
local currentBloodDrop = nil
local fingerprints = {}
local currentFingerprint = 0
local shotsFired = 0

local function dropBulletCasing(weapon, ped)
    local randX = math.random() + math.random(-1, 1)
    local randY = math.random() + math.random(-1, 1)
    local coords = GetOffsetFromEntityInWorldCoords(ped, randX, randY, 0)
    local serial = exports.ox_inventory:getCurrentWeapon().metadata.serial
    TriggerServerEvent('evidence:server:CreateCasing', weapon, serial, coords)
    Wait(300)
end

local function dnaHash(s)
    local h = string.gsub(s, '.', function(c)
        return string.format('%02x', string.byte(c))
    end)
    return h
end

---@param status string
local function setStatus(status)
    local duration = config.statuses[status].duration or 600

    playerStatus[status] = duration

    lib.callback.await('qbx_evidence:server:setStatus', false, playerStatus)
end

local function onPlayerShooting()
    shotsFired += 1

    if shotsFired > config.statuses.gsr.threshold then
        if math.random(1, 100) <= config.statuses.gsr.chance then
            setStatus('gsr')
        end
    end

    dropBulletCasing(cache.weapon, cache.ped)
end

---@param coords vector3
---@return string
local function getStreetLabel(coords)
    local s1, s2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street1 = GetStreetNameFromHashKey(s1)
    local street2 = GetStreetNameFromHashKey(s2)
    local streetLabel = street1
    if street2 then
        streetLabel = streetLabel .. ' | ' .. street2
    end
    local sanitized = streetLabel:gsub("%'", "")
    return sanitized
end

local function getPlayerDistanceFromCoords(coords)
    local pos = GetEntityCoords(cache.ped)
    return #(pos - coords)
end

---@class DrawEvidenceIfInRangeArgs
---@field evidenceId integer
---@field coords vector3
---@field text string
---@field metadata table
---@field serverEventOnPickup string

---@param args DrawEvidenceIfInRangeArgs
local function drawEvidenceIfInRange(args)
    if getPlayerDistanceFromCoords(args.coords) >= 1.5 then return end
    qbx.drawText3d({text = args.text, coords = args.coords})
    if IsControlJustReleased(0, 47) then
        TriggerServerEvent(args.serverEventOnPickup, args.evidenceId, args.metadata)
    end
end

local function canDiscoverEvidence()
    return LocalPlayer.state.isLoggedIn
    and QBX.PlayerData.job.type == 'leo'
    and QBX.PlayerData.job.onduty
    and IsPlayerFreeAiming(cache.playerId)
    and cache.weapon == `WEAPON_FLASHLIGHT`
end

---@param evidence table<number, {coords: vector3}>
---@return number? evidenceId
local function getCloseEvidence(evidence)
    local pos = GetEntityCoords(cache.ped, true)
    for evidenceId, v in pairs(evidence) do
        local dist = #(pos - v.coords)
        if dist < 1.5 then
            return evidenceId
        end
    end
end

RegisterNetEvent('qbx_evidence:client:addBloodDrop', function(bloodId, citizenid, bloodtype, coords)
    bloodDrops[bloodId] = {
        citizenid = citizenid,
        bloodtype = bloodtype,
        coords = vec3(coords.x, coords.y, coords.z - 0.9)
    }
end)

RegisterNetEvent('qbx_evidence:client:removeBloodDrop', function(bloodId)
    bloodDrops[bloodId] = nil
    currentBloodDrop = 0
end)

RegisterNetEvent('qbx_evidence:client:addFingerPrint', function(fingerId, fingerprint, coords)
    fingerprints[fingerId] = {
        fingerprint = fingerprint,
        coords = vec3(coords.x, coords.y, coords.z - 0.9)
    }
end)

RegisterNetEvent('qbx_evidence:client:removeFingerprint', function(fingerId)
    fingerprints[fingerId] = nil
    currentFingerprint = 0
end)

RegisterNetEvent('qbx_evidence:client:clearBloodDropsInArea', function()
    local pos = GetEntityCoords(cache.ped)
    local bloodDropList = {}
    if lib.progressCircle({
        duration = 5000,
        position = 'bottom',
        label = locale('clearing_blood'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            combat = true,
            mouse = false
        }
    })
    then
        if bloodDrops and next(bloodDrops) then
            for bloodId in pairs(bloodDrops) do
                if #(pos - bloodDrops[bloodId].coords) < 10.0 then
                    bloodDropList[#bloodDropList + 1] = bloodId
                end
            end
            TriggerServerEvent('qbx_evidence:server:clearBloodDrops', bloodDropList)
            exports.qbx_core:Notify(locale('blood_cleared'), 'success')
        end
    else
        exports.qbx_core:Notify(locale('canceled'), 'error')
    end
end)

RegisterNetEvent('qbx_evidence:client:addCasing', function(casingId, weapon, coords, serie)
    casings[casingId] = {
        type = weapon,
        serie = serie and serie or locale('serial_not_visible'),
        coords = vec3(coords.x, coords.y, coords.z - 0.9)
    }
end)

RegisterNetEvent('qbx_evidence:client:removeCasing', function(casingId)
    casings[casingId] = nil
    currentCasing = 0
end)

RegisterNetEvent('qbx_evidence:client:clearCasingsInArea', function()
    local pos = GetEntityCoords(cache.ped)
    local casingList = {}

    if lib.progressCircle({
        duration = 5000,
        position = 'bottom',
        label = locale('clearing_casing'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = false,
            car = false,
            combat = true,
            mouse = false,
        }
    })
    then
        if casings and next(casings) then
            for casingId in pairs(casings) do
                if #(pos - casings[casingId].coords) < 10.0 then
                    casingList[#casingList + 1] = casingId
                end
            end
            TriggerServerEvent('qbx_evidence:server:clearCasings', casingList)
            exports.qbx_core:Notify(locale('casing_cleared'), 'success')
        end
    else
        exports.qbx_core:Notify(locale('canceled'), 'error')
    end
end)

CreateThread(function() -- Gunpowder Status when shooting
    while true do
        Wait(0)
        if IsPedShooting(cache.ped) and not config.whitelistedWeapons[cache.weapon] then
            onPlayerShooting()
        end
    end
end)

--- draw 3D text on the ground to show evidence, if they press pickup button, set metadata and add it to their inventory.
CreateThread(function()
    while true do
        Wait(0)
        if currentCasing and currentCasing ~= 0 then
            drawEvidenceIfInRange({
                evidenceId = currentCasing,
                coords = casings[currentCasing].coords,
                text = locale('bullet_casing', casings[currentCasing].type),
                metadata = {
                    type = locale('casing'),
                    street = getStreetLabel(casings[currentCasing].coords),
                    ammolabel = config.ammoLabels[exports.qbx_core:GetWeapons()[casings[currentCasing].type].ammotype],
                    ammotype = casings[currentCasing].type,
                    serie = casings[currentCasing].serie
                },
                serverEventOnPickup = 'qbx_evidence:server:addCasingToInventory'
            })
        end

        if currentBloodDrop and currentBloodDrop ~= 0 then
            drawEvidenceIfInRange({
                evidenceId = currentBloodDrop,
                coords = bloodDrops[currentBloodDrop].coords,
                text = locale('blood_text', dnaHash(bloodDrops[currentBloodDrop].citizenid)),
                metadata = {
                    type = locale('blood'),
                    street = getStreetLabel(bloodDrops[currentBloodDrop].coords),
                    dnalabel = dnaHash(bloodDrops[currentBloodDrop].citizenid),
                    bloodtype = bloodDrops[currentBloodDrop].bloodtype
                },
                serverEventOnPickup = 'qbx_evidence:server:addBloodDropToInventory'
            })
        end

        if currentFingerprint and currentFingerprint ~= 0 then
            drawEvidenceIfInRange({
                evidenceId = currentFingerprint,
                coords = fingerprints[currentFingerprint].coords,
                text = locale('fingerprint_text'),
                metadata = {
                    type = locale('fingerprint'),
                    street = getStreetLabel(fingerprints[currentFingerprint].coords),
                    fingerprint = fingerprints[currentFingerprint].fingerprint
                },
                serverEventOnPickup = 'qbx_evidence:server:addFingerprintToInventory'
            })
        end
    end
end)

CreateThread(function()
    while true do
        local closeEvidenceSleep = 1000
        if canDiscoverEvidence() then
            closeEvidenceSleep = 10
            currentCasing = getCloseEvidence(casings) or currentCasing
            currentBloodDrop = getCloseEvidence(bloodDrops) or currentBloodDrop
            currentFingerprint = getCloseEvidence(fingerprints) or currentFingerprint
        end
        Wait(closeEvidenceSleep)
    end
end)