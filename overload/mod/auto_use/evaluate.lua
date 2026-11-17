local _M = {}

local Config = require "mod.auto_use.config"
local fail_log_cache = setmetatable({}, {__mode="k"})

local function shouldLogFailSkip(self, talent)
	local turn = game and game.turn or 0
	local cache = fail_log_cache[self]
	if not cache or cache.turn ~= turn then
		cache = {turn=turn, talents={}}
		fail_log_cache[self] = cache
	end
	local talent_key = talent.id or talent.name or tostring(talent)
	if cache.talents[talent_key] then return false end
	cache.talents[talent_key] = true
	return true
end

local function logEquilibriumSkip(self, talent, chance, threshold)
	if not shouldLogFailSkip(self, talent) then return end
	game.log("#LIGHT_BLUE#[AT]#LAST# EQ fail chance #RED#%0.1f%%#LAST# >= #ORANGE#%d%%#LAST#, not using: #GOLD#%s#LAST#",
		chance, threshold, talent.name)
end

local function logDebuffSkip(self, talent, chance, threshold, sources)
	if not shouldLogFailSkip(self, talent) then return end
	local source_text = {}
	for _, source in ipairs(sources) do
		source_text[#source_text + 1] = ("%s %0.1f%%"):format(source.label, source.chance)
	end
	game.log("#LIGHT_BLUE#[AT]#LAST# Debuff fail chance #RED#%0.1f%%#LAST# (%s) >= #ORANGE#%d%%#LAST#, not using: #GOLD#%s#LAST#",
		chance, table.concat(source_text, ", "), threshold, talent.name)
end

--- Speed effects that cancel on any non-movement action set one of these
--- temporary values: WILD_SPEED (movement infusion, Escape, Hunter),
--- LIGHTNING_SPEED, and STEP_UP. This mirrors the check in tome/class/Actor.lua
--- that uses them for motion blur.
function _M.hasActiveSpeedEffect(self)
	return self:attr("wild_speed") or self:attr("lightning_speed") or self:attr("step_up")
end

local function hpMatches(self, hp, hp_custom)
	local check = hp_custom or hp
	if not check or not check.op or not check.pct then return true end
	local threshold = self.max_life * check.pct / 100
	if check.op == "<" then return self.life < threshold
	elseif check.op == "<=" then return self.life <= threshold
	elseif check.op == ">" then return self.life > threshold
	elseif check.op == ">=" then return self.life >= threshold
	end
	return true
end

local function effectMatches(cfg, ctx)
	if not cfg then return true end
	if cfg == "physical" then return ctx.physical == 1
	elseif cfg == "mental" then return ctx.mental == 1
	elseif cfg == "magical" then return ctx.magical == 1
	elseif cfg == "any" then return ctx.physical == 1 or ctx.mental == 1 or ctx.magical == 1
	end
	return true
end

local function foeMatchesDistance(self, foe, distance)
	local d = core.fov.distance(self.x, self.y, foe.x, foe.y)
	if distance.min and d < distance.min then return false end
	if distance.max and d > distance.max then return false end
	return true
end

local function foeMatchesRange(self, foe, range_mode, talent_range)
	local dist_euclid = core.fov.distance(self.x, self.y, foe.x, foe.y)
	if range_mode == "melee" then return dist_euclid <= 1
	elseif range_mode == "two_tiles" then return dist_euclid <= 2
	elseif range_mode == "not_adjacent" then return dist_euclid >= 2 and dist_euclid <= talent_range
	elseif range_mode == "talent_max" then return dist_euclid <= talent_range
	end
	return true
end

function _M.buildContext(self, left_click, lc_target)
	local spotted = {}
	if self.x then
		core.fov.calc_circle(self.x, self.y, game.level.map.w, game.level.map.h, self.sight or 10, function(_, x, y) return game.level.map:opaque(x, y) end, function(_, x, y)
			local actor = game.level.map(x, y, game.level.map.ACTOR)
			if actor and self:reactionToward(actor) < 0 and self:canSee(actor) and game.level.map.seens(x, y) then
				spotted[#spotted + 1] = {x=x, y=y, actor=actor}
			end
		end, nil)
	end

	local physical, mental, magical = 0, 0, 0
	for eff_id, p in pairs(self.tmp) do
		local e = self.tempeffect_def[eff_id]
		if e and e.status == "detrimental" then
			if e.type == "physical" then physical = 1
			elseif e.type == "mental" then mental = 1
			elseif e.type == "magical" then magical = 1
			end
		end
	end

	local max_rank = 0
	for _, foe in pairs(spotted) do
		if foe.actor.rank > max_rank then max_rank = foe.actor.rank end
	end

	return {
		spotted = spotted,
		hp80 = self.max_life / 1.2,
		hp60 = self.max_life / 1.65,
		physical = physical,
		mental = mental,
		magical = magical,
		max_rank = max_rank,
		left_click = left_click,
		lc_target = lc_target,
	}
end

local function debuffFailureChance(self, talent)
	if talent.never_fail then return 0, {} end

	local active = self:isTalentActive(talent.id)
	local survival = 1
	local sources = {}
	local function addChance(label, chance)
		chance = util.bound(chance, 0, 100)
		if chance <= 0 then return end
		survival = survival * (1 - chance / 100)
		sources[#sources + 1] = {label=label, chance=chance}
	end

	if not active then
		if talent.is_spell then addChance("#ORCHID#spell#LAST#", self:attr("spell_failure") or 0) end
		if talent.is_nature then addChance("#LIGHT_GREEN#nature#LAST#", self:attr("nature_failure") or 0) end
		if talent.is_mind then addChance("#LIGHT_BLUE#mind#LAST#", self:attr("mind_failure") or 0) end
	end

	if (talent.mode ~= "sustained" or not active)
		and util.getval(talent.no_energy, self, talent) ~= true
		and not self:attr("force_talent_ignore_ressources")
		and not talent.innate
	then
		addChance("#GOLD#talent#LAST#", self:attr("talent_fail_chance") or 0)
	end

	return (1 - survival) * 100, sources
end

--- Called immediately before an auto-use action, after all rule, cooldown,
--- pre-use, target, and ordering checks have passed.
function _M.skipForFailureChance(self, talent)
	if not talent then return false end

	local active = self:isTalentActive(talent.id)
	local checks_equilibrium = talent.equilibrium or
		(talent.sustain_equilibrium and not active)
	if checks_equilibrium and not talent.never_fail
		and not self:attr("force_talent_ignore_ressources")
		and not self:attr("no_equilibrium_fail")
		and (not self:attr("no_equilibrium_summon_fail") or not talent.is_summon)
	then
		local eq_chance = math.min(1, math.max(0,
			math.sqrt(math.max(0, self:getEquilibrium() - self:getWil())) / 60
		)) * 100
		local threshold = Config.equilibriumFailChanceThreshold()
		if eq_chance > 0 and eq_chance >= threshold then
			logEquilibriumSkip(self, talent, eq_chance, threshold)
			return true
		end
	end

	local debuff_chance, debuff_sources = debuffFailureChance(self, talent)
	local threshold = Config.debuffFailChanceThreshold()
	if debuff_chance > 0 and debuff_chance >= threshold then
		logDebuffSkip(self, talent, debuff_chance, threshold, debuff_sources)
		return true
	end
	return false
end

function _M.isSafe(self, ctx)
	if #ctx.spotted > 0 or self:attr("blind") then return false end
	if self.in_combat then return false end
	return true
end

function _M.evaluate(self, cfg, ctx, talent, talent_range)
	if not cfg or not cfg.enabled then return false end

	if Config.noAutoUseDuringSpeedTalents() and _M.hasActiveSpeedEffect(self) then return false end

	if cfg.trigger == "left_click" then
		if not ctx.left_click then return false end
	elseif cfg.trigger == "auto" then
		if ctx.left_click then return false end
	end

	if cfg.resting == true and not self.resting then return false end
	if cfg.resting == false and self.resting then return false end

	if cfg.enemy_presence == "require" and #ctx.spotted == 0 then return false end
	if cfg.enemy_presence == "forbid" and not _M.isSafe(self, ctx) then return false end

	if not hpMatches(self, cfg.hp, cfg.hp_custom) then return false end
	if not effectMatches(cfg.effects, ctx) then return false end

	if cfg.enemy_rank_max and #ctx.spotted > 0 and ctx.max_rank > cfg.enemy_rank_max then
		return false
	end

	if talent.mode == "sustained" then
		if cfg.sustained == "on_when_safe" then
			if self.sustain_talents[talent.id] then return false end
			if not _M.isSafe(self, ctx) then return false end
			return true
		elseif cfg.sustained == "off_when_enemies" then
			if not self.sustain_talents[talent.id] then return false end
			if #ctx.spotted > 0 then return true end
			return false
		elseif cfg.sustained == "off_when_enemies_on_when_safe" then
			if self.sustain_talents[talent.id] then
				if #ctx.spotted > 0 then return true end
				return false
			end
			if not _M.isSafe(self, ctx) then return false end
			return true
		end
	end

	if (cfg.range and cfg.range ~= "none" or cfg.distance) and #ctx.spotted == 0 then
		return false
	end

	if cfg.range and cfg.range ~= "none" then
		if cfg.range == "not_adjacent" then
			for _, foe in pairs(ctx.spotted) do
				if core.fov.distance(self.x, self.y, foe.x, foe.y) <= 1 then
					return false
				end
			end
		end
		local matched = false
		for _, foe in pairs(ctx.spotted) do
			if cfg.distance and not foeMatchesDistance(self, foe, cfg.distance) then
			elseif not foeMatchesRange(self, foe, cfg.range, talent_range) then
			elseif cfg.enemy_rank_max and foe.actor.rank > cfg.enemy_rank_max then
			else
				matched = true
				break
			end
		end
		if not matched then return false end
	elseif cfg.distance and #ctx.spotted > 0 then
		if cfg.distance.min then
			for _, foe in pairs(ctx.spotted) do
				if core.fov.distance(self.x, self.y, foe.x, foe.y) < cfg.distance.min then
					return false
				end
			end
		end
		if cfg.distance.max then
			local matched = false
			for _, foe in pairs(ctx.spotted) do
				if core.fov.distance(self.x, self.y, foe.x, foe.y) <= cfg.distance.max then
					matched = true
					break
				end
			end
			if not matched then return false end
		end
	end

	return true
end

return _M
