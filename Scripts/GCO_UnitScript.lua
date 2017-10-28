--=====================================================================================--
--	FILE:	 UnitScript.lua
--  Gedemon (2017)
--=====================================================================================--

print("Loading UnitScript.lua...")

-----------------------------------------------------------------------------------------
-- Debug
-----------------------------------------------------------------------------------------

DEBUG_UNIT_SCRIPT			= true

function ToggleUnitDebug()
	DEBUG_UNIT_SCRIPT = not DEBUG_UNIT_SCRIPT
end


-----------------------------------------------------------------------------------------
-- Defines
-----------------------------------------------------------------------------------------

local GCO = ExposedMembers.GCO or {}

local UnitHitPointsTable 	= {} -- cached table to store the required values of an unit components based on it's HP
local UnitWithoutEquipment	= {} -- cached table to store units requiring equipment initialization
local UnitLastHealingValue	= {} -- cached table to store units HP gained from healing
--local UnitDelayedHealing	= {} -- cached table to store units with desync data for delayed healing

-- Delay equipment initialization (to allow a city/scenario to pass the equipment list to an unit that has just been build/spawned, after the mandatory data initialization on Events.UnitAddedToMap)
local InitializeEquipmentTimer 	= 0	
local InitializeEquipmentPause 	= 0.5
local initializeEquipmentCo		= false	-- the coroutine thread that will handle equipment initialization

local maxHP = GlobalParameters.COMBAT_MAX_HIT_POINTS -- 100

local reserveRatio = GameInfo.GlobalParameters["UNIT_RESERVE_RATIO"].Value

local lightRationing 			= tonumber(GameInfo.GlobalParameters["FOOD_RATIONING_LIGHT_RATIO"].Value)
local mediumRationing 			= tonumber(GameInfo.GlobalParameters["FOOD_RATIONING_MEDIUM_RATIO"].Value)
local heavyRationing 			= tonumber(GameInfo.GlobalParameters["FOOD_RATIONING_HEAVY_RATIO"].Value)

local SupplyLineLengthFactor	= tonumber(GameInfo.GlobalParameters["UNIT_SUPPLY_LINE_LENGTH_FACTOR"].Value)

local foodResourceID 		= GameInfo.Resources["RESOURCE_FOOD"].Index
local materielResourceID	= GameInfo.Resources["RESOURCE_MATERIEL"].Index
local horsesResourceID 		= GameInfo.Resources["RESOURCE_HORSES"].Index
local personnelResourceID	= GameInfo.Resources["RESOURCE_PERSONNEL"].Index
local medicineResourceID	= GameInfo.Resources["RESOURCE_MEDICINE"].Index

local foodResourceKey		= tostring(foodResourceID)
local materielResourceKey	= tostring(materielResourceID)
local horsesResourceKey		= tostring(horsesResourceID)
local personnelResourceKey	= tostring(personnelResourceID)
local medicineResourceKey	= tostring(medicineResourceID)

local attackerMaterielGainPercent	= tonumber(GameInfo.GlobalParameters["COMBAT_ATTACKER_MATERIEL_GAIN_PERCENT"].Value)
local attackerMaterielKillPercent	= tonumber(GameInfo.GlobalParameters["COMBAT_ATTACKER_MATERIEL_KILL_PERCENT"].Value)
local defenderMaterielGainPercent	= tonumber(GameInfo.GlobalParameters["COMBAT_DEFENDER_MATERIEL_GAIN_PERCENT"].Value)

--[[
local unitEquipment			= {}
for row in GameInfo.Units() do
	local unitType 	= row.UnitType
	local unitID 	= row.Index
	if row.EquipmentType then
		local equipmentID 	= GameInfo.Resources[row.EquipmentType].Index	-- equipment are special resources		
		if not unitEquipment[unitType] then unitEquipment[unitType] = {} end
		unitEquipment[unitType] = equipmentID
		-- This is to handle index, as pUnit:GetUnitType() returns an index...
		if not unitEquipment[unitID] then unitEquipment[unitID] = {} end
		unitEquipment[unitID] = equipmentID
		-- This is to accept hash like ToolTipHelper
		if not unitEquipment[row.Hash] then unitEquipment[row.Hash] = {} end
		unitEquipment[row.Hash] = equipmentID		
	end
	if row.Equipment > 0 and not row.EquipmentType then
		print("WARNING: Equipment required without EquipmentType for "..tostring(row.UnitType))
	end
end
--]]

local unitEquipmentClasses	= {}
for row in GameInfo.UnitEquipmentClasses() do
	local equipmentClass = row.EquipmentClass
	local unitType 	= row.UnitType
	local unitID 	= GameInfo.Units[unitType].Index
	if GameInfo.EquipmentClasses[equipmentClass] then
		local equipmentClassID 	= GameInfo.EquipmentClasses[equipmentClass].Index
		if not unitEquipmentClasses[unitType] then unitEquipmentClasses[unitType] = {} end
		unitEquipmentClasses[unitType][equipmentClassID] = {Amount = (GCO.Round(GameInfo.Units[unitType].Personnel * row.PercentageOfPersonnel / 100)), IsRequired = row.IsRequired}
		-- This is to handle index, as pUnit:GetUnitType() returns an index...
		if not unitEquipmentClasses[unitID] then unitEquipmentClasses[unitID] = {} end
		unitEquipmentClasses[unitID][equipmentClassID] = unitEquipmentClasses[unitType][equipmentClassID]
	else
		print("WARNING: no equipment class in GameInfo.EquipmentClasses for "..tostring(row.EquipmentClass))
	end
end

local EquipmentInfo = {}
for row in GameInfo.Equipment() do
	local equipmentType = row.ResourceType
	local equipmentID	= GameInfo.Resources[equipmentType].Index
	EquipmentInfo[equipmentID] = row
end

local equipmentTypeClasses	= {}
local equipmentIsClass		= {}
for row in GameInfo.EquipmentTypeClasses() do
	local equipmentClass 	= row.EquipmentClass
	local equipmentType 	= row.ResourceType
	if GameInfo.Resources[equipmentType] and GameInfo.Equipment[equipmentType] then -- equipment are special resources
		if GameInfo.EquipmentClasses[equipmentClass] then
			local equipmentClassID 	= GameInfo.EquipmentClasses[equipmentClass].Index
			local equipmentTypeID 	= GameInfo.Resources[equipmentType].Index
			local desirability = GameInfo.Equipment[equipmentType].Desirability

			-- This is to handle index, as pUnit:GetUnitType() returns an index...
			if not equipmentTypeClasses[equipmentClassID] then equipmentTypeClasses[equipmentClassID] = {} end
			table.insert(equipmentTypeClasses[equipmentClassID], {EquipmentID = equipmentTypeID, Desirability = desirability})
			-- helper to check if an equipment is part of a class
			if not equipmentIsClass[equipmentTypeID] then equipmentIsClass[equipmentTypeID] = {} end
			equipmentIsClass[equipmentTypeID][equipmentClassID] 	= true
		else
			print("WARNING: no equipment class in GameInfo.EquipmentClasses for "..tostring(equipmentClass))
		end
	else
		if GameInfo.Resources[equipmentType] then 
			print("WARNING: no equipment type in GameInfo.Equipment for "..tostring(equipmentType))
		else
			print("WARNING: no equipment type in GameInfo.Resources for "..tostring(equipmentType))
		end
	end
end

local equipmentUnitTypes	= {}
for unitTypeID, equipmentClasses in pairs(unitEquipmentClasses) do
	for equipmentClassID, _ in pairs(equipmentClasses) do
		if equipmentTypeClasses[equipmentClassID] then
			for _, equipmentData in pairs(equipmentTypeClasses[equipmentClassID]) do
				if not equipmentUnitTypes[equipmentData.EquipmentID] then
					equipmentUnitTypes[equipmentData.EquipmentID] = { [unitTypeID] = equipmentClassID }
					--print("Unit Type = ".. Locale.Lookup(GameInfo.Units[unitTypeID].Name) ..", Equipment Type = ".. Locale.Lookup(GameInfo.Resources[equipmentData.EquipmentID].Name) ..", class = ".. Locale.Lookup(GameInfo.EquipmentClasses[equipmentClassID].Name))
				elseif equipmentUnitTypes[equipmentData.EquipmentID][unitTypeID] then
					print("WARNING: Equipment Type ".. Locale.Lookup(GameInfo.Resources[equipmentData.EquipmentID].Name) .." in multiple classes (".. Locale.Lookup(GameInfo.EquipmentClasses[equipmentUnitTypes[equipmentData.EquipmentID][unitTypeID]].Name) ..", ".. Locale.Lookup(GameInfo.EquipmentClasses[equipmentClassID].Name) .." for unit type "..Locale.Lookup(GameInfo.units[unitTypeID].Name))
				else
					--print("Unit Type = ".. Locale.Lookup(GameInfo.Units[unitTypeID].Name) ..", Equipment Type = ".. Locale.Lookup(GameInfo.Resources[equipmentData.EquipmentID].Name) ..", class = ".. Locale.Lookup(GameInfo.EquipmentClasses[equipmentClassID].Name))
					equipmentUnitTypes[equipmentData.EquipmentID][unitTypeID] = equipmentClassID
				end
			end
		end
	end
end

-- Sort equipment list by desirability now, to prevent multiple calls to table.sort when dealing with equipment tranfert 
for row in GameInfo.EquipmentClasses() do
	if equipmentTypeClasses[row.Index] then
		table.sort(equipmentTypeClasses[row.Index], function(a, b) return a.Desirability > b.Desirability; end)
	end
end

-- Floating Texts LOD
local FLOATING_TEXT_NONE 	= 0
local FLOATING_TEXT_SHORT 	= 1
local FLOATING_TEXT_LONG 	= 2
local floatingTextLevel 	= FLOATING_TEXT_SHORT

-----------------------------------------------------------------------------------------
-- Initialize 
-----------------------------------------------------------------------------------------
local CombatTypes = {}
function InitializeUtilityFunctions()
	GCO 		= ExposedMembers.GCO			-- contains functions from other contexts
	CombatTypes = ExposedMembers.CombatTypes 	-- need those in combat results
	Dprint 		= GCO.Dprint					-- Dprint(bOutput, str) : print str if bOutput is true
	Dline		= GCO.Dline						-- output current code line number to firetuner/log
	Dlog		= GCO.Dlog						-- log a string entry, last 10 lines displayed after a call to GCO.Error()
	print("Exposed Functions from other contexts initialized...")
	PostInitialize()
end
function InitializeCheck()
	if not ExposedMembers.UnitData then GCO.Error("ExposedMembers.UnitData is nil after Initialization") end
end
LuaEvents.InitializeGCO.Add( InitializeUtilityFunctions )
LuaEvents.InitializeGCO.Add( InitializeCheck )

function PostInitialize() -- everything that may require other context to be loaded first
	LoadUnitTable()
end

function Initialize() -- Everything that can be initialized immediatly after loading this file(cached tables)
	CreateUnitHitPointsTable()
	ExposedMembers.UnitHitPointsTable = UnitHitPointsTable
	ShareFunctions()
	
	Events.UnitAddedToMap.Add( InitializeUnitFunctions )
	Events.UnitAddedToMap.Add( InitializeUnit ) -- InitializeUnitFunctions must be called before InitializeUnit...
end

-----------------------------------------------------------------------------------------
-- Unit composition
-----------------------------------------------------------------------------------------
local minCompLeftFactor = GameInfo.GlobalParameters["UNIT_MIN_COMPONENT_LEFT_FACTOR"].Value -- Modded global parameters are not in GlobalParameters.NAME like vanilla parameters ?????
local maxCompLeftFactor = GameInfo.GlobalParameters["UNIT_MAX_COMPONENT_LEFT_FACTOR"].Value
function GetNumComponentAtHP(maxNumComponent, HPLeft)
	local numComponent = 0
	local maxCompLeft100 = 0
	local minCompLeft100 = ((HPLeft * 100) * (maxNumComponent / maxHP) * (HPLeft / maxHP))
	if maxHP > maxNumComponent then
		maxCompLeft100 = math.min(HPLeft * 100, math.min(maxNumComponent * 100, (HPLeft * 100 / (maxNumComponent / maxHP))))
	else
		maxCompLeft100 = math.min(maxNumComponent * 100, HPLeft * 100 * ( maxNumComponent / maxHP))
	end
	local numComponent100 = math.max( 100, ((( minCompLeft100 * minCompLeftFactor) + ( maxCompLeft100 * maxCompLeftFactor)) / ( minCompLeftFactor + maxCompLeftFactor )))
	numComponent = math.ceil(numComponent100 / 100)
	return numComponent
end

function CreateUnitHitPointsTable()
	for row in GameInfo.Units() do
		UnitHitPointsTable[row.Index] = {}
		local Personnel 		= row.Personnel
		--local Equipment 		= row.Equipment
		local EquipmentClass 	= {}
		local classTable		= unitEquipmentClasses[row.Index]
		if classTable then
			for classType, data in pairs(classTable) do
				EquipmentClass[classType] = data.Amount
			end
		end
		local Horses = row.Horses
		local Materiel = row.Materiel
		for hp = 0, maxHP do
			UnitHitPointsTable[row.Index][hp] = {}
			if Personnel > 0 then UnitHitPointsTable[row.Index][hp].Personnel = GetNumComponentAtHP(Personnel, hp) else UnitHitPointsTable[row.Index][hp].Personnel = 0 end
			--Equipment
			for classType, value in pairs(EquipmentClass) do
				if not UnitHitPointsTable[row.Index][hp].EquipmentClass then UnitHitPointsTable[row.Index][hp].EquipmentClass = {} end
				if value > 0 then UnitHitPointsTable[row.Index][hp].EquipmentClass[classType] = GetNumComponentAtHP(value, hp) else UnitHitPointsTable[row.Index][hp].EquipmentClass[classType] = 0 end
			end
			if Horses > 0 then UnitHitPointsTable[row.Index][hp].Horses = GetNumComponentAtHP(Horses, hp) else UnitHitPointsTable[row.Index][hp].Horses = 0 end
			if Materiel > 0 then UnitHitPointsTable[row.Index][hp].Materiel = GetNumComponentAtHP(Materiel, hp) else UnitHitPointsTable[row.Index][hp].Materiel = 0 end
		end
	end
end

-----------------------------------------------------------------------------------------
-- Load/Save the tables
-----------------------------------------------------------------------------------------
-- Use Enum for faster serialization
local unitTableEnum = {

	unitID						= 1,
	playerID					= 2,
	unitType					= 3,
	--MaterielPerEquipment		= 4,
	Personnel					= 5,
	Equipment					= 6,
	Horses						= 7,
	Materiel					= 8,
	PersonnelReserve			= 9,
	EquipmentReserve			= 10,
	HorsesReserve				= 11,
	MaterielReserve				= 12,
	WoundedPersonnel			= 13,
	DamagedEquipment			= 14,
	Prisoners					= 15,
	FoodStock					= 16,
	PreviousFoodStock			= 17,
	TotalDeath					= 18,
	TotalEquipmentLost			= 19,
	TotalHorsesLost				= 20,
	TotalKill					= 21,
	TotalUnitsKilled			= 22,
	TotalShipSunk				= 23,
	TotalTankDestroyed			= 24,
	TotalAircraftKilled			= 25,
	Morale						= 26,
	PreviousMorale				= 27,
	LastCombatTurn				= 28,
	LastCombatResult			= 29,
	LastCombatType				= 30,
	FuelConsumptionPerVehicle	= 31,
	TotalXP						= 32,
	CombatXP					= 33,
	SupplyLineCityKey			= 34,
	SupplyLineEfficiency		= 35,
	FuelStock					= 36,
	PreviousFuelStock			= 37,
	HP 							= 38,
	testHP						= 39,
	TurnCreated					= 40,
	Stock						= 41,
	BaseFoodStock				= 42,
	PreviousPersonnel			= 43,
	PreviousEquipment			= 44,
	PreviousHorses				= 45,
	PreviousMateriel			= 46,
	PreviousPersonnelReserve	= 47,
	PreviousEquipmentReserve	= 48,
	PreviousHorsesReserve		= 49,
	PreviousMaterielReserve		= 50,
	PreviousWoundedPersonnel	= 51,
	PreviousDamagedEquipment	= 52,
	PreviousPrisoners			= 53,
	MedicineStock				= 54,
	PreviousMedicineStock		= 55,
	UnitLastHealingValue		= 56,
	
	EndOfEnum				= 99
}                           

function SaveUnitTable()
	local UnitData = ExposedMembers.UnitData
	print("--------------------------- UnitData: Save w/Enum ---------------------------")
	GCO.StartTimer("Saving And Checking UnitData")
	local t = {}
	for key, data in pairs(UnitData) do
		t[key] = {}
		for name, enum in pairs(unitTableEnum) do
			t[key][enum] = data[name]
		end
	end	
	GCO.SaveTableToSlot(t, "UnitData")	
end

function LoadUnitTable()

	--print("--------------------------- UnitData: Load w/Enum ---------------------------")
	local unitData = {}
	local loadedTable = GCO.LoadTableFromSlot("UnitData")
	if loadedTable then
		for key, data in pairs(loadedTable) do
			unitData[key] = {}
			for name, enum in pairs(unitTableEnum) do
				unitData[key][name] = data[enum]
			end			
		end
		ExposedMembers.UnitData = unitData
	else
		ExposedMembers.UnitData = {}
	end
end

function SaveTables()
	GCO.UnitDataSavingCheck = nil
	SaveUnitTable()
end
LuaEvents.SaveTables.Add(SaveTables)

function CheckSave()
	print("Checking Saved Table...")
	local unitData = {}
	local loadedTable = GCO.LoadTableFromSlot("UnitData")
	if loadedTable then
		for key, data in pairs(loadedTable) do
			unitData[key] = {}
			for name, enum in pairs(unitTableEnum) do
				unitData[key][name] = data[enum]
			end			
		end
	end
	if GCO.AreSameTables(ExposedMembers.UnitData, unitData) then
		print("- Tables are identical")
	else
		GCO.Error("reloading saved table show differences with actual table !")
		LuaEvents.StopAuToPlay()
		CompareData(ExposedMembers.UnitData, unitData)
	end	
	GCO.ShowTimer("Saving And Checking UnitData")
	GCO.UnitDataSavingCheck = true
end
LuaEvents.SaveTables.Add(CheckSave)

function ControlSave()
	if not GCO.UnitDataSavingCheck then
		GCO.ErrorWithLog("UnitData saving check failed !")
		ShowUnitData()
	end
end
LuaEvents.SaveTables.Add(ControlSave)

-- for debugging load/save
function ShowUnitData()
	for unitKey, data in pairs(ExposedMembers.UnitData) do
		print(unitKey, data)
		for k, v in pairs (data) do
			print("-", k, v)
			if k == "Prisoners" then
				for id, num in pairs (v) do
					print("-", "-", id, num)
				end			
			end
			
			if k == "Equipment" then
				for class, data in pairs (v) do
					print("-", "-", Locale.Lookup(GameInfo.EquipmentClasses[tonumber(class)].Name), data)
					
					for id, num in pairs (data) do
						print("-", "-", "-", Locale.Lookup(GameInfo.Resources[tonumber(id)].Name), num)
					end		
				end			
			end
		end
	end
end

function ShowUnitDataFromTable(UnitData)
	for unitKey, data in pairs(UnitData) do
		print(unitKey, data)
		for k, v in pairs (data) do
			print("-", k, v)
			if k == "Prisoners" then
				for id, num in pairs (v) do
					print("-", "-", id, num)
				end			
			end
		end
	end
end

function CompareData(data1, data2)
	print("comparing...")
	for key, data in pairs(data1) do
		for k, v in pairs (data) do
			if not data2[key] then
				print("- reloaded table is nil for key = ", key)
			elseif data2[key] and not data2[key][k] then			
				print("- no value for key = ", key, " entry =", k)
			elseif data2[key] and type(v) ~= "table" and v ~= data2[key][k] then
				print("- different value for key = ", key, " entry =", k, " Data1 value = ", v, type(v), " Data2 value = ", data2[key][k], type(data2[key][k]) )
			end
		end
	end
	print("no more data to compare...")
end

-----------------------------------------------------------------------------------------
-- Units Initialization
-----------------------------------------------------------------------------------------
function RegisterNewUnit(playerID, unit, partialHP) -- use partialHP to initialize incomplete unit

	--local DEBUG_UNIT_SCRIPT = true
	
	--[[ Current HP (ie unit:GetMaxDamage() - unit:GetDamage()) can't be trusted
	***********
	26-Oct-2017
	
	The DLL return the HP left after all combats, which are processed in GameCore before any of the current (non-crashing) Events
	related to player turn or units can be called, including Events.UnitAddedToMap.
	So we're using a virtual HP value, stocked in the UnitData table, updated only when the mod is controlling healing or checking damage,
	and we monitor and revert changes made outside the mod's control (actually only hardcoded healing from pillaging improvments)
	***********
	--]]
	
	local hp 		= partialHP or maxHP
	
	local unitType 	= unit:GetType()
	local unitID 	= unit:GetID()
	local unitKey 	= unit:GetKey()
	local food 		= SetBaseFoodStock(unitType)	
	
	local personnel = UnitHitPointsTable[unitType][hp].Personnel
	local horses 	= UnitHitPointsTable[unitType][hp].Horses
	local materiel 	= UnitHitPointsTable[unitType][hp].Materiel
	
	local PersonnelReserve	= 0--GetBasePersonnelReserve(unitType)
	local HorsesReserve		= 0--GetBaseHorsesReserve(unitType)
	local MaterielReserve	= 0--GetBaseMaterielReserve(unitType)
	
	local Morale 			= tonumber(GameInfo.GlobalParameters["MORALE_BASE_VALUE"].Value)
	local FuelStock 		= GetBaseFuelStock(unitType)

	-- Initialize the unit's data
	Dprint( DEBUG_UNIT_SCRIPT, "  - initialize unit data")
	ExposedMembers.UnitData[unitKey] = {
		TurnCreated				= Game.GetCurrentGameTurn(),
		unitID 					= unitID,
		playerID 				= playerID,
		unitType 				= unitType,
		--MaterielPerEquipment 	= GameInfo.Units[unitType].MaterielPerEquipment,
		HP	 					= hp, -- Should only update this when updating the unit's composition during mod's healing/damage to reflect the HP relative to the composition of the unit.
		testHP	 				= hp,
		UnitLastHealingValue	= 0,
		-- "Frontline" : combat ready, units HP are restored only if there is enough reserve to move to frontline for all required components
		Personnel 				= personnel,
		Equipment 				= {}, -- {[EquipmentClassKey] = { [ResourceKey] = value, ... } , ...}
		Horses 					= horses,
		Materiel 				= materiel,
		PreviousPersonnel 		= personnel,
		PreviousEquipment 		= {},
		PreviousHorses 			= horses,
		PreviousMateriel 		= materiel,
		-- "Tactical Reserve" : ready to reinforce frontline, that's where reinforcements from cities, healed personnel and repaired Equipment are affected first
		PersonnelReserve		= PersonnelReserve,
		EquipmentReserve		= {},
		HorsesReserve			= HorsesReserve,
		MaterielReserve			= MaterielReserve,
		PreviousPersonnelReserve= PersonnelReserve,
		PreviousEquipmentReserve= {},
		PreviousHorsesReserve	= HorsesReserve,		
		PreviousMaterielReserve	= MaterielReserve,
		-- "Rear"
		WoundedPersonnel		= 0,
		DamagedEquipment		= {},
		Prisoners				= GCO.CreateEverAliveTableWithDefaultValue(0), -- table with all civs in game (including Barbarians) to track Prisoners by nationality
		PreviousWoundedPersonnel= 0,
		PreviousDamagedEquipment= {},
		PreviousPrisoners		= GCO.CreateEverAliveTableWithDefaultValue(0),
		FoodStock 				= food,
		BaseFoodStock			= food,
		PreviousFoodStock		= food,
		FuelStock 				= FuelStock,
		PreviousFuelStock		= FuelStock,
		FuelConsumptionPerVehicle = GameInfo.Units[unitType].FuelConsumptionPerVehicle,
		MedicineStock			= 0,
		PreviousMedicineStock	= 0,
		Stock					= {},
		-- Statistics
		TotalDeath				= 0,
		TotalEquipmentLost		= {},
		TotalHorsesLost			= 0,
		TotalKill				= 0,
		TotalUnitsKilled		= 0,
		TotalShipSunk			= 0,
		TotalTankDestroyed		= 0,
		TotalAircraftKilled		= 0,
		-- Others
		Morale 					= Morale, -- 100
		--MoraleVariation			= 0,
		PreviousMorale			= Morale,
		LastCombatTurn			= 0,
		LastCombatResult		= 0,
		LastCombatType			= -1,
		--Alive 					= true,
		TotalXP 				= unit:GetExperience():GetExperiencePoints(),
		CombatXP 				= 0,
		SupplyLineCityKey		= nil,
		SupplyLineEfficiency 	= 0,
	}

	-- Mark the unit for delayed equipment initialization so we can get the equipment list from a city build queue as OnCityProductionCompleted is called after UnitAddedToMap
	-- Note : what if the AI attacks immediatly with a newly created unit ?
	-- Normally, in a city or with scenario/mod controlled spawn, 
	-- the unit will be equiped (next function call, or on event for city) immediatly after initialization by the mod
	-- So the delayed action should only be called for the initial units on a new game, before any possible combat...
	UnitWithoutEquipment[unitKey] = Automation.GetTime()
	if not initializeEquipmentCo then
		Dprint( DEBUG_UNIT_SCRIPT, "  - Creating Equipment Initialization coroutine...")
		initializeEquipmentCo = coroutine.create(DelayedEquipmentInitialization)
		--Events.GameCoreEventPublishComplete.Remove( CheckEquipmentInitializationTimer )
		Events.GameCoreEventPublishComplete.Add( CheckEquipmentInitializationTimer )
	end

	Dprint( DEBUG_UNIT_SCRIPT, "  - Set Supply lines")
	unit:SetSupplyLine()
	LuaEvents.NewUnitCreated()
