dofile("$GAME_DATA/Scripts/game/AnimationUtil.lua")
local renderables = { "$SURVIVAL_DATA/Character/Char_Tools/Char_logbook/char_logbook.rend" }
local renderablesTp = { "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_logbook.rend",
	"$SURVIVAL_DATA/Character/Char_Tools/Char_logbook/char_logbook_tp_animlist.rend" }
local renderablesFp = { "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_logbook.rend",
	"$SURVIVAL_DATA/Character/Char_Tools/Char_logbook/char_logbook_fp_animlist.rend" }

sm.tool.preloadRenderables(renderables)
sm.tool.preloadRenderables(renderablesTp)
sm.tool.preloadRenderables(renderablesFp)


MapTool = class()

function MapTool:client_onCreate()
	self.cl = {}
	self:client_onRefresh()

    load_map_data()
    self.mapIndex = 1
end

function load_map_data()
	g_maps = sm.json.open("$CONTENT_DATA/Maps/maps.json")
	local custom_maps = sm.json.open("$CONTENT_DATA/Maps/custom.json")
	if custom_maps then
		for k,v in ipairs(custom_maps) do
			g_maps[#g_maps+1] = v
		end
	end
end

function MapTool:cl_openGui()
    self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/MapTool.layout")

    self.gui:setOnCloseCallback("cl_onGuiClosed")
    self.gui:setButtonCallback("+1", "cl_change_map")
    self.gui:setButtonCallback("-1", "cl_change_map")

	self.gui:setButtonCallback("DeleteMap", "cl_delete_map_button")
	self.gui:setButtonCallback("LoadMap", "cl_load_map_button")
	self.gui:setButtonCallback("ShareMap", "cl_share_map_button")
	

    self:update_page()

	self.gui:open()
end

function MapTool:update_page()
    local map = g_maps[self.mapIndex]

    self.gui:setText("Title", map.name)
	self.gui:setVisible("DeleteMap", map.custom)
	self.gui:setVisible("ShareMap", map.custom)

	if not map.custom then
		self.gui:setText("Description", map.desc)
		self.gui:setImage("Image", "$CONTENT_DATA/Gui/Images/" .. map.image)
	else
		local unit = "minutes"
		local value = math.floor((os.time() - map.time)/60)
		if value >= 60 then
			unit = "hours"
			value = math.floor(value/60)
			if value >= 24 then
				unit = "days"
				value = math.floor(value/24)
			end
		end

		local date = tostring(value) .. " " .. unit .. " old"
		self.gui:setText("Description", date)
		self.gui:setImage("Image", "$CONTENT_DATA/Gui/Images/CustomMap.png")
	end
end

function MapTool:cl_change_map(button)
    local change = tonumber(button)
    self.mapIndex = self.mapIndex + change
    self.mapIndex = math.min(#g_maps, self.mapIndex)
    self.mapIndex = math.max(1, self.mapIndex)

    self:update_page()
end

function MapTool:cl_createConfirmGui(callback, description)
	self.gui:close()

	self.cl.confirmGui = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/PopUp/PopUp_YN.layout" )
	self.cl.confirmGui:setButtonCallback( "Yes", callback )
	self.cl.confirmGui:setButtonCallback( "No", callback )
	self.cl.confirmGui:setText( "Title", "#{MENU_YN_TITLE_ARE_YOU_SURE}" )
	self.cl.confirmGui:setText( "Message", description )
	self.cl.confirmGui:open()
end

function MapTool:cl_delete_map_button()
	local msg = "#999999Do you REALLY want to DELETE #ff0000" .. g_maps[self.mapIndex].name .. "#999999 FOREVER?"
	self:cl_createConfirmGui("cl_delete_map", msg)
end

function MapTool:cl_delete_map(name)
	if name == "Yes" then
		self.cl.confirmGui:close()
		
		sm.json.save({}, "$CONTENT_DATA/Maps/Custom/".. g_maps[self.mapIndex].blueprint ..".blueprint")

		local custom_maps = sm.json.open("$CONTENT_DATA/Maps/custom.json")
		for k, map in ipairs(custom_maps) do
			if map.name == g_maps[self.mapIndex].name then
				custom_maps[k] = nil
			end
		end
		sm.json.save(custom_maps, "$CONTENT_DATA/Maps/custom.json")
		load_map_data()
		self.mapIndex = math.min(#g_maps, self.mapIndex)


		sm.gui.displayAlertText("Map Deleted!")

	elseif name == "No" then
		self.cl.confirmGui:close()
	end
	self.cl.confirmGui = nil
end

function MapTool:cl_load_map_button()
	local msg = "#999999Do you want to load #00ff00" .. g_maps[self.mapIndex].name .. "#999999?\nThis will END your current game!"
	self:cl_createConfirmGui("cl_load_map", msg)
end

function MapTool:cl_share_map_button()
	sm.event.sendToGame("cl_shareMap", g_maps[self.mapIndex])
end


function MapTool:cl_load_map(name)
	if name == "Yes" then
		self.cl.confirmGui:close()
		
		local map = g_maps[self.mapIndex]
		name = map.blueprint
		if map.custom then
			name = "Custom/" .. name
		end
		self.network:sendToServer("sv_load_map", name)

		sm.gui.displayAlertText("Map Loading...")

	elseif name == "No" then
		self.cl.confirmGui:close()
	end
	self.cl.confirmGui = nil
end

function MapTool:sv_load_map(file)
	local world = self.tool:getOwner():getCharacter():getWorld()
	sm.event.sendToWorld(world, "server_changeMap", file)

	for _, player in ipairs(sm.player.getAllPlayers()) do
		local team = TeamManager.sv_getTeamColor(player)
		if team then
			TeamManager.sv_setTeam(player, nil)
			self.network:sendToClients("client_showMessage", player.name .. " is now a spectator")
		end
	end
end



function MapTool.client_onEquip(self)
    if not sm.isHost then
        sm.tool.forceTool(nil)
        return
    end


	if self.tool:isLocal() then
		self:cl_openGui()
	end

	self:client_onEquipAnimations()
end

function MapTool.client_equipWhileSeated(self)
	if not self.cl.seatedEquiped then
		self:cl_openGui()

		self.cl.seatedEquiped = true
	end
end

function MapTool.cl_onGuiClosed(self)
	sm.tool.forceTool(nil)
	self.cl.seatedEquiped = false
end

function MapTool.client_onUnequip( self ) end






--ANIMATION STUFF BELOW
function MapTool:client_onEquipAnimations()
	self.cl.wantsEquip = true
	self.cl.seatedEquiped = false

	local currentRenderablesTp = {}
	concat(currentRenderablesTp, renderablesTp)
	concat(currentRenderablesTp, renderables)

	local currentRenderablesFp = {}
	concat(currentRenderablesFp, renderablesFp)
	concat(currentRenderablesFp, renderables)

	self.tool:setTpRenderables(currentRenderablesTp)

	if self.tool:isLocal() then
		self.tool:setFpRenderables(currentRenderablesFp)
	end

	--TODO disable animations bc they are funny when broken haha lol xd OMG ROFL LMAO
	self:cl_loadAnimations()
	setTpAnimation(self.tpAnimations, "pickup", 0.0001)

	if self.tool:isLocal() then
		swapFpAnimation(self.fpAnimations, "unequip", "equip", 0.2)
	end
end

function MapTool.client_onRefresh(self)
	self:cl_loadAnimations()
end

function MapTool.client_onUpdate(self, dt)
	-- First person animation
	local isCrouching = self.tool:isCrouching()

	if self.tool:isLocal() then
		updateFpAnimations(self.fpAnimations, self.cl.equipped, dt)
	end

	if not self.cl.equipped then
		if self.cl.wantsEquip then
			self.cl.wantsEquip = false
			self.cl.equipped = true
		end
		return
	end

	local crouchWeight = isCrouching and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight
	local totalWeight = 0.0

	for name, animation in pairs(self.tpAnimations.animations) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min(animation.weight + (self.tpAnimations.blendSpeed * dt), 1.0)

			if animation.looping == true then
				if animation.time >= animation.info.duration then
					animation.time = animation.time - animation.info.duration
				end
			end
			if animation.time >= animation.info.duration - self.cl.blendTime and not animation.looping then
				if (name == "putdown") then
					self.cl.equipped = false
				elseif animation.nextAnimation ~= "" then
					setTpAnimation(self.tpAnimations, animation.nextAnimation, 0.001)
				end
			end
		else
			animation.weight = math.max(animation.weight - (self.tpAnimations.blendSpeed * dt), 0.0)
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs(self.tpAnimations.animations) do

		local weight = animation.weight / totalWeight
		if name == "idle" then
			self.tool:updateMovementAnimation(animation.time, weight)
		elseif animation.crouch then
			self.tool:updateAnimation(animation.info.name, animation.time, weight * normalWeight)
			self.tool:updateAnimation(animation.crouch.name, animation.time, weight * crouchWeight)
		else
			self.tool:updateAnimation(animation.info.name, animation.time, weight)
		end
	end
end

function MapTool.client_onUnequip(self)
	self.cl.wantsEquip = false
	self.cl.seatedEquiped = false
	if sm.exists(self.tool) then
		setTpAnimation(self.tpAnimations, "useExit")
		if self.tool:isLocal() and self.fpAnimations.currentAnimation ~= "unequip" and
			self.fpAnimations.currentAnimation ~= "useExit" then
			swapFpAnimation(self.fpAnimations, "equip", "useExit", 0.2)
		end
	end
end

function MapTool.cl_loadAnimations(self)
	-- TP
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "logbook_use_idle", { looping = true } },
			sprint = { "logbook_sprint" },
			pickup = { "logbook_pickup", { nextAnimation = "useInto" } },
			putdown = { "logbook_putdown" },
			useInto = { "logbook_use_into", { nextAnimation = "idle" } },
			useExit = { "logbook_use_exit", { nextAnimation = "putdown" } }
		}
	)

	local movementAnimations = {
		idle = "logbook_use_idle",
		idleRelaxed = "logbook_idle_relaxed",

		runFwd = "logbook_run_fwd",
		runBwd = "logbook_run_bwd",
		sprint = "logbook_sprint",

		jump = "logbook_jump",
		jumpUp = "logbook_jump_up",
		jumpDown = "logbook_jump_down",

		land = "logbook_jump_land",
		landFwd = "logbook_jump_land_fwd",
		landBwd = "logbook_jump_land_bwd",

		crouchIdle = "logbook_crouch_idle",
		crouchFwd = "logbook_crouch_fwd",
		crouchBwd = "logbook_crouch_bwd"
	}

	for name, animation in pairs(movementAnimations) do
		self.tool:setMovementAnimation(name, animation)
	end

	if self.tool:isLocal() then
		-- FP
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				idle = { "logbook_use_idle", { looping = true } },
				equip = { "logbook_pickup", { nextAnimation = "useInto" } },
				unequip = { "logbook_putdown" },
				useInto = { "logbook_use_into", { nextAnimation = "idle" } },
				useExit = { "logbook_use_exit", { nextAnimation = "unequip" } }
			}
		)
	end

	setTpAnimation(self.tpAnimations, "idle", 5.0)
	self.cl.blendTime = 0.2
end