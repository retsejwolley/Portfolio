local KingCrimson = {}
KingCrimson.__index = KingCrimson

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Dependencies
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DamageHandler = require(ServerScriptService:WaitForChild("DamageHandler"))
local BezierPunch = require(ServerStorage.BezierPunch)
local RagdollHandler = require(Modules:WaitForChild("RagdollHandler"))
local HitboxHandler = require(ServerScriptService:WaitForChild("HitboxHandler"))
local VFXHandler = require(Modules:WaitForChild("VFXHandler"))
local SFXHandler = require(Modules:WaitForChild("SFXHandler"))

local AbilityModels = ServerStorage:WaitForChild("AbilityModels")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InfoFolder = ReplicatedStorage:WaitForChild("AbilityModules")

-- Constants
local STAND_NAME = "KingCrimson"
local AbilityInfo = require(InfoFolder:WaitForChild(STAND_NAME))
local MOVES = AbilityInfo.GetMoves()
local ASSETS = AbilityInfo.GetAssets()

-- Constructor
function KingCrimson.new(player)
	local self = setmetatable({}, KingCrimson)

	self.Player = player
	self.Character = player.Character

	-- Instance specific state management prevents global variable conflicts
	self.State = {
		IsBarraging = false,
		BarrageAnim = nil,
		BarrageSound = nil,
		TimeEraseActive = false,
		AlreadyAttackPos = false,
		StayForwardTask = nil,
		OldTransparencyTable = nil
	}

	return self
end

-- Helper Methods
function KingCrimson:GetStand()
	if not self.Character then return nil end
	return self.Character:FindFirstChild(self.Player.Name .. "_Stand")
end

function KingCrimson:CreateBulletTracer(startPos, endPos)
	local distance = (endPos - startPos).Magnitude
	local tracer = Instance.new("Part")

	tracer.Name = "BulletTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 255, 100)
	tracer.Size = Vector3.new(0.25, 0.25, distance)
	tracer.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = workspace

	local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.In)
	TweenService:Create(tracer, fadeInfo, {Transparency = 1}):Play()
	Debris:AddItem(tracer, 0.25)
end

function KingCrimson:PlayAnim(targetModel, animId, speed)
	if not animId or not targetModel then return nil end

	local humanoid = targetModel:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local track = animator:LoadAnimation(animation)
	track:Play(0.1, 10, speed or 1)

	return track
end

function KingCrimson:AttackPosition(forwardAmount, duration)
	local stand = self:GetStand()
	if not stand then return end

	local standHrp = stand:WaitForChild("HumanoidRootPart")
	local motor = standHrp:FindFirstChild("StandConnector")
	if not motor then return end

	-- Cancel the previous reset task if the player attacks consecutively
	if self.State.AlreadyAttackPos and self.State.StayForwardTask then
		task.cancel(self.State.StayForwardTask)
		self.State.StayForwardTask = nil
	end

	local attackGoal = {C0 = CFrame.new(0, 0, -forwardAmount)}
	local attackInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(motor, attackInfo, attackGoal):Play()
	self.State.AlreadyAttackPos = true

	self.State.StayForwardTask = task.delay(duration, function()
		if motor and motor.Parent then
			local resetGoal = {C0 = CFrame.new(2, 1, 2)}
			local resetInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(motor, resetInfo, resetGoal):Play()
			self.State.AlreadyAttackPos = false
		end
	end)

	task.wait(0.2)
end

-- Core Abilities
function KingCrimson:Summon()
	local existingStand = self:GetStand()

	-- Handle despawn logic if the stand already exists
	if existingStand then
		local hrp = existingStand:FindFirstChild("HumanoidRootPart")
		local motor = hrp and hrp:FindFirstChild("StandConnector")

		if motor then
			TweenService:Create(motor, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {C0 = CFrame.new(0,0,0)}):Play()

			for _, v in pairs(existingStand:GetDescendants()) do	
				if v:IsA("BasePart") then
					TweenService:Create(v, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Transparency = 1}):Play()
				end
			end
		end

		task.delay(0.3, function() 
			if existingStand then existingStand:Destroy() end 
		end)
		return
	end

	-- Handle spawn logic
	if not self.Character then return end
	local hrp = self.Character:WaitForChild("HumanoidRootPart")
	local standModel = AbilityModels:FindFirstChild(STAND_NAME)

	if not standModel then return end

	local standClone = standModel:Clone()
	standClone.Name = self.Player.Name .. "_Stand"
	standClone.Parent = self.Character

	local standHrp = standClone:WaitForChild("HumanoidRootPart")
	for _, v in pairs(standClone:GetDescendants()) do 
		if v:IsA("BasePart") then 
			v.CanCollide = false 
			v.Massless = true 
		end 
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "StandConnector"
	motor.Part0 = hrp
	motor.Part1 = standHrp
	motor.Parent = standHrp
	motor.C0 = CFrame.new(0,0,0)

	SFXHandler.PlaySound(standHrp, ASSETS.Sounds.Summon)
	VFXHandler.PlayVFX(standClone, "#4_Summon", "HumanoidRootPart", 2)

	TweenService:Create(motor, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {C0 = CFrame.new(2,1,2)}):Play()

	if standClone.Parent then 
		self:PlayAnim(standClone, ASSETS.Animations.Idle) 
	end