end

function InitializeUnit(playerID, unitID)

	--local DEBUG_UNIT_SCRIPT = true
	
	local unit = UnitManager.GetUnit(playerID, unitID)
	if unit then
		local unitKey = unit:GetKey()
		if ExposedMembers.UnitData[unitKey] then 
			-- unit already registered, don't add it again...
			Dprint( DEBUG_UNIT_SCRIPT, "  - ".. unit:GetName() .." is already registered")
			return
		end
		
		-- check replacement for barbarian
		if Players[playerID]:IsBarbarian() then
			unit = CheckAndReplaceBarbarianUnit(unit)
		end
		
		if unit then
			Dprint( DEBUG_UNIT_SCRIPT, "Initializing new unit (".. Locale.Lookup(unit:GetName()) ..") for player #".. tostring(playerID).. " id#" .. tostring(unit:GetKey()))
			RegisterNewUnit(playerID, unit)
		end
	else
		print ("- WARNING : tried to initialize nil unit for player #".. tostring(playerID) .." (you can ignore this warning when launching a new game)")
	end

end

function InitializeEquipment(self, equipmentList) -- equipmentList optional, equipmentList = { EquipmentID = equipmentID, Value = value, Desirability = desirability }

	Dlog("InitializeEquipment /START")
	--local DEBUG_UNIT_SCRIPT = true	
	Dprint( DEBUG_UNIT_SCRIPT, "Initializing equipment for unit (".. Locale.Lookup(self:GetName()) ..") for player #".. tostring(self:GetOwner()).. " id#" .. tostring(self:GetKey()))
	
	local unitKey 	= self:GetKey()	
	
	-- what's below is (hopefully) deprecated with the use of virtualHP everywhere, else partialHP need to be passed 
	--[[
	-- Current HP can't be trusted, it's possible that the unit had already made an attack before InitializeEquipment() was called
	-- So we're initializing at maxHP (or partialHP if the argument exist), then we'll set back the current damage
	-- If there was indeed an attack before the initialization, we'll have to handle that in Combat event
	-- Actually Events.Combat is called after Events.CityProductionCompleted which call InitializeEquipment()
	-- with the equipmet list passed from the city that build it, but if that order change, we're fracked
 
	local currentDamage	= self:GetDamage()
	local initDamage	= 0
	if partialHP then initDamage = maxHP - partialHP end
	
	if initDamage ~= currentDamage then
		if not DEBUG_UNIT_SCRIPT then 
			print("WARNING: initDamage ~= currentDamage in InitializeEquipment() for unit (".. Locale.Lookup(self:GetName()) ..") of player #".. tostring(self:GetOwner()).. " id#" .. tostring(self:GetKey()))
			print("*******	currentDamage (GameCore) = ".. tostring(currentDamage) ..", initDamage = ".. tostring(initDamage).. ", partialHP = " .. tostring(partialHP))
		else
			print("WARNING: Current GameCore Damage ~= Initializing Damage")		
		end
	end
		
	--self:SetDamage(initDamage)
	--]]
	
	Dprint( DEBUG_UNIT_SCRIPT, " - Current GameCore Damage = ".. tostring(currentDamage) ..", initializing at Damage = ".. tostring(initDamage).. ", partialHP = " .. tostring(partialHP))
	
	-- set base equipment from a passed equipment list
	if equipmentList then
		Dprint( DEBUG_UNIT_SCRIPT, "  - add equipment from list")
		--table.sort(equipmentList, function(a, b) return a.Desirability > b.Desirability; end)
		for _, data in ipairs(equipmentList) do
			local equipmentID		= data.EquipmentID
			local equipmentClass	= self:GetEquipmentClass( equipmentID )
			local frontLineNeed		= self:GetEquipmentClassFrontLineNeed( equipmentClass )
			Dprint( DEBUG_UNIT_SCRIPT, "   - adding equipment class : ".. Locale.Lookup(GameInfo.EquipmentClasses[equipmentClass].Name))
			if data.Value > frontLineNeed then
				local reserveValue = data.Value - frontLineNeed
				Dprint( DEBUG_UNIT_SCRIPT, "   - equipment = ".. Locale.Lookup(GameInfo.Resources[equipmentID].Name), ", equipmentID = ", equipmentID, ", in frontline = ", frontLineNeed, ", in reserve = ", reserveValue)
				self:ChangeFrontLineEquipment( equipmentID, frontLineNeed )
				self:ChangeReserveEquipment( equipmentID, reserveValue )
			else
				Dprint( DEBUG_UNIT_SCRIPT, "   - equipment = ".. Locale.Lookup(GameInfo.Resources[equipmentID].Name), ", equipmentID = ", equipmentID, ", in frontline = ", data.Value)
				self:ChangeFrontLineEquipment( equipmentID, data.Value )
			end
		end	
	end
	
	-- complete (or set) basic equipment
	Dprint( DEBUG_UNIT_SCRIPT, "  - complete (or set) basic equipment")
	local requiredEquipmentClasses = self:GetRequiredEquipmentClasses()
	for equipmentClass, data in pairs(requiredEquipmentClasses) do
		Dprint( DEBUG_UNIT_SCRIPT, "   - adding equipment class : ".. Locale.Lookup(GameInfo.EquipmentClasses[equipmentClass].Name))

		local equipmentID	= GetLowerEquipmentType( equipmentClass )
		
		-- update frontline first, as GetEquipmentClassReserveNeed will refer to the number of equipment set in frontline...
		local frontLineNeed	= self:GetEquipmentClassFrontLineNeed( equipmentClass )
		self:ChangeFrontLineEquipment( equipmentID, frontLineNeed, equipmentClass )
		
		-- now that frontline is set, get requirement for reserve...
		local reserveNeed	= self:GetEquipmentClassReserveNeed( equipmentClass )
		self:ChangeReserveEquipment( equipmentID, reserveNeed, equipmentClass )
		
		Dprint( DEBUG_UNIT_SCRIPT, "   - equipment = ".. Locale.Lookup(GameInfo.Resources[equipmentID].Name), ", equipmentID = ", equipmentID, ", frontline = ", frontLineNeed, ", reserve = ", reserveNeed)
	end	
	
	-- Unmark the unit for equipment initialization
	UnitWithoutEquipment[unitKey] = nil
	
	-- Update unit's flag
	LuaEvents.UnitsCompositionUpdated(self:GetOwner(), self:GetID())
	
	-- Restore current damage	
	--self:SetDamage(currentDamage)
	
	Dlog("InitializeEquipment /END")
end

function IsWaitingForEquipment(self)
	local unitKey 	= self:GetKey()
	if UnitWithoutEquipment[unitKey] then
		return true
	else
		return false
	end
end

function DelayedEquipmentInitialization()

	--local DEBUG_UNIT_SCRIPT = true
	
	Dprint( DEBUG_UNIT_SCRIPT, "Starting Delayed Equipment Initialization...")
	Dprint( DEBUG_UNIT_SCRIPT, "coroutine.status = ", coroutine.status(initializeEquipmentCo))
	local count = 0
	while (true) do
		count = count + 1
		Dprint( DEBUG_UNIT_SCRIPT, "Checking units to equip - pass num#".. tostring(count))
		local totalNum 		= 0
		local equipedNum 	= 0
		for unitKey, timer in pairs(UnitWithoutEquipment) do
			totalNum = totalNum + 1
			if Automation.GetTime() >= timer + InitializeEquipmentPause then
				equipedNum = equipedNum + 1
				local unit = GetUnitFromKey ( unitKey )
				if unit then
					unit:InitializeEquipment()
				else
					UnitWithoutEquipment[unitKey] = nil -- If the unit doesn't exist anymore, unmark it for equipment initialization...
				end
			end
		end
		Dprint( DEBUG_UNIT_SCRIPT, "Equiped #"..tostring(equipedNum).." unit(s), on a total of #"..tostring(totalNum).." unit(s) waiting for equipment")	
		if totalNum == 0 then
			return
		end
		InitializeEquipmentTimer = Automation.GetTime()
		coroutine.yield()
	end
end

function StopDelayedEquipmentInitialization()
	--local DEBUG_UNIT_SCRIPT = true
	Dprint( DEBUG_UNIT_SCRIPT, "Stopping Delayed Equipment Initialization...")	
	Events.GameCoreEventPublishComplete.Remove( CheckEquipmentInitializationTimer )	
	initializeEquipmentCo = false
	SaveUnitTable() -- automated saving could occur before the end of the delayed equipment initialization, make sure to save the updated units table...
end

function CheckEquipmentInitializationTimer()
	--local DEBUG_UNIT_SCRIPT = true
	if not initializeEquipmentCo then
		print("- WARNING : CheckEquipmentInitializationTimer called but Initialize Equipment Coroutine = false")
		StopDelayedEquipmentInitialization()
	end
	if coroutine.status(initializeEquipmentCo)=="dead" then
		Dprint( DEBUG_UNIT_SCRIPT, "CheckEquipmentInitializationTimer : Initialize Equipment Coroutine = dead")		
		StopDelayedEquipmentInitialization()
		return
	end
	if Automation.GetTime() >= InitializeEquipmentTimer + InitializeEquipmentPause then
		InitializeEquipmentTimer = Automation.GetTime()
		coroutine.resume(initializeEquipmentCo)
	end
end

local barbarianUnits = {
	["ERA_ANCIENT"] 		= 
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_SPEARMAN", 		},
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HEAVY_CHARIOT", 	},
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_HEAVY_CHARIOT", 	},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_WARRIOR", 			AltType = "UNIT_SWORDSMAN", AltProbability = 30 },
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_GALLEY", 			},
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER", },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_GALLEY", 			},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_SLINGER", 			AltType = "UNIT_ARCHER", AltProbability = 40 },
			--["PROMOTION_CLASS_SIEGE"] 			= { },
			--["PROMOTION_CLASS_SUPPORT"] 		= { },
	
		} ,
	["ERA_CLASSICAL"] 		=
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_SPEARMAN", 		},
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		AltType = "UNIT_BARBARIAN_HORSE_ARCHER", AltProbability = 35 },
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_SWORDSMAN",		},
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_GALLEY", 			},
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER", },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_GALLEY", 			},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_ARCHER", 			},
			["PROMOTION_CLASS_SIEGE"] 			= { Type = "UNIT_CATAPULT", 		},
			["PROMOTION_CLASS_SUPPORT"] 		= { Type = "UNIT_BATTERING_RAM", 	},	
		} ,
	["ERA_MEDIEVAL"] 		=
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_SPEARMAN", 		AltType = "UNIT_PIKEMAN", AltProbability = 35 },
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		AltType = "UNIT_BARBARIAN_HORSE_ARCHER", AltProbability = 10 },
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_KNIGHT", 			},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_SWORDSMAN",		},
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_QUADRIREME", 		},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_CROSSBOWMAN", 		AltType = "UNIT_ARCHER", AltProbability = 35 },
			["PROMOTION_CLASS_SIEGE"] 			= { Type = "UNIT_CATAPULT", 		},
			["PROMOTION_CLASS_SUPPORT"] 		= { Type = "UNIT_SIEGE_TOWER", 		},
	
		} ,
	["ERA_RENAISSANCE"] 	=
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_PIKEMAN", 			AltType = "UNIT_MUSKETMAN", AltProbability = 35 },
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		AltType = "UNIT_BARBARIAN_HORSE_ARCHER", AltProbability = 10 },
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_KNIGHT", 			},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_SWORDSMAN",		},
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_QUADRIREME", 		},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_CROSSBOWMAN", 		AltType = "UNIT_ARCHER", AltProbability = 35 },
			["PROMOTION_CLASS_SIEGE"] 			= { Type = "UNIT_CATAPULT", 		},
			["PROMOTION_CLASS_SUPPORT"] 		= { Type = "UNIT_SIEGE_TOWER", 		},
	
		} ,
	["ERA_INDUSTRIAL"] 		=
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_SPEARMAN", 		AltType = "UNIT_PIKEMAN", AltProbability = 35 },
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		AltType = "UNIT_BARBARIAN_HORSE_ARCHER", AltProbability = 10 },
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_KNIGHT", 			},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_SWORDSMAN",		},
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_QUADRIREME", 		},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_CROSSBOWMAN", 		AltType = "UNIT_ARCHER", AltProbability = 35 },
			["PROMOTION_CLASS_SIEGE"] 			= { Type = "UNIT_CATAPULT", 		},
			["PROMOTION_CLASS_SUPPORT"] 		= { Type = "UNIT_SIEGE_TOWER", 		},
	
		} ,
	["ERA_MODERN"] 			=
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_SPEARMAN", 		AltType = "UNIT_PIKEMAN", AltProbability = 35 },
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		AltType = "UNIT_BARBARIAN_HORSE_ARCHER", AltProbability = 10 },
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_KNIGHT", 			},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_SWORDSMAN",		},
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_QUADRIREME", 		},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_CROSSBOWMAN", 		AltType = "UNIT_ARCHER", AltProbability = 35 },
			["PROMOTION_CLASS_SIEGE"] 			= { Type = "UNIT_CATAPULT", 		},
			["PROMOTION_CLASS_SUPPORT"] 		= { Type = "UNIT_SIEGE_TOWER", 		},
	
		} ,
	["ERA_ATOMIC"] 			=
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_SPEARMAN", 		AltType = "UNIT_PIKEMAN", AltProbability = 35 },
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		AltType = "UNIT_BARBARIAN_HORSE_ARCHER", AltProbability = 10 },
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_KNIGHT", 			},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_SWORDSMAN",		},
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_QUADRIREME", 		},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_CROSSBOWMAN", 		AltType = "UNIT_ARCHER", AltProbability = 35 },
			["PROMOTION_CLASS_SIEGE"] 			= { Type = "UNIT_CATAPULT", 		},
			["PROMOTION_CLASS_SUPPORT"] 		= { Type = "UNIT_SIEGE_TOWER", 		},
	
		} ,
	["ERA_INFORMATION"] 	=
		{
			["PROMOTION_CLASS_RECON"] 			= { Type = "UNIT_SCOUT", 			},
			["PROMOTION_CLASS_ANTI_CAVALRY"] 	= { Type = "UNIT_SPEARMAN", 		AltType = "UNIT_PIKEMAN", AltProbability = 35 },
			["PROMOTION_CLASS_LIGHT_CAVALRY"] 	= { Type = "UNIT_HORSEMAN", 		AltType = "UNIT_BARBARIAN_HORSE_ARCHER", AltProbability = 10 },
			["PROMOTION_CLASS_HEAVY_CAVALRY"] 	= { Type = "UNIT_KNIGHT", 			},
			["PROMOTION_CLASS_MELEE"] 			= { Type = "UNIT_SWORDSMAN",		},
			["PROMOTION_CLASS_NAVAL_MELEE"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RAIDER"] 	= { Type = "UNIT_BARBARIAN_RAIDER",	AltType = "UNIT_NORWEGIAN_LONGSHIP", AltProbability = 50 },
			["PROMOTION_CLASS_NAVAL_RANGED"] 	= { Type = "UNIT_QUADRIREME", 		},
			["PROMOTION_CLASS_RANGED"] 			= { Type = "UNIT_CROSSBOWMAN", 		AltType = "UNIT_ARCHER", AltProbability = 35 },
			["PROMOTION_CLASS_SIEGE"] 			= { Type = "UNIT_CATAPULT", 		},
			["PROMOTION_CLASS_SUPPORT"] 		= { Type = "UNIT_SIEGE_TOWER", 		},
	
		} ,
}

function CheckAndReplaceBarbarianUnit(unit)
	local DEBUG_UNIT_SCRIPT = true
	Dprint( DEBUG_UNIT_SCRIPT, "Check And Replace Barbarian Unit type...")
	
	local eraType			= GameInfo.Eras[GCO.GetGameEra()].EraType
	local unitTypeID		= unit:GetType()
	local promotionClass 	= GameInfo.Units[unitTypeID].PromotionClass
	local playerUnits		= Players[unit:GetOwner()]:GetUnits()
	
	Dprint( DEBUG_UNIT_SCRIPT, " - Era = ", eraType, ", Type = ", GameInfo.Units[unitTypeID].UnitType , ", PromotionClass = ", promotionClass )
	
	if barbarianUnits[eraType] and barbarianUnits[eraType][promotionClass] then
		local row = barbarianUnits[eraType][promotionClass]
		if row.AltType then
			local prob = Automation.GetRandomNumber(100)
			Dprint( DEBUG_UNIT_SCRIPT, " - AltType = ", row.AltType, ", Probability = ", row.AltProbability, ", rng = ", prob )
			if row.AltProbability and row.AltProbability > prob then
				local newTypeID = GameInfo.Units[row.AltType].Index
				if newTypeID ~= unitTypeID then
					Dprint( DEBUG_UNIT_SCRIPT, " - Replacing unit..." )
					local plotX = unit:GetX()
					local plotY = unit:GetY()
					playerUnits:Destroy(unit)
					return playerUnits:Create(newTypeID, plotX, plotY)
				else
					return unit
				end
			end
		end		
		local newTypeID = GameInfo.Units[row.Type].Index
		Dprint( DEBUG_UNIT_SCRIPT, " - Replacement Type = ", row.Type )
		if newTypeID ~= unitTypeID then
			Dprint( DEBUG_UNIT_SCRIPT, " - Replacing unit..." )
			local plotX = unit:GetX()
			local plotY = unit:GetY()
			playerUnits:Destroy(unit)
			return playerUnits:Create(newTypeID, plotX, plotY)
		end		
		return unit	-- did not found a replacement
	else -- class not allowed in this era
		playerUnits:Destroy(unit)
		return nil
	end
end

-----------------------------------------------------------------------------------------
-- Units functions
-----------------------------------------------------------------------------------------
function IsInitialized(self)
	local unitKey 	= self:GetKey()
	if ExposedMembers.UnitData[unitKey] then return true end
end

function GetUnitKeyFromIDs(ownerID, unitID) -- local
	return unitID..","..ownerID
end

-- return unique key for units table [unitID,playerID]
function GetKey(self)
	local ownerID = self:GetOwner()
	local unitID = self:GetID()
	local unitKey = GetUnitKeyFromIDs(ownerID, unitID)
	return unitKey
end

function GetUnitFromKey ( unitKey )
	if ExposedMembers.UnitData[unitKey] then
		local unit = GetUnit(ExposedMembers.UnitData[unitKey].playerID, ExposedMembers.UnitData[unitKey].unitID)
		if unit then
			return unit
		else
			print ("- WARNING: unit is nil for GetUnitFromKey(".. tostring(unitKey).."), unit type = ".. tostring(GameInfo.Units[ExposedMembers.UnitData[unitKey].unitType].UnitType) )
			--ExposedMembers.UnitData[unitKey].Alive = false
		end
	else
		print ("- WARNING: ExposedMembers.UnitData[unitKey] is nil for GetUnitFromKey(".. tostring(unitKey)..")")
	end
end


-----------------------------------------------------------------------------------------
-- Resources functions
-----------------------------------------------------------------------------------------

-- unitType functions
function GetBasePersonnelReserve(unitType)
	return 0 --GCO.Round(GameInfo.Units[unitType].Personnel * reserveRatio / 10) * 10
end

--[[
function GetBaseEquipmentReserve(unitType)
	return GCO.Round((GameInfo.Units[unitType].Equipment * reserveRatio / 10) * 10)
end

function GetEquipmentName(unitType) -- also accept index and hash
	local equipmentID = unitEquipment[unitType]
	if equipmentID then return Locale.Lookup(GameInfo.Resources[equipmentID].Name) end
	return "unknown"
end

function GetEquipmentID(unitType) -- also accept index and hash
	return unitEquipment[unitType]
end
--]]

function GetBaseHorsesReserve(unitType)
	return 0 --GCO.Round(GameInfo.Units[unitType].Horses * reserveRatio / 10) * 10
end

function GetBaseMaterielReserve(unitType)
	return 0 --GameInfo.Units[unitType].Materiel -- 100% stock for materiel reserve
end

function GetUnitConstructionResources(unitType)

	local resTable = {}

	local personnel = GameInfo.Units[unitType].Personnel 	--+ GCO.GetBasePersonnelReserve(unitType)
	--local equipment = GameInfo.Units[unitType].Equipment 	+ GCO.GetBaseEquipmentReserve(unitType)
	local horses 	= GameInfo.Units[unitType].Horses 		--+ GCO.GetBaseHorsesReserve(unitType)	
	local materiel 	= GameInfo.Units[unitType].Materiel 	--+ GCO.GetBaseMaterielReserve(unitType)	
	
	--[[
	local equipmentResourceID 	= GCO.GetEquipmentID(unitType)
	if not equipmentResourceID then
		materiel = materiel + equipment
		equipment = 0
	end
	--]]
	
	
	if personnel 	> 0 then resTable[personnelResourceID]	= personnel end
	--if equipment 	> 0 then resTable[equipmentResourceID]	= equipment end
	if horses 		> 0 then resTable[horsesResourceID]		= horses	end
	if materiel 	> 0 then resTable[materielResourceID]	= materiel end
	
	return resTable

end

function GetUnitConstructionOrResources(unitType)
	return GetUnitConstructionEquipment(unitType, "REQUIRED")
end

function GetUnitConstructionOptionalResources(unitType)
	return GetUnitConstructionEquipment(unitType, "OPTIONAL")
end

-- Unit functions
function GetMaxFrontLinePersonnel(self)
	return GameInfo.Units[self:GetType()].Personnel
end

function GetMaxFrontLineMateriel(self)
	return GameInfo.Units[self:GetType()].Materiel
end

function GetMaxPersonnelReserve(self)
	--return GCO.Round((GameInfo.Units[self:GetType()].Personnel * reserveRatio / 10) * 10)
	local neededForHealing = self:GetMaxFrontLinePersonnel() - self:GetComponent("Personnel")	
	return neededForHealing
end

--[[
function GetMaxEquipmentReserve(self)
	return GCO.Round((GameInfo.Units[self:GetType()].Equipment * reserveRatio / 10) * 10)
end
--]]

function GetMaxHorsesReserve(self)
	return GCO.Round((GameInfo.Units[self:GetType()].Horses * reserveRatio / 10) * 10)
end

function GetMaxMaterielReserve(self)
	return GameInfo.Units[self:GetType()].Materiel -- 100% stock for materiel reserve
end

function GetBaseFoodStock(self)
	local unitKey = self:GetKey()
	local unitData = ExposedMembers.UnitData[unitKey] or {}
	return unitData.BaseFoodStock or 0
end

function GetMaxFoodStock(self)
	return GetBaseFoodStock(self)
end

function GetMaxMedicineStock(self)
	if GameInfo.Units[self:GetType()].Combat > 0 then
		return GCO.Round(GetMaxPersonnelReserve(self)/10)
	else		
		return 0
	end
end

function GetFoodConsumptionRatio(self)
	local unitKey = self:GetKey()
	local unitData = ExposedMembers.UnitData[unitKey]
	local ratio = 1
	local baseFoodStock = self:GetBaseFoodStock()
	if unitData.FoodStock < (baseFoodStock * heavyRationing) then
		ratio = heavyRationing
	elseif unitData.FoodStock < (baseFoodStock * mediumRationing) then
		ratio = mediumRationing
	elseif unitData.FoodStock < (baseFoodStock * lightRationing) then
		ratio = lightRationing
	end
	return ratio
end

