-- Service
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

-- Remote
local cameraJoin = ReplicatedStorage.Remote:WaitForChild("CameraJoinEvent")
local cameraLeave = ReplicatedStorage.Remote:WaitForChild("CameraLeaveEvent")

local party = {}

local RoomManager = {}
local RoomVariable = {}
RoomManager.__index = RoomManager

function RoomManager.add(Map : Folder, Max : IntValue)
	local JoinPart = Map:WaitForChild("Join")
	local ExitPart = Map:WaitForChild("Exit")
	local BasePart = Map:WaitForChild("Room")
	local SurfaceGui = JoinPart:FindFirstChild("SurfaceGui")

	-- SetAttribtue the map folder
	Map:SetAttribute("Map_Name", "None")
	Map:SetAttribute("PlaceId", 0)

	local MetaTable = {
		Teleporting = false,
		Map = Map,
		Max = Max,
		InQueue = {},
		JoinPart = JoinPart,
		BasePart = BasePart,
		SurfaceGui = SurfaceGui,
		ExitPart = ExitPart,
		CountDown = 0,
		OnChangeCountDown = function() end
	}

	return setmetatable(MetaTable, RoomManager)
end

function RoomManager:AutoStart()
	self.CountDown = 15
	-- Countdown
	self.OnChangeCountDown = function()
		for _, player in ipairs(self.InQueue) do
			if (not player) then
				continue
			end
			local playerGui = player:FindFirstChild("PlayerGui")
			local CountDown = playerGui.PartyUI.CountDownFrame.TextLabel
			CountDown.Text = self.CountDown
			CountDown.Parent.Visible = true	
		end
	end
	
	coroutine.wrap(function()
		while #self.InQueue > 0 and self.CountDown > 0 and #self.InQueue == self.Max do
			self.CountDown -=1
			self.OnChangeCountDown()
			
			if (self.CountDown <= 0) then
				self:Teleport()
			end
			task.wait(1)
		end
	end)()
end

function RoomManager:UpdateVisual()
	-- Update Text
	self.SurfaceGui.MaxPlayers.Text = #self.InQueue .."/".. self.Max
	self.SurfaceGui.MapName.Text = self.Map:GetAttribute("Map_Name")
end

function RoomManager:Check(player)
	for _,plr in ipairs(self.InQueue) do
		if plr == player then
			return true
		end
	end

	return false
end

function RoomManager:Teleport()
	local success, result = pcall(function()
		print("Teleporting Players of ".. self.Map.Name)
		local teleportOption: TeleportOptions = Instance.new("TeleportOptions")
		teleportOption.ShouldReserveServer = true
		TeleportService:TeleportAsync(self.Map:GetAttribute("PlaceId"), self.InQueue, teleportOption)
	end)

	if success then
		self.Teleporting = true
		for _, player in ipairs(self.InQueue) do
			player.Character.HumanoidRootPart.CFrame = self.ExitPart.CFrame + Vector3.new(0, 1, 0)

			local playerGui = player:FindFirstChild("PlayerGui")
			local partyUI = playerGui.PartyUI
			local leaveFrame = partyUI.Frame.LeaveFrame
			local startBtn = playerGui.PartyUI.Frame.StartFrame
			playerGui.TeleportScreen.Enabled = true
			startBtn.Visible = false
			leaveFrame.Visible = false
			partyUI.Frame.Visible = false
			partyUI.Frame.TextLabel.Visible = true
			leaveFrame.Position = UDim2.new(0.34, 0, 0.99, 0)
		end

		self.InQueue = {}
		self.Map:SetAttribute("Map_Name", "None")
		self.Map:SetAttribute("PlaceId", 0)
		self:UpdateVisual()
	else
		self.CountDown = 15
	end
	

end

