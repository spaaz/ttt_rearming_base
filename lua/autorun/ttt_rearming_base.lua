CreateConVar("ttt_use_weapon_spawn_scripts_lua", "1")

local hl2_ammo_replace = {
   ["item_ammo_pistol"] = "item_ammo_pistol_ttt",
   ["item_box_buckshot"] = "item_box_buckshot_ttt",
   ["item_ammo_smg1"] = "item_ammo_smg1_ttt",
   ["item_ammo_357"] = "item_ammo_357_ttt",
   ["item_ammo_357_large"] = "item_ammo_357_ttt",
   ["item_ammo_revolver"] = "item_ammo_revolver_ttt", -- zm
   ["item_ammo_ar2"] = "item_ammo_pistol_ttt",
   ["item_ammo_ar2_large"] = "item_ammo_smg1_ttt",
   ["item_ammo_smg1_grenade"] = "weapon_zm_pistol",
   ["item_battery"] = "item_ammo_357_ttt",
   ["item_healthkit"] = "weapon_zm_shotgun",
   ["item_suitcharger"] = "weapon_zm_mac10",
   ["item_ammo_ar2_altfire"] = "weapon_zm_mac10",
   ["item_rpg_round"] = "item_ammo_357_ttt",
   ["item_ammo_crossbow"] = "item_box_buckshot_ttt",
   ["item_healthvial"] = "weapon_zm_molotov",
   ["item_healthcharger"] = "item_ammo_revolver_ttt",
   ["item_ammo_crate"] = "weapon_ttt_confgrenade",
   ["item_item_crate"] = "ttt_random_ammo"
};

local hl2_weapon_replace = {
   ["weapon_smg1"] = "weapon_zm_mac10",
   ["weapon_shotgun"] = "weapon_zm_shotgun",
   ["weapon_ar2"] = "weapon_ttt_m16",
   ["weapon_357"] = "weapon_zm_rifle",
   ["weapon_crossbow"] = "weapon_zm_pistol",
   ["weapon_rpg"] = "weapon_zm_sledge",
   ["weapon_slam"] = "item_ammo_pistol_ttt",
   ["weapon_frag"] = "weapon_zm_revolver",
   ["weapon_crowbar"] = "weapon_zm_molotov"
};

local SpawnableSWEPs = nil

local SpawnableAmmoClasses = nil

local SpawnTypes = {"info_player_deathmatch", "info_player_combine",
"info_player_rebel", "info_player_counterterrorist", "info_player_terrorist",
"info_player_axis", "info_player_allies", "gmod_player_start",
"info_player_teamspawn"}

local function RemoveCrowbars()
   for k, ent in ipairs(ents.FindByClass("weapon_zm_improvised")) do
      ent:Remove()
   end
end

local function CreateImportedEnt(cls, pos, ang, kv)
   if not cls or not pos or not ang or not kv then return false end

   local ent = ents.Create(cls)
   if not IsValid(ent) then return false end
   ent:SetPos(pos)
   ent:SetAngles(ang)

   for k,v in pairs(kv) do
      ent:SetKeyValue(k, v)
   end

   ent:Spawn()

   ent:PhysWake()

   return true
end

local function RemoveReplaceables()
   -- This could be transformed into lots of FindByClass searches, one for every
   -- key in the replace tables. Hopefully this is faster as more of the work is
   -- done on the C side. Hard to measure.
   for _, ent in ipairs(ents.FindByClass("item_*")) do
      if hl2_ammo_replace[ent:GetClass()] then
         ent:Remove()
      end
   end

   for _, ent in ipairs(ents.FindByClass("weapon_*")) do
      if hl2_weapon_replace[ent:GetClass()] then
         ent:Remove()
      end
   end
end

local function RemoveWeaponEntities()
   RemoveReplaceables()

   for _, cls in pairs(ents.TTT.GetSpawnableAmmo()) do
      for k, ent in ipairs(ents.FindByClass(cls)) do
         ent:Remove()
      end
   end

   for _, sw in pairs(ents.TTT.GetSpawnableSWEPs()) do
      local cn = WEPS.GetClass(sw)
      for k, ent in ipairs(ents.FindByClass(cn)) do
         ent:Remove()
      end
   end

   ents.TTT.RemoveRagdolls(false)
   RemoveCrowbars()