function GetFoodConsumption(self)
	local unitKey = self:GetKey()
	local unitData = ExposedMembers.UnitData[unitKey]
	local foodConsumption1000 = 0
	local ratio = self:GetFoodConsumptionRatio()
	foodConsumption1000 = foodConsumption1000 + ((unitData.Personnel + unitData.PersonnelReserve) * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_PERSONNEL_FACTOR"].Value) * ratio)
	foodConsumption1000 = foodConsumption1000 + ((unitData.Horses + unitData.HorsesReserve) * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_HORSES_FACTOR"].Value) * ratio)
	-- value belows may be nil
	if unitData.WoundedPersonnel then
		foodConsumption1000 = foodConsumption1000 + (unitData.WoundedPersonnel * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_WOUNDED_FACTOR"].Value) * ratio )
	end
	if unitData.Prisoners then	
		foodConsumption1000 = foodConsumption1000 + (GCO.GetTotalPrisoners(unitData) * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_PRISONERS_FACTOR"].Value) * ratio )
	end	
	return math.max(1, GCO.ToDecimals( foodConsumption1000 / 1000 ))
end

function GetUnitTypeFoodConsumption(unitData) -- local
	local foodConsumption1000 = 0
	foodConsumption1000 = foodConsumption1000 + ((unitData.Personnel + unitData.PersonnelReserve) * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_PERSONNEL_FACTOR"].Value))
	foodConsumption1000 = foodConsumption1000 + ((unitData.Horses + unitData.HorsesReserve) * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_HORSES_FACTOR"].Value))
	return math.max(1, GCO.Round( foodConsumption1000 / 1000 ))
end

function SetBaseFoodStock(unitType) -- local
	local unitData = {}
	unitData.unitType 			= unitType
	unitData.Personnel 			= GameInfo.Units[unitType].Personnel
	unitData.Horses 			= GameInfo.Units[unitType].Horses
	unitData.PersonnelReserve	= GetBasePersonnelReserve(unitType)
	unitData.HorsesReserve 		= GetBaseHorsesReserve(unitType)
	return GetUnitTypeFoodConsumption(unitData)*5 -- set enough stock for 5 turns
end

function GetFuelConsumptionRatio(unitData) -- local
	local ratio = 1
	local lightRationing 	= tonumber(GameInfo.GlobalParameters["FUEL_RATIONING_LIGHT_RATIO"].Value)
	local mediumRationing 	= tonumber(GameInfo.GlobalParameters["FUEL_RATIONING_MEDIUM_RATIO"].Value)
	local heavyRationing 	= tonumber(GameInfo.GlobalParameters["FUEL_RATIONING_HEAVY_RATIO"].Value)
	local baseFuelStock = GetBaseFuelStock(unitData.unitType)
	if unitData.FuelStock < (baseFuelStock * heavyRationing) then
		ratio = tonumber(GameInfo.GlobalParameters["FUEL_CONSUMPTION_HEAVY_RATIO"].Value)
	elseif unitData.FuelStock < (baseFuelStock * mediumRationing) then
		ratio = tonumber(GameInfo.GlobalParameters["FUEL_CONSUMPTION_MEDIUM_RATIO"].Value)
	elseif unitData.FuelStock < (baseFuelStock * lightRationing) then
		ratio = tonumber(GameInfo.GlobalParameters["FUEL_CONSUMPTION_LIGHT_RATIO"].Value)
	end
	return ratio
end

function GetFuelConsumption(self)
	local unitKey = self:GetKey()
	local unitData = ExposedMembers.UnitData[unitKey]
	--[[
	if (not unitData.Equipment) or (unitData.Equipment == 0) then
		return 0
	end
	--]]
	local fuelConsumption1000 = 0
	if not unitData.FuelConsumptionPerVehicle then unitData.FuelConsumptionPerVehicle = GameInfo.Units[unitData.unitType].FuelConsumptionPerVehicle end
	if unitData.FuelConsumptionPerVehicle == 0 then return 0 end
	
	local ratio = GetFuelConsumptionRatio(unitData)
	
	fuelConsumption1000 = fuelConsumption1000 + GetBaseFuelConsumption1000(unitData) * ratio
	
	--[[
	if unitData.DamagedEquipment then	
		fuelConsumption1000 = fuelConsumption1000 + (unitData.DamagedEquipment * unitData.FuelConsumptionPerVehicle * tonumber(GameInfo.GlobalParameters["FUEL_CONSUMPTION_DAMAGED_FACTOR"].Value) * ratio )
	end
	--]]
	return math.max(1, GCO.Round( fuelConsumption1000 / 1000))
end

function GetBaseFuelConsumption1000(unitData) -- local
	return 0 --unitData.Equipment * unitData.FuelConsumptionPerVehicle * tonumber(GameInfo.GlobalParameters["FUEL_CONSUMPTION_ACTIVE_FACTOR"].Value)
end

function GetBaseFuelConsumption(unitData) -- local
	return 0 --math.max(1, GCO.Round( GetBaseFuelConsumption1000(unitData) / 1000))
end

function GetBaseFuelStock(unitType) -- local
	return  0
	--[[
	local unitData = {}
	unitData.unitType 					= unitType
	unitData.Equipment 					= GameInfo.Units[unitType].Equipment
	unitData.FuelConsumptionPerVehicle 	= GameInfo.Units[unitType].FuelConsumptionPerVehicle	
	if unitData.Equipment > 0 and unitData.FuelConsumptionPerVehicle > 0 then
		return GetBaseFuelConsumption(unitData) * 5 -- set enough stock for 5 turns
	end
	return 0
	--]]
end

function GetMaxTransferTable(self)
	local maxTranfert = {}
	local unitType = self:GetType()
	local unitInfo = GameInfo.Units[unitType]
	maxTranfert.Personnel 	= GCO.Round(GetMaxFrontLinePersonnel(self)*GameInfo.GlobalParameters["UNIT_MAX_PERSONNEL_PERCENT_FROM_RESERVE"].Value/100)
	maxTranfert.Materiel 	= GCO.Round(GetMaxFrontLineMateriel(self)*GameInfo.GlobalParameters["UNIT_MAX_MATERIEL_PERCENT_FROM_RESERVE"].Value/100)
	return maxTranfert
end

function ChangeStock(self, resourceID, value) -- "stock" means "reserve" or "rear" for units
	local resourceKey = tostring(resourceID)
	local unitKey = self:GetKey()
	local unitData = ExposedMembers.UnitData[unitKey]
	
	if not unitData then
		print("WARNING, unitData[unitKey] is nil in ChangeStock() for " .. self:GetName(), unitKey)
		return
	end
	
	if resourceKey == personnelResourceKey then
		unitData.PersonnelReserve = math.max(0, unitData.PersonnelReserve + value)
		
	--elseif resourceKey == materielResourceKey then
	--	unitData.MaterielReserve = math.max(0, unitData.MaterielReserve + value)
		
	--elseif resourceKey == horsesResourceKey then
	--	unitData.HorsesReserve = math.max(0, unitData.HorsesReserve + value)
		
	elseif resourceKey == foodResourceKey then
		unitData.FoodStock = math.max(0, GCO.ToDecimals(unitData.FoodStock + value))
		
	elseif resourceKey == medicineResourceKey then
		unitData.MedicineStock = math.max(0, unitData.MedicineStock + value)
	
	elseif self:IsEquipment(resourceID) then
		self:ChangeReserveEquipment( resourceID, value )
		
	else
		unitData.Stock[resourceKey] = math.max(0, GCO.ToDecimals((unitData.Stock[resourceKey] or 0) + value))
	end
end

function GetStock(self, resourceID) -- "stock" means "reserve" or "rear" for units
	local resourceKey = tostring(resourceID)
	local unitKey = self:GetKey()
	local unitData = ExposedMembers.UnitData[unitKey]
	
	if not unitData then
		print("WARNING, unitData[unitKey] is nil in GetStock() for " .. self:GetName(), unitKey)
		return 0
	end
	
	if resourceKey == personnelResourceKey then
		return unitData.PersonnelReserve or 0
		
	elseif resourceKey == materielResourceKey then
		return unitData.MaterielReserve or 0
		
	elseif resourceKey == horsesResourceKey then
		return unitData.HorsesReserve or 0
		
	elseif resourceKey == foodResourceKey then
		return unitData.FoodStock or 0
		
	else
		return unitData.Stock[resourceKey] or 0
	end
end

function GetAllExcedent(self) -- Return all resources that can be transfered back to a city (or a nearby unit/improvement ?)

	--local DEBUG_UNIT_SCRIPT = true
	Dprint( DEBUG_UNIT_SCRIPT, "- check excedent for : ".. Locale.Lookup(self:GetName()))
	
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	local excedent	= {}
	
	if not unitData then
		print("WARNING, unitData[unitKey] is nil in GetAllExcedent() for " .. self:GetName(), unitKey)
		return excedent
	end
	
	-- get excedent from reserve
	excedent[personnelResourceID]	= math.max(0, self:GetStock(personnelResourceKey) - self:GetMaxPersonnelReserve())
	excedent[materielResourceID]	= math.max(0, self:GetStock(materielResourceKey) - self:GetMaxMaterielReserve())
	excedent[horsesResourceID]		= math.max(0, self:GetStock(horsesResourceKey) - self:GetMaxHorsesReserve())
	excedent[foodResourceID]		= math.max(0, self:GetStock(foodResourceKey) - self:GetMaxFoodStock())

	-- all resource in "stock" (ie not "reserve") can be send to city
	for resourceKey, value in pairs(unitData.Stock) do
		excedent[tonumber(resourceKey)]	= math.max(0, value)
	end

	-- get excedent from equipment in reserve
	local equipmentClasses = self:GetEquipmentClasses()
	for classType, classData in pairs(equipmentClasses) do
		local classExcedent 	= math.max(0, self:GetEquipmentClassReserve(classType) - self:GetMaxEquipmentReserve(classType))
		Dprint( DEBUG_UNIT_SCRIPT, "   - check excedent for equipment class : ".. Locale.Lookup(GameInfo.EquipmentClasses[classType].Name), " = ", classExcedent)
		if classExcedent > 0 then
			local equipmentTypes 	= GetEquipmentTypes(classType)
			local bestNum 			= 0
			for i = #equipmentTypes, 1, -1 do -- iterate from least to most wanted equipment			
				local equipmentID = equipmentTypes[i].EquipmentID
				local num = self:GetReserveEquipment(equipmentID, classType)				
				
				-- we want the least wanted available, and we increment the number of least wanted equipment already set as excedent for the next loop...
				bestNum = bestNum + num
				excedent[equipmentID] = math.min(bestNum, classExcedent )
				Dprint( DEBUG_UNIT_SCRIPT, "   - equipment = ".. Locale.Lookup(GameInfo.Resources[equipmentID].Name), ", equipmentID = ", equipmentID, ", num = ", num, ", class excedent left = ", classExcedent, ", total equipment checked = ", bestNum, ", excedent removed = ", excedent[equipmentID])
				classExcedent = math.max(0, classExcedent - excedent[equipmentID])
			end
		end
	end

	return excedent
	
end

function GetNumResourceNeeded(self, resourceID)
	local resourceKey 	= tostring(resourceID)
	local unitKey 		= self:GetKey()
	local unitData 		= ExposedMembers.UnitData[unitKey]
	local unitType 		= self:GetType()
	local equipmentNeed = self:GetEquipmentReserveNeed()
	
	if resourceKey == personnelResourceKey then
		return math.max(0, self:GetMaxPersonnelReserve() - unitData.PersonnelReserve)
		
	elseif resourceKey == materielResourceKey then
		return math.max(0, self:GetMaxMaterielReserve() - unitData.MaterielReserve)
		
	elseif resourceKey == horsesResourceKey then
		return math.max(0, self:GetMaxHorsesReserve() - unitData.HorsesReserve)
		
	elseif resourceKey == foodResourceKey then
		return math.max(0, self:GetMaxFoodStock() - unitData.FoodStock)
		
	elseif resourceKey == medicineResourceKey then
		return math.max(0, self:GetMaxMedicineStock() - unitData.MedicineStock)
		
	--elseif unitEquipment[unitType] and unitEquipment[unitType] == resourceID then
	--	return math.max(0, self:GetMaxEquipmentReserve() - unitData.EquipmentReserve)
	
	elseif GCO.IsResourceEquipment(resourceID) and equipmentNeed[resourceID] then
		return math.max(0, equipmentNeed[resourceID])
		
	end
	
	return 0
end

function GetRequirements(self)

	--local DEBUG_UNIT_SCRIPT = true
	
	local unitKey 			= self:GetKey()
	local unitData 			= ExposedMembers.UnitData[unitKey]
	if not unitData then
		print("WARNING, unitData[unitKey] is nil in GetRequirements() for " .. self:GetName(), unitKey)
		local requirements 		= {}
		requirements.Resources 	= {}
		return requirements
	end
	local unitType 			= self:GetType()
	local listResources		= {personnelResourceID, horsesResourceID, materielResourceID, foodResourceID, medicineResourceID}
	local listEquipment		= self:GetEquipmentReserveNeed()
	local requirements 		= {}
	requirements.Resources 	= {}
	
	Dprint( DEBUG_UNIT_SCRIPT, "Get Requirements for unit ".. tostring(unitKey), Locale.Lookup(UnitManager.GetTypeName(self)) )
	
	for _, resourceID in ipairs(listResources) do
		requirements.Resources[resourceID] = self:GetNumResourceNeeded(resourceID)
		Dprint( DEBUG_UNIT_SCRIPT, " - ".. Locale.Lookup(GameInfo.Resources[resourceID].Name).." = ".. tostring(requirements.Resources[resourceID]))
	end
	for equipmentID, value in pairs(listEquipment) do
		requirements.Resources[equipmentID] = value
		Dprint( DEBUG_UNIT_SCRIPT, " - ".. Locale.Lookup(GameInfo.Resources[equipmentID].Name).." = ".. tostring(value))
	end

	return requirements
end

function GetComponent(self, component)
	local unitKey = self:GetKey()
	if not ExposedMembers.UnitData[unitKey] then
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil for " .. self:GetName(), unitKey)
		return 0
	end
	return ExposedMembers.UnitData[unitKey][component]
end

function SetComponent(self, component, value)
	local unitKey = self:GetKey()
	ExposedMembers.UnitData[unitKey][component] = math.max(0,GCO.ToDecimals(value))
end

function ChangeComponent(self, component, value)
	local unitKey = self:GetKey()
	ExposedMembers.UnitData[unitKey][component] = math.max(0, GCO.ToDecimals(ExposedMembers.UnitData[unitKey][component] + value))
end

function GetComponentVariation(self, component)
	local unitKey = self:GetKey()
	local previousComponent = "Previous"..tostring(component)
	return GCO.ToDecimals(ExposedMembers.UnitData[unitKey][component] - ExposedMembers.UnitData[unitKey][previousComponent])
end


-----------------------------------------------------------------------------------------
-- Equipment functions 
-----------------------------------------------------------------------------------------

-- Types functions
function IsEquipmentClass(equipmentType, equipmentClass)
	return equipmentIsClass[equipmentType] and equipmentIsClass[equipmentType][equipmentClass]
end

function IsUnitEquipment(unitTypeID, equipmentTypeID)
	if equipmentUnitTypes[equipmentTypeID] and equipmentUnitTypes[equipmentTypeID][unitTypeID] then
		return true
	end
	return false
end

function GetEquipmentTypes(equipmentClass)
	return equipmentTypeClasses[tonumber(equipmentClass)] or {}
end

function GetUnitEquipmentClass(unitTypeID, equipmentTypeID)
	if equipmentUnitTypes[equipmentTypeID] then
		return equipmentUnitTypes[equipmentTypeID][unitTypeID] -- classTypeID
	end
end

function GetLowerEquipmentType(classType)
	local equipmentTypes 	= GetEquipmentTypes(classType)
	--table.sort(equipmentTypes, function(a, b) return a.Desirability < b.Desirability; end)	
	return equipmentTypes[#equipmentTypes].EquipmentID
end

function GetUnitEquipmentClasses(unitTypeID)
	return unitEquipmentClasses[unitTypeID] or {}
end

function GetUnitConstructionEquipment(unitType, sCondition)

	local resTable = {}
	
	local bAll 				= (sCondition == "ALL" or sCondition == nil)
	local bRequiredOnly 	= (sCondition == "REQUIRED")
	local bOptionalOnly 	= (sCondition == "OPTIONAL")

	local equipmentClasses = GetUnitEquipmentClasses(unitType)
	
	if equipmentClasses then
		for classType, classData in pairs(equipmentClasses) do
			if bAll or (bRequiredOnly and classData.IsRequired) or (bOptionalOnly and not classData.IsRequired) then
				resTable[classType]				= {}
				resTable[classType].Resources	= {}
				resTable[classType].Value 		= classData.Amount --+ GCO.Round(classData.Amount * reserveRatio / 10) * 10
				local equipmentTypes 			= GetEquipmentTypes(classType)
				
				for _, data in ipairs(equipmentTypes) do
					table.insert(resTable[classType].Resources, data.EquipmentID)
				end
			end
		end
	end
	return resTable

end

function GetUnitTypeFromEquipmentList(promotionClass, equipmentList)

end

-- Unit functions
function IsEquipment(self, equipmentTypeID) 				-- to check if equipmentTypeID is used by this unit
	return IsUnitEquipment(self:GetType(), equipmentTypeID)
end

function GetEquipmentClasses(self)							-- get all equipment classes of this unit
	return unitEquipmentClasses[self:GetType()] or {}
end

function GetRequiredEquipmentClasses(self)					-- get equipment classes required by this unit
	local requiredClasses 	= {}
	local allClasses 		= unitEquipmentClasses[self:GetType()]	
	if not allClasses then
		return {}
	end	
	for classType, data in pairs(allClasses) do
		if data.IsRequired then
			requiredClasses[classType] = data
		end
	end
	return requiredClasses
end

function IsRequiringEquipmentClass(self, equipmentClassID)	-- return true if that equipment class is required by this unit
	local unitType = self:GetType()
	return unitEquipmentClasses[unitType] and unitEquipmentClasses[unitType][equipmentClassID] and unitEquipmentClasses[unitType][equipmentClassID].IsRequired
end

function GetEquipmentClass(self, equipmentTypeID)			-- return the class of an equipment type used by this unit
	return GetUnitEquipmentClass(self:GetType(), equipmentTypeID)
end

function GetMaxEquipmentFrontLine(self, equipmentClass)		-- get max equipment in frontline for that class
	if unitEquipmentClasses[self:GetType()] then
		-- handle ID, key
		local row = unitEquipmentClasses[self:GetType()][tonumber(equipmentClass)] 
		if row then
			return row.Amount or 0
		end
	end
	return 0
end

function GetMaxEquipmentReserve(self, equipmentClass)		-- get max equipment in reserve for that class
	--return GCO.Round(self:GetMaxEquipmentFrontLine(equipmentClass) * reserveRatio / 10) * 10
	local neededForHealing = self:GetMaxEquipmentFrontLine(equipmentClass) - self:GetEquipmentClassFrontLine(equipmentClass)
	--print("neededForHealing = GetMaxEquipmentFrontLine - GetEquipmentClassFrontLine ", self:GetMaxEquipmentFrontLine(equipmentClass), self:GetEquipmentClassFrontLine(equipmentClass), equipmentClass)
	return neededForHealing
end

function GetEquipmentClassFrontLine(self, equipmentClass)	-- get current number of equipment of that class in frontline
	local unitKey = self:GetKey()
	if not ExposedMembers.UnitData[unitKey] then
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil for " .. self:GetName(), unitKey)
		return 0
	end
	local equipmentClassKey = tostring(equipmentClass)
	local equipment = ExposedMembers.UnitData[unitKey].Equipment[equipmentClassKey]
	if equipment then
		return GCO.TableSummation(equipment)
	else
		return 0
	end
end

function GetEquipmentClassReserve(self, equipmentClass)		-- get current number of equipment of that class in reserve
	local unitKey = self:GetKey()
	if not ExposedMembers.UnitData[unitKey] then
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil for " .. self:GetName(), unitKey)
		return 0
	end
	local equipmentClassKey = tostring(equipmentClass)
	local equipment = ExposedMembers.UnitData[unitKey].EquipmentReserve[equipmentClassKey]
	if equipment then 
		return GCO.TableSummation(equipment)
	else
		return 0
	end
end

function GetEquipmentClassReserveNeed(self, equipmentClass)	-- get number of equipment of that class needed in reserve
	local need 	= self:GetMaxEquipmentReserve(equipmentClass)
	local stock	= self:GetEquipmentClassReserve(equipmentClass)
	--print("GetEquipmentClassReserveNeed -> need, stock, equipmentClass = ", need, stock, equipmentClass)
	if stock < need then
		return need - stock
	else
		return 0
	end
end

function GetEquipmentClassFrontLineNeed(self, equipmentClass) -- get number of equipment of that class needed in frontline
	local hp 	= self:GetHP() --self:GetMaxDamage() - self:GetDamage() -- use virtual HP here ?
	local need 	= UnitHitPointsTable[self:GetType()][hp].EquipmentClass[equipmentClass] --self:GetMaxEquipmentFrontLine(equipmentClass)
	local stock	= self:GetEquipmentClassFrontLine(equipmentClass)
	if stock < need then
		return need - stock
	else
		return 0
	end
end

function GetFrontLineEquipment(self, equipmentType, classType) -- get current number of this equipment type in frontline (classType optional)
	local unitKey = self:GetKey()
	if not ExposedMembers.UnitData[unitKey] then
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil for " .. self:GetName(), unitKey)
		return 0
	end
	local equipmentClass	= classType or self:GetEquipmentClass(equipmentType)
	local equipmentClassKey = tostring(equipmentClass)
	local equipmentTypeKey 	= tostring(equipmentType)
	if ExposedMembers.UnitData[unitKey].Equipment[equipmentClassKey] then
		return ExposedMembers.UnitData[unitKey].Equipment[equipmentClassKey][equipmentTypeKey] or 0
	end
	return 0
end

function GetReserveEquipment(self, equipmentType, classType) -- get current number of this equipment type in reserve (classType optional)
	local unitKey = self:GetKey()
	if not ExposedMembers.UnitData[unitKey] then
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil for " .. self:GetName(), unitKey)
		return 0
	end
	local equipmentClass	= classType or self:GetEquipmentClass(equipmentType)
	local equipmentClassKey = tostring(equipmentClass)
	local equipmentTypeKey 	= tostring(equipmentType)
	if ExposedMembers.UnitData[unitKey].EquipmentReserve[equipmentClassKey] then
		return ExposedMembers.UnitData[unitKey].EquipmentReserve[equipmentClassKey][equipmentTypeKey] or 0
	end
	return 0
end

function GetEquipmentReserveNeed(self)						-- return a table with all equipment types needed in reserve { [equipmentID] = num }
	local equipmentNeed = {}
	local equipmentClasses = self:GetEquipmentClasses()
	for classType, classData in pairs(equipmentClasses) do
		local equipmentTypes 	= GetEquipmentTypes(classType)
		local maxReserve		= self:GetMaxEquipmentReserve(classType)
		local bestNum 			= 0
		--table.sort(equipmentTypes, function(a, b) return a.Desirability > b.Desirability; end)
		if equipmentTypes then
			for _, data in ipairs(equipmentTypes) do
				local equipmentID = data.EquipmentID
				local num = self:GetReserveEquipment(equipmentID, classType)
				-- we want the best available, and we increment the number of better equipment already in frontline for the next loop...
				bestNum = bestNum + num
				equipmentNeed[equipmentID] = math.max(0, maxReserve - bestNum)
			end
		end
	end
	return equipmentNeed
end

function GetEquipmentFrontLineNeed(self)					-- return a table with all equipment types needed in frontline { [equipmentID] = num }
	local equipmentNeed = {}
	local equipmentClasses = self:GetEquipmentClasses()
	for classType, classData in pairs(equipmentClasses) do
		local equipmentTypes 	= GetEquipmentTypes(classType)
		local maxFrontLine		= self:GetMaxEquipmentFrontLine(classType)
		local bestNum 			= 0
		--table.sort(equipmentTypes, function(a, b) return a.Desirability > b.Desirability; end)
		if equipmentTypes then
			for _, data in ipairs(equipmentTypes) do
				local equipmentID = data.EquipmentID
				local num = self:GetFrontLineEquipment(equipmentID, classType)
				-- we want the best available, and we increment the number of better equipment already in frontline for the next loop...
				bestNum = bestNum + num
				equipmentNeed[equipmentID] = math.max(0, maxFrontLine - bestNum)
			end
		end
	end
	return equipmentNeed
end

function ChangeReserveEquipment(self, equipmentID, value, classType)  -- change number of this equipment type in reserve by value (classType optional)
	local unitKey = self:GetKey()
	if not ExposedMembers.UnitData[unitKey] then
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil for " .. self:GetName(), unitKey)
		return 0
	end
	local equipmentClass	= classType or self:GetEquipmentClass(equipmentID)
	local equipmentClassKey = tostring(equipmentClass)
	local equipmentTypeKey 	= tostring(equipmentID)
	if not ExposedMembers.UnitData[unitKey].EquipmentReserve[equipmentClassKey] then
		ExposedMembers.UnitData[unitKey].EquipmentReserve[equipmentClassKey] = { [equipmentTypeKey] = math.max(0, value)}
	else
		ExposedMembers.UnitData[unitKey].EquipmentReserve[equipmentClassKey][equipmentTypeKey] = math.max(0, (ExposedMembers.UnitData[unitKey].EquipmentReserve[equipmentClassKey][equipmentTypeKey] or 0) + value)
	end
end

function ChangeFrontLineEquipment(self, equipmentID, value, classType)  -- change number of this equipment type in frontline by value (classType optional)
	local unitKey = self:GetKey()
	if not ExposedMembers.UnitData[unitKey] then
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil for " .. self:GetName(), unitKey)
		return 0
	end
	local equipmentClass	= classType or self:GetEquipmentClass(equipmentID)
	local equipmentClassKey = tostring(equipmentClass)
	local equipmentTypeKey 	= tostring(equipmentID)
	if not ExposedMembers.UnitData[unitKey].Equipment[equipmentClassKey] then
		ExposedMembers.UnitData[unitKey].Equipment[equipmentClassKey] = { [equipmentTypeKey] = math.max(0, value)}
	else
		ExposedMembers.UnitData[unitKey].Equipment[equipmentClassKey][equipmentTypeKey] = math.max(0, (ExposedMembers.UnitData[unitKey].Equipment[equipmentClassKey][equipmentTypeKey] or 0) + value)
	end
end


----------------------------------------------
-- Morale function
----------------------------------------------

function GetMoraleFromFood(self)
	local unitKey 			= self:GetKey()
	local unitData 			= ExposedMembers.UnitData[unitKey]
	local moralefromFood 	= tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_WELL_FED"].Value)
	local lightRationing 	= tonumber(GameInfo.GlobalParameters["FOOD_RATIONING_LIGHT_RATIO"].Value)
	local mediumRationing 	= tonumber(GameInfo.GlobalParameters["FOOD_RATIONING_MEDIUM_RATIO"].Value)
	local heavyRationing 	= tonumber(GameInfo.GlobalParameters["FOOD_RATIONING_HEAVY_RATIO"].Value)
	local baseFoodStock 	= self:GetBaseFoodStock()
	
	if unitData.FoodStock < (baseFoodStock * heavyRationing) then
		moralefromFood = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_FOOD_RATIONING_HEAVY"].Value)
	elseif unitData.FoodStock < (baseFoodStock * mediumRationing) then
		moralefromFood = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_FOOD_RATIONING_MEDIUM"].Value)
	elseif unitData.FoodStock < (baseFoodStock * lightRationing) then
		moralefromFood = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_FOOD_RATIONING_LIGHT"].Value)
	end
	return moralefromFood	
end

function GetMoraleFromLastCombat(self)
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	if (Game.GetCurrentGameTurn() - unitData.LastCombatTurn) > tonumber(GameInfo.GlobalParameters["MORALE_COMBAT_EFFECT_NUM_TURNS"].Value) then
		return 0
	end
	local moraleFromCombat = 0
	if unitData.LastCombatResult > tonumber(GameInfo.GlobalParameters["COMBAT_HEAVY_DIFFERENCE_VALUE"].Value) then
		moraleFromCombat = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_COMBAT_LARGE_VICTORY"].Value)
	elseif unitData.LastCombatResult > 0 then
		moraleFromCombat = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_COMBAT_VICTORY"].Value)	
	elseif unitData.LastCombatResult < 0 then
		moraleFromCombat = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_COMBAT_DEFEAT"].Value)	
	elseif unitData.LastCombatResult < - tonumber(GameInfo.GlobalParameters["COMBAT_HEAVY_DIFFERENCE_VALUE"].Value) then
		moraleFromCombat = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_COMBAT_LARGE_DEFEAT"].Value)	
	end
	
	if unitData.LastCombatType ~= CombatTypes.MELEE then
		moraleFromCombat = GCO.Round(moraleFromCombat * tonumber(GameInfo.GlobalParameters["MORALE_COMBAT_NON_MELEE_RATIO"].Value))
	end

	return moraleFromCombat	
end

function GetMoraleFromWounded(self)
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	local moraleFromWounded = 0
	if unitData.WoundedPersonnel > ( (unitData.Personnel + unitData.PersonnelReserve) * tonumber(GameInfo.GlobalParameters["MORALE_WOUNDED_HIGH_PERCENT"].Value) / 100) then
		moraleFromWounded = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_WOUNDED_HIGH"].Value)
	elseif unitData.WoundedPersonnel > ( (unitData.Personnel + unitData.PersonnelReserve) * tonumber(GameInfo.GlobalParameters["MORALE_WOUNDED_LOW_PERCENT"].Value) / 100) then 
		moraleFromWounded = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_WOUNDED_LOW"].Value)	
	end
	return moraleFromWounded	
end

function GetMoraleFromHP(self)
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	local moraleFromHP = 0
	local unit = UnitManager.GetUnit(unitData.playerID, unitData.unitID)
	if unit then
		local HP = unit:GetMaxDamage() - unit:GetDamage()		
		if HP == maxHP then
			moraleFromHP = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_HP_FULL"].Value)
		else
			local percentHP = (HP / maxHP * 100)
			if  percentHP < tonumber(GameInfo.GlobalParameters["MORALE_HP_VERY_LOW_PERCENT"].Value) then
				moraleFromHP = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_HP_VERY_LOW"].Value)
			elseif  percentHP < tonumber(GameInfo.GlobalParameters["MORALE_HP_LOW_PERCENT"].Value) then
				moraleFromHP = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_HP_LOW"].Value)
			end
		end
	end
	return moraleFromHP
end

function GetMoraleFromHome(self)
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	local moraleFromHome = 0
	if unitData.SupplyLineCityKey then
		local supplyEfficiency = unitData.SupplyLineEfficiency
		if supplyEfficiency >= tonumber(GameInfo.GlobalParameters["MORALE_CLOSE_TO_HOME_EFFICIENCY_VALUE"].Value) then
			moraleFromHome = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_CLOSE_TO_HOME"].Value)
		elseif supplyEfficiency >= tonumber(GameInfo.GlobalParameters["MORALE_LINKED_TO_HOME_EFFICIENCY_VALUE"].Value) then
			moraleFromHome = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_LINKED_TO_HOME"].Value)
		elseif supplyEfficiency <= tonumber(GameInfo.GlobalParameters["MORALE_FAR_FROM_HOME_EFFICIENCY_VALUE"].Value) then
			moraleFromHome = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_FAR_FROM_HOME"].Value)
		end	
	else
		moraleFromHome = tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_NO_WAY_HOME"].Value)
	end
	return moraleFromHome
end


----------------------------------------------
-- Texts function
----------------------------------------------
-- Flag
function GetFoodConsumptionString(self)
	local unitKey 			= self:GetKey()
	local unitData 			= ExposedMembers.UnitData[unitKey]
	local str 				= ""
	local ratio 			= self:GetFoodConsumptionRatio()
	local totalPersonnel 	= unitData.Personnel + unitData.PersonnelReserve
	if totalPersonnel > 0 then 
		local personnelFood = ( totalPersonnel * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_PERSONNEL_FACTOR"].Value) )/1000
		str = str .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITFLAG_FOOD_CONSUMPTION_PERSONNEL", GCO.ToDecimals(personnelFood * ratio), totalPersonnel) 
	end	
	local totalHorses = unitData.Horses + unitData.HorsesReserve
	if totalHorses > 0 then 
		local horsesFood = ( totalHorses * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_HORSES_FACTOR"].Value) )/1000
		str = str .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITFLAG_FOOD_CONSUMPTION_HORSES", GCO.ToDecimals(horsesFood * ratio), totalHorses ) 
	end
	
	-- value belows may be nil
	if unitData.WoundedPersonnel and unitData.WoundedPersonnel > 0 then 
		local woundedFood = ( unitData.WoundedPersonnel * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_WOUNDED_FACTOR"].Value) )/1000
		str = str .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITFLAG_FOOD_CONSUMPTION_WOUNDED", GCO.ToDecimals(woundedFood * ratio), unitData.WoundedPersonnel ) 
	end
	if unitData.Prisoners then	
		local totalPrisoners = GCO.GetTotalPrisoners(unitData)		
		if totalPrisoners > 0 then 
			local prisonnersFood = ( totalPrisoners * tonumber(GameInfo.GlobalParameters["FOOD_CONSUMPTION_PRISONERS_FACTOR"].Value) )/1000
			str = str .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITFLAG_FOOD_CONSUMPTION_PRISONERS", GCO.ToDecimals(prisonnersFood * ratio), totalPrisoners )
		end
	end	
	return str
end

function GetMoraleString(self) 
	local unitKey 			= self:GetKey()
	local unitData 			= ExposedMembers.UnitData[unitKey]
	local baseMorale 		= tonumber(GameInfo.GlobalParameters["MORALE_BASE_VALUE"].Value)
	local lowMorale 		= GCO.Round(baseMorale * tonumber(GameInfo.GlobalParameters["MORALE_LOW_PERCENT"].Value) / 100)
	local badMorale 		= GCO.Round(baseMorale * tonumber(GameInfo.GlobalParameters["MORALE_BAD_PERCENT"].Value) / 100)
	local unitMorale 		= unitData.Morale
	local moraleVariation	= self:GetComponentVariation("Morale")--unitData.MoraleVariation
	
	local str = ""
	-- summary, one line
	if unitMorale < badMorale then
		str = Locale.Lookup("LOC_UNITFLAG_BAD_MORALE", unitMorale, baseMorale)
	elseif unitMorale < lowMorale then
		str = Locale.Lookup("LOC_UNITFLAG_LOW_MORALE", unitMorale, baseMorale)
	elseif unitMorale == baseMorale then
		str = Locale.Lookup("LOC_UNITFLAG_HIGH_MORALE", unitMorale, baseMorale)
	else
		str = Locale.Lookup("LOC_UNITFLAG_MORALE", unitMorale, baseMorale)
	end	
	if moraleVariation > 0 then
		str = str .. " [ICON_PressureUp]"
	elseif moraleVariation < 0 then
		str = str .. " [ICON_PressureDown]"
	end
	
	-- details, multiple lines
	local moraleFromFood = self:GetMoraleFromFood()
	if moraleFromFood > 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_WELL_FED", moraleFromFood)
	elseif moraleFromFood < 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_FOOD_RATIONING", moraleFromFood)
	end	
	
	local moraleFromCombat = self:GetMoraleFromLastCombat()
	local turnLeft = tonumber(GameInfo.GlobalParameters["MORALE_COMBAT_EFFECT_NUM_TURNS"].Value) - (Game.GetCurrentGameTurn() - unitData.LastCombatTurn)
	if moraleFromCombat > 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_VICTORY", moraleFromCombat, turnLeft)
	elseif moraleFromCombat < 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_DEFEAT", moraleFromCombat, turnLeft)
	end			
	
	local moraleFromWounded = self:GetMoraleFromWounded()
	if moraleFromWounded > 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_NO_WOUNDED", moraleFromWounded)
	elseif moraleFromWounded < 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_WOUNDED", moraleFromWounded)
	end	
	
	local moraleFromHP = self:GetMoraleFromHP()
	if moraleFromHP > 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_FULL_HP", moraleFromHP)
	elseif moraleFromHP < 0 then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_LOW_HP", moraleFromHP)
	end
	
	local moraleFromHome = self:GetMoraleFromHome()
	if moraleFromHome == tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_NO_WAY_HOME"].Value) then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_NO_WAY_HOMEP", moraleFromHome)
	elseif moraleFromHome == tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_FAR_FROM_HOME"].Value) then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_FAR_FROM_HOME", moraleFromHome)
	elseif moraleFromHome == tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_LINKED_TO_HOME"].Value) then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_LINKED_TO_HOME", moraleFromHome)
	elseif moraleFromHome == tonumber(GameInfo.GlobalParameters["MORALE_CHANGE_CLOSE_TO_HOME"].Value) then
		str = str .. Locale.Lookup("LOC_UNITFLAG_MORALE_CLOSE_TO_HOME", moraleFromHome)
	end
	
	return str
end

function GetFuelStockString(self) 
	local unitKey 			= self:GetKey()
	local unitData 			= ExposedMembers.UnitData[unitKey]
	local lightRationing = 	tonumber(GameInfo.GlobalParameters["FUEL_RATIONING_LIGHT_RATIO"].Value)
	local mediumRationing = tonumber(GameInfo.GlobalParameters["FUEL_RATIONING_MEDIUM_RATIO"].Value)
	local heavyRationing = 	tonumber(GameInfo.GlobalParameters["FUEL_RATIONING_HEAVY_RATIO"].Value)
	local baseFuelStock = GetBaseFuelStock(unitData.unitType)
	local fuelStockVariation = unitData.FuelStock - unitData.PreviousFuelStock
	local str = ""
	if unitData.FuelStock < (baseFuelStock * heavyRationing) then
		str = Locale.Lookup("LOC_UNITFLAG_FUEL_STOCK_HEAVY_RATIONING", unitData.FuelStock, baseFuelStock)
	elseif unitData.FuelStock < (baseFuelStock * mediumRationing) then
		str = Locale.Lookup("LOC_UNITFLAG_FUEL_STOCK_MEDIUM_RATIONING", unitData.FuelStock, baseFuelStock)
	elseif unitData.FuelStock < (baseFuelStock * lightRationing) then
		str = Locale.Lookup("LOC_UNITFLAG_FUEL_STOCK_LIGHT_RATIONING", unitData.FuelStock, baseFuelStock)
	else
		str = Locale.Lookup("LOC_UNITFLAG_FUEL_STOCK", unitData.FuelStock, baseFuelStock)
	end	
	
	str =  str .. GCO.GetVariationString(self:GetComponentVariation("FuelStock"))
	
	return str
end

function GetFuelConsumptionString(self)
	if self:GetFuelConsumption() == 0 then return "" end
	local unitKey 			= self:GetKey()
	local unitData 			= ExposedMembers.UnitData[unitKey]
	local str = ""
	local ratio = GetFuelConsumptionRatio(unitData)
	--[[
	if unitData.Equipment > 0 then 
		local fuel = ( unitData.Equipment * tonumber(GameInfo.GlobalParameters["FUEL_CONSUMPTION_ACTIVE_FACTOR"].Value) )/1000
		str = str .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITFLAG_FUEL_CONSUMPTION_ACTIVE", GCO.ToDecimals(fuel * ratio), unitData.Equipment) 
	end
	if unitData.DamagedEquipment > 0 then 
		local fuel = ( unitData.DamagedEquipment * tonumber(GameInfo.GlobalParameters["FUEL_CONSUMPTION_ACTIVE_FACTOR"].Value) )/1000
		str = str .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITFLAG_FUEL_CONSUMPTION_DAMAGED", GCO.ToDecimals(fuel * ratio), unitData.DamagedEquipment) 
	end
	--]]
	return str
end

function GetFoodStockString(self) 
	local unitKey 			= self:GetKey()
	local data 				= ExposedMembers.UnitData[unitKey]
	local baseFoodStock 	= self:GetBaseFoodStock()
	local foodStock			= GCO.Round(data.FoodStock)
	local str = ""
	if data.FoodStock < (baseFoodStock * heavyRationing) then
		str = Locale.Lookup("LOC_UNITFLAG_FOOD_RATION_HEAVY_RATIONING", foodStock, baseFoodStock)
	elseif data.FoodStock < (baseFoodStock * mediumRationing) then
		str = Locale.Lookup("LOC_UNITFLAG_FOOD_RATION_MEDIUM_RATIONING", foodStock, baseFoodStock)
	elseif data.FoodStock < (baseFoodStock * lightRationing) then
		str = Locale.Lookup("LOC_UNITFLAG_FOOD_RATION_LIGHT_RATIONING", foodStock, baseFoodStock)
	else
		str = Locale.Lookup("LOC_UNITFLAG_FOOD_RATION", foodStock, baseFoodStock)
	end
	
	str =  str .. GCO.GetVariationString(self:GetComponentVariation("FoodStock")) 
	
	return str
end

function GetFrontLineEquipmentString(self)
	local unitKey 			= self:GetKey()
	local data 				= ExposedMembers.UnitData[unitKey]
	local equipmentClasses	= self:GetEquipmentClasses()
	local str = ""
	for classType, classData in pairs(equipmentClasses) do
		local classNum = self:GetEquipmentClassFrontLine(classType)
		local maxClass = self:GetMaxEquipmentFrontLine(classType)
		if classNum > 0 then
			str = str .. "[NEWLINE]".. Locale.Lookup("LOC_UNITFLAG_EQUIPMENT_CLASS_FRONTLINE", classNum, maxClass, GameInfo.EquipmentClasses[classType].Name, GCO.GetResourceIcon()) --[ICON_Production] " .. tostring(classNum) .. " " .. Locale.Lookup(GameInfo.EquipmentClasses[classType].Name)
			local equipmentList = GetEquipmentTypes(classType)
			if #equipmentList > 1 then  -- show sub-entries only if there could be more than one equipment type in this class
				for _, equipmentData in ipairs(equipmentList) do
					local equipmentID 	= equipmentData.EquipmentID
					local equipmentNum 	= self:GetFrontLineEquipment( equipmentID, classType)
					if equipmentNum > 0 then
						local percentage =  GCO.Round(equipmentNum / classNum * 100)
						str = str .. "[NEWLINE] [ICON_BULLET] " .. Locale.Lookup("LOC_UNITFLAG_EQUIPMENT_FRONTLINE", equipmentNum, percentage, GameInfo.Resources[equipmentID].Name, GCO.GetResourceIcon(equipmentID)) --" .. tostring(equipmentNum) .. " " .. Locale.Lookup(GameInfo.Resources[equipmentID].Name)
					end
				end
			end
		end
	end
	return str
end

function GetReserveEquipmentString(self) 
	local unitKey 			= self:GetKey()
	local data 				= ExposedMembers.UnitData[unitKey]
	local equipmentClasses	= self:GetEquipmentClasses()
	local str = ""
	for classType, classData in pairs(equipmentClasses) do
		local classNum = self:GetEquipmentClassReserve(classType)
		if classNum > 0 then
			str = str .. "[NEWLINE]".. Locale.Lookup("LOC_UNITFLAG_EQUIPMENT_CLASS_RESERVE", classNum, GameInfo.EquipmentClasses[classType].Name, GCO.GetResourceIcon()) --[ICON_Production] " .. tostring(classNum) .. " " .. Locale.Lookup(GameInfo.EquipmentClasses[classType].Name)
			local equipmentList = GetEquipmentTypes(classType)
			if #equipmentList > 1 then -- show sub-entries only if there could be more than one equipment type in this class
				for _, equipmentData in ipairs(equipmentList) do
					local equipmentID 	= equipmentData.EquipmentID
					local equipmentNum 	= self:GetReserveEquipment( equipmentID, classType)			
					if equipmentNum > 0 then
						str = str .. "[NEWLINE] [ICON_BULLET] " .. Locale.Lookup("LOC_UNITFLAG_EQUIPMENT_RESERVE", equipmentNum, GameInfo.Resources[equipmentID].Name, GCO.GetResourceIcon(equipmentID)) -- ..tostring(equipmentNum) .. " " .. Locale.Lookup(GameInfo.Resources[equipmentID].Name)
					end
				end
			end
		end
	end
	return str
end

function GetResourcesStockString(self)
	local unitKey 	= self:GetKey()
	local data 		= ExposedMembers.UnitData[unitKey]
	local str 		= ""
	for resourceKey, value in pairs(data.Stock) do	
		local resourceID 		= tonumber(resourceKey)		
		if (value) > 0 then
			local resRow 			= GameInfo.Resources[resourceID]
			str = str .. "[NEWLINE]" .. Locale.Lookup("LOC_UNITFLAG_RESOURCE_STOCK", value, resRow.Name, GCO.GetResourceIcon(resourceID))
		end
	end
	return str
end

-- Floating text
function ShowCasualtiesFloatingText(CombatData)
	if floatingTextLevel == FLOATING_TEXT_NONE then
		return
	end
	local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
	if (pLocalPlayerVis ~= nil) then
		if (pLocalPlayerVis:IsVisible(CombatData.unit:GetX(), CombatData.unit:GetY())) then
			local sText = ""
			if floatingTextLevel == FLOATING_TEXT_SHORT then
				-- Show everything in 2 calls to AddWorldViewText
				-- Format text with newlines or separator as required, with 3 lines max
				local bNeedNewLine, bNeedSeparator = false, false
				if CombatData.PersonnelCasualties > 0 then
					sText = sText .. Locale.Lookup("LOC_FRONTLINE_PERSONNEL_CASUALTIES_DETAILS_SHORT", CombatData.Dead, CombatData.Captured, CombatData.Wounded)
					-- The string above is near the lenght limit of what AddWorldViewText can accept, so call it now.
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
				-- 
				sText = ""
				--[[
				if CombatData.EquipmentCasualties > 0 then
					if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					sText = sText .. Locale.Lookup("LOC_FRONTLINE_EQUIPMENT_CASUALTIES_DETAILS_SHORT", CombatData.EquipmentLost, CombatData.DamagedEquipment)
					bNeedNewLine = true
				end
				--]]
				if CombatData.HorsesLost > 0 then
					if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					sText = sText .. Locale.Lookup("LOC_FRONTLINE_HORSES_CASUALTIES_SHORT", CombatData.HorsesLost)
					bNeedNewLine, bNeedSeparator = false, true
				end
				if CombatData.MaterielLost > 0 then
					if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					if bNeedSeparator then sText = sText .. "," end
					sText = sText .. Locale.Lookup("LOC_FRONTLINE_MATERIEL_CASUALTIES_SHORT", CombatData.MaterielLost)
				end				
				Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
			
			else
				-- Show details with multiple calls to AddWorldViewText
				if CombatData.PersonnelCasualties > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_PERSONNEL_CASUALTIES", CombatData.PersonnelCasualties)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
				if CombatData.Dead + CombatData.Captured + CombatData.Wounded > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_PERSONNEL_CASUALTIES_DETAILS", CombatData.Dead, CombatData.Captured, CombatData.Wounded)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end

				--[[
				if CombatData.EquipmentCasualties > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_EQUIPMENT_CASUALTIES", CombatData.EquipmentCasualties)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
				if CombatData.EquipmentLost +CombatData.DamagedEquipment > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_EQUIPMENT_CASUALTIES_DETAILS", CombatData.EquipmentLost, CombatData.DamagedEquipment)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
				--]]

				if CombatData.HorsesLost > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_HORSES_CASUALTIES", CombatData.HorsesLost)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end

				if CombatData.MaterielLost > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_MATERIEL_CASUALTIES", CombatData.MaterielLost)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
			end
		end
	end
end

function ShowCombatPlunderingFloatingText(CombatData)
	if floatingTextLevel == FLOATING_TEXT_NONE then
		return
	end
	local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
	if (pLocalPlayerVis ~= nil) then
		if (pLocalPlayerVis:IsVisible(CombatData.unit:GetX(), CombatData.unit:GetY())) then
			local sText = ""
			if floatingTextLevel == FLOATING_TEXT_SHORT then
				-- Show everything in one call to AddWorldViewText
				-- Format text with newlines or separator as required
				local bNeedNewLine, bNeedSeparator = false, false
				-- first line				
				if CombatData.Prisoners and CombatData.Prisoners > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_PRISONERS_CAPTURED_SHORT", CombatData.Prisoners)
					bNeedNewLine, bNeedSeparator = true, true
				end
				if CombatData.MaterielGained and CombatData.MaterielGained > 0 then
					if bNeedSeparator then sText = sText .. "," end
					sText = Locale.Lookup("LOC_FRONTLINE_MATERIEL_CAPTURED_SHORT", CombatData.MaterielGained)
					bNeedNewLine, bNeedSeparator = true, false
				end
				-- second line
				if bNeedNewLine then Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0) end
				sText = ""
				bNeedSeparator = false -- we don't want a separator at the beginning of a new line
				if CombatData.LiberatedPrisoners and CombatData.LiberatedPrisoners > 0 then -- LiberatedPrisoners is not nil only when the defender is dead...
					--if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					sText = Locale.Lookup("LOC_FRONTLINE_LIBERATED_PRISONERS_SHORT", CombatData.LiberatedPrisoners)
					bNeedNewLine, bNeedSeparator = false, true
				end				
				if CombatData.FoodGained and CombatData.FoodGained > 0 then  -- FoodGained is not nil only when the defender is dead...
					--if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					if bNeedSeparator then sText = sText .. "," end
					sText = Locale.Lookup("LOC_FRONTLINE_FOOD_CAPTURED_SHORT", CombatData.FoodGained)
				end
				Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
			else
				-- Show details with multiple calls to AddWorldViewText			
				if CombatData.Prisoners > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_PRISONERS_CAPTURED", CombatData.Prisoners)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
				if CombatData.MaterielGained > 0 then
					sText = Locale.Lookup("LOC_FRONTLINE_MATERIEL_CAPTURED", CombatData.MaterielGained)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
				if CombatData.LiberatedPrisoners and CombatData.LiberatedPrisoners > 0 then -- LiberatedPrisoners is not nil only when the defender is dead...
					sText = Locale.Lookup("LOC_FRONTLINE_LIBERATED_PRISONERS", CombatData.LiberatedPrisoners)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end				
				if CombatData.FoodGained and CombatData.FoodGained > 0 then  -- FoodGained is not nil only when the defender is dead...
					sText = Locale.Lookup("LOC_FRONTLINE_FOOD_CAPTURED", CombatData.FoodGained)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, CombatData.unit:GetX(), CombatData.unit:GetY(), 0)
				end
			end
		end
	end
end

function ShowFoodFloatingText(foodData)
	if floatingTextLevel == FLOATING_TEXT_NONE then
		return
	end
	if foodData.foodEat + foodData.foodGet > 0 then
		local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
		if (pLocalPlayerVis ~= nil) then
			if (pLocalPlayerVis:IsVisible(foodData.X, foodData.Y)) then
				local sText = ""
				if foodData.foodEat > 0 then sText = Locale.Lookup("LOC_UNIT_EATING", foodData.foodEat) end
				if foodData.foodGet > 0 then sText = sText .. "[NEWLINE]" ..Locale.Lookup("LOC_UNIT_GET_FOOD", foodData.foodGet) end
				Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, foodData.X, foodData.Y, 0)
			end
		end
	end
end

function ShowFrontLineHealingFloatingText(healingData)
	if floatingTextLevel == FLOATING_TEXT_NONE then
		return
	end
	local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
	if (pLocalPlayerVis ~= nil) then
		if (pLocalPlayerVis:IsVisible(healingData.X, healingData.Y)) then
			local sText = ""
			if floatingTextLevel == FLOATING_TEXT_SHORT then
				-- Show everything in 2 calls to AddWorldViewText
				-- Format text with newlines or separator as required
				local bNeedNewLine, bNeedSeparator = false, false
				if healingData.reqPersonnel + healingData.reqMateriel > 0 then
					sText = sText .. Locale.Lookup("LOC_PERSONNEL_RESERVE_TRANSFER", healingData.reqPersonnel)
					bNeedNewLine, bNeedSeparator = true, true
				end
				if healingData.reqMateriel > 0 then
					if bNeedSeparator then sText = sText .. "," end
					sText = sText .. Locale.Lookup("LOC_MATERIEL_RESERVE_TRANSFER", healingData.reqMateriel)
					bNeedNewLine, bNeedSeparator = true, true
				end
				-- second line
				if bNeedNewLine then Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0) end
				bNeedNewLine, bNeedSeparator = false, false
				sText = ""
				--[[
				if healingData.reqEquipment > 0 then
					--if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					sText = sText .. Locale.Lookup("LOC_EQUIPMENT_RESERVE_TRANSFER", healingData.reqEquipment)					
					bNeedNewLine, bNeedSeparator = false, true
				end
				--]]
				if healingData.reqHorses > 0 then
					--if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					if bNeedSeparator then sText = sText .. "," end
					sText = sText .. Locale.Lookup("LOC_HORSES_RESERVE_TRANSFER", healingData.reqHorses)
				end
				Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0)
			else
				-- Show details with multiple calls to AddWorldViewText	
				if healingData.reqPersonnel + healingData.reqMateriel > 0 then
					sText = Locale.Lookup("LOC_HEALING_PERSONNEL_MATERIEL", healingData.reqPersonnel, healingData.reqMateriel)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0)
				end
				--[[
				if healingData.reqEquipment > 0 then
					sText = Locale.Lookup("LOC_HEALING_EQUIPMENT", healingData.reqEquipment)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0)
				end
				--]]
				if healingData.reqHorses > 0 then
					sText = Locale.Lookup("LOC_HEALING_HORSES", healingData.reqHorses)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0)
				end
			end
		end
	end
