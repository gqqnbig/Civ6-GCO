--=====================================================================================--
--	FILE:	 PlayerScript.lua
--  Gedemon (2017)
--=====================================================================================--

print ("Loading PlayerScript.lua...")

-----------------------------------------------------------------------------------------
-- Defines
-----------------------------------------------------------------------------------------

local _cached				= {}	-- cached table to reduce calculations


-----------------------------------------------------------------------------------------
-- Initialize
-----------------------------------------------------------------------------------------

local GCO = {}
function InitializeUtilityFunctions() 	-- Get functions from other contexts
	GCO = ExposedMembers.GCO
	print ("Exposed Functions from other contexts initialized...")
	PostInitialize()
end
LuaEvents.InitializeGCO.Add( InitializeUtilityFunctions )

function SaveTables()
	print("--------------------------- Saving PlayerData ---------------------------")
	GCO.SaveTableToSlot(ExposedMembers.PlayerData, "PlayerData")
end
LuaEvents.SaveTables.Add(SaveTables)

function PostInitialize() -- everything that may require other context to be loaded first
	ExposedMembers.PlayerData = GCO.LoadTableFromSlot("PlayerData") or {}
	InitializePlayerFunctions()
	InitializePlayerData() -- after InitializePlayerFunctions
end

function InitializePlayerData()
	for _, playerID in ipairs(PlayerManager.GetWasEverAliveIDs()) do
		local player = Players[playerID]
		if player and not ExposedMembers.PlayerData[player:GetKey()] then
			player:InitializeData()
		end	
	end
end


-----------------------------------------------------------------------------------------
-- Player functions
-----------------------------------------------------------------------------------------

function UpdatePopulationNeeds(self)
	local era = self:GetEra()
	for row in GameInfo.PopulationNeeds() do
		local startEra 	= GameInfo.Eras[row.StartEra].Index
		local EndEra	= GameInfo.Eras[row.EndEra].Index
		if (not startEra or (startEra and startEra >= era)) and (not EndEra or (EndEra and EndEra < era)) then
			local resourceID 	= GameInfo.Resources[row.ResourceType].Index
			local populationID 	= GameInfo.Populations[row.PopulationType].Index
			if not _cached.PopulationNeeds then _cached.PopulationNeeds = {} end
			if not _cached.PopulationNeeds[populationID] then _cached.PopulationNeeds[populationID] = {} end
			if not _cached.PopulationNeeds[populationID][resourceID] then _cached.PopulationNeeds[populationID][resourceID] = {} end
			if not _cached.PopulationNeeds[populationID][resourceID][row.AffectedType] then _cached.PopulationNeeds[populationID][resourceID][row.AffectedType] = {} end
			_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].NeededCalculFunction 	= loadstring(row.NeededCalculFunction)
			_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].EffectCalculFunction 	= loadstring(row.EffectCalculFunction)
			--_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].StartEra 				= GameInfo.Eras[row.StartEra].Index
			--_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].EndEra 				= GameInfo.Eras[row.EndEra].Index
			_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].OnlyBonus 				= row.OnlyBonus
			_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].OnlyPenalty 			= row.OnlyPenalty
			_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].MaxEffectValue 			= row.MaxEffectValue
			_cached.PopulationNeeds[populationID][resourceID][row.AffectedType].Treshold 				= row.Treshold
		end		 
	end
end

function GetPopulationNeeds(self, populationID)
	if not _cached.PopulationNeeds then self:UpdatePopulationNeeds() end
	return _cached.PopulationNeeds[populationID]
end

function InitializeData(self)
	local playerKey = self:GetKey()
	ExposedMembers.PlayerData[playerKey] = {
		CurrentTurn = Game.GetCurrentGameTurn(),
	}
end

function GetKey(self)
	return tostring(self:GetID())
end

function IsResourceVisible(self, resourceID)
	return GCO.IsResourceVisibleFor(self, resourceID)
end
	
function SetCurrentTurn(self)
	local playerKey = self:GetKey()
	ExposedMembers.PlayerData[playerKey].CurrentTurn = Game.GetCurrentGameTurn()
end

function HasStartedTurn(self)
	local playerKey = self:GetKey()
	return (ExposedMembers.PlayerData[playerKey].CurrentTurn == Game.GetCurrentGameTurn())
end

function UpdateUnitsFlags(self)
	local playerUnits = self:GetUnits()
	if playerUnits then
		for i, unit in playerUnits:Members() do			
			LuaEvents.UnitsCompositionUpdated(self:GetID(), unit:GetID())
		end
	end