end

function KingCrimson:BarrageStart()
	local stand = self:GetStand()
	if not stand or self.State.IsBarraging then return end

	local data = MOVES.Barrage
	self.Player:SetAttribute("IsHolding_Barrage", true)
	self.State.IsBarraging = true

	self.State.BarrageSound = SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.Barrage[1], false, 0, ASSETS.Sounds.Barrage[2])
	self.State.BarrageAnim = self:PlayAnim(stand, ASSETS.Animations.Barrage)

	BezierPunch.Start(stand, data.HitDuration)
	self:AttackPosition(data.SelfForward, data.SelfDuration)
	HitboxHandler.Run(self.Player, stand, data)
end

function KingCrimson:BarrageStop()
	if not self.State.IsBarraging then return end

	self.Player:SetAttribute("IsHolding_Barrage", nil)
	self.State.IsBarraging = false

	if self.State.BarrageAnim then self.State.BarrageAnim:Stop(0.2) end
	if self.State.BarrageSound then 
		self.State.BarrageSound:Stop()
		self.State.BarrageSound:Destroy() 
	end

	local stand = self:GetStand()
	if stand then
		BezierPunch.Stop(stand)
		local motor = stand.HumanoidRootPart:FindFirstChild("StandConnector")
		if motor then
			TweenService:Create(motor, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {C0 = CFrame.new(2, 1, 2)}):Play()
		end
	end
end

function KingCrimson:Heavy()
	local stand = self:GetStand()
	if not stand then return end

	local data = MOVES.Heavy
	SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.Heavy)

	self:PlayAnim(stand, ASSETS.Animations.Heavy, 2.25)
	self:AttackPosition(data.SelfForward, data.SelfDuration)

	task.delay(0.35, function()
		HitboxHandler.Run(self.Player, stand, data)
	end)
end

function KingCrimson:Punch()
	local stand = self:GetStand()
	if not stand then return end

	local data = MOVES.Punch
	self:PlayAnim(stand, ASSETS.Animations.M1, 2)
	self:AttackPosition(data.SelfForward, data.SelfDuration)

	HitboxHandler.Run(self.Player, stand, data)
end

function KingCrimson:Chop()
	local stand = self:GetStand()
	if not stand then return end

	local data = table.clone(MOVES.Chop)
	local speed = 1

	-- Apply buffs if Time Erase is currently active
	if self.State.TimeEraseActive then
		speed = 2
		data.DPSTotal = 50
		data.Ragdoll = true
		BezierPunch.Start(stand, 0.75)
	end

	SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.Chop)
	self:PlayAnim(stand, ASSETS.Animations.Chop, speed)
	self:AttackPosition(data.SelfForward, data.SelfDuration)

	task.delay(0.3 / speed, function()
		HitboxHandler.Run(self.Player, stand, data)
	end)
end

function KingCrimson:ReverseErase()
	if not self.State.TimeEraseActive then return end

	Remotes.ScreenAction:FireClient(self.Player, "TimeErase")

	if self.Character then
		local hum = self.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 end

		local hrp = self.Character:FindFirstChild("HumanoidRootPart")
		if hrp then SFXHandler.PlaySound(hrp, ASSETS.Sounds.TimeEraseStop) end

		self.Character:SetAttribute("Safe", nil)
		self.Character:SetAttribute("TimeErase", nil)

		-- Restore visibility dynamically to prevent memory leaks
		if self.State.OldTransparencyTable then
			for _, info in pairs(self.State.OldTransparencyTable) do
				if info.Part then info.Part.Transparency = info.OldTrans end
			end
		end

		self.State.OldTransparencyTable = nil
	end

	task.wait(1)
	self.State.TimeEraseActive = false
end

