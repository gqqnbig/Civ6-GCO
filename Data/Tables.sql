/*
	GCO
	by Gedemon (2017)
	
*/

-----------------------------------------------
-- Modified Tables
-----------------------------------------------

CREATE TABLE IF NOT EXISTS TechnologiesGCO (
		TechnologyType TEXT NOT NULL,
		Name TEXT,
		Cost INTEGER NOT NULL,
		Repeatable BOOLEAN NOT NULL CHECK (Repeatable IN (0,1)) DEFAULT 0,
		EmbarkUnitType TEXT,
		EmbarkAll BOOLEAN NOT NULL CHECK (EmbarkAll IN (0,1)) DEFAULT 0,
		Description TEXT,
		EraType TEXT NOT NULL,
		Critical BOOLEAN NOT NULL CHECK (Critical IN (0,1)) DEFAULT 0,
		BarbarianFree BOOLEAN NOT NULL CHECK (BarbarianFree IN (0,1)) DEFAULT 0,
		UITreeRow INTEGER DEFAULT 10,
		AdvisorType TEXT,
		PRIMARY KEY(TechnologyType)
		);
		
		
CREATE TABLE IF NOT EXISTS TechnologyPrereqsGCO (
		Technology TEXT NOT NULL,
		PrereqTech TEXT NOT NULL,
		PRIMARY KEY(Technology, PrereqTech)
		);