end

function UpdateCitiesBanners(self)
	local playerCities = self:GetCities()
	if playerCities then
		for i, city in playerCities:Members() do			
			LuaEvents.CityCompositionUpdated(self:GetID(), city:GetID())
		end
	end
end

function UpdateDataOnNewTurn(self)
	local playerConfig = PlayerConfigurations[self:GetID()]
	print("---------------------------------------------------------------------------")
	print("- Updating Data on new turn for "..Locale.Lookup(playerConfig:GetCivilizationShortDescription()))
	local playerCities = self:GetCities()
	if playerCities then
		for i, city in playerCities:Members() do
			GCO.AttachCityFunctions(city)
			city:UpdateDataOnNewTurn()
		end
	end
	local playerUnits = self:GetUnits()
	if playerUnits then
		for j, unit in playerUnits:Members() do
			GCO.AttachUnitFunctions(unit)
			unit:UpdateDataOnNewTurn()
		end
	end
end


function DoPlayerTurn( playerID )
	if (playerID == -1) then playerID = 0 end -- this is necessary when starting in AutoPlay
	local player = Players[playerID]
	local playerConfig = PlayerConfigurations[playerID]
	print("---============================================================================================================================================================================---")
	print("--- STARTING TURN # ".. tostring(Game.GetCurrentGameTurn()) .." FOR PLAYER # ".. tostring(playerID) .. " ( ".. tostring(Locale.ToUpper(Locale.Lookup(playerConfig:GetCivilizationShortDescription()))) .." )")
	print("---============================================================================================================================================================================---")
	player:UpdatePopulationNeeds()
	LuaEvents.DoUnitsTurn( playerID )
	LuaEvents.DoCitiesTurn( playerID )
	-- update flags after resources transfers
	player:UpdateUnitsFlags()
	player:UpdateCitiesBanners()
	player:SetCurrentTurn()
end
--LuaEvents.StartPlayerTurn.Add(DoPlayerTurn)

-- can't use those, they makes the game crash at self.m_Instance.UnitIcon:SetToolTipString( Locale.Lookup(nameString) ) in UnitFlagManager, and some other unidentified parts of the code...
--GameEvents.PlayerTurnStarted.Add(DoPlayerTurn)
--GameEvents.PlayerTurnStartComplete.Add(DoPlayerTurn)

function DoTurnForLocal()
	local playerID = Game.GetLocalPlayer()
	local player = Players[playerID]
	if player and not player:HasStartedTurn() then
		DoPlayerTurn(playerID)
		LuaEvents.SaveTables()
	end
end
Events.LocalPlayerTurnBegin.Add( DoTurnForLocal )

function DoTurnForRemote( playerID )
	DoPlayerTurn(playerID)
end
Events.RemotePlayerTurnBegin.Add( DoTurnForRemote )



-----------------------------------------------------------------------------------------
-- Shared Functions
-----------------------------------------------------------------------------------------
function GetPlayer(playerID)
	local player= Players[playerID]
	if not player then
		print("ERROR : player is nil in GetPlayer for playerID#", playerID)
		return
	end
	InitializePlayerFunctions(player)
	return player
end

-----------------------------------------------------------------------------------------
-- Initialize Player Functions
-----------------------------------------------------------------------------------------
function InitializePlayerFunctions(player) -- Note that those functions are limited to this file context
	if not player then player = Players[0] end
	local p = getmetatable(player).__index
	
	p.GetKey					= GetKey
	p.InitializeData			= InitializeData
	p.IsResourceVisible			= IsResourceVisible
	p.UpdateUnitsFlags			= UpdateUnitsFlags
	p.UpdateCitiesBanners		= UpdateCitiesBanners
	p.SetCurrentTurn			= SetCurrentTurn
	p.HasStartedTurn			= HasStartedTurn
	p.UpdateDataOnNewTurn		= UpdateDataOnNewTurn
	p.UpdatePopulationNeeds		= UpdatePopulationNeeds
	p.GetPopulationNeeds		= GetPopulationNeeds
	
end


----------------------------------------------
-- Share functions for other contexts
----------------------------------------------
function Initialize()
	if not ExposedMembers.GCO then ExposedMembers.GCO = {} end
	ExposedMembers.GCO.GetPlayer 					= GetPlayer
	ExposedMembers.GCO.InitializePlayerFunctions 	= InitializePlayerFunctions
	ExposedMembers.PlayerScript_Initialized 		= true
end
Initialize()