end

function ShowReserveHealingFloatingText(healingData)
	if floatingTextLevel == FLOATING_TEXT_NONE then
		return
	end
	local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
	if (pLocalPlayerVis ~= nil) then
		if (pLocalPlayerVis:IsVisible(healingData.X, healingData.Y)) then
			local sText = ""
			if floatingTextLevel == FLOATING_TEXT_SHORT then
				-- Show everything in 2 calls to AddWorldViewText
				-- Format text with NEWLINE as required				
				local bNeedNewLine, bNeedSeparator = false, false
				-- first line
				if healingData.deads + healingData.healed > 0 then
					sText = sText .. Locale.Lookup("LOC_HEALING_WOUNDED", healingData.deads, healingData.healed)
					bNeedNewLine, bNeedSeparator = true, false
				end
				-- second line
				--[[
				if bNeedNewLine then Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0) end
				sText = ""
				bNeedSeparator = false
				if healingData.repairedEquipment > 0 then
					--if bNeedNewLine then sText = sText .. "[NEWLINE]" end
					sText = sText .. Locale.Lookup("LOC_REPAIRING_EQUIPMENT", healingData.repairedEquipment)
				end
				Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0)
				--]]
			else			
				-- Show details with multiple calls to AddWorldViewText	
				if healingData.deads + healingData.healed > 0 then
					sText = Locale.Lookup("LOC_HEALING_WOUNDED", healingData.deads, healingData.healed)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0)
				end
				--[[
				if healingData.repairedEquipment > 0 then
					sText = Locale.Lookup("LOC_REPAIRING_EQUIPMENT", healingData.repairedEquipment)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, healingData.X, healingData.Y, 0)
				end
				--]]
			end
		end
	end