-- Create temporary Building/Resources/Units tables that will be used to fill all required tables using SQL in PostUpdate.sql
CREATE TABLE IF NOT EXISTS BuildingsGCO (
		BuildingType TEXT NOT NULL,
		Name TEXT NOT NULL DEFAULT 'BUILDING_NAME', -- so we don't have to set the LOC_NAME manually and update the field automatically in PostUpdate.sql
		PrereqTech TEXT,
		PrereqCivic TEXT,
		Cost INTEGER NOT NULL,
		MaxPlayerInstances INTEGER NOT NULL DEFAULT -1,
		MaxWorldInstances INTEGER NOT NULL DEFAULT -1,
		Capital BOOLEAN NOT NULL CHECK (Capital IN (0,1)) DEFAULT 0,
		PrereqDistrict TEXT NOT NULL DEFAULT 'DISTRICT_CITY_CENTER',
		AdjacentDistrict TEXT,
		Description TEXT,
		RequiresPlacement BOOLEAN NOT NULL CHECK (RequiresPlacement IN (0,1)) DEFAULT 0,
		RequiresRiver BOOLEAN NOT NULL CHECK (RequiresRiver IN (0,1)) DEFAULT 0,
		OuterDefenseHitPoints INTEGER,
		Housing INTEGER NOT NULL DEFAULT 0,
		Entertainment INTEGER NOT NULL DEFAULT 0,
		AdjacentResource TEXT,
		Coast BOOLEAN CHECK (Coast IN (0,1)),
		EnabledByReligion BOOLEAN NOT NULL CHECK (EnabledByReligion IN (0,1)) DEFAULT 0,
		AllowsHolyCity BOOLEAN NOT NULL CHECK (AllowsHolyCity IN (0,1)) DEFAULT 0,
		PurchaseYield TEXT,
		MustPurchase BOOLEAN NOT NULL CHECK (MustPurchase IN (0,1)) DEFAULT 0,
		Maintenance INTEGER NOT NULL DEFAULT 0,
		IsWonder BOOLEAN NOT NULL CHECK (IsWonder IN (0,1)) DEFAULT 0,
		TraitType TEXT,
		OuterDefenseStrength INTEGER NOT NULL DEFAULT 0,
		CitizenSlots INTEGER,
		MustBeLake BOOLEAN NOT NULL CHECK (MustBeLake IN (0,1)) DEFAULT 0,
		MustNotBeLake BOOLEAN NOT NULL CHECK (MustNotBeLake IN (0,1)) DEFAULT 0,
		RegionalRange INTEGER NOT NULL DEFAULT 0,
		AdjacentToMountain BOOLEAN NOT NULL CHECK (AdjacentToMountain IN (0,1)) DEFAULT 0,
		ObsoleteEra TEXT NOT NULL DEFAULT NO_ERA,
		RequiresReligion BOOLEAN NOT NULL CHECK (RequiresReligion IN (0,1)) DEFAULT 0,
		GrantFortification INTEGER NOT NULL DEFAULT 0,
		DefenseModifier INTEGER NOT NULL DEFAULT 0,
		InternalOnly BOOLEAN NOT NULL CHECK (InternalOnly IN (0,1)) DEFAULT 0,
		RequiresAdjacentRiver BOOLEAN NOT NULL CHECK (RequiresAdjacentRiver IN (0,1)) DEFAULT 0,
		Quote TEXT,
		QuoteAudio TEXT,
		MustBeAdjacentLand BOOLEAN NOT NULL CHECK (MustBeAdjacentLand IN (0,1)) DEFAULT 0,
		AdvisorType TEXT NOT NULL DEFAULT 'ADVISOR_GENERIC',
		AdjacentCapital BOOLEAN NOT NULL CHECK (AdjacentCapital IN (0,1)) DEFAULT 0,
		AdjacentImprovement TEXT,
		CityAdjacentTerrain TEXT,
		-- Hidden Buildings
		NoPedia 		BOOLEAN NOT NULL CHECK (NoPedia IN (0,1)) DEFAULT 0,		-- Do not show in Civilopedia
		NoCityScreen 	BOOLEAN NOT NULL CHECK (NoCityScreen IN (0,1)) DEFAULT 0, 	-- Do not show in City Screens
		Unlockers 		BOOLEAN NOT NULL CHECK (Unlockers IN (0,1)) DEFAULT 0, 		-- Unlockers for buildings and units
		--
		EquipmentStock	integer DEFAULT 0, 											-- Equipment that can be stocked by the building
		-- Materiel ratio for Buildings construction
		MaterielPerProduction 	INTEGER DEFAULT '4', 								-- Materiel per unit of production needed for buildings construction
		-- Employment
		EmploymentSize	REAL DEFAULT 0, 											-- Employment slots provided by the building
		PRIMARY KEY(BuildingType),
		FOREIGN KEY (AdjacentDistrict) REFERENCES Districts(DistrictType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PrereqDistrict) REFERENCES Districts(DistrictType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (AdjacentResource) REFERENCES Resources(ResourceType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PrereqCivic) REFERENCES Civics(CivicType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PurchaseYield) REFERENCES Yields(YieldType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (TraitType) REFERENCES Traits(TraitType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (BuildingType) REFERENCES Types(Type) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (AdjacentImprovement) REFERENCES Improvements(ImprovementType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (CityAdjacentTerrain) REFERENCES Terrains(TerrainType) ON DELETE CASCADE ON UPDATE CASCADE);
--INSERT INTO temp_Buildings SELECT * FROM Buildings;
--DROP TABLE Buildings;
--ALTER TABLE temp_Buildings RENAME TO Buildings;

/*
CREATE TABLE IF NOT EXISTS ResourcesGCO (
		ResourceType TEXT NOT NULL,
		Name TEXT NOT NULL DEFAULT 'RESOURCE_NAME', -- so we don't have to set the LOC_NAME manually and update the field automatically in PostUpdate.sql
		ResourceClassType TEXT NOT NULL,
		Happiness INTEGER NOT NULL DEFAULT 0,
		NoRiver BOOLEAN NOT NULL CHECK (NoRiver IN (0,1)) DEFAULT 0,
		RequiresRiver BOOLEAN NOT NULL CHECK (RequiresRiver IN (0,1)) DEFAULT 0,
		Frequency INTEGER NOT NULL DEFAULT 0,
		Clumped BOOLEAN NOT NULL CHECK (Clumped IN (0,1)) DEFAULT 0,
		PrereqTech TEXT,
		PrereqCivic TEXT,
		PeakEra TEXT NOT NULL DEFAULT NO_ERA,
		RevealedEra INTEGER NOT NULL DEFAULT 1,
		LakeEligible BOOLEAN NOT NULL CHECK (LakeEligible IN (0,1)) DEFAULT 1,
		AdjacentToLand BOOLEAN NOT NULL CHECK (AdjacentToLand IN (0,1)) DEFAULT 0,
		SeaFrequency INTEGER NOT NULL DEFAULT 0,
		-- Resources trading
		FixedPrice BOOLEAN NOT NULL CHECK (FixedPrice IN (0,1)) DEFAULT 0, 		-- Not price variation after production
		MaxPriceVariationPercent INTEGER NOT NULL DEFAULT 100, 					-- Max price variation each turn
		NoExport 	BOOLEAN NOT NULL CHECK (NoExport IN (0,1)) DEFAULT 0, 		-- Not allowed on international trade routes
		NoTransfer 	BOOLEAN NOT NULL CHECK (NoTransfer IN (0,1)) DEFAULT 0,		-- Not allowed on internal trade routes		
		SpecialStock BOOLEAN NOT NULL CHECK (SpecialStock IN (0,1)) DEFAULT 0, 	-- Stocked in specific buildings only
		NotLoot BOOLEAN NOT NULL CHECK (NotLoot IN (0,1)) DEFAULT 0, 			-- Can't be captured when attacking cities
		DecayRate INTEGER,														-- Also used to get minimal route efficiency (bUseroute = RouteEfficiency >= DecayRate*DecayToEfficiencyFactor)
		UnitsPerTonnage INTEGER DEFAULT 1,										-- Number of units of this resource per SupplyRoute tonnage
		PRIMARY KEY(ResourceType),
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (PrereqCivic) REFERENCES Civics(CivicType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Types(Type) ON DELETE CASCADE ON UPDATE CASCADE);
		*/
CREATE TABLE IF NOT EXISTS ResourcesGCO (
		ResourceType TEXT NOT NULL,
		Name TEXT NOT NULL DEFAULT 'RESOURCE_NAME', -- so we don't have to set the LOC_NAME manually and update the field automatically in PostUpdate.sql
		ResourceClassType TEXT ,
		Happiness INTEGER,
		NoRiver BOOLEAN,
		RequiresRiver BOOLEAN,
		Frequency INTEGER,
		Clumped BOOLEAN,
		PrereqTech TEXT,
		PrereqCivic TEXT,
		PeakEra TEXT,
		RevealedEra INTEGER,
		LakeEligible BOOLEAN,
		AdjacentToLand BOOLEAN,
		SeaFrequency INTEGER,
		-- Resources trading
		FixedPrice BOOLEAN, 				-- Not price variation after production
		MaxPriceVariationPercent INTEGER, 	-- Max price variation each turn
		NoExport 	BOOLEAN, 				-- Not allowed on international trade routes
		NoTransfer 	BOOLEAN,				-- Not allowed on internal trade routes		
		SpecialStock BOOLEAN, 				-- Stocked in specific buildings only
		NotLoot BOOLEAN, 					-- Can't be captured when attacking cities
		DecayRate REAL,					-- Also used to get minimal route efficiency (bUseroute = RouteEfficiency >= DecayRate*DecayToEfficiencyFactor)
		UnitsPerTonnage INTEGER,			-- Number of units of this resource per SupplyRoute tonnage
		PRIMARY KEY(ResourceType),
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (PrereqCivic) REFERENCES Civics(CivicType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Types(Type) ON DELETE CASCADE ON UPDATE CASCADE);
--INSERT INTO temp_Resources SELECT * FROM Resources;
--DROP TABLE Resources;
--ALTER TABLE temp_Resources RENAME TO Resources;

-- Units Table without "NOT NULL" requirements (except UnitType)
CREATE TABLE IF NOT EXISTS UnitsGCO (
		UnitType TEXT NOT NULL,
		Name TEXT,
		BaseSightRange INTEGER,
		BaseMoves INTEGER,
		Combat INTEGER,
		RangedCombat INTEGER,
		Range INTEGER,
		Bombard INTEGER,
		Domain TEXT,
		FormationClass TEXT,
		Cost INTEGER,
		PopulationCost INTEGER,
		FoundCity BOOLEAN,
		FoundReligion BOOLEAN,
		MakeTradeRoute BOOLEAN,
		EvangelizeBelief BOOLEAN,
		LaunchInquisition BOOLEAN,
		RequiresInquisition BOOLEAN,
		BuildCharges INTEGER,
		ReligiousStrength INTEGER,
		ReligionEvictPercent INTEGER,
		SpreadCharges INTEGER,
		ExtractsArtifacts BOOLEAN,
		Description TEXT,
		Flavor TEXT,
		CanCapture BOOLEAN,
		CanRetreatWhenCaptured BOOLEAN,
		TraitType TEXT,
		AllowBarbarians BOOLEAN,
		CostProgressionModel TEXT,
		CostProgressionParam1 INTEGER,
		PromotionClass TEXT,
		InitialLevel INTEGER,
		NumRandomChoices INTEGER,
		PrereqTech TEXT,
		PrereqCivic TEXT,
		PrereqDistrict TEXT,
		PrereqPopulation INTEGER,
		LeaderType TEXT,
		CanTrain BOOLEAN,
		StrategicResource TEXT,
		PurchaseYield TEXT,
		MustPurchase BOOLEAN,
		Maintenance INTEGER,
		Stackable BOOLEAN,
		AirSlots INTEGER,
		CanTargetAir,
		PseudoYieldType TEXT,
		ZoneOfControl BOOLEAN,
		AntiAirCombat INTEGER,
		Spy BOOLEAN,
		WMDCapable BOOLEAN,
		ParkCharges INTEGER,
		IgnoreMoves BOOLEAN,
		TeamVisibility BOOLEAN,
		ObsoleteTech TEXT,
		ObsoleteCivic TEXT,
		MandatoryObsoleteTech TEXT,
		MandatoryObsoleteCivic TEXT,
		AdvisorType TEXT,
		-- Composition in personnel of an unit at full health (for units that doesn't use military organization level)
		Personnel integer,
		-- Materiel required  
		Materiel integer, 			-- total value for unit at 100% health, representing general equipement, armement and munitions
		-- Casualties modifier
		AntiPersonnel 	integer, 	-- 100 means all personnel casualties are dead, no wounded, no prisonners
		AntiArmor 		integer,
		AntiShip 		integer,
		AntiAir 		integer,
		PRIMARY KEY(UnitType),
		FOREIGN KEY (Flavor) REFERENCES Flavors(FlavorType),
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType),
		FOREIGN KEY (PrereqCivic) REFERENCES Civics(CivicType),
		FOREIGN KEY (TraitType) REFERENCES Traits(TraitType),
		FOREIGN KEY (StrategicResource) REFERENCES Resources(ResourceType),
		FOREIGN KEY (PurchaseYield) REFERENCES Yields(YieldType),
		FOREIGN KEY (PrereqDistrict) REFERENCES Districts(DistrictType),
		FOREIGN KEY (PromotionClass) REFERENCES UnitPromotionClasses(PromotionClassType),
		FOREIGN KEY (PseudoYieldType) REFERENCES PseudoYields(PseudoYieldType),
		FOREIGN KEY (PrereqCivic) REFERENCES Civics(CivicType),
		FOREIGN KEY (PurchaseYield) REFERENCES Yields(YieldType),
		FOREIGN KEY (ObsoleteCivic) REFERENCES Civics(CivicType),
		FOREIGN KEY (MandatoryObsoleteCivic) REFERENCES Civics(CivicType),
		FOREIGN KEY (MandatoryObsoleteTech) REFERENCES Technologies(TechnologyType),
		FOREIGN KEY (ObsoleteTech) REFERENCES Technologies(TechnologyType)
	);

-- Units Table without "NOT NULL" requirements (except UnitType) and short names
CREATE TABLE IF NOT EXISTS UnitsShort (
		UnitType TEXT NOT NULL, -- Without 'UNIT_'
		SR INTEGER,				-- BaseSightRange
		BM INTEGER,				-- BaseMoves
		Cb INTEGER,				-- Combat
		RC INTEGER,				-- RangedCombat
		Rg INTEGER,				-- Range
		Bd INTEGER,				-- Bombard
		Domain TEXT,			-- Without 'DOMAIN_'
		FormationClass TEXT,	-- Without 'FORMATION_CLASS_'
		Cs INTEGER,				-- Cost
		Flavor TEXT,
		Cpt BOOLEAN,			-- CanCapture
		PromotionClass TEXT,	-- Without 'PROMOTION_CLASS_'
		District TEXT,			-- PrereqDistrict, Without 'DISTRICT_'
		CanTrain BOOLEAN,
		PurYld TEXT,			-- PurchaseYield, Without 'YIELD_'
		MustPurchase BOOLEAN,
		Mt INTEGER,				-- Maintenance
		Stk BOOLEAN,			-- Stackable
		AiS INTEGER,			-- AirSlots
		CTA BOOLEAN,			-- CanTargetAir
		PsYld TEXT,				-- PseudoYieldType
		ZOC BOOLEAN,			-- ZoneOfControl
		AAC INTEGER,			-- AntiAirCombat
		Spy BOOLEAN,
		WMD BOOLEAN,			-- WMDCapable
		IM BOOLEAN,				-- IgnoreMoves
		TeamVisibility BOOLEAN,
		Advisor TEXT,			-- AdvisorType, Without 'ADVISOR_'
		-- Composition in personnel of an unit at full health (for units that doesn't use military organization level)
		Personnel integer,
		-- Casualties modifier
		AntiPersonnel 	integer, 	-- 100 means all personnel casualties are dead, no wounded, no prisonners
		AntiArmor 		integer,
		AntiShip 		integer,
		AntiAir 		integer,
		PRIMARY KEY(UnitType)
	);	
	
/*
-- Full unit table copy
CREATE TABLE IF NOT EXISTS UnitsGCO (
		UnitType TEXT NOT NULL,
		Name TEXT NOT NULL DEFAULT 'UNIT_NAME',
		BaseSightRange INTEGER NOT NULL,
		BaseMoves INTEGER NOT NULL,
		Combat INTEGER NOT NULL DEFAULT 0,
		RangedCombat INTEGER NOT NULL DEFAULT 0,
		Range INTEGER NOT NULL DEFAULT 0,
		Bombard INTEGER NOT NULL DEFAULT 0,
		Domain TEXT NOT NULL,
		FormationClass TEXT NOT NULL,
		Cost INTEGER NOT NULL,
		PopulationCost INTEGER,
		FoundCity BOOLEAN NOT NULL CHECK (FoundCity IN (0,1)) DEFAULT 0,
		FoundReligion BOOLEAN NOT NULL CHECK (FoundReligion IN (0,1)) DEFAULT 0,
		MakeTradeRoute BOOLEAN NOT NULL CHECK (MakeTradeRoute IN (0,1)) DEFAULT 0,
		EvangelizeBelief BOOLEAN NOT NULL CHECK (EvangelizeBelief IN (0,1)) DEFAULT 0,
		LaunchInquisition BOOLEAN NOT NULL CHECK (LaunchInquisition IN (0,1)) DEFAULT 0,
		RequiresInquisition BOOLEAN NOT NULL CHECK (RequiresInquisition IN (0,1)) DEFAULT 0,
		BuildCharges INTEGER NOT NULL DEFAULT 0,
		ReligiousStrength INTEGER NOT NULL DEFAULT 0,
		ReligionEvictPercent INTEGER NOT NULL DEFAULT 0,
		SpreadCharges INTEGER NOT NULL DEFAULT 0,
		ExtractsArtifacts BOOLEAN NOT NULL CHECK (ExtractsArtifacts IN (0,1)) DEFAULT 0,
		Description TEXT,
		Flavor TEXT,
		CanCapture BOOLEAN NOT NULL CHECK (CanCapture IN (0,1)) DEFAULT 1,
		CanRetreatWhenCaptured BOOLEAN NOT NULL CHECK (CanRetreatWhenCaptured IN (0,1)) DEFAULT 0,
		TraitType TEXT,
		AllowBarbarians BOOLEAN NOT NULL CHECK (AllowBarbarians IN (0,1)) DEFAULT 0,
		CostProgressionModel TEXT NOT NULL DEFAULT NO_COST_PROGRESSION,
		CostProgressionParam1 INTEGER NOT NULL DEFAULT 0,
		PromotionClass TEXT,
		InitialLevel INTEGER NOT NULL DEFAULT 1,
		NumRandomChoices INTEGER NOT NULL DEFAULT 0,
		PrereqTech TEXT,
		PrereqCivic TEXT,
		PrereqDistrict TEXT,
		PrereqPopulation INTEGER,
		LeaderType TEXT,
		CanTrain BOOLEAN NOT NULL CHECK (CanTrain IN (0,1)) DEFAULT 1,
		StrategicResource TEXT,
		PurchaseYield TEXT,
		MustPurchase BOOLEAN NOT NULL CHECK (MustPurchase IN (0,1)) DEFAULT 0,
		Maintenance INTEGER NOT NULL DEFAULT 0,
		Stackable BOOLEAN NOT NULL CHECK (Stackable IN (0,1)) DEFAULT 0,
		AirSlots INTEGER NOT NULL DEFAULT 0,
		CanTargetAir BOOLEAN NOT NULL CHECK (CanTargetAir IN (0,1)) DEFAULT 0,
		PseudoYieldType TEXT,
		ZoneOfControl BOOLEAN NOT NULL CHECK (ZoneOfControl IN (0,1)) DEFAULT 0,
		AntiAirCombat INTEGER NOT NULL DEFAULT 0,
		Spy BOOLEAN NOT NULL CHECK (Spy IN (0,1)) DEFAULT 0,
		WMDCapable BOOLEAN NOT NULL CHECK (WMDCapable IN (0,1)) DEFAULT 0,
		ParkCharges INTEGER NOT NULL DEFAULT 0,
		IgnoreMoves BOOLEAN NOT NULL CHECK (IgnoreMoves IN (0,1)) DEFAULT 0,
		TeamVisibility BOOLEAN NOT NULL CHECK (TeamVisibility IN (0,1)) DEFAULT 0,
		ObsoleteTech TEXT,
		ObsoleteCivic TEXT,
		MandatoryObsoleteTech TEXT,
		MandatoryObsoleteCivic TEXT,
		AdvisorType TEXT,
		-- Composition in personnel, vehicles and horses of an unit at full health 
		Personnel integer DEFAULT '0',
		Equipment integer DEFAULT '0',
		EquipmentType TEXT,
		Horses integer DEFAULT '0',
		-- Materiel required  
		Materiel integer DEFAULT '0', 			-- total value for unit at 100% health, representing general equipement, armement and munitions
		-- Casualties modifier
		AntiPersonnel 	integer DEFAULT '55', 	-- 100 means all personnel casualties are dead, no wounded, no prisonners
		AntiArmor 		integer DEFAULT '20',
		AntiShip 		integer DEFAULT '50',
		AntiAir 		integer DEFAULT '50',
		PRIMARY KEY(UnitType),
		FOREIGN KEY (Flavor) REFERENCES Flavors(FlavorType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PrereqCivic) REFERENCES Civics(CivicType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (TraitType) REFERENCES Traits(TraitType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (StrategicResource) REFERENCES Resources(ResourceType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PurchaseYield) REFERENCES Yields(YieldType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PrereqDistrict) REFERENCES Districts(DistrictType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PromotionClass) REFERENCES UnitPromotionClasses(PromotionClassType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PseudoYieldType) REFERENCES PseudoYields(PseudoYieldType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (PrereqCivic) REFERENCES Civics(CivicType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (UnitType) REFERENCES Types(Type) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (PurchaseYield) REFERENCES Yields(YieldType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (ObsoleteCivic) REFERENCES Civics(CivicType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (MandatoryObsoleteCivic) REFERENCES Civics(CivicType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (MandatoryObsoleteTech) REFERENCES Technologies(TechnologyType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT,
		FOREIGN KEY (ObsoleteTech) REFERENCES Technologies(TechnologyType) ON DELETE SET DEFAULT ON UPDATE SET DEFAULT);

 */
--INSERT INTO temp_Units SELECT * FROM Units;
--DROP TABLE Units;
--ALTER TABLE temp_Units RENAME TO Units;
		
-- Composition in personnel of an unit at full health (for units that doesn't use military organization level)
ALTER TABLE Units ADD COLUMN Personnel integer DEFAULT '0';

-- Casualties modifier
ALTER TABLE Units ADD COLUMN AntiPersonnel 	integer; -- 
--ALTER TABLE Units ADD COLUMN AntiArmor 		integer DEFAULT '20';
--ALTER TABLE Units ADD COLUMN AntiShip 		integer DEFAULT '50';
--ALTER TABLE Units ADD COLUMN AntiAir 		integer DEFAULT '50';

-- Columns used when Culture Diffusion is ON and CULTURE_DIFFUSION_VARIATION_BY_ERA = 1
ALTER TABLE Eras ADD COLUMN CultureMinimumForAcquisitionMod integer DEFAULT '100';		-- Percentage of CULTURE_MINIMUM_FOR_ACQUISITION
ALTER TABLE Eras ADD COLUMN CultureDiffusionThresholdMod integer DEFAULT '100';			-- Percentage of CULTURE_DIFFUSION_THRESHOLD
ALTER TABLE Eras ADD COLUMN CultureFlippingMaxDistance integer DEFAULT '100';			-- Replace CULTURE_FLIPPING_MAX_DISTANCE (0 = unlimited)
ALTER TABLE Eras ADD COLUMN CultureConquestEnabled integer DEFAULT '100';				-- Replace CULTURE_CONQUEST_ENABLED (boolean = 0,1) 

ALTER TABLE Eras ADD COLUMN ArmyMaxPercentOfPopulation integer DEFAULT '1';				-- max percentage of total population in the army (max personnel when not at war)
ALTER TABLE Eras ADD COLUMN ArmyMaxPercentWarBoost integer DEFAULT '5';					-- raise max percentage of total population in the army by this value (max personnel when at war)

ALTER TABLE Eras ADD COLUMN ArmyPersonnelPopulationRatio integer DEFAULT '1';			-- Number of Population required to train 1 personnel (this is to compensate the fact that at the scale of the mod we can have real population numbers for cities but not for units)

ALTER TABLE Policies ADD COLUMN ArmyMaxPercentBoost integer DEFAULT '0';				-- raise max percentage of total population in the army by this value (max personnel when at war)
ALTER TABLE Policies ADD COLUMN ActiveTurnsLeftBoost integer DEFAULT '0';				-- raise max number of turn an unit can be drafted before disbanding 

-- Culture Diffusion modifiers
ALTER TABLE Features ADD COLUMN CultureThreshold integer DEFAULT '0';
ALTER TABLE Features ADD COLUMN CulturePenalty integer DEFAULT '0';
ALTER TABLE Features ADD COLUMN CultureMaxPercent integer DEFAULT '0';
ALTER TABLE Terrains ADD COLUMN CultureThreshold integer DEFAULT '0';
ALTER TABLE Terrains ADD COLUMN CulturePenalty integer DEFAULT '0';
ALTER TABLE Terrains ADD COLUMN CultureMaxPercent integer DEFAULT '0';

-- Resources trading
ALTER TABLE Resources ADD COLUMN FixedPrice 				BOOLEAN NOT NULL CHECK (FixedPrice IN (0,1)) DEFAULT 0; 	-- Not price variation after production
ALTER TABLE Resources ADD COLUMN MaxPriceVariationPercent 	INTEGER NOT NULL DEFAULT 100; 								-- Max price variation each turn
ALTER TABLE Resources ADD COLUMN NoExport 					BOOLEAN NOT NULL CHECK (NoExport IN (0,1)) DEFAULT 0; 		-- Not allowed on international trade routes
ALTER TABLE Resources ADD COLUMN NoTransfer 				BOOLEAN NOT NULL CHECK (NoTransfer IN (0,1)) DEFAULT 0; 	-- Not allowed on internal trade routes
ALTER TABLE Resources ADD COLUMN UnitsPerTonnage 			INTEGER DEFAULT '1';    									-- Number of units of this resource per SupplyRoute tonnage
ALTER TABLE Resources ADD COLUMN SpecialStock 				BOOLEAN NOT NULL CHECK (SpecialStock IN (0,1)) DEFAULT 0; 	-- Stocked in specific buildings only
ALTER TABLE Resources ADD COLUMN NotLoot 					BOOLEAN NOT NULL CHECK (NotLoot IN (0,1)) DEFAULT 0; 		-- Can't be captured when attacking cities
ALTER TABLE Resources ADD COLUMN DecayRate 					REAL; 														-- Also used to get minimal route efficiency (bUseroute = RouteEfficiency >= DecayRate*DecayToEfficiencyFactor)
ALTER TABLE Resources ADD COLUMN ResearchType				TEXT; 														-- is a knowledge resource for a specific research
ALTER TABLE Resources ADD COLUMN TechnologyType				TEXT; 														-- is a knowledge resource for a specific technology

-- Hidden Buildings
ALTER TABLE Buildings ADD COLUMN NoPedia 		BOOLEAN NOT NULL CHECK (NoPedia IN (0,1)) DEFAULT 0; 		-- Do not show in Civilopedia
ALTER TABLE Buildings ADD COLUMN NoCityScreen 	BOOLEAN NOT NULL CHECK (NoCityScreen IN (0,1)) DEFAULT 0; 	-- Do not show in City Screens
--
ALTER TABLE Buildings ADD COLUMN Unlockers 		BOOLEAN NOT NULL CHECK (Unlockers IN (0,1)) DEFAULT 0; 		-- Unlockers for buildings and units
ALTER TABLE Buildings ADD COLUMN EquipmentStock	INTEGER DEFAULT 0; 											-- Equipment that can be stocked by the building
ALTER TABLE Buildings ADD COLUMN FishingRange 	INTEGER DEFAULT 0;											-- Range to work sea resources
-- Materiel ratio for Buildings construction
ALTER TABLE Buildings ADD COLUMN MaterielPerProduction 	INTEGER DEFAULT 4; 		-- Materiel per unit of production needed for buildings construction
-- Employment
ALTER TABLE Buildings ADD COLUMN EmploymentSize	REAL DEFAULT 0; 					-- Employment slots provided by the building

-- Technologies
ALTER TABLE Technologies ADD COLUMN FishingRange INTEGER DEFAULT 0;					-- Range to work sea resources


-----------------------------------------------
-- New Tables
-----------------------------------------------

-- Create a version of the LocalizedText table in GameData, the Mod text will be copied there, then PostUpdate.sql populate the corresponding entries, if the text exists
CREATE TABLE IF NOT EXISTS LocalizedText (
	Language TEXT NOT NULL,
	Tag TEXT NOT NULL,
	Text TEXT,
	Gender TEXT,
	Plurality TEXT,
	PRIMARY KEY (Language, Tag));

CREATE TABLE IF NOT EXISTS CultureGroups
	(	CultureType TEXT NOT NULL,
		Name TEXT,
		Adjective TEXT,
		StartDate INTEGER,
		EndDate INTEGER,
		PeakDate INTEGER,
		PeakStrength INTEGER,
		Agressivity INTEGER,
		SpawnCivilization TEXT,
		Ethnicity TEXT,
		PRIMARY KEY(CultureType)
		--FOREIGN KEY (SpawnCivilization) REFERENCES Civilizations(CivilizationType)
	);
	
CREATE TABLE IF NOT EXISTS CultureGroupsStartingRegions
	(	CultureType TEXT NOT NULL,
		StartingRegion TEXT NOT NULL,
		PRIMARY KEY(CultureType, StartingRegion)
	);
	
CREATE TABLE IF NOT EXISTS BuildingConstructionResources (
		BuildingType TEXT NOT NULL,
		ResourceType TEXT NOT NULL,
		Quantity INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY(BuildingType, ResourceType),
		FOREIGN KEY (BuildingType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS BuildingResourcesConverted (
		BuildingType TEXT NOT NULL,
		ResourceType TEXT NOT NULL,
		ResourceCreated TEXT NOT NULL,
		MultiResRequired BOOLEAN NOT NULL CHECK (MultiResRequired IN (0,1)) DEFAULT 0,	-- ResourceCreated requires multiple ResourceType (multi rows definition)
		MultiResCreated BOOLEAN NOT NULL CHECK (MultiResCreated IN (0,1)) DEFAULT 0,	-- 1 unit of ResourceType creates multiple ResourceCreated (multi rows definition)
		MaxConverted INTEGER NOT NULL DEFAULT 0,
		Ratio REAL NOT NULL DEFAULT 1,
		CostFactor REAL NOT NULL DEFAULT 1,		-- production cost factor
		Priority INTEGER NOT NULL DEFAULT 0, 	-- higher value means higher priority when consuming resources
		PRIMARY KEY(BuildingType, ResourceType, ResourceCreated),
		FOREIGN KEY (BuildingType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE,		
		FOREIGN KEY (ResourceCreated) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS BuildingStock (
		BuildingType TEXT NOT NULL,
		ResourceType TEXT,
		ResourceClassType TEXT,
		Stock INTEGER NOT NULL DEFAULT 0,
		FixedValue BOOLEAN NOT NULL CHECK (FixedValue IN (0,1)) DEFAULT 0,	-- if true, city size doesn't affect that building stock
		FOREIGN KEY (BuildingType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS BuildingPopulationEffect	(
		BuildingType TEXT NOT NULL,
		PopulationType TEXT NOT NULL,		-- POPULATION_UPPER, POPULATION_MIDDLE, POPULATION_LOWER, POPULATION_SLAVE
		EffectType TEXT NOT NULL,			-- CLASS_MAX_PERCENT, CLASS_MIN_PERCENT
		EffectValue INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY(BuildingType, PopulationType, EffectType),
		FOREIGN KEY (BuildingType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (PopulationType) REFERENCES Populations(PopulationType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS FeatureResourcesProduced	(
		FeatureType TEXT NOT NULL,
		ResourceType TEXT NOT NULL,
		NumPerFeature REAL NOT NULL DEFAULT 0,
		PRIMARY KEY(FeatureType, ResourceType),
		FOREIGN KEY (FeatureType) REFERENCES Features(FeatureType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS TerrainResourcesProduced	(
		TerrainType TEXT NOT NULL,
		ResourceType TEXT NOT NULL,
		NumPerTerrain REAL NOT NULL DEFAULT 0,
		PRIMARY KEY(TerrainType, ResourceType),
		FOREIGN KEY (TerrainType) REFERENCES Terrains(TerrainType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS Populations (
		PopulationType TEXT NOT NULL,
		Name TEXT NOT NULL,
		Description TEXT NOT NULL,
		PRIMARY KEY(PopulationType)
	);
	
CREATE TABLE IF NOT EXISTS ResourceStockUsage (
		ResourceType TEXT NOT NULL,
		MinPercentLeftToSupply INTEGER NOT NULL DEFAULT 50,		-- stock above that percentage are available for reinforcing units
		MinPercentLeftToTransfer INTEGER NOT NULL DEFAULT 75,	-- stock above that percentage are available for transfer to other cities of the same civilization
		MinPercentLeftToExport INTEGER NOT NULL DEFAULT 75,		-- stock above that percentage are available for trade with other civilizations cities
		MinPercentLeftToConvert INTEGER NOT NULL DEFAULT 0,		-- stock above that percentage are available for use by local industries
		MaxPercentLeftToRequest INTEGER NOT NULL DEFAULT 100,	-- until that percentage is reached, allow trade from other civilizations cities 
		MaxPercentLeftToImport INTEGER NOT NULL DEFAULT 75,		-- until that percentage is reached, allow internal transfer from other cities of the same civilization (must be <= MinPercentLeftToExport)
		PRIMARY KEY(ResourceType),
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE
	);
		
CREATE TABLE IF NOT EXISTS EquipmentClasses	(
		EquipmentClass TEXT NOT NULL, 		-- CLASS_VEHICLE, CLASS_GEAR, ...
		Name TEXT,							-- "Tanks", "Iron Materiel",...
		PRIMARY KEY(EquipmentClass)
	);
	
CREATE TABLE IF NOT EXISTS EquipmentTypeClasses	(
		ResourceType TEXT NOT NULL,
		EquipmentClass TEXT NOT NULL, 				
		PRIMARY KEY(ResourceType, EquipmentClass)	-- an equipment could belong to multiple classes
	);
	
CREATE TABLE IF NOT EXISTS Equipment (
		ResourceType TEXT NOT NULL,										-- Equipment are handled as resources
		ResourceClassType TEXT NOT NULL DEFAULT 'RESOURCECLASS_EQUIPMENT',
		Size INTEGER NOT NULL DEFAULT 1,								-- Space taken in a city stockage capacity
		Desirability INTEGER NOT NULL DEFAULT 0,						-- Units will request ResourceType of higher desirability first
		LogisticCost REAL NOT NULL DEFAULT 0,							-- Personnel in cities required to maintain one piece of this equipment
		Toughness INTEGER NOT NULL CHECK (Toughness > 0) DEFAULT 1,		-- Global value used to determine if a equipment casualty result in destruction or damage (or prevent the equipment casualty and sent it to reserve depending of requirement)
		PersonnelArmor INTEGER,											-- 0 = high death rate, 100 = low death rate
		AntiPersonnel INTEGER,											-- 0 = low kill rate, 100 = high kill rate
		AntiPersonnelArmor INTEGER,										-- 0 = low damage to equipment with PersonnelArmor values, 100 = high damage to equipment with PersonnelArmor values
		IgnorePersonnelArmor INTEGER,									-- lower PersonnelArmor values
		VehicleArmor INTEGER,											-- 0 = high personnel loss from death/capture, 100 = low personnel loss from death/capture
		AntiVehicle INTEGER,											-- 0 = low destruction, 100 = high destruction
		AntiVehicleArmor INTEGER,										-- 0 = low damage to equipment with VehicleArmor values, 100 = high damage to equipment with VehicleArmor values
		IgnoreVehicleArmor INTEGER,										-- 100 = high captured/killed personnel, 0 = low captured/killed personnel
		Reliability INTEGER,											-- Percentage, 100 means no loss from breakdown, lower values means possible loss from unreliability ( = captured or destroyed instead of damaged -> in reserve)
		FuelConsumption INTEGER,
		FuelType TEXT,
		PrereqTech TEXT,
		ObsoleteTech TEXT,
		FixedPrice BOOLEAN NOT NULL CHECK (FixedPrice IN (0,1)) DEFAULT 0, 		-- Not price variation after construction
		MaxPriceVariationPercent INTEGER NOT NULL DEFAULT 100, 					-- Max price variation each turn
		NoExport BOOLEAN NOT NULL CHECK (NoExport IN (0,1)) DEFAULT 0, 			-- Not allowed on international trade routes
		NoTransfer BOOLEAN NOT NULL CHECK (NoTransfer IN (0,1)) DEFAULT 0, 		-- Not allowed on internal trade routes
		SpecialStock BOOLEAN NOT NULL CHECK (SpecialStock IN (0,1)) DEFAULT 0, 	-- Stocked in specific buildings only
		NotLoot BOOLEAN NOT NULL CHECK (NotLoot IN (0,1)) DEFAULT 0, 			-- Can't be captured when attacking cities
		RevealedEra INTEGER NOT NULL DEFAULT 1,
		PRIMARY KEY(ResourceType),
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS EquipmentEffects (
		ResourceType TEXT, 				
		EquipmentEffect TEXT,
		EffectMaxStrength INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY(ResourceType, EquipmentEffect)		-- an equipment could have multiple effects
	);
		
CREATE TABLE IF NOT EXISTS UnitEquipmentClasses (
		UnitType TEXT NOT NULL,
		EquipmentClass TEXT, 																	-- 
		PercentageOfPersonnel INTEGER NOT NULL CHECK (PercentageOfPersonnel >0) DEFAULT 100,	-- Percentage of equipement for personnel, for examples: 100% for 1:1 personnel:equipment ratio (ie "swords"), 50% for 2:1 (ie "chariot"), 25% for 4:1 (ie "tank")
		IsRequired BOOLEAN NOT NULL CHECK (IsRequired IN (0,1)) DEFAULT 1,						-- If required, the equipement is part of the healing table
		CanBeRepaired BOOLEAN NOT NULL CHECK (CanBeRepaired IN (0,1)) DEFAULT 0,				-- Can this equipment be repaired in reserve, or does it need a complete replacement
		UseInStats BOOLEAN NOT NULL CHECK (UseInStats IN (0,1)) DEFAULT 0,						-- Should we track this equipment losses in unit's statistic
		PRIMARY KEY(UnitType, EquipmentClass),
		FOREIGN KEY (UnitType) REFERENCES Units(UnitType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (EquipmentClass) REFERENCES EquipmentClasses(EquipmentClass) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS UnitConstructionResources ( -- Resources needed for an unit construction (but not for reinforcement), added to the required equipment
		UnitType TEXT NOT NULL,
		ResourceType TEXT NOT NULL,
		Quantity INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY(UnitType, ResourceType),
		FOREIGN KEY (UnitType) REFERENCES Units(UnitType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE IF NOT EXISTS PromotionClassEquipmentClasses (
		PromotionClassType TEXT NOT NULL,
		EquipmentClass TEXT, 															-- 
		PercentageOfPersonnel INTEGER,													--  If exist, override the value from the UnitEquipmentClasses table
		VariablePercent BOOLEAN NOT NULL CHECK (VariablePercent IN (0,1)) DEFAULT 0,	-- Override PercentageOfPersonnel with a calculated value
		IsRequired BOOLEAN NOT NULL CHECK (IsRequired IN (0,1)) DEFAULT 1,				-- If required, the equipement is part of the healing table 
		CanBeRepaired BOOLEAN NOT NULL CHECK (CanBeRepaired IN (0,1)) DEFAULT 0,		-- Can this equipment be repaired in reserve, or does it need a complete replacement
		UseInStats BOOLEAN NOT NULL CHECK (UseInStats IN (0,1)) DEFAULT 0,				-- Should we track this equipment losses in unit's statistic
		PRIMARY KEY(PromotionClassType, EquipmentClass),
		FOREIGN KEY (PromotionClassType) REFERENCES UnitPromotionClasses(PromotionClassType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (EquipmentClass) REFERENCES EquipmentClasses(EquipmentClass) ON DELETE CASCADE ON UPDATE CASCADE
	);	
	
CREATE TABLE IF NOT EXISTS MilitaryOrganisationLevels (
		OrganisationLevelType TEXT NOT NULL,				--
		Name TEXT,											-- 
		PromotionType TEXT,			 						-- promotion given to units of that OrganisationLevelType
		SupplyLineLengthFactor REAL NOT NULL,				-- SupplyLineEfficiency = ( 100 - math.pow(distance * SupplyLineLengthFactor,2) ) at 0.3 max distance = 33, at 0.85 max distance = 11, at 1.80 max distance = 5
		MaxPersonnelPercentFromReserve INTEGER NOT NULL,	-- Percentage of max personnel in frontline that can be transfered from reserve when healing
		MaxmaterielPercentFromReserve INTEGER NOT NULL,		-- Percentage of max materiel in frontline that can be transfered from reserve when healing
		MaxHealingPerTurn INTEGER NOT NULL,					-- Max HP per turn when healing
		FOREIGN KEY (PromotionType) REFERENCES UnitPromotions(UnitPromotionType) ON DELETE CASCADE ON UPDATE CASCADE,
		PRIMARY KEY(OrganisationLevelType)
	);
	
CREATE TABLE IF NOT EXISTS MilitaryFormations (
		MilitaryFormationType TEXT NOT NULL,
		Name TEXT,
		PRIMARY KEY(MilitaryFormationType)
	);
	
CREATE TABLE IF NOT EXISTS MilitaryFormationStructures (
		OrganisationLevelType TEXT NOT NULL,
		PromotionClassType TEXT NOT NULL, 		-- unit lines are defined by promotion classes
		MilitaryFormationType TEXT NOT NULL, 	-- 
		PromotionType TEXT, 					-- promotion given to units of that MilitaryFormationType & OrganisationLevelType ("strength in number")
		SizeString TEXT,						-- text to be displayed above the unit flag to show its maximum number of personnel
		FrontLinePersonnel INTEGER NOT NULL,	-- max number of personnel in Frontline
		ReservePersonnel INTEGER NOT NULL,		-- max number of personnel in Reserve (added to the default value which is the number of personnel missing in frontline)
		PRIMARY KEY(OrganisationLevelType, PromotionClassType),
		FOREIGN KEY (PromotionClassType) REFERENCES UnitPromotionClasses(PromotionClassType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (PromotionType) REFERENCES UnitPromotions(UnitPromotionType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (MilitaryFormationType) REFERENCES MilitaryFormations(MilitaryFormationType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (OrganisationLevelType) REFERENCES MilitaryOrganisationLevels(OrganisationLevelType) ON DELETE CASCADE ON UPDATE CASCADE
	);	
	
CREATE TABLE IF NOT EXISTS PopulationNeeds (
		ResourceType TEXT NOT NULL,
		PopulationType TEXT NOT NULL,
		--EffectType TEXT NOT NULL,		-- HUNGER, ... (allow same resource and same population type to have different effect
		AffectedType TEXT NOT NULL,		-- DEATH_RATE, BIRTH_RATE, STABILITY, ... (same resource, same population and same effect can affect multiple point)
		StartEra TEXT,
		EndEra TEXT,
		Priority INTEGER NOT NULL DEFAULT 0, -- higher value means higher priority when consuming resources
		Ratio REAL NOT NULL DEFAULT 0,	-- consumption ratio
		NeededCalculFunction TEXT NOT NULL,	-- function to get the value of the need from Population number
		OnlyBonus BOOLEAN NOT NULL CHECK (OnlyBonus IN (0,1)) DEFAULT 0,	-- only apply effect if stock > needed
		OnlyPenalty BOOLEAN NOT NULL CHECK (OnlyPenalty IN (0,1)) DEFAULT 1,	-- only apply effect if stock < needed		
		EffectCalculFunction TEXT NOT NULL,	-- DIFF (max(0,needed-stock)) | PERCENT (MaxEffectValue*(100-stock/needed*100))	  or needed/stock if stock > needed
		MaxEffectValue INTEGER,			-- max value for the result of EffectCalculType
		Treshold INTEGER,				-- don't apply value under that Treshold
		PRIMARY KEY(ResourceType, PopulationType, AffectedType),
		FOREIGN KEY (ResourceType) REFERENCES Resources(ResourceType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (PopulationType) REFERENCES Populations(PopulationType) ON DELETE CASCADE ON UPDATE CASCADE
	);

CREATE TABLE IF NOT EXISTS CustomYields	(
		YieldType TEXT NOT NULL,
		Name TEXT NOT NULL,
		IconString TEXT NOT NULL,
		OccupiedCityChange REAL NOT NULL DEFAULT 0,
		PRIMARY KEY(YieldType)
	);
	
CREATE TABLE IF NOT EXISTS Building_CustomYieldChanges (
		BuildingType TEXT NOT NULL,
		YieldType TEXT NOT NULL,
		YieldChange INTEGER NOT NULL,
		PRIMARY KEY(BuildingType, YieldType),
		FOREIGN KEY (BuildingType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (YieldType) REFERENCES CustomYields(YieldType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
/* Yields that are related to the city production factor */
CREATE TABLE IF NOT EXISTS Building_YieldPerOutputChanges (
		BuildingType TEXT NOT NULL,
		YieldType TEXT NOT NULL,
		YieldChange REAL NOT NULL,
		MaxYieldChange INTEGER,
		PRIMARY KEY(BuildingType, YieldType),
		FOREIGN KEY (BuildingType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (YieldType) REFERENCES Yields(YieldType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
/* BuildingRealPrereqsOR is created in Unlockers.sql and is a copy of BuildingPrereqs */
CREATE TABLE IF NOT EXISTS BuildingRealPrereqsAND (
		Building TEXT NOT NULL,
		PrereqBuilding TEXT NOT NULL,
		PRIMARY KEY(Building, PrereqBuilding),
		FOREIGN KEY (Building) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (PrereqBuilding) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE
	);

/* Unit_RealBuildingPrereqsOR is created in Unlockers.sql and is a copy of Unit_BuildingPrereqs */
CREATE TABLE IF NOT EXISTS Unit_RealBuildingPrereqsAND (
		Unit TEXT NOT NULL,
		PrereqBuilding TEXT NOT NULL,
		NumSupported INTEGER NOT NULL DEFAULT -1,
		PRIMARY KEY(Unit, PrereqBuilding),
		FOREIGN KEY (Unit) REFERENCES Units(UnitType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (PrereqBuilding) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE UnitUpgradesGCO (
		Unit TEXT NOT NULL UNIQUE,
		UpgradeUnit TEXT NOT NULL,
		PRIMARY KEY(Unit),
		FOREIGN KEY (UpgradeUnit) REFERENCES Units(UnitType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (Unit) REFERENCES Units(UnitType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE BuildingUpgrades (
		BuildingType TEXT NOT NULL UNIQUE,
		UpgradeType TEXT NOT NULL,
		ProductionBonus INTEGER,
		PRIMARY KEY(BuildingType), -- , UpgradeType --< needed ?
		FOREIGN KEY (BuildingType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE,
		FOREIGN KEY (UpgradeType) REFERENCES Buildings(BuildingType) ON DELETE CASCADE ON UPDATE CASCADE
	);
	
CREATE TABLE LeadersTimeLine (
		CivilizationType TEXT NOT NULL,
		LeaderName TEXT NOT NULL,
		Gender TEXT  NOT NULL DEFAULT 'Male' CHECK (Gender IN ('Male', 'Female')),
		StartDate INTEGER NOT NULL,
		EndDate INTEGER NOT NULL,
		GovernmentType TEXT,
		PRIMARY KEY(CivilizationType, LeaderName),
		FOREIGN KEY (CivilizationType) REFERENCES Civilizations(CivilizationType)
	);

CREATE TABLE TechnologyContributionTypes (
		ContributionType TEXT NOT NULL,
		Name TEXT,
		IsResearch BOOLEAN NOT NULL CHECK (IsResearch IN (0,1)) DEFAULT 0,
		IconString TEXT,
		ColorString TEXT,
		PRIMARY KEY(ContributionType)
	);

CREATE TABLE TechnologyRequirementTypes (
		RequirementType TEXT NOT NULL,
		PRIMARY KEY(RequirementType)
	);

CREATE TABLE TechnologyResearchContribution (
		Technology TEXT NOT NULL,
		ContributionType TEXT NOT NULL,
		MaxContributionPercent INTEGER NOT NULL DEFAULT 100,
		PRIMARY KEY(Technology, ContributionType),
		FOREIGN KEY (Technology) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (ContributionType) REFERENCES TechnologyContributionTypes(ContributionType) ON DELETE SET NULL ON UPDATE CASCADE
	);
	
CREATE TABLE TechnologyEventContribution (
		Technology TEXT NOT NULL,
		ContributionType TEXT NOT NULL,
		MaxContributionPercent INTEGER NOT NULL DEFAULT 100,
		TypeTag TEXT,
		PrereqTech TEXT,
		PrereqEra TEXT,
		BaseValue INTEGER NOT NULL DEFAULT 1,
		FOREIGN KEY (ContributionType) REFERENCES TechnologyContributionTypes(ContributionType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (TypeTag) REFERENCES Tags(Tag) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE
	);
	
CREATE TABLE TechnologyEventUnlock (
		Technology TEXT NOT NULL,
		ContributionType TEXT NOT NULL,
		TypeTag TEXT,
		FOREIGN KEY (ContributionType) REFERENCES TechnologyContributionTypes(ContributionType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (TypeTag) REFERENCES Tags(Tag) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (Technology) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE
	);
	
CREATE TABLE TechnologyResearchEventPoints (
		ResearchType TEXT NOT NULL,
		ContributionType TEXT NOT NULL,
		BaseValue INTEGER NOT NULL DEFAULT 1,
		TypeTag TEXT,
		FOREIGN KEY (ContributionType) REFERENCES TechnologyContributionTypes(ContributionType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (TypeTag) REFERENCES Tags(Tag) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (ResearchType) REFERENCES TechnologyContributionTypes(ContributionType) ON DELETE SET NULL ON UPDATE CASCADE
	);
	
CREATE TABLE TechnologyNeedsContribution (
		Technology TEXT NOT NULL,
		ContributionType TEXT NOT NULL,
		MaxContributionPercent INTEGER NOT NULL DEFAULT 100,
		PrereqTech TEXT,
		PrereqEra TEXT,
		BaseValue INTEGER NOT NULL DEFAULT 1,
		FOREIGN KEY (Technology) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (ContributionType) REFERENCES TechnologyContributionTypes(ContributionType) ON DELETE SET NULL ON UPDATE CASCADE
	);

CREATE TABLE TechnologyNeedsRequirement (
		Technology TEXT NOT NULL,
		RequirementType TEXT NOT NULL,
		TypeTag TEXT,
		FOREIGN KEY (Technology) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (TypeTag) REFERENCES Tags(Tag) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (RequirementType) REFERENCES TechnologyRequirementTypes(RequirementType) ON DELETE SET NULL ON UPDATE CASCADE
	);
	
CREATE TABLE TechnologyApplications (
		Application TEXT NOT NULL,
		Cost INTEGER NOT NULL,
		Technology TEXT,
		PrereqApp TEXT,
		PrereqTech TEXT,
		PRIMARY KEY(Application),
		FOREIGN KEY (PrereqApp) REFERENCES TechnologyApplications(Application) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (Technology) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE,
		FOREIGN KEY (PrereqTech) REFERENCES Technologies(TechnologyType) ON DELETE SET NULL ON UPDATE CASCADE
	);

CREATE TABLE TechnologyKnowledgeResourceClass (
		ResourceClass 	TEXT NOT NULL,
		Name		 	TEXT NOT NULL,
		ContributionType TEXT NOT NULL,
		ResourcePrefix	TEXT NOT NULL,
		DecayPer1000 	INTEGER NOT NULL,
		ResearchPer100 	INTEGER NOT NULL,
		PRIMARY KEY(ResourceClass)
	);

-- SupplyRoutes
CREATE TABLE IF NOT EXISTS SupplyRoutes
     (  SupplyRouteType TEXT NOT NULL,				-- River, Sea, Road, Rail, Trader, Airport
        BaseMaintainedRoute INT NOT NULL DEFAULT 0,
        BaseIncomingRoute INT NOT NULL DEFAULT 0,
        BaseRouteLengthEfficiency INT NOT NULL,		-- RouteEfficiency = ( 100 - math.pow(  ( routeLength * ((100-BaseRouteLengthEfficiency)/100) ),2 )  )
        BaseMaxRouteTonnage  INT NOT NULL			-- Maximum tonnage for a route should be the lower value between both end
     );

CREATE TABLE IF NOT EXISTS SupplyRouteChanges
     (   BuildingType TEXT NOT NULL,
         TechnologyType TEXT NOT NULL,
         EraType TEXT NOT NULL,
         ApplicationType TEXT NOT NULL,
         SupplyRouteType TEXT NOT NULL,
         MaintainedRoute INT,			-- Number of trade routes maintained by this building in its city
         IncomingRoute INT,				-- Number of incoming routes to this building
         RouteLengthEfficiencyChange INT,
         MaxRouteTonnageChange  INT);
	
-----------------------------------------------
-- Edit Tables
-----------------------------------------------

/* Civilopedia query */
DELETE FROM CivilopediaPageQueries WHERE SectionId ='BUILDINGS'; -- recreated in GamePlay.xml
