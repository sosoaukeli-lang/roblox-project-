-- HouseClient (LocalScript) - tells the player which house is theirs.
-- The server is the only one who decides; this script just shows what it is told.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOAST_SECONDS = 6

local gui = Instance.new("ScreenGui")
gui.Name = "HouseNotice"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.fromScale(0.5, 0.88)
toast.Size = UDim2.fromOffset(420, 52)
toast.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
toast.BackgroundTransparency = 1
toast.TextColor3 = Color3.fromRGB(255, 255, 255)
toast.TextTransparency = 1
toast.TextScaled = true
toast.Font = Enum.Font.SourceSansBold
toast.Parent = gui

local showId = 0
local function showToast(text)
	showId += 1
	local myId = showId
	toast.Text = text
	toast.BackgroundTransparency = 0.25
	toast.TextTransparency = 0
	task.delay(TOAST_SECONDS, function()
		if myId == showId then -- a newer toast replaced this one otherwise
			TweenService:Create(toast, TweenInfo.new(0.6), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end
	end)
end

Remotes.Get("HouseAssigned").OnClientEvent:Connect(function(houseId)
	local info = type(houseId) == "number" and Config.HouseColors[houseId]
	if not info then
		return
	end
	showToast(("بيتك رقم %d - سقفه %s"):format(houseId, info.Name))
end)

-- Connect first, then ask: otherwise the answer could arrive before we listen.
Remotes.Get("ClientReady"):FireServer()