end

function ShowDesertionFloatingText(desertionData)
	if floatingTextLevel == FLOATING_TEXT_NONE then
		return
	end
	local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
	if (pLocalPlayerVis ~= nil) then
		if (pLocalPlayerVis:IsVisible(desertionData.X, desertionData.Y)) then
			local sText = Locale.Lookup("LOC_UNIT_PERSONNEL_DESERTION", desertionData.Personnel)
			local bNeedNewLine, bNeedSeparator = true, false
			--[[
			if desertionData.Equipment > 0 then
				if bNeedNewLine then sText = sText .. "[NEWLINE]" end
				if bNeedSeparator then sText = sText .. "," end
				sText = sText .. Locale.Lookup("LOC_EQUIPMENT_RESERVE_TRANSFER", desertionData.Equipment)
				bNeedNewLine, bNeedSeparator = false, true
			end
			--]]
			if desertionData.Horses > 0 then
				if bNeedNewLine then sText = sText .. "[NEWLINE]" end
				if bNeedSeparator then sText = sText .. "," end
				sText = sText .. Locale.Lookup("LOC_HORSES_RESERVE_TRANSFER", desertionData.Horses)
				bNeedNewLine, bNeedSeparator = false, true
			end
			if desertionData.Materiel > 0 then
				if bNeedNewLine then sText = sText .. "[NEWLINE]" end
				if bNeedSeparator then sText = sText .. "," end
				sText = sText .. Locale.Lookup("LOC_MATERIEL_RESERVE_TRANSFER", desertionData.Materiel)
				bNeedNewLine, bNeedSeparator = false, true
			end
			Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, desertionData.X, desertionData.Y, 0)
		end
	end
end

function ShowFuelConsumptionFloatingText(fuelData)
	if floatingTextLevel == FLOATING_TEXT_NONE then
		return
	end
	if fuelData.fuelConsumption > 0 then
		local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
		if (pLocalPlayerVis ~= nil) then
			if (pLocalPlayerVis:IsVisible(fuelData.X, fuelData.Y)) then
				local sText = Locale.Lookup("LOC_UNIT_FUEL_CONSUMPTION", fuelData.fuelConsumption)
				Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, fuelData.X, fuelData.Y, 0)
			end
		end
	end
end


-----------------------------------------------------------------------------------------
-- Combat
-----------------------------------------------------------------------------------------

function GetAntiPersonnelPercent(self)
	
	--local DEBUG_UNIT_SCRIPT = true
	
	local antiPersonnel = GameInfo.Units[self:GetType()].AntiPersonnel -- 0 = no kill, 100 = all killed
	local classAP		= {}
	local numClassAP	= 0		-- number of equipment classes with Anti-Personnel value (usually weapons or ammunition)
	
	local equipmentClasses = self:GetEquipmentClasses()
	for classType, classData in pairs(equipmentClasses) do
		local equipmentTypes 	= GetEquipmentTypes(classType)
		local totalFrontLine	= self:GetEquipmentClassFrontLine(classType)
		--table.sort(equipmentTypes, function(a, b) return a.Desirability > b.Desirability; end)
		if equipmentTypes then
			for _, data in ipairs(equipmentTypes) do
				local equipmentAP 		= EquipmentInfo[data.EquipmentID].AntiPersonnel
				if equipmentAP then
					local equipmentID = data.EquipmentID
					local num = self:GetFrontLineEquipment(equipmentID, classType)
					if num > 0 then
						local ratio = num / totalFrontLine 
						if not classAP[classType] then 
							classAP[classType] = equipmentAP * ratio
							numClassAP = numClassAP + 1
						else
							classAP[classType] = classAP[classType] + (equipmentAP * ratio)
						end
					end
				end
			end
		end
	end
	
	local averageAP = (GCO.TableSummation(classAP) + antiPersonnel) / ( numClassAP + 1 )
	
	Dprint( DEBUG_UNIT_SCRIPT, "- Getting AP value for ".. Locale.Lookup(self:GetName()), " averageAP = ", tostring(averageAP), " base AP = ", tostring(antiPersonnel), ", classAP = ", GCO.TableSummation(classAP), ", numClassAP = ", numClassAP )
	
	return averageAP
end

function AddCombatInfoTo(Opponent)

	Opponent.unit = GetUnit(Opponent.playerID, Opponent.unitID)
	
	if Opponent.unit then
		Opponent.unitType 	= Opponent.unit:GetType()
		Opponent.unitKey 	= Opponent.unit:GetKey()
		
		if UnitWithoutEquipment[Opponent.unitKey] then
			print("WARNING: Unit no equiped yet in AddCombatInfoTo, forcing initialization for ".. Locale.Lookup(Opponent.unit:GetName()) .." of player #".. tostring(Opponent.unit:GetOwner()).. " id#" .. tostring(Opponent.unit:GetKey()))
			Opponent.unit:InitializeEquipment() 
		end
		
		Opponent.IsLandUnit = GameInfo.Units[Opponent.unitType].Domain == "DOMAIN_LAND"
		-- Max number of prisonners can't be higher than the unit's operationnal number of personnel or the number of remaining valid personnel x10
		Opponent.MaxPrisoners = math.min(GameInfo.Units[Opponent.unitType].Personnel, (ExposedMembers.UnitData[Opponent.unitKey].Personnel+ExposedMembers.UnitData[Opponent.unitKey].PersonnelReserve)*10)
		local diff = (Opponent.MaxPrisoners - GCO.GetTotalPrisoners(ExposedMembers.UnitData[Opponent.unitKey]))
		if diff > 0 then
			Opponent.MaxCapture = GCO.Round(diff * GameInfo.GlobalParameters["COMBAT_CAPTURE_FROM_CAPACITY_PERCENT"].Value/100)
		else
			Opponent.MaxCapture = 0
		end
		Opponent.AntiPersonnel = Opponent.unit:GetAntiPersonnelPercent()
	else
		Opponent.unitKey = GetUnitKeyFromIDs(Opponent.playerID, Opponent.unitID)
	end	
	
	Opponent.unitData 	= ExposedMembers.UnitData[Opponent.unitKey]
	
	local pendingHeal = UnitLastHealingValue[Opponent.unitKey]
	if pendingHeal and Opponent.InitialHP ~= Opponent.unitData.HP then
		Opponent.InitialHP 			= math.min( maxHP , Opponent.InitialHP + pendingHeal)
		Opponent.FinalHP 			= math.min( maxHP , Opponent.FinalHP + pendingHeal)
		Opponent.ShiftHP 			= true
		Dprint( DEBUG_UNIT_SCRIPT, "-- Pending heal detected, shifting HP values by ", pendingHeal, " InitialHP = ", Opponent.InitialHP, " FinalHP = ", Opponent.FinalHP )
	end		
	return Opponent
end

function AddFrontLineCasualtiesInfoTo(Opponent)

	local UnitHitPoints = ExposedMembers.UnitHitPointsTable[Opponent.unitType]

	if Opponent.IsDead then
		Opponent.FinalHP = 0
	end
	
	if Opponent.unit then Dprint( DEBUG_UNIT_SCRIPT, "Add FrontLine Casualties Info To "..tostring(GameInfo.Units[Opponent.unit:GetType()].UnitType).." id#".. tostring(Opponent.unit:GetKey()).." player#"..tostring(Opponent.unit:GetOwner())) end
	Dprint( DEBUG_UNIT_SCRIPT, "Initial HP = " .. tostring(Opponent.InitialHP) .. ", Final HP = " .. tostring(Opponent.FinalHP))
	
	Opponent.PersonnelCasualties 	= UnitHitPoints[Opponent.InitialHP].Personnel 	- UnitHitPoints[Opponent.FinalHP].Personnel
	Opponent.HorsesCasualties 		= UnitHitPoints[Opponent.InitialHP].Horses		- UnitHitPoints[Opponent.FinalHP].Horses
	Opponent.MaterielCasualties		= UnitHitPoints[Opponent.InitialHP].Materiel 	- UnitHitPoints[Opponent.FinalHP].Materiel
	
	Dprint( DEBUG_UNIT_SCRIPT, "- Calculating casualties to Personnel : initial = ".. tostring(UnitHitPoints[Opponent.InitialHP].Personnel), " casualties = ", Opponent.PersonnelCasualties, " final = ", tostring(UnitHitPoints[Opponent.FinalHP].Personnel) )
	Dprint( DEBUG_UNIT_SCRIPT, "- Calculating casualties to Horses : 	initial = ".. tostring(UnitHitPoints[Opponent.InitialHP].Horses), " casualties = ", Opponent.HorsesCasualties, " final = ", tostring(UnitHitPoints[Opponent.FinalHP].Horses) )
	Dprint( DEBUG_UNIT_SCRIPT, "- Calculating casualties to Materiel : initial = ".. tostring(UnitHitPoints[Opponent.InitialHP].Materiel), " casualties = ", Opponent.MaterielCasualties, " final = ", tostring(UnitHitPoints[Opponent.FinalHP].Materiel) )

	Opponent.EquipmentCasualties 	= {}
	for equipmentClassKey, equipmentData in pairs(Opponent.unitData.Equipment) do
		local equipmentClassID 	= tonumber(equipmentClassKey)
		local isRequired	 	= (unitEquipmentClasses[Opponent.unitType] and unitEquipmentClasses[Opponent.unitType][equipmentClassID] and unitEquipmentClasses[Opponent.unitType][equipmentClassID].IsRequired)
		if isRequired then 	-- required equipment follow exactly the UnitHitPoints table
			Opponent.EquipmentCasualties[equipmentClassKey] = UnitHitPoints[Opponent.InitialHP].EquipmentClass[equipmentClassID] - UnitHitPoints[Opponent.FinalHP].EquipmentClass[equipmentClassID]
		else 				-- optional equipment use relative value, UnitHitPoints is used to handle the max value at HP Left
			local damageRatio 	= (Opponent.InitialHP - Opponent.FinalHP) / maxHP
			local maxClassLeft 	= UnitHitPoints[Opponent.FinalHP].EquipmentClass[equipmentClassID]
			local classLeft		= GCO.TableSummation(equipmentData)
			local casualty		= GCO.Round(classLeft * damageRatio)
			if classLeft - casualty > maxClassLeft then
				casualty = classLeft - maxClassLeft
			end
			Opponent.EquipmentCasualties[equipmentClassKey] = casualty
		end
	end	

end

function AddCasualtiesInfoByTo(FromOpponent, Opponent)

	--local DEBUG_UNIT_SCRIPT = true
	
	local UnitData = Opponent.unitData
	
	if Opponent.unit then Dprint( DEBUG_UNIT_SCRIPT, "Add Casualties Info To "..tostring(GameInfo.Units[Opponent.unit:GetType()].UnitType).." id#".. tostring(Opponent.unit:GetKey()).." player#"..tostring(Opponent.unit:GetOwner())) end
	Dprint( DEBUG_UNIT_SCRIPT, "- Handling casualties to Personnel : initial = ".. tostring(UnitData.Personnel), " casualties = ", Opponent.PersonnelCasualties, " final = ", tostring(UnitData.Personnel  	- Opponent.PersonnelCasualties) )
	Dprint( DEBUG_UNIT_SCRIPT, "- Handling casualties to Horses : initial = ".. tostring(UnitData.Horses), " casualties = ", Opponent.HorsesCasualties, " final = ", tostring(UnitData.Horses  	- Opponent.HorsesCasualties) )
	Dprint( DEBUG_UNIT_SCRIPT, "- Handling casualties to Materiel : initial = ".. tostring(UnitData.Materiel), " casualties = ", Opponent.MaterielCasualties, " final = ", tostring(UnitData.Materiel  	- Opponent.MaterielCasualties) )
	
	-- Remove casualties from frontline
	UnitData.Personnel 	= UnitData.Personnel  	- Opponent.PersonnelCasualties
	if UnitData.Personnel < 0 then
		GCO.Error("UnitData.Personnel < 0 ", UnitData.Personnel, " casualties = ", Opponent.PersonnelCasualties)
	end
	
	UnitData.Horses		= UnitData.Horses	  	- Opponent.HorsesCasualties
	if UnitData.Horses < 0 then
		GCO.Error("UnitData.Horses < 0 ", UnitData.Horses, " casualties = ", Opponent.HorsesCasualties)
	end
	
	UnitData.Materiel 	= UnitData.Materiel 	- Opponent.MaterielCasualties
	if UnitData.Materiel < 0 then
		GCO.Error("UnitData.Materiel < 0 ", UnitData.Materiel, " casualties = ", Opponent.MaterielCasualties)
	end
		
	Opponent.EquipmentLost 		= {}
	Opponent.DamagedEquipment 	= {}
	
	-- Remove equipment from frontline, and handle destoyed/damaged/captured equipment
	for equipmentClassKey, classCasualty in pairs(Opponent.EquipmentCasualties) do
		local totalEquipment 	= GCO.TableSummation(UnitData.Equipment[equipmentClassKey])
		local equipment 		= {}
		local averageToughness	= 0
		local totalPondered		= 0
		
		Dprint( DEBUG_UNIT_SCRIPT, "- Handling casualties to equipment class : ".. Locale.Lookup(GameInfo.EquipmentClasses[tonumber(equipmentClassKey)].Name), " casualties = ", classCasualty, " total class equipment = ", totalEquipment)
		
		for equipmentTypeKey, value in pairs(UnitData.Equipment[equipmentClassKey]) do
			if value > 0 then
				local equipmentID 	= tonumber(equipmentTypeKey)
				local toughness		= EquipmentInfo[equipmentID].Toughness
				local relativeValue = value / toughness	-- the SQL column constrain says toughness > 0
				table.insert(equipment, {Key = equipmentTypeKey, ID = equipmentID, RelativeValue = relativeValue })		
				totalPondered = totalPondered + relativeValue
				Dprint( DEBUG_UNIT_SCRIPT, "  - data for ".. Locale.Lookup(GameInfo.Resources[equipmentID].Name), ", number = ", value, ", relative number = ", relativeValue, "percentage of class = ", GCO.Round(value / totalEquipment * 100))
			end
		end
		
		table.sort(equipment, function(a, b) return a.RelativeValue > b.RelativeValue; end) -- order from taking most damage to less damage
		
		local casualtyLeft = classCasualty
		for i, equipmentData in pairs(equipment) do
			local equipmentCasualty = 0
			local equipmentNumber		= UnitData.Equipment[equipmentClassKey][equipmentData.Key]
			if i == #equipment then -- last item = casualtyLeft (to avoid rounding error)
				equipmentCasualty = math.min( equipmentNumber, casualtyLeft )
			else
				equipmentCasualty = math.min( equipmentNumber, math.floor(classCasualty * (equipmentData.RelativeValue / totalPondered)) )		
			end
			casualtyLeft = casualtyLeft - equipmentCasualty
			
			local lost 		= GCO.Round(equipmentCasualty / 2) -- hardcoded for testing			
			local damaged 	= equipmentCasualty - lost
			
			Dprint( DEBUG_UNIT_SCRIPT, "  - equipment casualties for ".. Locale.Lookup(GameInfo.Resources[equipmentData.ID].Name), ", lost = ", lost, ", damaged = ", damaged, " relative percentage of class = ", GCO.Round(equipmentData.RelativeValue / totalPondered * 100))

			Opponent.EquipmentLost[equipmentData.Key] 		= lost		-- part of the lost equipment will be captured
			Opponent.DamagedEquipment[equipmentData.Key] 	= damaged	-- todo : handle the case where the equipment can't be repaired (just don't add it to UnitData.DamagedEquipment but do add it to TotalEquipmentLost if the stat is tracked) 
			
			if not UnitData.TotalEquipmentLost[equipmentClassKey] then UnitData.TotalEquipmentLost[equipmentClassKey] = {} end
			UnitData.TotalEquipmentLost[equipmentClassKey][equipmentData.Key] = (UnitData.TotalEquipmentLost[equipmentClassKey][equipmentData.Key] or 0) + lost
			
			if not UnitData.DamagedEquipment[equipmentClassKey] then UnitData.DamagedEquipment[equipmentClassKey] = {} end
			UnitData.DamagedEquipment[equipmentClassKey][equipmentData.Key] = (UnitData.DamagedEquipment[equipmentClassKey][equipmentData.Key] or 0) + damaged
			
			UnitData.Equipment[equipmentClassKey][equipmentData.Key] = UnitData.Equipment[equipmentClassKey][equipmentData.Key] - equipmentCasualty
			
			if UnitData.Equipment[equipmentClassKey][equipmentData.Key] < 0 then
				GCO.Error("UnitData.Equipment[equipmentClassKey][equipmentData.Key] < 0 ", UnitData.Equipment[equipmentClassKey][equipmentData.Key], " casualties = ", equipmentCasualty)
			end
			
		end
		
		if casualtyLeft > 0 then -- this could happen because of rounding...
		
			for i, equipmentData in pairs(equipment) do
				local equipmentCasualty = 0
				local equipmentNumber		= UnitData.Equipment[equipmentClassKey][equipmentData.Key]
				if equipmentNumber > casualtyLeft then
					equipmentCasualty = casualtyLeft
				else
					equipmentCasualty = equipmentNumber	
				end
				casualtyLeft = casualtyLeft - equipmentCasualty
				
				local lost = equipmentCasualty
				
				Dprint( DEBUG_UNIT_SCRIPT, "  - Extra equipment casualties for ".. Locale.Lookup(GameInfo.Resources[equipmentData.ID].Name), ", lost = ", lost)

				Opponent.EquipmentLost[equipmentData.Key] 		= (Opponent.EquipmentLost[equipmentData.Key] or 0) + lost		-- part of the lost equipment will be captured
				
				if not UnitData.TotalEquipmentLost[equipmentClassKey] then UnitData.TotalEquipmentLost[equipmentClassKey] = {} end
				UnitData.TotalEquipmentLost[equipmentClassKey][equipmentData.Key] = (UnitData.TotalEquipmentLost[equipmentClassKey][equipmentData.Key] or 0) + lost				
				
				UnitData.Equipment[equipmentClassKey][equipmentData.Key] = UnitData.Equipment[equipmentClassKey][equipmentData.Key] - equipmentCasualty
				
				if UnitData.Equipment[equipmentClassKey][equipmentData.Key] < 0 then
					GCO.Error("UnitData.Equipment[equipmentClassKey][equipmentData.Key] < 0 ", UnitData.Equipment[equipmentClassKey][equipmentData.Key], " casualties = ", equipmentCasualty)
				end
				
			end			
		end
		
		if casualtyLeft > 0 then -- but that shouldn't happen...
			GCO.Error("casualtyLeft > 0 ", casualtyLeft)
		end	
	end
	

	-- Send wounded to the rear, bury the dead, take prisonners
	if FromOpponent.AntiPersonnel then
		Opponent.Dead = GCO.Round(Opponent.PersonnelCasualties * FromOpponent.AntiPersonnel / 100)
	else
		Opponent.Dead = GCO.Round(Opponent.PersonnelCasualties * GameInfo.GlobalParameters["COMBAT_BASE_ANTIPERSONNEL_PERCENT"].Value / 100)
	end
	
	if FromOpponent.CanTakePrisoners then	
		if FromOpponent.CapturedPersonnelRatio then
			Opponent.Captured = GCO.Round((Opponent.PersonnelCasualties - Opponent.Dead) * FromOpponent.CapturedPersonnelRatio / 100)
		else
			Opponent.Captured = GCO.Round((Opponent.PersonnelCasualties - Opponent.Dead) * GameInfo.GlobalParameters["COMBAT_CAPTURED_PERSONNEL_PERCENT"].Value / 100)
		end	
		if FromOpponent.MaxCapture then
			Opponent.Captured = math.min(FromOpponent.MaxCapture, Opponent.Captured)
		end
	else
		Opponent.Captured = 0
	end	
	Opponent.Wounded = Opponent.PersonnelCasualties - Opponent.Dead - Opponent.Captured
	
	-- Salvage Equipment
	--Opponent.EquipmentLost = GCO.Round(Opponent.EquipmentCasualties / 2) -- hardcoded for testing, to do : get Anti-Vehicule stat (anti-tank, anti-ship, anti-air...) from opponent, maybe use also era difference (asymetry between weapon and protection used)
	--Opponent.DamagedEquipment = Opponent.EquipmentCasualties - Opponent.EquipmentLost
	-- They Shoot Horses, Don't They?
	Opponent.HorsesLost = Opponent.HorsesCasualties -- some of those may be captured ?
	
	-- Materiel too is a full lost
	Opponent.MaterielLost = Opponent.MaterielCasualties
				
	-- Apply Casualties	transfer
	UnitData.WoundedPersonnel 	= UnitData.WoundedPersonnel 	+ Opponent.Wounded
	--UnitData.DamagedEquipment = UnitData.DamagedEquipment 	+ Opponent.DamagedEquipment
	
	-- Update Stats
	UnitData.TotalDeath				= UnitData.TotalDeath 		+ Opponent.Dead
	--UnitData.TotalEquipmentLost	= UnitData.TotalEquipmentLost 	+ Opponent.EquipmentLost
	UnitData.TotalHorsesLost 		= UnitData.TotalHorsesLost 	+ Opponent.HorsesLost
	
	-- Update virtual HP
	-- There may be a bug with CombatResultParameters.FINAL_DAMAGE_TO always equal to 0 when CombatResultParameters.DAMAGE_TO = 0,
	-- while its supposed to return the global damage value of the unit, and in that case Opponent.FinalHP is always 100 which may not be the unit's real value
	-- (27-Oct-17)
	if Opponent.Damage > 0 then UnitData.HP = Opponent.FinalHP end
end

function GetMaterielFromKillOfBy(OpponentA, OpponentB)
	-- capture most materiel, convert some damaged Equipment
	local materielFromKill = 0
	local materielFromCombat = OpponentA.MaterielLost * attackerMaterielGainPercent / 100
	local materielFromReserve = ExposedMembers.UnitData[OpponentA.unitKey].MaterielReserve * attackerMaterielKillPercent /100
	local materielFromEquipment = 0 --ExposedMembers.UnitData[OpponentA.unitKey].DamagedEquipment * ExposedMembers.UnitData[OpponentA.unitKey].MaterielPerEquipment * tonumber(GameInfo.GlobalParameters["UNIT_MATERIEL_TO_REPAIR_VEHICLE_PERCENT"].Value) / 100 * tonumber(GameInfo.GlobalParameters["COMBAT_ATTACKER_EQUIPMENT_KILL_PERCENT"].Value) / 100
	materielFromKill = GCO.Round(materielFromCombat + materielFromReserve + materielFromEquipment) 
	return materielFromKill
end