function RoomManager:JoinSetup()

	-- Touched
	self.JoinPart.Touched:Connect(function(hit)
		if hit.Parent:FindFirstChild("Humanoid") then
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player then
				-- Check apakah player sdh ada diroom?
				if (not self:Check(player)) then
					-- Check apakah room sudah penuh?
					if (#self.InQueue < self.Max) then
						-- Tambahkan player kedalam antrian
						table.insert(self.InQueue, player)
						self:UpdateVisual()
						-- Character Position
						player.Character:SetPrimaryPartCFrame(self.BasePart.CFrame + Vector3.new(0, 2, 0))
						-- Camera
						cameraJoin:FireClient(player, self.Map, hit.Parent)
						-- UI
						local playerGui = player:FindFirstChild("PlayerGui")
						local partyUI = playerGui.PartyUI
						local CountDown = partyUI.CountDownFrame.TextLabel

						partyUI.Frame.Visible = true
						local leaveBtn = playerGui.PartyUI.Frame.LeaveFrame
						-- Tween
						local leaveAnim = TweenService:Create(leaveBtn, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {Position = UDim2.new(0.34, 0, 0.8, 0)})
						leaveBtn.Visible = true
						-- Captain ( Hanya Host yg bisa select map )
						if self.InQueue[1] == player then
							playerGui.MapSelection.Frame.Visible = true
						else
							leaveAnim:Play()
						end
						-- Print
						print(player.Name.." Joined ".. self.Map.Name)
					end

				end

			end
		end
	end)
end

function party:Add(data)
	for _, v in data do
		RoomVariable[v.Folder.Name] = RoomManager.add(v.Folder, v.Max)
		RoomVariable[v.Folder.Name]:JoinSetup()
		RoomVariable[v.Folder.Name]:UpdateVisual()
	end

end

function party:Start(player)
	for name, meta in pairs(RoomVariable) do

		if (meta:Check(player)) then

			-- is Captain?
			if (meta.InQueue[1] == player) then

				-- Is Max and not teleporting
				if (#meta.InQueue == meta.Max and not meta.Teleporting) then
					-- TP
					meta:Teleport()
				else
					warn("player not enough")
				end

			end

		end

	end
end

function party:Leave(player)
	for name, meta in pairs(RoomVariable) do

		if (meta:Check(player)) then
			local isHost = meta.InQueue[1] == player
			table.remove(meta.InQueue, table.find(meta.InQueue, player))
			if (not player.Character) then
				return
			end
			player.Character.HumanoidRootPart.CFrame = meta.ExitPart.CFrame + Vector3.new(0, 1, 0)
			cameraLeave:FireClient(player)

			-- UI
			local playerGui = player:FindFirstChild("PlayerGui")
			local partyUI = playerGui.PartyUI
			local leaveFrame = partyUI.Frame.LeaveFrame
			local startBtn = playerGui.PartyUI.Frame.StartFrame
			local CountDown = playerGui.PartyUI.CountDownFrame.TextLabel
			CountDown.Parent.Visible = false
			startBtn.Visible = false
			leaveFrame.Visible = false
			partyUI.Frame.Visible = false
			partyUI.Frame.TextLabel.Visible = true
			leaveFrame.Position = UDim2.new(0.34, 0, 0.99, 0)
			

			-- Validation
			if (#meta.InQueue == 0) then
				meta.Map:SetAttribute("Map_Name", "None")
				meta.Map:SetAttribute("PlaceId", 0)
			else
				if isHost then
					meta.InQueue[1].PlayerGui.PartyUI.Frame.StartFrame.Visible = true
				end
			end

			meta:UpdateVisual()
		end

	end
end

function party:Select(player, map, mapId)
	for name, meta in pairs(RoomVariable) do

		if (meta:Check(player) and meta.InQueue[1] == player) then
			meta.Map:SetAttribute("Map_Name", map)
			meta.Map:SetAttribute("PlaceId", mapId)
			meta:UpdateVisual()
			-- Active Start Button
			local playerGui = player:FindFirstChild("PlayerGui")
			local startBtn = playerGui.PartyUI.Frame.StartFrame
			local leaveBtn = playerGui.PartyUI.Frame.LeaveFrame
			playerGui.MapSelection.Frame.Visible = false
			-- Tween
			local leaveAnim = TweenService:Create(leaveBtn, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {Position = UDim2.new(0.34, 0, 0.8, 0)})
			startBtn.Visible = true
			leaveBtn.Visible = true
			leaveAnim:Play()
			meta:AutoStart()
		end

	end
end

return party
