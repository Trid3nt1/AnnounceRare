-------------------------------------------------------------------------------
-- Announce Rare (BFA 8.2) By Crackpotx (US, Lightbringer)
-------------------------------------------------------------------------------
local AR = LibStub("AceAddon-3.0"):NewAddon("AnnounceRare", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0")
AR.version = GetAddOnMetadata("AnnounceRare", "Version")
local CTL = assert(ChatThrottleLib, "AnnounceRare requires ChatThrottleLib.")
local L = LibStub("AceLocale-3.0"):GetLocale("AnnounceRare", false)

-- local api cache
local C_ChatInfo_GetNumActiveChannels = C_ChatInfo.GetNumActiveChannels
local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Map_GetMapInfo = C_Map.GetMapInfo
local C_Map_GetPlayerMapPosition = C_Map.GetPlayerMapPosition
local CombatLogGetCurrentEventInfo = _G["CombatLogGetCurrentEventInfo"]
local EnumerateServerChannels = _G["EnumerateServerChannels"]
local GetChannelName = _G["GetChannelName"]
local GetGameTime = _G["GetGameTime"]
local GetItemInfo = _G["GetItemInfo"]
local GetLocale = _G["GetLocale"]
local GetPlayerMapPosition = _G["GetPlayerMapPosition"]
local GetZoneText = _G["GetZoneText"]
local SendChatMessage = _G["SendChatMessage"]
local UnitAffectingCombat = _G["UnitAffectingCombat"]
local UnitAura = _G["UnitAura"]
local UnitClassification = _G["UnitClassification"]
local UnitExists = _G["UnitExists"]
local UnitGUID = _G["UnitGUID"]
local UnitHealth = _G["UnitHealth"]
local UnitHealthMax = _G["UnitHealthMax"]
local UnitIsDead = _G["UnitIsDead"]
local UnitName = _G["UnitName"]

local band = bit.band
local ceil = math.ceil
local match = string.match
local format = string.format
local pairs = pairs
local strsplit = strsplit
local tonumber = tonumber
local tostring = tostring

local channelFormat = "%s - %s"
local channelRUFormat = "%s: %s"
local outputChannel = "|cffffff00%s|r"
local messageToSend = L["%s%s (%s/%s %.2f%%) is at %s %s%s, and %s"]
local deathMessage = L["%s%s has been slain %sat %02d:%02d!"]
local defaults = {
	global = {
		armory = true,
		autoAnnounce = false,
		advertise = false,
		announceDeath = true,
		onLoad = false,
		output = "CHANNEL",
	}
}

local rares = {
	[151884] = "Fungarian Furor", -- Fungarian Furor
    [135497] = "Fungarian Furor", -- Fungarian Furor
    [151625] = "The Scrap King", -- The Scrap King
    [151623] = "The Scrap King (Mounted)", -- The Scrap King (Mounted)
    [152569] = "Crazed Trogg (Green)", -- Crazed Trogg (Green)
    [152570] = "Crazed Trogg (Blue)", -- Crazed Trogg (Blue)
	[149847] = "Crazed Trogg (Orange)", -- Crazed Trogg (Orange)
}

local function UpdateDuplicates(id)
	if id == 151884 then
		AR.rares[#AR.rares + 1] = 135497
	elseif id == 135497 then
		AR.rares[#AR.rares + 1] = 151884
	elseif id == 151625 then
		AR.rares[#AR.rares + 1] = 151623
	elseif id == 151623 then
		AR.rares[#AR.rares + 1] = 151625
	elseif id == 152569 then
		AR.rares[#AR.rares + 1] = 152570
		AR.rares[#AR.rares + 1] = 149847
	elseif id == 152570 then
		AR.rares[#AR.rares + 1] = 152569
		AR.rares[#AR.rares + 1] = 149847
	elseif id == 149847 then
		AR.rares[#AR.rares + 1] = 152569
		AR.rares[#AR.rares + 1] = 152570
	end
end

local function GetTargetId()
	local guid = UnitGUID("target")
	if guid == nil then return nil end
	local unitType, _, _, _, _, unitId = strsplit("-", guid);
	return (unitType == "Creature" or UnitType == "Vehicle") and tonumber(unitId) or nil
end

local function GetNPCGUID(guid)
	if guid == nil then return nil end
	local unitType, _, _, _, _, unitId = strsplit("-", guid);
	return (unitType == "Creature" or UnitType == "Vehicle") and tonumber(unitId) or nil
end

local function GetGeneralChannelNumber()
	local zoneText = GetZoneText()
	local general = EnumerateServerChannels()
	if zoneText == nil or general == nil then return false end
	return GetChannelName(GetLocale() == "ruRU" and channelRUFormat:format(general, zoneText) or channelFormat:format(general, zoneText))
end

local function IsValidOutputChannel(chan)
	return (chan == "general" or chan == "say" or chan == "guild" or chan == "yell" or chan == "party" or chan == "raid") and true or false
end

-- Time Displacement
local function IsInAltTimeline()
	for i = 1, 40 do
		local name = UnitAura("player", i)
		if name == "Time Displacement" then
			return true
		end
	end
	return false
end

local function GetConfigStatus(configVar)
	return configVar == true and L["|cff00ff00ENABLED|r"] or L["|cffff0000DISABLED|r"]
end

local function FormatNumber(n)
    if n >= 10^6 then
        return format("%.2fm", n / 10^6)
    elseif n >= 10^3 then
        return format("%.2fk", n / 10^3)
    else
        return tostring(n)
    end
end

local function FindInArray(toFind, arraySearch)
	if #arraySearch == 0 then return false end
	for _, value in pairs(arraySearch) do
		if value == toFind then
			return true
		end
	end
	return false
end

local function DecRound(num, decPlaces)
	return format("%." .. (decPlaces or 0) .. "f", num)
end

local function AnnounceRare()
	-- player target is a rare
	local tarId, tarCombat = GetTargetId(), UnitAffectingCombat("target")
	local tarHealth, tarHealthMax = UnitHealth("target"), UnitHealthMax("target")
	local tarHealthPercent = (tarHealth / tarHealthMax) * 100
	local tarPos = C_Map_GetPlayerMapPosition(C_Map_GetBestMapForUnit("player"), "player")
	local genId = GetGeneralChannelNumber()

	if tarId == nil then
		AR:Print(L["Unable to determine target's GUID."])
	elseif AR.db.global.output:upper() == "CHANNEL" and not genId then
		AR:Print(L["Unable to determine your general channel number."])
	else
		CTL:SendChatMessage("NORMAL", "AnnounceRare", messageToSend:format(
			AR.db.global.advertise == true and "AnnounceRare: " or "",
			rares[tarId] ~= nil and rares[tarId] or UnitName("target"),
			FormatNumber(tarHealth),
			FormatNumber(tarHealthMax),
			tarHealthPercent,
			ceil(tarPos.x * 10000) / 100,
			ceil(tarPos.y * 10000) / 100,
			IsInAltTimeline() == true and " " .. L["in the alternative timeline"] or "",
			UnitAffectingCombat("target") == true and L["has been engaged!"] or L["has NOT been engaged!"]
		), AR.db.global.output:upper(), nil, AR.db.global.output:upper() == "CHANNEL" and genId or nil)
	end
end

local function ValidTarget()
	-- if no target, then fail
	if not UnitExists("target") then
		return false
	else
		local tarClass = UnitClassification("target")
		if tarClass ~= "rare" and tarClass ~= "rareelite" then
			return false
		else
			if UnitIsDead("target") then
				return false
			else
				local tarId = GetNPCGUID(UnitGUID("target"))
				if tarId == nil then
					return false
				else 
					return (not FindInArray(tarId, AR.rares)) and true or false
				end
			end
		end
	end
end

function AR:CheckZone(...)
	local mapId = C_Map_GetBestMapForUnit("player")
	local mapInfo = C_Map_GetMapInfo(mapId)
	if (mapId == 1355 or mapInfo["parentMapID"] == 1355) or (mapId == 1462 or mapInfo["parentMapID"] == 1462) and self.correctZone == false then
		self.correctZone = true
	elseif ((mapId ~= 1355 and mapInfo["parentMapID"] ~= 1355 and mapId ~= 1462 and mapInfo["parentMapID"] ~= 1462) or mapId == nil) and self.correctZone == true then
		self.correctZone = false
	end
end

function AR:Print(msg)
	print(("|cffff7d0aAR:|r |cffffffff%s|r"):format(msg))
end

function AR:PLAYER_TARGET_CHANGED()
	if self.db.global.autoAnnounce and self.correctZone and ValidTarget() then
		local tarId = GetTargetId()
		if tarId ~= nil then
			AnnounceRare()
			self.rares[#self.rares + 1] = tarId
			UpdateDuplicates(tarId)
		end
	end
end

function AR:COMBAT_LOG_EVENT_UNFILTERED()
	local _, subevent, _, _, _, sourceFlags, _, srcGuid, srcName = CombatLogGetCurrentEventInfo()
	if subevent == "UNIT_DIED" and self.correctZone then
		local id = GetNPCGUID(srcGuid) 
		if id ~= 151623 and self.db.global.announceDeath == true and #self.rares > 0 and FindInArray(id, self.rares) then
			local hours, minutes = GetGameTime()
			local genId = GetGeneralChannelNumber()

			if id == nil then
				self:Print(L["Unable to determine the NPC's GUID."])
			elseif self.db.global.output:upper() == "CHANNEL" and not genId then
				self:Print(L["Unable to determine your general channel number."])
			else
				CTL:SendChatMessage("NORMAL", "AnnounceRare", deathMessage:format(
					self.db.global.advertise == true and "AnnounceRare: " or "",
					rares[id] ~= nil and rares[id] or srcName,
					IsInAltTimeline() == true and L["in the alternative timeline"] .. " " or "",
					hours,
					minutes
				), self.db.global.output:upper(), nil, self.db.global.output:upper() == "CHANNEL" and genId or nil)
			end
		end
	end
end

function AR:UPDATE_MOUSEOVER_UNIT(...)
	if self.correctZone then
		local ttItemName = GameTooltip:GetUnit()
		local armoryName, gravName  = GetItemInfo(169868)
		if self.db.global.armory and ttItemName == armoryName and self.lastArmory <= time() - 600 then
			local genId = GetGeneralChannelNumber()
			local tarPos = C_Map_GetPlayerMapPosition(C_Map_GetBestMapForUnit("player"), "player")
			CTL:SendChatMessage("NORMAL", "AnnounceRare", (L["Armory is located at %s %s!"]):format(ceil(tarPos.x * 10000) / 100, ceil(tarPos.y * 10000) / 100), self.db.global.output:upper(), nil, self.db.global.output:upper() == "CHANNEL" and genId or nil)
			self.lastArmory = time()
		end
	end
end

function AR:PLAYER_ENTERING_WORLD()
	self.rares = {}
	self.correctZone = false
	self.lastArmory = 0
	self:CheckZone()

	-- chat command using aceconsole-3.0
	self:RegisterChatCommand("rare", function(args)
		local key = self:GetArgs(args, 1)
		if key == "auto" then
			self.db.global.autoAnnounce = not self.db.global.autoAnnounce
			self:Print((L["Auto Announce has been %s!"]):format(GetConfigStatus(self.db.global.autoAnnounce)))
		elseif key == "death" then
			self.db.global.announceDeath = not self.db.global.announceDeath
			self:Print((L["Death Announcements have been %s!"]):format(GetConfigStatus(self.db.global.announceDeath)))
		elseif key == "adv" then
			self.db.global.advertise = not self.db.global.advertise
			self:Print((L["Advertisements have been %s!"]):format(GetConfigStatus(self.db.global.advertise)))
		elseif key == "armory" then
			self.db.global.armory = not self.db.global.armory
			self.Print((L["Armory announcements have been %s!"]):format(GetConfigStatus(self.db.global.armory)))
		elseif key == "help" or key == "?" then
			self:Print(L["Command Line Help"])
			self:Print(L["|cffffff00/rare|r - Announce rare to general chat."])
			self:Print(L["|cffffff00/rare armory|r - Toggle armory announcements."])
			self:Print(L["|cffffff00/rare auto|r - Toggle auto announcements."])
			self:Print(L["|cffffff00/rare death|r - Toggle death announcements."])
			self:Print(L["|cffffff00/rare load|r - Toggle loading announcement."])
			self:Print(L["|cffffff00/rare output (general|say|yell|guild|party|raid)|r - Change output channel."])
			self:Print(L["|cffffff00/rare status|r or |cffffff00/rare config|r - Print current configuration."])
			self:Print(L["|cffffff00/rare help|r or |cffffff00/rare ?|r - Print this help again."])
		elseif key == "load" then
			self.db.global.onLoad = not self.db.global.onLoad
			self:Print((L["Loading message has been %s!"]):format(GetConfigStatus(self.db.global.onLoad)))
		elseif key == "status" or key == "config" then
			self:Print((L["AnnounceRare by Crackpotx v%s"]):format(self.version))
			self:Print(L["For Help: |cffffff00/rare help|r"])
			self:Print((L["Advertisements: %s"]):format(GetConfigStatus(self.db.global.advertise)))
			self:Print((L["Armory Announcements: %s"]):format(GetConfigStatus(self.db.global.armory)))
			self:Print((L["Automatic Announcements: %s"]):format(GetConfigStatus(self.db.global.autoAnnounce)))
			self:Print((L["Death Announcements: %s"]):format(GetConfigStatus(self.db.global.announceDeath)))
			self:Print((L["Load Announcement: %s"]):format(GetConfigStatus(self.db.global.onLoad)))
			self:Print((L["Output Channel: |cffffff00%s|r"]):format(self.db.global.output:upper() == "CHANNEL" and "GENERAL" or self.db.global.output))
		elseif key == "output" then
			local _, value = self:GetArgs(args, 2)
			value = value:lower()
			if value == "" or value == nil then
				self:Print(L["You must provide an output channel for the announcements."])
			else
				if not IsValidOutputChannel(value) then
					self:Print((L["Valid Outputs: %s, %s, %s, %s, %s, %s"]):format(
						outputChannel:format(L["general"]),
						outputChannel:format(L["say"]),
						outputChannel:format(L["yell"]),
						outputChannel:format(L["guild"]),
						outputChannel:format(L["party"]),
						outputChannel:format(L["raid"])
					))
				else
					self.db.global.output = value ~= "general" and value:upper() or "CHANNEL"
					self:Print((L["Changed output to %s!"]):format(outputChannel:format(value:upper())))
				end
			end
		else 
			local zoneText = GetZoneText()
			local tarClass = UnitClassification("target")
			-- only do anything when the player is in mechagon or nazjatar
			if self.correctZone then
				if ValidTarget() then
					AnnounceRare()
				elseif not UnitExists("target") then
					self:Print(L["You do not have a target."])
				elseif UnitIsDead("target") then
					self:Print(format(L["%s is already dead."], UnitName("target"))) 
				elseif (tarClass ~= "rare" and tarClass ~= "rareelite") then
					self:Print(format(L["%s is not a rare or you have killed it today."], UnitName("target")))
				end
			else
				self:Print(L["You must be in Mechagon or Nazjatar to use this command."])
			end
		end
	end)

	if self.db.global.onLoad == true then
		self:Print((L["AnnounceRare v%s loaded! Please use |cffffff00/rare help|r for commands."]):format(GetAddOnMetadata("AnnounceRare", "Version")))
	end
end

function AR:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("AnnounceRareDB", defaults)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	self:RegisterEvent("ZONE_CHANGED", function() AR:CheckZone() end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() AR:CheckZone() end)
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end