local combatCount = 0
function OnCombat( combatResult )

	--local DEBUG_UNIT_SCRIPT = true
	
	-- for console debugging...
	ExposedMembers.lastCombat = combatResult
	
	combatCount = combatCount + 1
	Dprint( DEBUG_UNIT_SCRIPT, "--============================================--")
	Dprint( DEBUG_UNIT_SCRIPT, "-- Starting Combat #"..tostring(combatCount))
	Dprint( DEBUG_UNIT_SCRIPT, "--============================================--")

	local attacker = combatResult[CombatResultParameters.ATTACKER]
	local defender = combatResult[CombatResultParameters.DEFENDER]

	local combatType = combatResult[CombatResultParameters.COMBAT_TYPE]

	attacker.IsUnit = attacker[CombatResultParameters.ID].type == ComponentType.UNIT
	defender.IsUnit = defender[CombatResultParameters.ID].type == ComponentType.UNIT

	local componentString = { [ComponentType.UNIT] = "UNIT", [ComponentType.CITY] = "CITY", [ComponentType.DISTRICT] = "DISTRICT"}
	Dprint( DEBUG_UNIT_SCRIPT, "-- Attacker is " .. tostring(componentString[attacker[CombatResultParameters.ID].type]) ..", Damage = " .. attacker[CombatResultParameters.DAMAGE_TO] ..", Final HP = " .. tostring(attacker[CombatResultParameters.MAX_HIT_POINTS] - attacker[CombatResultParameters.FINAL_DAMAGE_TO]))
	Dprint( DEBUG_UNIT_SCRIPT, "-- Defender is " .. tostring(componentString[defender[CombatResultParameters.ID].type]) ..", Damage = " .. defender[CombatResultParameters.DAMAGE_TO] ..", Final HP = " .. tostring(defender[CombatResultParameters.MAX_HIT_POINTS] - defender[CombatResultParameters.FINAL_DAMAGE_TO]))

	-- We need to set some info before handling the change in the units composition
	if attacker.IsUnit then
		attacker.IsAttacker = true
		-- attach everything required by the update functions from the base CombatResultParameters
		attacker.FinalHP 	= attacker[CombatResultParameters.MAX_HIT_POINTS] - attacker[CombatResultParameters.FINAL_DAMAGE_TO]
		attacker.InitialHP 	= attacker.FinalHP + attacker[CombatResultParameters.DAMAGE_TO]
		attacker.Damage 	= attacker[CombatResultParameters.DAMAGE_TO]
		attacker.IsDead 	= attacker[CombatResultParameters.FINAL_DAMAGE_TO] > attacker[CombatResultParameters.MAX_HIT_POINTS]
		attacker.playerID 	= tostring(attacker[CombatResultParameters.ID].player) -- playerID is a key for Prisoners table
		attacker.unitID 	= attacker[CombatResultParameters.ID].id
		-- add information needed to handle casualties made to the other opponent (including unitKey)
		attacker = AddCombatInfoTo(attacker)
		--
		attacker.CanTakePrisoners = attacker.IsLandUnit and combatType == CombatTypes.MELEE and not attacker.IsDead
		if attacker.unit then 
			Dprint( DEBUG_UNIT_SCRIPT, "-- Attacker data initialized : "..tostring(GameInfo.Units[attacker.unit:GetType()].UnitType).." id#".. tostring(attacker.unit:GetKey()).." player#"..tostring(attacker.unit:GetOwner()) .. ", IsDead = ".. tostring(attacker.IsDead) .. ", CanTakePrisoners = ".. tostring(attacker.CanTakePrisoners))
		end
	end
	if defender.IsUnit then
		defender.IsDefender = true
		-- attach everything required by the update functions from the base CombatResultParameters
		defender.FinalHP 	= defender[CombatResultParameters.MAX_HIT_POINTS] - defender[CombatResultParameters.FINAL_DAMAGE_TO]
		defender.InitialHP 	= defender.FinalHP + defender[CombatResultParameters.DAMAGE_TO]
		defender.Damage 	= defender[CombatResultParameters.DAMAGE_TO]
		defender.IsDead 	= defender[CombatResultParameters.FINAL_DAMAGE_TO] > defender[CombatResultParameters.MAX_HIT_POINTS]
		defender.playerID 	= tostring(defender[CombatResultParameters.ID].player)
		defender.unitID 	= defender[CombatResultParameters.ID].id
		-- add information needed to handle casualties made to the other opponent (including unitKey)
		defender = AddCombatInfoTo(defender)
		--
		defender.CanTakePrisoners = defender.IsLandUnit and combatType == CombatTypes.MELEE and not defender.IsDead
		if defender.unit then
			Dprint( DEBUG_UNIT_SCRIPT, "-- Defender data initialized : "..tostring(GameInfo.Units[defender.unit:GetType()].UnitType).." id#".. tostring(defender.unit:GetKey()).." player#"..tostring(defender.unit:GetOwner()) .. ", IsDead = ".. tostring(defender.IsDead) .. ", CanTakePrisoners = ".. tostring(defender.CanTakePrisoners))
		end
	end

	-- Error control
	---[[
	if attacker.unit then
		local testHP = attacker.unit:GetMaxDamage() - attacker.unit:GetDamage()
		if attacker.unitData.HP ~= attacker.InitialHP then -- testHP ~= attacker.FinalHP or 
			-- this can happen when an unit takes part in multiple combat, the DLL return the HP left after all combat, while combatResult show the HP at the moment of the combat
			print ("WARNING: HP not equals to prediction in combatResult for "..tostring(GameInfo.Units[attacker.unit:GetType()].UnitType).." id#".. tostring(attacker.unit:GetKey()).." player#"..tostring(attacker.unit:GetOwner()))
			Dprint( DEBUG_UNIT_SCRIPT, "attacker.FinalHP = MAX_HP - FINAL_DAMAGE_TO .. = ", attacker.FinalHP, "=", attacker[CombatResultParameters.MAX_HIT_POINTS], "-", attacker[CombatResultParameters.FINAL_DAMAGE_TO])
			Dprint( DEBUG_UNIT_SCRIPT, "gamecore HP = GetMaxDamage() - GetDamage() ... = ", testHP)
			Dprint( DEBUG_UNIT_SCRIPT, "attacker.InitialHP ........................... = ", attacker.InitialHP)
			Dprint( DEBUG_UNIT_SCRIPT, "PreviousHP = unitData.HP ..................... = ", attacker.unitData.HP)
			Dprint( DEBUG_UNIT_SCRIPT, "attacker[CombatResultParameters.DAMAGE_TO] ... = ", attacker[CombatResultParameters.DAMAGE_TO])
			Dprint( DEBUG_UNIT_SCRIPT, "attacker.unitData.UnitLastHealingValue ....... = ", attacker.unitData.UnitLastHealingValue)
			Dprint( DEBUG_UNIT_SCRIPT, "attacker.ShiftHP ............................. = ", attacker.ShiftHP)
			--attacker.InitialHP = attacker.unitData.HP
			--attacker.FinalHP = testHP			
		end		
		--attacker.unitData.HP = testHP
		--attacker.unitData.HP = attacker.FinalHP
	end
	if defender.unit then
		local testHP = defender.unit:GetMaxDamage() - defender.unit:GetDamage()
		if defender.unitData.HP ~= defender.InitialHP then --testHP ~= defender.FinalHP or 
			print ("WARNING: HP not equals to prediction in combatResult for "..tostring(GameInfo.Units[defender.unit:GetType()].UnitType).." id#".. tostring(defender.unit:GetKey()).." player#"..tostring(defender.unit:GetOwner()))
			Dprint( DEBUG_UNIT_SCRIPT, "defender.FinalHP = MAX_HP - FINAL_DAMAGE_TO .. = ", defender.FinalHP, "=", defender[CombatResultParameters.MAX_HIT_POINTS], "-", defender[CombatResultParameters.FINAL_DAMAGE_TO])
			Dprint( DEBUG_UNIT_SCRIPT, "gamecore HP = GetMaxDamage() - GetDamage() ... = ", testHP)
			Dprint( DEBUG_UNIT_SCRIPT, "defender.InitialHP ........................... = ", defender.InitialHP)
			Dprint( DEBUG_UNIT_SCRIPT, "PreviousHP = unitData.HP ..................... = ", defender.unitData.HP)
			Dprint( DEBUG_UNIT_SCRIPT, "defender[CombatResultParameters.DAMAGE_TO] ... = ", defender[CombatResultParameters.DAMAGE_TO])
			Dprint( DEBUG_UNIT_SCRIPT, "defender.unitData.UnitLastHealingValue ....... = ", defender.unitData.UnitLastHealingValue)
			Dprint( DEBUG_UNIT_SCRIPT, "defender.ShiftHP ............................. = ", defender.ShiftHP)
			--defender.InitialHP = defender.unitData.HP
			--defender.FinalHP = testHP			
		end		
		--defender.unitData.HP = testHP
	end	
	
	if attacker.IsUnit then --and not attacker.IsDead then
		CheckComponentsHP(attacker.unit, "attacker before handling combat casualties", true)
	end
	if defender.IsUnit then --and not defender.IsDead then
		CheckComponentsHP(defender.unit, "defender before handling combat casualties", true)
	end	

	Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
	Dprint( DEBUG_UNIT_SCRIPT, "-- Casualties in Combat #"..tostring(combatCount))
	Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
	--]]

	-- Handle casualties
	if attacker.IsUnit then -- and attacker[CombatResultParameters.DAMAGE_TO] > 0 (we must fill data for even when the unit didn't take damage, else we'll have to check for nil entries before all operations...)
		if attacker.unit then
			if attacker.unitData then
				AddFrontLineCasualtiesInfoTo(attacker) 		-- Set Personnel, Equipment, Horses and Materiel casualties from the HP lost
				AddCasualtiesInfoByTo(defender, attacker) 	-- set detailed casualties (Dead, Captured, Wounded, Damaged, ...) from frontline Casualties and return the updated table
				if not attacker.IsDead then
					--LuaEvents.UnitsCompositionUpdated(attacker.playerID, attacker.unitID) 	-- call to update flag
					ShowCasualtiesFloatingText(attacker)									-- visualize all casualties
				end
			end
		end
	end

	if defender.IsUnit then -- and defender[CombatResultParameters.DAMAGE_TO] > 0 (we must fill data for even when the unit didn't take damage, else we'll have to check for nil entries before all operations...)
		if defender.unit then
			if defender.unitData then
				AddFrontLineCasualtiesInfoTo(defender) 		-- Set Personnel, Equipment, Horses and Materiel casualties from the HP lost
				AddCasualtiesInfoByTo(attacker, defender) 	-- set detailed casualties (Dead, Captured, Wounded, Damaged, ...) from frontline Casualties and return the updated table
				if not defender.IsDead then
					--LuaEvents.UnitsCompositionUpdated(defender.playerID, defender.unitID)	-- call to update flag
					ShowCasualtiesFloatingText(defender)									-- visualize all casualties
				end
			end
		end
	end
	

	--Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
	--Dprint( DEBUG_UNIT_SCRIPT, "-- Stats in Combat #"..tostring(combatCount))
	--Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")

	-- Update some stats
	if attacker.IsUnit and defender.Dead then attacker.unitData.TotalKill = attacker.unitData.TotalKill + defender.Dead end
	if defender.IsUnit and attacker.Dead then defender.unitData.TotalKill = defender.unitData.TotalKill + attacker.Dead end

	if attacker.IsUnit and defender.IsUnit then
		local turn = Game.GetCurrentGameTurn()
		attacker.unitData.LastCombatTurn = turn
		defender.unitData.LastCombatTurn = turn

		attacker.unitData.LastCombatResult = defender[CombatResultParameters.DAMAGE_TO] - attacker[CombatResultParameters.DAMAGE_TO]
		defender.unitData.LastCombatResult = attacker[CombatResultParameters.DAMAGE_TO] - defender[CombatResultParameters.DAMAGE_TO]

		attacker.unitData.LastCombatType = combatType
		defender.unitData.LastCombatType = combatType
	end
	

	--Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
	--Dprint( DEBUG_UNIT_SCRIPT, "-- Plundering in Combat #"..tostring(combatCount))
	--Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")

	-- Plundering (with some bonuses to attack)
	if defender.IsLandUnit and combatType == CombatTypes.MELEE then -- and attacker.IsLandUnit (allow raiding on coast ?)

		if defender.IsDead and attacker.unit then

			attacker.Prisoners 			= defender.Captured + defender.unitData.WoundedPersonnel -- capture all the wounded (to do : add prisonners from enemy nationality here)
			attacker.MaterielGained 	= GetMaterielFromKillOfBy(defender, attacker)
			attacker.HorsesGained 		= math.floor(defender.HorsesLost * attackerMaterielGainPercent / 100) + math.floor(defender.unitData.Horses * attackerMaterielKillPercent /100)
			attacker.LiberatedPrisoners = GCO.GetTotalPrisoners(defender.unitData) 	-- to do : recruit only some of the enemy prisonners and liberate own prisonners
			attacker.FoodGained 		= math.floor(defender.unitData.FoodStock * tonumber(GameInfo.GlobalParameters["COMBAT_ATTACKER_FOOD_KILL_PERCENT"].Value) / 100)
			attacker.EquipmentGained 	= {}
			for equipmentKey, value in pairs(defender.EquipmentLost) do
				local fromCombat		= value * attackerMaterielGainPercent / 100
				local equipmentID		= tonumber(equipmentKey)
				local equipmentClassID	= GetUnitEquipmentClass(defender.unitType, equipmentID)
				local equipmentClassKey	= tostring(equipmentClassID)
				local fromReserve		= defender.unitData.Equipment[equipmentClassKey][equipmentKey] * attackerMaterielKillPercent / 100
				local equipmentGained	= math.floor(fromCombat + fromReserve)
				
				attacker.EquipmentGained[equipmentKey] = equipmentGained
				
				-- Update composition
				if attacker.unit:IsEquipment(equipmentID) then -- maybe a bit faster than letting unit:ChangeStock() handle the distribution
					attacker.unit:ChangeReserveEquipment(equipmentID, equipmentGained, equipmentClassID)
				else
					attacker.unit:ChangeStock(equipmentID, equipmentGained)
				end
			end
			
			-- Update composition
			defender.unitData.WoundedPersonnel 	= 0 -- Just to keep things clean...
			defender.unitData.FoodStock 		= GCO.ToDecimals(defender.unitData.FoodStock - attacker.FoodGained) -- Just to keep things clean...
			attacker.unit:ChangeComponent("MaterielReserve", attacker.MaterielGained)
			attacker.unit:ChangeComponent("PersonnelReserve", attacker.LiberatedPrisoners)
			attacker.unit:ChangeComponent("FoodStock", attacker.FoodGained)
			-- To do : prisonners by nationality
			attacker.unitData.Prisoners[defender.playerID]	= attacker.unitData.Prisoners[defender.playerID] + attacker.Prisoners

		else
			-- attacker
			if attacker.unit then
				attacker.Prisoners 			= defender.Captured
				attacker.MaterielGained 	= math.floor(defender.MaterielLost * attackerMaterielGainPercent /100)
				attacker.HorsesGained 		= math.floor(defender.HorsesLost * attackerMaterielGainPercent / 100)
				
				attacker.EquipmentGained 	= {}
				for equipmentKey, value in pairs(defender.EquipmentLost) do
					local equipmentID		= tonumber(equipmentKey)
					local equipmentGained	= math.floor(value * attackerMaterielGainPercent / 100)
					
					attacker.EquipmentGained[equipmentKey] = equipmentGained
					
					-- Update composition
					if attacker.unit:IsEquipment(equipmentID) then -- maybe a bit faster to check here than letting unit:ChangeStock() handle the distribution ?
						attacker.unit:ChangeReserveEquipment(equipmentID, equipmentGained)
					else
						attacker.unit:ChangeStock(equipmentID, equipmentGained) -- captured equipment that can't be used by the attacker will be placed in "stock"
					end
				end
			
				attacker.unit:ChangeStock(materielResourceID, attacker.MaterielGained)
				attacker.unit:ChangeStock(horsesResourceID, attacker.HorsesGained)
				
				attacker.unitData.Prisoners[defender.playerID]	= attacker.unitData.Prisoners[defender.playerID] + attacker.Prisoners
			end
			
			-- defender
			if defender.unit then
				defender.Prisoners 			= attacker.Captured
				defender.MaterielGained 	= math.floor(attacker.MaterielLost * defenderMaterielGainPercent / 100)
				defender.HorsesGained 		= math.floor(defender.HorsesLost * defenderMaterielGainPercent / 100)
				
				defender.EquipmentGained 	= {}
				for equipmentKey, value in pairs(defender.EquipmentLost) do
					local equipmentID		= tonumber(equipmentKey)
					local equipmentGained	= math.floor(value * defenderMaterielGainPercent / 100)
					
					defender.EquipmentGained[equipmentKey] = equipmentGained
					
					-- Update composition
					if defender.unit:IsEquipment(equipmentID) then -- maybe a bit faster than letting unit:ChangeStock() handle the distribution ?
						defender.unit:ChangeReserveEquipment(equipmentID, equipmentGained)
					else
						defender.unit:ChangeStock(equipmentID, equipmentGained) -- captured equipment that can't be used by the defender will be placed in "stock" (and then send in linked city)
					end
				end
				
				defender.unit:ChangeStock(materielResourceID, defender.MaterielGained)
				defender.unit:ChangeStock(horsesResourceID, defender.HorsesGained)
				defender.unitData.Prisoners[attacker.playerID]	= defender.unitData.Prisoners[attacker.playerID] + defender.Prisoners
			end
		end

	end
	
	-- Update unit's flag & visualize for attacker
	if attacker.unit then
		ShowCombatPlunderingFloatingText(attacker)
		LuaEvents.UnitsCompositionUpdated(attacker.playerID, attacker.unitID)
	end

	-- Update unit's flag & visualize for defender
	if defender.unit then
		ShowCombatPlunderingFloatingText(defender)
		LuaEvents.UnitsCompositionUpdated(defender.playerID, defender.unitID)
	end
	
	---[[
	Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
	Dprint( DEBUG_UNIT_SCRIPT, "-- Control in Combat #"..tostring(combatCount))
	Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
		
	if attacker.IsUnit and not attacker.IsDead then CheckComponentsHP(attacker.unit, "attacker after combat") end
	if defender.IsUnit and not defender.IsDead then CheckComponentsHP(defender.unit, "defender after combat") end		
	
	function p(table)
		 for k, v in pairs(table) do
			 if type(k) == "string" and type(v) ~= "table" then Dprint( DEBUG_UNIT_SCRIPT, k,v); end
		end;
	end
--[[
	Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
	Dprint( DEBUG_UNIT_SCRIPT, "-- Ending Combat #"..tostring(combatCount))
	Dprint( DEBUG_UNIT_SCRIPT, "--++++++++++++++++++++++--")
	Dprint( DEBUG_UNIT_SCRIPT, "-  ATTACKER -")
	Dprint( DEBUG_UNIT_SCRIPT, "--+++++++++--")
	p(attacker)
	Dprint( DEBUG_UNIT_SCRIPT, "--+++++++++--")
	Dprint( DEBUG_UNIT_SCRIPT, "-  DEFENDER -")
	Dprint( DEBUG_UNIT_SCRIPT, "--+++++++++--")
	p(defender)
	Dprint( DEBUG_UNIT_SCRIPT, "-----------------------------------------------------------------------------------------")
	--]]
	
end
Events.Combat.Add( OnCombat )


-----------------------------------------------------------------------------------------
-- Healing
-----------------------------------------------------------------------------------------
function HealingUnits(playerID)
	Dlog("HealingUnits /START")
	local DEBUG_UNIT_SCRIPT = true

	local player 		= Players[playerID]
	local playerConfig 	= PlayerConfigurations[playerID]
	local playerUnits 	= player:GetUnits()
	
	if playerUnits then
		Dprint( DEBUG_UNIT_SCRIPT, "-----------------------------------------------------------------------------------------")
		Dprint( DEBUG_UNIT_SCRIPT, "Healing units for " .. tostring(Locale.Lookup(playerConfig:GetCivilizationShortDescription())))

		local startTime = Automation.GetTime()
		for i, unit in playerUnits:Members() do
			unit:Heal()
		end

		local endTime = Automation.GetTime()
		Dprint( DEBUG_UNIT_SCRIPT, "-----------------------------------------------------------------------------------------")
		Dprint( DEBUG_UNIT_SCRIPT, "Healing units used " .. tostring(endTime-startTime) .. " seconds")
		Dprint( DEBUG_UNIT_SCRIPT, "-----------------------------------------------------------------------------------------")
	end
	Dlog("HealingUnits /END")
end

function GetHP(self)
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	if unitData then
		return unitData.HP
	else
		GCO.Error("Trying to get HP but unitData is nil for "..Locale.Lookup(GameInfo.Units[self:GetType()].Name).." id#".. tostring(unitKey).." player#"..tostring(self:GetOwner()))
		return 0
	end	
end

function SetHP(self, value)
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	if unitData then
		unitData.HP = value
	else
		GCO.Error("Trying to set HP but unitData is nil for "..Locale.Lookup(GameInfo.Units[self:GetType()].Name).." id#".. tostring(unitKey).." player#"..tostring(self:GetOwner()))
	end	
end

function Heal(self)

	if self:GetDamage() == 0 then return end

	local DEBUG_UNIT_SCRIPT = true
	Dprint( DEBUG_UNIT_SCRIPT, "-----------------------------------------------------------------------------------------")
	Dprint( DEBUG_UNIT_SCRIPT, "Healing " .. Locale.Lookup(self:GetName()).." id#".. tostring(self:GetKey()).." player#"..tostring(self:GetOwner()))
	
	local unitKey = self:GetKey()
	--[[
	if UnitDelayedHealing[unitKey] and UnitDelayedHealing[unitKey] < Game.GetCurrentGameTurn() then
		GCO.Warning("Unit with desynchronized data wasn't healed during the previous turn :[NEWLINE]"..Locale.Lookup(self:GetName()).." id#".. tostring(self:GetKey()).." player#"..tostring(self:GetOwner()).." prevTurn = "..tostring(unitDelayedHealing[unitKey]).." currTurn = "..tostring(Game.GetCurrentGameTurn()))
	end
	
	if (not CheckComponentsHP(self, "bypassing healing")) then
		if ExposedMembers.UnitData[unitKey] then
			UnitDelayedHealing[unitKey] = Game.GetCurrentGameTurn()
			GCO.Warning("desynchronized data in HealingUnits() for :[NEWLINE]"..Locale.Lookup(GameInfo.Units[self:GetType()].Name).." id#".. tostring(unitKey).." player#"..tostring(self:GetOwner()))
			ExposedMembers.UI.LookAtPlot(self:GetX(), self:GetY(), 0.3)
			--print("WARNING: desynchronized data in HealingUnits() for unit: "..Locale.Lookup(GameInfo.Units[self:GetType()].Name).." id#".. tostring(unitKey).." player#"..tostring(self:GetOwner()))
		end
		return
	end
	--]]
	
	local unitData = ExposedMembers.UnitData[unitKey]
	if not unitData then 
		print ("WARNING, no entry for " .. Locale.Lookup(self:GetName()) .. " id#" .. tostring(self:GetKey()))
		return
	end
	
	--UnitDelayedHealing[unitKey] = nil

	local restoredHP 		= 0 	-- HP gained to apply en masse after all reinforcements are calculated (visual fix)
	local maxTransfer 		= self:GetMaxTransferTable()	-- maximum value of a component that can be used to heal in one turn
	local alreadyUsed 		= {}	-- materiel is used both to heal the unit (reserve -> front) and repair Equipment in reserve, up to a limit
	alreadyUsed.Materiel 	= 0
	local damage 			= self:GetDamage()
	local initialHP 		= self:GetHP() --maxHP - damage
	local hasReachedLimit 	= false
	local unitInfo 			= GameInfo.Units[self:GetType()]
	local hitPoints 		= UnitHitPointsTable[unitInfo.Index]

	-- try to reinforce the selected Units (move personnel, vehicule, horses, materiel from reserve to frontline)
	-- up to MAX_HP_HEALED (or an self component limit), 1hp per loop
	for healHP = 1, GameInfo.GlobalParameters["UNIT_MAX_HP_HEALED_FROM_RESERVE"].Value do -- to do : add limit by Units in the loop
		if not hasReachedLimit then
			if (initialHP + restoredHP < maxHP) then
				local loopHP = initialHP + restoredHP + 1
				-- check here if the unit has enough reserves to get +1HP
				local reqPersonnel 	= hitPoints[loopHP].Personnel - hitPoints[initialHP].Personnel
				if reqPersonnel > tonumber(maxTransfer.Personnel) then
					hasReachedLimit = true
					Dprint( DEBUG_UNIT_SCRIPT, "- Reached healing limit for " .. Locale.Lookup(self:GetName()) .. " at " .. tostring(healHP) ..", Personnel Requirements = ".. tostring(reqPersonnel) .. ", Max transferable per turn = ".. tostring(maxTransfer.Personnel))

				else
					local reqMateriel 	= hitPoints[loopHP].Materiel 	- hitPoints[initialHP].Materiel
					if reqMateriel > tonumber(maxTransfer.Materiel) then
						hasReachedLimit = true
						Dprint( DEBUG_UNIT_SCRIPT, "- Reached healing limit for " .. Locale.Lookup(self:GetName()) .. " at " .. tostring(healHP) ..", Materiel Requirements = " .. tostring(reqMateriel) .. ", Max transferable per turn = ".. tostring(maxTransfer.Materiel) )
					
					else
						if unitData.PersonnelReserve 	< reqPersonnel 	then hasReachedLimit = true end
						if unitData.MaterielReserve 	< reqMateriel 	then hasReachedLimit = true end											
						if unitData.HorsesReserve 		< (hitPoints[loopHP].Horses - hitPoints[initialHP].Horses) then hasReachedLimit = true end
							
						for equipmentClassKey, equipmentData in pairs(unitData.Equipment) do
							local equipmentClassID 	= tonumber(equipmentClassKey)
							if self:IsRequiringEquipmentClass(equipmentClassID) then 	-- required equipment follow exactly the selfHitPoints table								
								if self:GetEquipmentClassReserve(equipmentClassID) < hitPoints[loopHP].EquipmentClass[equipmentClassID] - hitPoints[initialHP].EquipmentClass[equipmentClassID] then
									hasReachedLimit = true
								end
							end
						end
					end
				end

				if not hasReachedLimit then
					restoredHP = restoredHP + 1 -- store +1 HP for this self
				end
			end
		end
	end
	
	CheckComponentsHP(self, "before Healing")

	local finalHP 					= initialHP + restoredHP
	unitData.HP 					= finalHP
	UnitLastHealingValue[unitKey] 	= restoredHP
	unitData.UnitLastHealingValue 	= restoredHP
	
	if finalHP < initialHP then
		GCO.Error("finalHP < initialHP for ", unitKey, " initialHP:", initialHP , " finalHP:", finalHP, " restoredHP :", restoredHP)
	end		
	Dprint( DEBUG_UNIT_SCRIPT, "initialHP = ", initialHP , " finalHP = ", finalHP, " restoredHP = ", restoredHP, " core initialHP = ", maxHP - damage, " core finalHP = ", maxHP - damage + restoredHP)
				
	self:SetDamage(damage-restoredHP)
	
	-- update reserve and frontline...
	local reqPersonnel 	= hitPoints[finalHP].Personnel 	- hitPoints[initialHP].Personnel
	local reqHorses 	= hitPoints[finalHP].Horses 	- hitPoints[initialHP].Horses
	local reqMateriel 	= hitPoints[finalHP].Materiel 	- hitPoints[initialHP].Materiel
	local reqEquipment 	= {}
	
	unitData.PersonnelReserve 	= unitData.PersonnelReserve - reqPersonnel
	unitData.HorsesReserve 		= unitData.HorsesReserve 	- reqHorses
	unitData.MaterielReserve 	= unitData.MaterielReserve 	- reqMateriel

	unitData.Personnel 	= unitData.Personnel 	+ reqPersonnel
	unitData.Horses 	= unitData.Horses 		+ reqHorses
	unitData.Materiel 	= unitData.Materiel 	+ reqMateriel
	
	for equipmentClassKey, equipmentData in pairs(unitData.Equipment) do
		local equipmentClassID 	= tonumber(equipmentClassKey)
		if self:IsRequiringEquipmentClass(equipmentClassID) then
			local required	 			= hitPoints[finalHP].EquipmentClass[equipmentClassID] - hitPoints[initialHP].EquipmentClass[equipmentClassID]
			local equipmentTypes 		= GetEquipmentTypes(equipmentClassID)						
			local numEquipmentToProvide	= required						
			for _, data in ipairs(equipmentTypes) do							
				if numEquipmentToProvide > 0 then
					local equipmentID 		= data.EquipmentID
					local equipmentReserve 	= self:GetReserveEquipment(equipmentID, equipmentClassID)
					local equipmentUsed		= 0
					if equipmentReserve >= numEquipmentToProvide then
						equipmentUsed 			= numEquipmentToProvide
						numEquipmentToProvide	= 0
					else
						equipmentUsed 			= equipmentReserve
						numEquipmentToProvide	= numEquipmentToProvide - equipmentReserve
					end
					if equipmentUsed > 0 then
						reqEquipment[equipmentID] = equipmentUsed
						self:ChangeReserveEquipment(equipmentID, -equipmentUsed, equipmentClassID)
						self:ChangeFrontLineEquipment(equipmentID, equipmentUsed, equipmentClassID)								
					end
				end
			end						
		end
	end
	
	alreadyUsed.Materiel = reqMateriel

	-- Visualize healing
	local healingData = {reqPersonnel = reqPersonnel, reqMateriel = reqMateriel, reqHorses = reqHorses, X = self:GetX(), Y = self:GetY() } --reqEquipment = reqEquipment, 
	ShowFrontLineHealingFloatingText(healingData)
	
	CheckComponentsHP(self, "after Healing")

	-- try to heal wounded and repair Equipment using materiel (move healed personnel and repaired Equipment to reserve)	

	-- hardcoding and magic numbers everywhere, to do : era, promotions, support					
	-- check available medicine...
	local availableMedicine = unitData.MedicineStock
	
	-- get the number of wounded that may heal or die this turn
	local woundedToHandle	= GCO.Round(math.min(unitData.WoundedPersonnel, math.max(20,unitData.WoundedPersonnel * 50/100)))
	
	-- wounded soldiers may die...
	local potentialDeads 	= GCO.Round(woundedToHandle / 2)
	local savedWithMedicine	= math.min(availableMedicine*10, GCO.Round(potentialDeads/2))
	local medicineUsed		= math.ceil(savedWithMedicine/10)
	
	local deads				= potentialDeads - savedWithMedicine
	availableMedicine		= availableMedicine - medicineUsed
	
	unitData.WoundedPersonnel 	= unitData.WoundedPersonnel - deads
	--unitData.TotalDeath			= unitData.TotalDeath 		+ deads	-- Update Stats

	-- wounded soldiers may heal...
	local potentialHealed 		= woundedToHandle - potentialDeads
	local healedDirectly		= GCO.Round(potentialHealed/2)
	local healedWithMedicine	= math.min(availableMedicine*10, potentialHealed - healedDirectly )
	medicineUsed				= medicineUsed + math.ceil(healedWithMedicine/10)
	
	local healed 				= healedDirectly + healedWithMedicine
	
	unitData.WoundedPersonnel = unitData.WoundedPersonnel - healed
	unitData.PersonnelReserve = unitData.PersonnelReserve + healed
	
	-- remove used medicine
	if unitData.MedicineStock - medicineUsed < 0 then
		print ("WARNING : used more medicine than available, initial stock = ".. tostring(unitData.MedicineStock) ..", used =".. tostring(medicineUsed)..", wounded to treat = ".. tostring(woundedToHandle))
		Dprint( DEBUG_UNIT_SCRIPT, "deads = ", deads, " healed = ", healed, " potentialDeads = ", potentialDeads, " savedWithMedicine = ", savedWithMedicine, " potentialHealed = ", potentialHealed, " healedDirectly = ", healedDirectly, " requiredMedicine = ", requiredMedicine)
	end
	unitData.MedicineStock = math.max(0, unitData.MedicineStock - medicineUsed)

	-- try to repair vehicles with materiel available left (= logistic/maintenance limit)
	local repairedEquipment = 0
	--[[
	if unitData.MaterielPerEquipment > 0 then
		local materielAvailable = maxTransfer.Materiel - alreadyUsed.Materiel
		local maxRepairedEquipment = GCO.Round(materielAvailable/(unitData.MaterielPerEquipment* GameInfo.GlobalParameters["self_MATERIEL_TO_REPAIR_VEHICLE_PERCENT"].Value/100))
		local repairedEquipment = 0
		if maxRepairedEquipment > 0 then
			repairedEquipment = math.min(maxRepairedEquipment, unitData.DamagedEquipment)
			unitData.DamagedEquipment = unitData.DamagedEquipment - repairedEquipment
			unitData.EquipmentReserve = unitData.EquipmentReserve + repairedEquipment
		end
	end
	--]]

	-- Visualize healing
	local healingData = {deads = deads, healed = healed, repairedEquipment = repairedEquipment, X = self:GetX(), Y = self:GetY() }
	ShowReserveHealingFloatingText(healingData)
	
	-- when called from GameEvents.PlayerTurnStarted() this makes the game crash at self.m_Instance.selfIcon:SetToolTipString( Locale.Lookup(nameString) ) in selfFlagManager
	LuaEvents.UnitsCompositionUpdated(playerID, self:GetID()) -- call to update flag	
end

function HealingControl (playerID, unitID, newDamage, prevDamage)
	local unit = UnitManager.GetUnit(playerID, unitID)
	if unit then
		local unitKey 	= unit:GetKey()
		local data 		= ExposedMembers.UnitData[unitKey]
		local testHP 	= unit:GetMaxDamage() - unit:GetDamage()
		local value		= testHP - data.testHP
		local change	= prevDamage - newDamage
		Dprint( DEBUG_UNIT_SCRIPT, "--------------------------------------- UnitDamageChanged ---------------------------------------")
		Dprint( DEBUG_UNIT_SCRIPT, "changing HP of unit "..tostring(GameInfo.Units[unit:GetType()].UnitType).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner()))
		Dprint( DEBUG_UNIT_SCRIPT, "previous Core HP .... =", data.testHP)
		Dprint( DEBUG_UNIT_SCRIPT, "current Core HP ..... =", testHP)
		Dprint( DEBUG_UNIT_SCRIPT, "core HP change ...... =", value)
		Dprint( DEBUG_UNIT_SCRIPT, "current HP change ... =", change)
		Dprint( DEBUG_UNIT_SCRIPT, "pending Heal ........ =", UnitLastHealingValue[unitKey])
		Dprint( DEBUG_UNIT_SCRIPT, "last Heal ........... =", data.UnitLastHealingValue)
		Dprint( DEBUG_UNIT_SCRIPT, "newDamage, prevDamage =", newDamage, prevDamage)
		Dprint( DEBUG_UNIT_SCRIPT, "------------------------------------------------------------------------------")
		data.testHP = testHP		
		
		if change > 0 and UnitLastHealingValue[unitKey] ~= change then -- that unit has received health outside the mod control (like when pillaging, hardcoding is bad Firaxis, bad !)
			--ExposedMembers.UI.LookAtPlot(unit:GetX(), unit:GetY(), 0.3)
			local plot = Map.GetPlot(unit:GetX(), unit:GetY())
			Dprint( DEBUG_UNIT_SCRIPT, "Reverting unexpected healing : +"..tostring(change).." HP for "..tostring(GameInfo.Units[unit:GetType()].UnitType).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner()), ", in city = ", plot:IsCity())
			unit:SetDamage(prevDamage)
		--elseif UnitDelayedHealing[unitKey] then -- now that combat damage has been applied, try to heal units marked for delayed healing again (the Heal function will check for desync again)
		--	unit:Heal()
		--	return
		end
		if change == UnitLastHealingValue[unitKey] then		
			Dprint( DEBUG_UNIT_SCRIPT, "Marking pending healing done for "..Locale.Lookup(unit:GetName()).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner()))
			UnitLastHealingValue[unitKey] = nil
		end
	end
