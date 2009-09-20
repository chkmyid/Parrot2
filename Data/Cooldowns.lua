local Parrot = Parrot

local mod = Parrot:NewModule("Cooldowns", "AceEvent-3.0", "AceTimer-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale("Parrot_Cooldowns")

local newList, del = Parrot.newList, Parrot.del
local deepCopy = Parrot.deepCopy
local debug = Parrot.debug

local wipe = table.wipe

local db = nil
local dbDefaults = {
	profile = {
		threshold = 0,
		filters = {},
	}
}

local GCD = 1.8

function mod:OnInitialize()
	db = Parrot.db1:RegisterNamespace("Cooldowns", dbDefaults)
end

function mod:OnEnable()
	self:ResetSpells()

	self:ScheduleRepeatingTimer("OnUpdate", 0.1)
	self:RegisterEvent("SPELLS_CHANGED", "ResetSpells")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
end

Parrot:RegisterCombatEvent{
	category = "Notification",
	subCategory = L["Cooldowns"],
	name = "Skill cooldown finish",
	localName = L["Skill cooldown finish"],
	defaultTag = L["[[Spell] ready!]"],
	tagTranslations = {
		Spell = 1,
		Icon = 2,
	},
	tagTranslationHelp = {
		Spell = L["The name of the spell or ability which is ready to be used."],
	},
	color = "ffffff", -- white
	sticky = false,
}

local cooldowns = {}

function mod:GetCDs()
	return cooldowns
end

local spellNameToTree = {}

--[[function mod:ResetCooldownState()
	for name, id in pairs(spellNameToID) do
		local start, duration = GetSpellCooldown(id, "spell")
		cooldowns[name] = start > 0 and duration > GCD and duration > db.profile.threshold
	end
end--]]

local nextUpdate
local lastRecalc
local recalcTimer

local expired = {}

local function recalcCooldowns()
	local minCD -- find the Cooldown closest to expiration
	for spell, tree in pairs(spellNameToTree) do
		local old = cooldowns[spell]
		local start, duration = GetSpellCooldown(spell)
		local check = start > 0 and duration > GCD and duration > db.profile.threshold
		cooldowns[spell] = check or nil
		if old and not check then -- cooldown expired
			expired[spell] = tree
		end
		local exp = duration - GetTime() + start -- remaining Cooldown
		if check and (not minCD or minCD > exp) then
			minCD = exp
		end -- if check
	end -- for spell
	nextUpdate = minCD and GetTime() + minCD or nil
	lastRecalc = GetTime()
end

local function delayedRecalc()
	recalcTimer = nil
	recalcCooldowns()
end

function mod:SPELL_UPDATE_COOLDOWN()
	-- if the last update was less then 0.1 seconds ago, the update will be
	-- delayed by 0.1 seconds
	if lastRecalc and (GetTime() - lastRecalc) < 0.1 then
		if not recalcTimer then
			self:ScheduleTimer(delayedRecalc, 0.1, true)
		end
		return
	end
	recalcCooldowns()
end

function mod:ResetSpells()
	wipe(cooldowns)
	wipe(spellNameToTree)
	for i = 1, GetNumSpellTabs() do
		local _, _, offset, num = GetSpellTabInfo(i)
		for j = 1, num do
			local id = offset+j
			local spell = GetSpellName(id, "spell")
			spellNameToTree[spell] = i
		end
	end
	recalcCooldowns()
end

local groups = {
	[GetSpellInfo(14311)] = L["Frost traps"], -- "Freezing Trap"
	[GetSpellInfo(13809)] = L["Frost traps"], -- "Frost Trap"

	[GetSpellInfo(27023)] = L["Fire traps"], -- "Immolation Trap"
	[GetSpellInfo(27025)] = L["Fire traps"], -- "Explosive Trap"
	[GetSpellInfo(63668)] = L["Fire traps"], -- "Black Arrow"

	[GetSpellInfo(25464)] = L["Shocks"], -- "Frost Shock"
	[GetSpellInfo(25457)] = L["Shocks"], -- "Flame Shock"
	[GetSpellInfo(25454)] = L["Shocks"], -- "Earth Shock"

	[GetSpellInfo(53407)] = L["Judgements"], -- Judgement of Justice
	[GetSpellInfo(20271)] = L["Judgements"], -- Judgement of Light
	[GetSpellInfo(53408)] = L["Judgements"], -- Judgement of Wisdom
}

function mod:OnUpdate()
	if not nextUpdate or nextUpdate > GetTime() then
		-- only run the update when the time is right
		return
	end
	recalcCooldowns()
	if not next(expired) then
		return
	end
	local expired2 = deepCopy(expired)
	wipe(expired)
	local treeCount = newList()
	for name, tree in pairs(expired2) do
		Parrot:FirePrimaryTriggerCondition("Spell ready", name)
		if not groups[name] then
			treeCount[tree] = (treeCount[tree] or 0) + 1
		end
	end
	for tree, num in pairs(treeCount) do
		if num >= 3 then
			for name, tree2 in pairs(expired2) do
				-- remove all spells from that tree from the list
				if tree == tree2 then
					expired2[name] = nil
				end
			end
			local name, texture = GetSpellTabInfo(tree)
			local info = newList(L["%s Tree"]:format(name), texture)
			Parrot:TriggerCombatEvent("Notification", "Skill cooldown finish", info)
			info = del(info)
		end
	end
	treeCount = del(treeCount)
	local groupsToTrigger = newList()
	for name in pairs(expired2) do
		if groups[name] then
			groupsToTrigger[groups[name]] = true
			expired2[name] = nil
		end
	end
	for name in pairs(groupsToTrigger) do
		local info = newList(name)
		Parrot:TriggerCombatEvent("Notification", "Skill cooldown finish", info)
		info = del(info)
	end
	groupsToTrigger = del(groupsToTrigger)
	for name in pairs(expired2) do
		local info = newList(name, GetSpellTexture(name, "spell"))
		Parrot:TriggerCombatEvent("Notification", "Skill cooldown finish", info)
		info = del(info)
	end
	expired2 = del(expired2)
end

local function parseSpell(arg)
	return tostring(arg or "")
end
local function saveSpell(arg)
	return tonumber(arg) or arg
end

Parrot:RegisterPrimaryTriggerCondition {
	subCategory = L["Cooldowns"],
	name = "Spell ready",
	localName = L["Spell ready"],
	param = {
		type = 'string',
		usage = L["<Spell name>"],
		save = saveSpell,
		parse = parseSpell,
	},
}

Parrot:RegisterSecondaryTriggerCondition {
	subCategory = L["Cooldowns"],
	name = "Spell ready",
	localName = L["Spell ready"],
	param = {
		type = 'string',
		usage = L["<Spell name>"],
		save = saveSpell,
		parse = parseSpell,
	},
	check = function(param)
		if(tonumber(param)) then
			param = GetSpellInfo(param)
		elseif(type(param) == 'string') then
			return (GetSpellCooldown(param) == 0)
		else
			debug("param was not a string but ", type(param))
			return false
		end
	end,
}

Parrot:RegisterSecondaryTriggerCondition {
	subCategory = L["Cooldowns"],
	name = "Spell usable",
	localName = L["Spell usable"],
	param = {
		type = 'string',
		usage = L["<Spell name>"],
		save = saveSpell,
		parse = parseSpell,
	},
	check = function(param)
		if(tonumber(param)) then
			param = GetSpellInfo(param)
		end

		return IsUsableSpell(param)
	end,
}

function mod:OnOptionsCreate()
	local cd_opt = {
		type = 'group',
		name = L["Cooldowns"],
		desc = L["Cooldowns"],
		args = {
			threshold = {
				name = L["Threshold"],
				desc = L["Minimum time the cooldown must have (in seconds)"],
				type = 'range',
				min = 0,
				max = 300,
				step = 1,
				bigStep = 10,
				get = function() return db.profile.threshold end,
				set = function(info, value) db.profile.threshold = value end,
				order = 1,
			},
		},
		order = 100,
	}

	local function removeFilter(spellName)
		cd_opt.args[spellName] = nil
		db.profile.filters[spellName] = nil
		mod:ResetSpells()
	end

	local function addFilter(spellName)
		if cd_opt.args[spellName] then return end
		db.profile.filters[spellName] = true
		local button = {
			type = 'execute',
			name = spellName,
			desc = L["Click to remove"],
			func = function(info) removeFilter(info.arg) end,
			arg = spellName,
		}
		cd_opt.args[spellName] = button
	end

	cd_opt.args.newFilter = {
		type = 'input',
		name = L["Ignore"],
		desc = L["Ignore Cooldown"],
		get = function() return end,
		set = function(info, value) addFilter(value); mod:ResetSpells() end,
		order = 2,
	}

	for k,v in pairs(db.profile.filters) do
		addFilter(k)
	end

	Parrot:AddOption('cooldowns', cd_opt)
end