end

local function RemoveSpawnEntities()
   for k, ent in pairs(GetSpawnEnts(false, true)) do
      ent.BeingRemoved = true -- they're not gone til next tick
      SafeRemoveEntityDelayed(ent, 0)
   end
end

local function CanImportEntitiesLua(map)
   if not tostring(map) then return false end
   if not GetConVar("ttt_use_weapon_spawn_scripts_lua"):GetBool() then return false end

   local fname = "lua/maps/" .. map .. "_ttt.lua"

   return file.Exists(fname, "GAME")
end

local function ImportSettings(map)
   if not CanImportEntitiesLua(map) then return end

   local fname = "lua/maps/" .. map .. "_ttt.lua"
   local buf = file.Read(fname, "GAME")

   local settings = {}

   local lines = string.Explode("\n", buf)
   for k, line in pairs(lines) do
      if string.match(line, "^setting") then
         local key, val = string.match(line, "^setting:\t(%w*) ([0-9]*)")
         val = tonumber(val)

         if key and val then
            settings[key] = val
         else
            ErrorNoHalt("Invalid setting line " .. k .. " in " .. fname .. "\n")
         end
      end
   end

   return settings
end

local classremap = {
   ttt_playerspawn = "info_player_deathmatch"
};

local function ImportEntities(map)
   if not CanImportEntitiesLua(map) then return end

   local fname = "lua/maps/" .. map .. "_ttt.lua"

   local num = 0
   for k, line in ipairs(string.Explode("\n", file.Read(fname, "GAME"))) do
      if (not string.match(line, "^#")) and (not string.match(line, "^setting")) and line != "" and line != "--[[" and line != "--]]" and string.byte(line) != 0 then
         local data = string.Explode("\t", line)

         local fail = true -- pessimism

         if data[2] and data[3] then
            local cls = data[1]
            local ang = nil
            local pos = nil

            local posraw = string.Explode(" ", data[2])
            pos = Vector(tonumber(posraw[1]), tonumber(posraw[2]), tonumber(posraw[3]) + 25)

            local angraw = string.Explode(" ", data[3])
            ang = Angle(tonumber(angraw[1]), tonumber(angraw[2]), tonumber(angraw[3]))

            -- Random weapons have a useful keyval
            local kv = {}
            if data[4] then
               local kvraw = string.Explode(" ", data[4])
               local key = kvraw[1]
               local val = tonumber(kvraw[2])

               if key and val then
                  kv[key] = val
               end
            end

            -- Some dummy ents remap to different, real entity names
            cls = classremap[cls] or cls

            fail = not CreateImportedEnt(cls, pos, ang, kv)
         end

         if fail then
            ErrorNoHalt("Invalid line " .. k .. " in " .. fname .. "\n")
         else
            num = num + 1
         end
      end
   end

   MsgN("Spawned " .. num .. " entities found in script.")

   return true
end

hook.Add( "TTTPrepareRound", "ttt_rearming_base", function()
	if CLIENT then return end
	if CanImportEntitiesLua(game.GetMap()) then
		local map = game.GetMap()
	
   		MsgN("Weapon/ammo placement script found, attempting import...")

   		MsgN("Reading settings from script...")
   		local settings = ImportSettings(map)

   		if tobool(settings.replacespawns) then
      			MsgN("Removing existing player spawns")
      			RemoveSpawnEntities()
   		end

   		MsgN("Removing existing weapons/ammo")
  		RemoveWeaponEntities()

   		MsgN("Importing entities...")
   		local result = ImportEntities(map)
   		if result then
      			MsgN("Weapon placement script import successful!")
   		else
      			ErrorNoHalt("Weapon placement script import failed!\n")
   		end
		SpawnWillingPlayers()
	end	
end)