end
Events.UnitDamageChanged.Add(HealingControl)

function CheckComponentsHP(unit, str, bNoWarning)
	local DEBUG_UNIT_SCRIPT = true
	
	if not unit then
		print ("WARNING : unit is nil in CheckComponentsHP() for " .. tostring(str))
		return
	end
	
	local unitType 	= unit:GetType()
	local key 		= unit:GetKey()
	local unitData 	= ExposedMembers.UnitData[key]
	
	if not unitData then
		print ("WARNING : unitData is nil in CheckComponentsHP() for " .. tostring(str))
		return
	end	
	
	local coreHP 	= unit:GetMaxDamage() - unit:GetDamage()
	local virtualHP = unit:GetHP()
	
	function debug(unit, HP, str, bNoWarning, hitPoint)
		Dprint( DEBUG_UNIT_SCRIPT, "---------------------------------------------------------------------------")
		Dprint( DEBUG_UNIT_SCRIPT, "in CheckComponentsHP() for " .. tostring(str))
		if bNoWarning then
			Dprint( DEBUG_UNIT_SCRIPT, "SHOWING : For "..tostring(GameInfo.Units[unit:GetType()].UnitType).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner()))
		else
			print ("WARNING : For "..tostring(GameInfo.Units[unit:GetType()].UnitType).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner()))
		end
		Dprint( DEBUG_UNIT_SCRIPT, "key = ", key, " unitType = ", unitType, " GameCore HP = ", coreHP, " Virtual HP = ", virtualHP, " testing at HP = ", HP, " last Heal = ", unitData.UnitLastHealingValue)
		Dprint( DEBUG_UNIT_SCRIPT, "UnitData[key].Personnel .. =", unitData.Personnel, 	" HitPointsTable[HP].Personnel .. =", hitPoint.Personnel)
		Dprint( DEBUG_UNIT_SCRIPT, "UnitData[key].Horses ..... =", unitData.Horses, 	" HitPointsTable[HP].Horses ..... =", hitPoint.Horses)
		Dprint( DEBUG_UNIT_SCRIPT, "UnitData[key].Materiel ... =", unitData.Materiel, 	" HitPointsTable[HP].Materiel ... =", hitPoint.Materiel)
		
		for equipmentClassKey, equipmentData in pairs(unitData.Equipment) do
			local equipmentClassID 	= tonumber(equipmentClassKey)
			if unit:IsRequiringEquipmentClass(equipmentClassID) then 	-- required equipment follow exactly the UnitHitPoints table
				Dprint( DEBUG_UNIT_SCRIPT, "UnitData[key].EquipmentClass[".. Locale.Lookup(GameInfo.EquipmentClasses[tonumber(equipmentClassKey)].Name), "] = ", unit:GetEquipmentClassFrontLine(equipmentClassID), " HitPointsTable[HP].EquipmentClass[equipmentClassID] = ", hitPoint.EquipmentClass[equipmentClassID])
			end
		end
		Dprint( DEBUG_UNIT_SCRIPT, "---------------------------------------------------------------------------")
	end
	
	function CheckComponentsSynchronizedHP(unit, HP, str, bNoWarning)	
	
		local hitPoint = ExposedMembers.UnitHitPointsTable[unitType][HP]
		local bEquipmentCheckFail = false
		for equipmentClassKey, equipmentData in pairs(unitData.Equipment) do
			local equipmentClassID 	= tonumber(equipmentClassKey)
			if unit:IsRequiringEquipmentClass(equipmentClassID) then 	-- required equipment follow exactly the UnitHitPoints table								
				if unit:GetEquipmentClassFrontLine(equipmentClassID) ~= hitPoint.EquipmentClass[equipmentClassID] then
					bEquipmentCheckFail = true
				end
			end
		end	
		
		if 		unitData.Personnel 	~= hitPoint.Personnel 
			or 	bEquipmentCheckFail  
			or 	unitData.Horses		~= hitPoint.Horses	 
			or 	unitData.Materiel 	~= hitPoint.Materiel 
		then 
			debug(unit, HP, str, bNoWarning, hitPoint)
			return false
		end		
		Dprint( DEBUG_UNIT_SCRIPT, str .. " : OK For "..tostring(GameInfo.Units[unit:GetType()].UnitType).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner()))
		return true
	end

	local bIsCoreSynchronized = CheckComponentsSynchronizedHP(unit, coreHP, str .. " for Core synchronization", bNoWarning)
	local bIsDataSynchronized = CheckComponentsSynchronizedHP(unit, virtualHP, str .. " for Data consistency", bNoWarning)
	
	if not bIsDataSynchronized then GCO.Error("Data inconsistency detected for :[NEWLINE] "..Locale.Lookup(unit:GetName()).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner())) end
	
	return bIsCoreSynchronized and bIsDataSynchronized
end

-- Handle pillage healing
-- (Deprecated by HealingControl based on last healing value)
local PillagingUnit = nil
function MarkUnitOnPillage(playerID, unitID)
	local unit = UnitManager.GetUnit(playerID, unitID)
	local testHP = unit:GetMaxDamage() - unit:GetDamage()
	local unitKey = unit:GetKey()
	if ExposedMembers.UnitData[unitKey] then
		Dprint( DEBUG_UNIT_SCRIPT, "Marking unit on pillage : ", playerID, unitID, unit:GetDamage(), testHP, ExposedMembers.UnitData[unitKey].HP)
	else
		GCO.Error("ExposedMembers.UnitData[unitKey] is nil when marking unit on pillage : ", playerID, unitID, unit:GetDamage(), testHP, unitKey)
	end
	PillagingUnit = unit
end
GameEvents.OnPillage.Add(MarkUnitOnPillage)

--[[
function DamageChanged (playerID, unitID, newDamage, prevDamage)
	local unit = UnitManager.GetUnit(playerID, unitID)
	if unit and unit == PillagingUnit then
		PillagingUnit = nil
		local testHP = unit:GetMaxDamage() - unit:GetDamage()
		local unitKey = unit:GetKey()
		Dprint( DEBUG_UNIT_SCRIPT, "Handling Damage Changed for pillaging unit : ", playerID, unitID, unit:GetDamage(), testHP, ExposedMembers.UnitData[unitKey].HP, newDamage, prevDamage)
		unit:SetDamage(prevDamage)
		Dprint( DEBUG_UNIT_SCRIPT, "Damage restored to ", unit:GetDamage() )
	end
end
Events.UnitDamageChanged.Add(DamageChanged)
--]]

-----------------------------------------------------------------------------------------
-- Supply Lines
-----------------------------------------------------------------------------------------
-- cf Worldinput.lua
--pathPlots, turnsList, obstacles = UnitManager.GetMoveToPath( kUnit, endPlotId )

function GetSupplyPathPlots(self)
	local unitKey 	= self:GetKey()
	local unitData 	= ExposedMembers.UnitData[unitKey]
	local timer = Automation.GetTime()
	while not unitData do -- this prevent a "trying to index nil" error on the following line... is it linked to the script/UI not being synchronized ?
		unitData 	= ExposedMembers.UnitData[unitKey]
		if Automation.GetTime() + 0.5 > timer then
			print("- WARNING : unitData= ExposedMembers.UnitData[unitKey] is nil for unit ".. tostring(self:GetName()) .." (key = ".. tostring(key) ..") in GetSupplyPathPlots()")
			print("- ExposedMembers.UnitData[unitKey] =  ".. tostring(ExposedMembers.UnitData[unitKey]) .." unitData = ".. unitData)
			unitData 	= ExposedMembers.UnitData[unitKey]
			if not unitData then return else break end
		end
	end 
	if unitData.SupplyLineCityKey then
		local city = GCO.GetCityFromKey( unitData.SupplyLineCityKey )
		if city then
			local cityPlot = Map.GetPlot(city:GetX(), city:GetY())
			local bShortestRoute = true
			local bIsPlotConnected = GCO.IsPlotConnected(Players[self:GetOwner()], Map.GetPlot(self:GetX(), self:GetY()), cityPlot, "Land", bShortestRoute, nil, GCO.SupplyPathBlocked)
			if bIsPlotConnected then
				return GCO.GetRoutePlots()
			end
		end
	end
end 

function SetSupplyLine(self)
	Dlog("SetSupplyLine /START")
	local key 			= self:GetKey()
	local NoLinkToCity 	= true
	local unitData 		= ExposedMembers.UnitData[key]
	local closestCity, distance = GCO.FindNearestPlayerCity( self:GetOwner(), self:GetX(), self:GetY() )
	if closestCity then
		GCO.AttachCityFunctions(closestCity)
		local cityPlot = Map.GetPlot(closestCity:GetX(), closestCity:GetY())
		--[[
		local pathPlots, turnsList, obstacles = GCO.GetMoveToPath( unit, cityPlot:GetIndex() ) -- can't be used as it takes unit stacking in account and return false if there is an unit in the city.
		if table.count(pathPlots) > 1 then
			local numTurns = turnsList[table.count( turnsList )]
			local efficiency = GCO.Round( 100 - math.pow(numTurns,2) )
			if efficiency > 50 then -- to do : allow players to change this value
				unitData.SupplyLineCityKey = GCO.GetCityKey(closestCity)
				unitData.SupplyLineCityOwner = closestCity:GetOwner()
				unitData.SupplyLineEfficiency = efficiency
				NoLinkToCity = false
			end
		--]]
		local bShortestRoute = true
		local bIsPlotConnected = GCO.IsPlotConnected(Players[self:GetOwner()], Map.GetPlot(self:GetX(), self:GetY()), cityPlot, "Land", bShortestRoute, nil, GCO.SupplyPathBlocked)
		local routeLength = GCO.GetRouteLength()
		if bIsPlotConnected then
			local efficiency = GCO.GetRouteEfficiency(routeLength*SupplyLineLengthFactor)
			if efficiency > 0 then
				unitData.SupplyLineCityKey = closestCity:GetKey()
				unitData.SupplyLineEfficiency = efficiency
				NoLinkToCity = false
			else
				unitData.SupplyLineCityKey = closestCity:GetKey()
				unitData.SupplyLineEfficiency = 0
				NoLinkToCity = false
			end
		
		elseif distance == 0 then -- unit is on the city's plot...
			unitData.SupplyLineCityKey = closestCity:GetKey()
			unitData.SupplyLineEfficiency = 100
			NoLinkToCity = false
		end
	end
	
	if NoLinkToCity then
		unitData.SupplyLineCityKey = nil
		unitData.SupplyLineEfficiency = 0
	end
	Dlog("SetSupplyLine /END")
end

function GetSupplyLineEfficiency(self)
	local unitKey = self:GetKey()
	return ExposedMembers.UnitData[unitKey].SupplyLineEfficiency or 0
end

function OnUnitMoveComplete(playerID, unitID, iX, iY)
	local unit = UnitManager.GetUnit(playerID, unitID)
	if unit then
		unit:SetSupplyLine()
		LuaEvents.UnitsCompositionUpdated(playerID, unitID)
	end
end
Events.UnitMoveComplete.Add(OnUnitMoveComplete)


-----------------------------------------------------------------------------------------
-- Do Turn for Units
-----------------------------------------------------------------------------------------
function UpdateDataOnNewTurn(self) -- called for every player at the beginning of a new turn
	
	Dlog("UpdateDataOnNewTurn for ".. Locale.Lookup(self:GetName()) ..", key = ".. tostring(self:GetKey()) .." /START")
	local DEBUG_UNIT_SCRIPT = false
	
	Dprint( DEBUG_UNIT_SCRIPT, "---------------------------------------------------------------------------")
	
	local unitKey 			= self:GetKey()	
	if not ExposedMembers.UnitData[unitKey] then
		Dprint( DEBUG_UNIT_SCRIPT, "Skipping (not initialized ?) :", Locale.Lookup(self:GetName())," key = ",unitKey)
		return
	end
	
	Dprint( DEBUG_UNIT_SCRIPT, "Updating Unit Data for ", Locale.Lookup(self:GetName())," key = ",unitKey)
	
	local unitData = ExposedMembers.UnitData[unitKey]
	
	-- Update basic components
	--local componentsToUpdate = {"Personnel","Equipment","Horses","Materiel","PersonnelReserve","EquipmentReserve","HorsesReserve","MaterielReserve","WoundedPersonnel","DamagedEquipment","FoodStock","FuelStock","Morale","MedicineStock"}
	local componentsToUpdate = {"Personnel","Horses","Materiel","PersonnelReserve","HorsesReserve","MaterielReserve","WoundedPersonnel","FoodStock","FuelStock","Morale","MedicineStock"}
		for _, component in ipairs(componentsToUpdate) do
		local previousComponent = "Previous"..tostring(component)
		local currentValue		= self:GetComponent(component)
		self:SetComponent(previousComponent, currentValue)
	end
	
	-- Update prisoners table	
	for playerKey, number in pairs(unitData.Prisoners) do
		ExposedMembers.UnitData[unitKey].PreviousPrisoners[playerKey] = number
	end
	
	-- Update equipment tables
	for equipmentClass, data in pairs(unitData.Equipment) do
		for equipmentType, value in pairs(data) do
			if not ExposedMembers.UnitData[unitKey].PreviousEquipment[equipmentClass] then
				ExposedMembers.UnitData[unitKey].PreviousEquipment[equipmentClass] = { [equipmentType] = value }
			else
				ExposedMembers.UnitData[unitKey].PreviousEquipment[equipmentClass][equipmentType] = value
			end
		end
	end	
	for equipmentClass, data in pairs(unitData.EquipmentReserve) do
		for equipmentType, value in pairs(data) do
			if not ExposedMembers.UnitData[unitKey].PreviousEquipmentReserve[equipmentClass] then
				ExposedMembers.UnitData[unitKey].PreviousEquipmentReserve[equipmentClass] = { [equipmentType] = value }
			else
				ExposedMembers.UnitData[unitKey].PreviousEquipmentReserve[equipmentClass][equipmentType] = value
			end
		end
	end	
	for equipmentClass, data in pairs(unitData.DamagedEquipment) do
		for equipmentType, value in pairs(data) do
			if not ExposedMembers.UnitData[unitKey].PreviousDamagedEquipment[equipmentClass] then
				ExposedMembers.UnitData[unitKey].PreviousDamagedEquipment[equipmentClass] = { [equipmentType] = value }
			else
				ExposedMembers.UnitData[unitKey].PreviousDamagedEquipment[equipmentClass][equipmentType] = value
			end
		end
	end
	
	Dlog("UpdateDataOnNewTurn /END")
end

function DoFood(self)

	Dlog("DoFood /START")
	local key = self:GetKey()
	local unitData = ExposedMembers.UnitData[key]
	
	if unitData.TurnCreated == Game.GetCurrentGameTurn() then return end -- don't eat on first turn

	-- Eat Food
	local foodEat = math.min(self:GetFoodConsumption(), unitData.FoodStock)

	-- Get Food
	local foodGet = 0
	local iX = self:GetX()
	local iY = self:GetY()
	local adjacentRatio = tonumber(GameInfo.GlobalParameters["FOOD_COLLECTING_ADJACENT_PLOT_RATIO"].Value)
	local yieldFood = GameInfo.Yields["YIELD_FOOD"].Index
	local maxFoodStock = self:GetMaxFoodStock()
	-- Get food from the plot
	local plot = Map.GetPlot(iX, iY)
	if plot then
		foodGet = foodGet + (plot:GetYield(yieldFood) / (math.max(1, Units.GetUnitCountInPlot(plot))))
	end
	-- Get food from adjacent plots
	for direction = 0, DirectionTypes.NUM_DIRECTION_TYPES - 1, 1 do
		adjacentPlot = Map.GetAdjacentPlot(iX, iY, direction);
		if (adjacentPlot ~= nil) and ((not adjacentPlot:IsOwned()) or adjacentPlot:GetOwner() == self:GetOwner() ) then
			foodGet = foodGet + ((adjacentPlot:GetYield(yieldFood) / (1 + Units.GetUnitCountInPlot(adjacentPlot))) * adjacentRatio)
		end
	end
	foodGet = math.max(0, math.min(maxFoodStock + foodEat - unitData.FoodStock, foodGet))
	foodGet = GCO.ToDecimals(foodGet)

	-- Update variation
	local foodVariation = foodGet - foodEat
	self:ChangeComponent("FoodStock", foodVariation)

	-- Visualize
	local foodData = { foodEat = foodEat, foodGet = foodGet, X = self:GetX(), Y = self:GetY() }
	ShowFoodFloatingText(foodData)
	Dlog("DoFood /END")