function KingCrimson:TimeEraseStart()
	local stand = self:GetStand()
	if not self.Character or not stand then return end

	local hum = self.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	end

	local data = MOVES.TimeErase
	self.Character:SetAttribute("Safe", true)
	self.Character:SetAttribute("TimeErase", true)
	self.State.TimeEraseActive = true

	local anim = self:PlayAnim(stand, ASSETS.Animations.TimeEraseStand)
	self:PlayAnim(self.Character, ASSETS.Animations.TimeErasePlayer)
	self:AttackPosition(data.SelfForward, data.SelfDuration)	

	SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.TimeErase, false, 0, 1.5)

	anim.KeyframeReached:Once(function(name)
		if name ~= "Erase" then return end

		if hum then
			hum.WalkSpeed = 32
			hum.JumpPower = 50
		end

		self.State.OldTransparencyTable = {}

		-- Map current elements to store their original transparency state
		for _, part in pairs(self.Character:GetDescendants()) do
			if (part:IsA("BasePart") and part.Name ~= "HumanoidRootPart") or part:IsA("Decal") or part:IsA("Texture") then
				table.insert(self.State.OldTransparencyTable, {
					Part = part,
					OldTrans = part.Transparency
				})
				part.Transparency = 1
			end
		end

		-- Dispatch UI event to client
		Remotes.ScreenAction:FireClient(self.Player, "TimeErase", {
			Duration = data.Duration, 
			Weight = 2.5,
			State = true, 
			List = self.State.OldTransparencyTable
		})

		task.delay(data.Duration, function()
			self:ReverseErase()
		end)
	end)
end

function KingCrimson:TimeEraseStop()
	self:ReverseErase()
end

function KingCrimson:Epitaph()
	if not self.Character then return end
	local root = self.Character:FindFirstChild("HumanoidRootPart")
	local hum = self.Character:FindFirstChildOfClass("Humanoid")

	local moveData = MOVES.Epitaph
	local duration = moveData.Duration or 2

	self.Character:SetAttribute("StandName", "KingCrimson")
	self.Character:SetAttribute("Countering", "Epitaph")

	if root and ASSETS.Sounds.Epitaph then
		SFXHandler.PlaySound(root, ASSETS.Sounds.Epitaph, false, 0, 2)
	end

	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	end

	local shadow = Instance.new("Highlight")
	shadow.Name = "CounterShadow"
	shadow.Parent = self.Character
	shadow.FillColor = Color3.new(0, 0, 0)
	shadow.OutlineTransparency = 1
	shadow.FillTransparency = 1
	shadow.DepthMode = Enum.HighlightDepthMode.Occluded

	local tweenInfo = TweenInfo.new(duration / 2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(shadow, tweenInfo, {FillTransparency = 0.1}):Play()

	task.delay(duration, function()
		if self.Character:GetAttribute("Countering") == "Epitaph" then
			self.Character:SetAttribute("Countering", nil)

			if shadow then
				local endTween = TweenService:Create(shadow, TweenInfo.new(0.5), {FillTransparency = 1})
				endTween:Play()
				endTween.Completed:Wait()
				shadow:Destroy()
			end

			if hum then
				hum.WalkSpeed = 16
				hum.JumpPower = 50
			end
		end
	end)
end

function KingCrimson:EpitaphApply(attackerChar)
	local victimRoot = self.Character:FindFirstChild("HumanoidRootPart")
	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart")

	-- Clear counter state
	self.Character:SetAttribute("Countering", nil)
	local shadow = self.Character:FindFirstChild("CounterShadow")
	if shadow then shadow:Destroy() end

	if victimRoot and attackerRoot then
		SFXHandler.PlaySound(victimRoot, ASSETS.Sounds.TimeSkip, false, 0, 1)

		-- Position behind the attacker
		local behindCFrame = attackerRoot.CFrame * CFrame.new(0, 0, 5)
		victimRoot.CFrame = CFrame.lookAt(behindCFrame.Position, attackerRoot.Position)

		task.delay(0.3, function() 
			if not self.Character.Parent or not attackerChar.Parent then return end

			local hum = self.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.AutoRotate = false
				hum.WalkSpeed = 0 
				hum.JumpPower = 0
			end

			HitboxHandler.Run(self.Player, self.Character, MOVES.Epitaph)

			task.delay(0.5, function() 
				if hum then
					hum.AutoRotate = true
					hum.WalkSpeed = 16
					hum.JumpPower = 50
				end
			end)
		end)
	end
end

return KingCrimson