end

function DoMorale(self)
	Dlog("DoMorale /START")

	if not CheckComponentsHP(self, "bypassing DoMorale()") then
		return
	end
	
	local key = self:GetKey()
	local unitData = ExposedMembers.UnitData[key]
	local moraleVariation = 0
	
	moraleVariation = moraleVariation + self:GetMoraleFromFood()
	moraleVariation = moraleVariation + self:GetMoraleFromLastCombat()
	moraleVariation = moraleVariation + self:GetMoraleFromWounded()
	moraleVariation = moraleVariation + self:GetMoraleFromHP()
	moraleVariation = moraleVariation + self:GetMoraleFromHome()
	
	local morale = math.max(0, math.min(unitData.Morale + moraleVariation, tonumber(GameInfo.GlobalParameters["MORALE_BASE_VALUE"].Value)))
	unitData.Morale = morale
	--unitData.MoraleVariation = moraleVariation

	local desertionRate, minPercentHP, minPercentReserve = 0
	if morale < tonumber(GameInfo.GlobalParameters["MORALE_BAD_PERCENT"].Value) then -- very low morale
		desertionRate 		= tonumber(GameInfo.GlobalParameters["MORALE_BAD_DESERTION_RATE"].Value) --3
		minPercentHP 		= tonumber(GameInfo.GlobalParameters["MORALE_BAD_MIN_PERCENT_HP"].Value) --50
		minPercentReserve 	= tonumber(GameInfo.GlobalParameters["MORALE_BAD_MIN_PERCENT_RESERVE"].Value) --25
	elseif morale < tonumber(GameInfo.GlobalParameters["MORALE_LOW_PERCENT"].Value) then -- low morale
		desertionRate 		= tonumber(GameInfo.GlobalParameters["MORALE_LOW_DESERTION_RATE"].Value) --1
		minPercentHP 		= tonumber(GameInfo.GlobalParameters["MORALE_LOW_MIN_PERCENT_HP"].Value) --75
		minPercentReserve 	= tonumber(GameInfo.GlobalParameters["MORALE_LOW_MIN_PERCENT_RESERVE"].Value) --50
	end
	
	CheckComponentsHP(self, "In DoMorale(), desertion Rate = " .. tostring(desertionRate))
	if false then--desertionRate > 0 then -- to do : reactivate after writing the code to handle Equipment balance between front/reserve
		local HP = self:GetMaxDamage() - self:GetDamage()
		local unitType = self:GetType()
		local personnelReservePercent = GCO.Round( unitData.PersonnelReserve / self:GetMaxPersonnelReserve() * 100)
		local desertionData = {Personnel = 0, Equipment = 0, Horses = 0, Materiel = 0, GiveDamage = false, Show = false, X = self:GetX(), Y = self:GetY() }
		local lostHP = 0
		local finalHP = HP
		if HP > minPercentHP then
			lostHP = math.max(1, GCO.Round(HP * desertionRate / 100))
			finalHP = HP - lostHP

			-- Get desertion number
			desertionData.Personnel = UnitHitPointsTable[unitType][HP].Personnel 	- UnitHitPointsTable[unitType][finalHP].Personnel
			--desertionData.Equipment 	= UnitHitPointsTable[unitType][HP].Equipment 	- UnitHitPointsTable[unitType][finalHP].Equipment
			desertionData.Horses 	= UnitHitPointsTable[unitType][HP].Horses		- UnitHitPointsTable[unitType][finalHP].Horses
			desertionData.Materiel	= UnitHitPointsTable[unitType][HP].Materiel 	- UnitHitPointsTable[unitType][finalHP].Materiel

			-- Remove deserters from frontline
			unitData.Personnel 	= unitData.Personnel  	- desertionData.Personnel
			--unitData.Equipment  	= unitData.Equipment  	- desertionData.Equipment
			unitData.Horses		= unitData.Horses	  	- desertionData.Horses
			unitData.Materiel 	= unitData.Materiel 	- desertionData.Materiel

			-- Store materiel, vehicles, horses
			--unitData.EquipmentReserve  	= unitData.EquipmentReserve 	+ desertionData.Equipment
			unitData.HorsesReserve		= unitData.HorsesReserve	+ desertionData.Horses
			unitData.MaterielReserve 	= unitData.MaterielReserve 	+ desertionData.Materiel

			desertionData.GiveDamage = true
			desertionData.Show = true

		end
		if personnelReservePercent > minPercentReserve then
			local lostPersonnel = math.max(1, GCO.Round(unitData.PersonnelReserve * desertionRate / 100))

			-- Add desertion number
			desertionData.Personnel = desertionData.Personnel + lostPersonnel

			-- Remove deserters from reserve
			unitData.PersonnelReserve 	= unitData.PersonnelReserve	- lostPersonnel

			desertionData.Show = true

		end
		-- Visualize
		if desertionData.Show then
			ShowDesertionFloatingText(desertionData)
		end

		-- Set Damage
		if desertionData.GiveDamage then
			self:SetDamage(self:GetDamage() + lostHP)
			unitData.HP = finalHP
		end
	end
	CheckComponentsHP(self, "after DoMorale()")	
	Dlog("DoMorale /END")
end

function DoFuel(self)
	Dlog("DoFuel /START")

	local key = self:GetKey()
	local unitData = ExposedMembers.UnitData[key]
	local fuelConsumption = math.min(self:GetFuelConsumption(), unitData.FuelStock)
	if fuelConsumption > 0 then
		-- Update variation
		--unitData.PreviousFuelStock = unitData.FuelStock
		unitData.FuelStock = unitData.FuelStock - fuelConsumption
		-- Visualize
		local fuelData = { fuelConsumption = fuelConsumption, X = self:GetX(), Y = self:GetY() }
		ShowFuelConsumptionFloatingText(fuelData)
	end
	Dlog("DoFuel /END")
end

function DoTurn(self)
	local key = self:GetKey()
	if not unitData then
		return
	end
	local playerID = self:GetOwner()
	
	self:DoFood()
	self:DoMorale()
	self:DoFuel()
	self:SetSupplyLine()
end

function DoUnitsTurn( playerID )
	
	local DEBUG_UNIT_SCRIPT = true	
	Dprint( DEBUG_UNIT_SCRIPT, "---------------------------------------------------------------------------")
	Dprint( DEBUG_UNIT_SCRIPT, "Units turn")
	
	HealingUnits( playerID )

	local player = Players[playerID]
	local playerConfig = PlayerConfigurations[playerID]
	local playerUnits = player:GetUnits()
	if playerUnits then
		for i, unit in playerUnits:Members() do
			unit:DoTurn()
		end
	end	
	GCO.PlayerTurnsDebugChecks[playerID].UnitsTurn	= true
end
LuaEvents.DoUnitsTurn.Add( DoUnitsTurn )

function DoHealing( playerID )
	
	local DEBUG_UNIT_SCRIPT = true	
	Dprint( DEBUG_UNIT_SCRIPT, "---------------------------------------------------------------------------")
	Dprint( DEBUG_UNIT_SCRIPT, "Healing turn for ".. tostring(Locale.ToUpper(Locale.Lookup(PlayerConfigurations[playerID]:GetCivilizationShortDescription()))))
	
	HealingUnits( playerID )

end
--GameEvents.PlayerTurnStarted.Add(DoHealing)

-----------------------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------------------
local ProductionTypes = {
		UNIT		= 0,
		BUILDING	= 1,
		DISTRICT 	= 2
	}

function OnUnitProductionCompleted(playerID, cityID, productionID, objectID, bCanceled, typeModifier)
	local city = GCO.GetCity(playerID, cityID)
	if productionID ~= ProductionTypes.UNIT then
		return--if GameInfo.Buildings[objectID] and GameInfo.Buildings[objectID].Unlockers then return end
	end
	--print("OnCityProductionCompleted", Locale.Lookup(city:GetName()), playerID, cityID, productionID, objectID, bCanceled, typeModifier)
	Dlog("OnUnitProductionCompleted /START")
	local unitTypeName = GameInfo.Units[objectID].UnitType
	Dprint( DEBUG_UNIT_SCRIPT, GCO.Separator)
	Dprint( DEBUG_UNIT_SCRIPT, "OnCityProductionCompleted", unitTypeName)
	
	local equipmentList 		= city:GetBuildingQueueAllStock(unitTypeName)
	local sortedEquipmentList 	= {} -- { EquipmentID = equipmentID, Value = value, Desirability = desirability }

	for resourceKey, value in pairs(equipmentList) do
		local resourceID 	= tonumber(resourceKey)
		if GCO.IsResourceEquipment(resourceID) then
			local desirability 	= EquipmentInfo[resourceID].Desirability
			table.insert(sortedEquipmentList, { EquipmentID = resourceID, Value = value, Desirability = desirability })
			Dprint( DEBUG_UNIT_SCRIPT, "- Add equipment ".. Locale.Lookup(GameInfo.Resources[resourceID].Name), " to list : { EquipmentID = resourceID, Value = value, Desirability = desirability })", resourceID, value, desirability )
		end
	end
	
	table.sort(sortedEquipmentList, function(a, b) return a.Desirability > b.Desirability; end)
	
	-- search for the unit on city plots...
	--[[
	local possiblePlots = {}
	
	table.insert(possiblePlots, Map.GetPlot(city:GetX(), city:GetY()))
	
	local cityDistricts = city:GetDistricts();
	for i,district in cityDistricts:Members() do
	
		if GameInfo.Districts[district:GetType()].DistrictType == "DISTRICT_ENCAMPMENT" and  GameInfo.Units[objectID].Domain == "DOMAIN_LAND" then
			table.insert(possiblePlots, Map.GetPlot(district:GetX(), district:GetY()))
		elseif GameInfo.Districts[district:GetType()].DistrictType == "DISTRICT_AERODROME" and  GameInfo.Units[objectID].Domain == "DOMAIN_AIR"  then		
			table.insert(possiblePlots, Map.GetPlot(district:GetX(), district:GetY()))
		elseif GameInfo.Districts[district:GetType()].DistrictType == "DISTRICT_HARBOR" and  GameInfo.Units[objectID].Domain == "DOMAIN_SEA"  then		
			table.insert(possiblePlots, Map.GetPlot(district:GetX(), district:GetY()))
		end
	end
	--]]

	local cityPlots	= GCO.GetCityPlots(city)
	Dprint( DEBUG_UNIT_SCRIPT, "- Scanning city plots for any unit waiting for equipment...")
	for i, plotID in ipairs(cityPlots) do
		local plot 		= Map.GetPlotByIndex(plotID)
		local aUnits 	= Units.GetUnitsInPlot(plot)
		for j, unit in ipairs(aUnits) do
			if unit:IsWaitingForEquipment() and unit:GetType() == objectID then
				Dprint( DEBUG_UNIT_SCRIPT, "- Calling immediate equipment initialization for ".. Locale.Lookup(unit:GetName()) .." of player #".. tostring(playerID).. " id#" .. tostring(unit:GetKey()))
				unit:InitializeEquipment(sortedEquipmentList) 
			end			
		end
	end
	Dprint( DEBUG_UNIT_SCRIPT, "- Clearing BuildingQueueStock...")
	city:ClearBuildingQueueStock(unitTypeName)
	Dlog("OnUnitProductionCompleted /END")
end
Events.CityProductionCompleted.Add(	OnUnitProductionCompleted)

function OnImprovementActivated(locationX, locationY, unitOwner, unitID, improvementType, improvementOwner,	activationType, activationValue)
	--print(locationX, locationY, unitOwner, unitID, improvementType, improvementOwner,	activationType, activationValue)
	local unit = UnitManager.GetUnit(unitOwner, unitID)
	if unit then
		if( GameInfo.Improvements[improvementType].BarbarianCamp ) then
			Dprint( DEBUG_UNIT_SCRIPT, "Barbarian Village Cleaned");
			local food 		= Automation.GetRandomNumber(100)
			local bows 		= Automation.GetRandomNumber(1000)
			local spears 	= Automation.GetRandomNumber(1000)
			local bswords 	= Automation.GetRandomNumber(1000)
			local iswords 	= Automation.GetRandomNumber(300)
			local materiel 	= Automation.GetRandomNumber(300)
			unit:ChangeStock(foodResourceID, food)
			unit:ChangeStock(GameInfo.Resources["EQUIPMENT_WOODEN_BOWS"].Index, bows)
			unit:ChangeStock(GameInfo.Resources["EQUIPMENT_BRONZE_SPEARS"].Index, spears)
			unit:ChangeStock(GameInfo.Resources["EQUIPMENT_BRONZE_SWORDS"].Index, bswords)	
			unit:ChangeStock(GameInfo.Resources["EQUIPMENT_IRON_SWORDS"].Index, iswords)
			unit:ChangeStock(materielResourceID, materiel)

			LuaEvents.UnitsCompositionUpdated(unitOwner, unitID)			
			
			local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
			if (pLocalPlayerVis ~= nil) then
				if (pLocalPlayerVis:IsVisible(locationX, locationY)) then
					local sText = "+" .. tostring(bows).." ".. Locale.Lookup(GameInfo.Resources["EQUIPMENT_WOODEN_BOWS"].Name) 
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, locationX, locationY, 0)
					
					local sText = "+" .. tostring(spears).." ".. Locale.Lookup(GameInfo.Resources["EQUIPMENT_BRONZE_SPEARS"].Name) 
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, locationX, locationY, 0)
					
					local sText = "+" .. tostring(bswords).." ".. Locale.Lookup(GameInfo.Resources["EQUIPMENT_BRONZE_SWORDS"].Name) 
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, locationX, locationY, 0)
					
					local sText = "+" .. tostring(iswords).." ".. Locale.Lookup(GameInfo.Resources["EQUIPMENT_IRON_SWORDS"].Name) 
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, locationX, locationY, 0)
					
					local sText = "+" .. tostring(food).." "..GCO.GetResourceIcon(foodResourceID) ..", +" .. tostring(materiel).." "..GCO.GetResourceIcon(materielResourceID)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, locationX, locationY, 0)					
				end
			end
		end
		if( GameInfo.Improvements[improvementType].Goody ) then
			Dprint( DEBUG_UNIT_SCRIPT, "GoodyHut Activated"); 
			local food 		= Automation.GetRandomNumber(100)
			local materiel 	= Automation.GetRandomNumber(300)
			local personnel	= Automation.GetRandomNumber(1000)
			local medicine 	= Automation.GetRandomNumber(500)
			local wheat 	= Automation.GetRandomNumber(500)
			local materiel 	= Automation.GetRandomNumber(300)
			unit:ChangeStock(foodResourceID, food)
			unit:ChangeStock(materielResourceID, materiel)
			unit:ChangeStock(personnelResourceID, personnel)
			unit:ChangeStock(medicineResourceID, medicine)
			unit:ChangeStock(GameInfo.Resources["RESOURCE_WHEAT"].Index, wheat)
			
			LuaEvents.UnitsCompositionUpdated(unitOwner, unitID)
			
			local pLocalPlayerVis = PlayersVisibility[Game.GetLocalPlayer()]
			if (pLocalPlayerVis ~= nil) then
				if (pLocalPlayerVis:IsVisible(locationX, locationY)) then
					local sText = "+" .. tostring(food).." "..GCO.GetResourceIcon(foodResourceID) ..", +" .. tostring(materiel).." "..GCO.GetResourceIcon(materielResourceID)..", +" .. tostring(personnel).." "..GCO.GetResourceIcon(personnelResourceID)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, locationX, locationY, 0)
					
					local sText = "+" .. tostring(medicine).." "..GCO.GetResourceIcon(medicineResourceID)..", +" .. tostring(wheat).." "..GCO.GetResourceIcon(GameInfo.Resources["RESOURCE_WHEAT"].Index)
					Game.AddWorldViewText(EventSubTypes.DAMAGE, sText, locationX, locationY, 0)			
				end
			end			
		end
	end
end
Events.ImprovementActivated.Add( OnImprovementActivated )

-----------------------------------------------------------------------------------------
-- General Functions
-----------------------------------------------------------------------------------------
function CleanUnitData() -- called in GCO_GameScript.lua
	-- remove dead units from the table
	Dprint( DEBUG_UNIT_SCRIPT, "-----------------------------------------------------------------------------------------")
	Dprint( DEBUG_UNIT_SCRIPT, "Cleaning UnitData...")
	
	local DEBUG_UNIT_SCRIPT = false
	
	local unitData = ExposedMembers.UnitData
	for unitKey, data in pairs(unitData) do
		local unit = GetUnitFromKey ( unitKey )
		if (not unit) then		
			Dprint( DEBUG_UNIT_SCRIPT, "REMOVING unit ID#"..tostring(data.unitID).." from player ID#"..tostring(data.playerID), "unit type = ".. tostring(GameInfo.Units[data.unitType].UnitType))
			ExposedMembers.UnitData[unitKey] = nil
		else
			Dprint( DEBUG_UNIT_SCRIPT, "Keeping unit ID#"..unit:GetKey(), "damage = ", unit:GetDamage(), "location =", unit:GetX(), unit:GetY(), "unit type =", Locale.Lookup(UnitManager.GetTypeName(unit)))

			-- Check data syncronization
			if (not CheckComponentsHP(unit, "CleanUnitData")) then
				GCO.Error("desynchronization detected in CleanUnitData() for :[NEWLINE]"..Locale.Lookup(GameInfo.Units[unit:GetType()].Name).." id#".. tostring(unitKey).." player#"..tostring(unit:GetOwner()))
				ExposedMembers.UI.LookAtPlot(unit:GetX(), unit:GetY(), 0.3)
			end			
		end
	end
end
--Events.TurnBegin.Add(CleanUnitData)
--GameEvents.OnGameTurnStarted.Add(CleanUnitData)


-----------------------------------------------------------------------------------------
-- Shared Functions
-----------------------------------------------------------------------------------------
function GetUnit(playerID, unitID) -- return an unit with unitScript functions for another context
	local unit = UnitManager.GetUnit(playerID, unitID)
	AttachUnitFunctions(unit)
	return unit
end


-----------------------------------------------------------------------------------------
-- Initialize Unit Functions
-----------------------------------------------------------------------------------------
function InitializeUnitFunctions(playerID, unitID) -- Note that those are limited to this file context
	local unit = UnitManager.GetUnit(playerID, unitID)
	if unit then
		AttachUnitFunctions(unit)
		Events.UnitAddedToMap.Remove(InitializeUnitFunctions)
	end
end

function AttachUnitFunctions(unit)
	if unit then -- unit could have been killed during initialization by other scripts (removing CS, TSL enforcement, ...)
		local u = getmetatable(unit).__index
		
		u.IsInitialized				= IsInitialized
		u.GetKey					= GetKey
		u.ChangeStock				= ChangeStock
		u.GetBaseFoodStock			= GetBaseFoodStock
		u.GetFoodConsumption 		= GetFoodConsumption
		u.GetFoodConsumptionRatio	= GetFoodConsumptionRatio
		u.GetFuelConsumption 		= GetFuelConsumption
		u.GetMaxFrontLinePersonnel	= GetMaxFrontLinePersonnel
		u.GetMaxFrontLineMateriel	= GetMaxFrontLineMateriel
		u.GetMaxFoodStock			= GetMaxFoodStock
		u.GetMaxMedicineStock		= GetMaxMedicineStock		
		u.GetMaxHorsesReserve		= GetMaxHorsesReserve
		u.GetMaxMaterielReserve		= GetMaxMaterielReserve
		u.GetMaxPersonnelReserve	= GetMaxPersonnelReserve
		--u.GetMaxEquipmentReserve	= GetMaxEquipmentReserve
		u.GetMaxTransferTable		= GetMaxTransferTable
		u.GetMoraleFromFood			= GetMoraleFromFood
		u.GetMoraleFromLastCombat	= GetMoraleFromLastCombat
		u.GetMoraleFromWounded		= GetMoraleFromWounded
		u.GetMoraleFromHP			= GetMoraleFromHP
		u.GetMoraleFromHome			= GetMoraleFromHome
		u.GetNumResourceNeeded		= GetNumResourceNeeded
		u.GetRequirements			= GetRequirements
		u.GetStock					= GetStock
		u.GetAllExcedent			= GetAllExcedent
		u.GetSupplyPathPlots 		= GetSupplyPathPlots
		u.SetSupplyLine				= SetSupplyLine
		u.GetSupplyLineEfficiency	= GetSupplyLineEfficiency
		u.Heal						= Heal
		u.GetHP 					= GetHP
		u.SetHP 					= SetHP
		--
		u.GetAntiPersonnelPercent	= GetAntiPersonnelPercent
		--
		u.GetComponent				= GetComponent
		u.SetComponent				= SetComponent
		u.ChangeComponent			= ChangeComponent
		u.GetComponentVariation		= GetComponentVariation
		--
		u.InitializeEquipment				= InitializeEquipment
		u.IsEquipment						= IsEquipment
		u.GetEquipmentClass					= GetEquipmentClass
		u.GetEquipmentClasses				= GetEquipmentClasses
		u.GetRequiredEquipmentClasses		= GetRequiredEquipmentClasses
		u.IsRequiringEquipmentClass			= IsRequiringEquipmentClass
		u.GetMaxEquipmentFrontLine			= GetMaxEquipmentFrontLine
		u.GetMaxEquipmentReserve			= GetMaxEquipmentReserve
		u.GetEquipmentClassFrontLine		= GetEquipmentClassFrontLine
		u.GetEquipmentClassReserve			= GetEquipmentClassReserve
		u.GetEquipmentClassReserveNeed		= GetEquipmentClassReserveNeed
		u.GetEquipmentClassFrontLineNeed 	= GetEquipmentClassFrontLineNeed
		u.GetReserveEquipment				= GetReserveEquipment
		u.GetFrontLineEquipment				= GetFrontLineEquipment
		u.GetEquipmentReserveNeed			= GetEquipmentReserveNeed
		u.GetEquipmentFrontLineNeed			= GetEquipmentFrontLineNeed
		u.ChangeReserveEquipment			= ChangeReserveEquipment
		u.ChangeFrontLineEquipment			= ChangeFrontLineEquipment
		u.IsWaitingForEquipment				= IsWaitingForEquipment
		--
		u.UpdateDataOnNewTurn		= UpdateDataOnNewTurn
		u.DoFood 					= DoFood
		u.DoMorale 					= DoMorale
		u.DoFuel 					= DoFuel
		u.DoTurn 					= DoTurn
		--
		
		-- flag strings
		u.GetFoodStockString			= GetFoodStockString
		u.GetFoodConsumptionString		= GetFoodConsumptionString
		u.GetMoraleString				= GetMoraleString
		u.GetFuelStockString 			= GetFuelStockString
		u.GetFuelConsumptionString 		= GetFuelConsumptionString
		u.GetFrontLineEquipmentString	= GetFrontLineEquipmentString
		u.GetReserveEquipmentString		= GetReserveEquipmentString
		u.GetResourcesStockString		= GetResourcesStockString
		
		u.HasAttachedFunctions			= true
		
		-- fix when attaching to an unit from UI context: the game is using "GetType" in gameplay script context and "GetUnitType" in UI context...
		if not u.GetType then u.GetType = u.GetUnitType end
	end
end


----------------------------------------------
-- Share functions for other contexts
----------------------------------------------
function ShareFunctions()
	if not ExposedMembers.GCO then ExposedMembers.GCO = {} end
	--
	ExposedMembers.GCO.GetUnit 								= GetUnit
	ExposedMembers.GCO.GetUnitFromKey 						= GetUnitFromKey
	ExposedMembers.GCO.AttachUnitFunctions 					= AttachUnitFunctions
	ExposedMembers.GCO.GetBasePersonnelReserve 				= GetBasePersonnelReserve
	ExposedMembers.GCO.GetBaseHorsesReserve 				= GetBaseHorsesReserve
	ExposedMembers.GCO.GetBaseMaterielReserve 				= GetBaseMaterielReserve
	ExposedMembers.GCO.GetUnitConstructionResources			= GetUnitConstructionResources
	ExposedMembers.GCO.GetUnitConstructionOrResources		= GetUnitConstructionOrResources
	ExposedMembers.GCO.GetUnitConstructionOptionalResources	= GetUnitConstructionOptionalResources
	ExposedMembers.GCO.CleanUnitData 						= CleanUnitData
	--
	ExposedMembers.UnitScript_Initialized 	= true
end


-----------------------------------------------------------------------------------------
-- Initialize after loading the file...
-----------------------------------------------------------------------------------------
Initialize()


-----------------------------------------------------------------------------------------
-- Test / Debug
-----------------------------------------------------------------------------------------

function TestDamage()
	if not ExposedMembers.UnitData then return end
	for unitKey, data in pairs(ExposedMembers.UnitData) do
		local unit = UnitManager.GetUnit(data.playerID, data.unitID)
		if unit then
			local testHP = unit:GetMaxDamage() - unit:GetDamage()
			if testHP ~= data.testHP then
				Dprint( DEBUG_UNIT_SCRIPT, "--------------------------------------- GameCoreEventPublishComplete ---------------------------------------")
				Dprint( DEBUG_UNIT_SCRIPT, "changing HP of unit "..tostring(GameInfo.Units[unit:GetType()].UnitType).." id#".. tostring(unit:GetKey()).." player#"..tostring(unit:GetOwner()))
				Dprint( DEBUG_UNIT_SCRIPT, "previous HP =", data.testHP)
				Dprint( DEBUG_UNIT_SCRIPT, "new HP =", testHP)
				Dprint( DEBUG_UNIT_SCRIPT, "HP change =", testHP - data.testHP)
				Dprint( DEBUG_UNIT_SCRIPT, "------------------------------------------------------------------------------")
				data.testHP = testHP
			end
		end
	end
end
--Events.GameCoreEventPublishComplete.Add( TestDamage )


