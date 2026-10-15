-- Remotes (ModuleScript) - the one place RemoteEvents are declared.
-- The server creates them (and must require this module early); clients wait for them.
-- Usage: Remotes.Get("HouseAssigned")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local EVENT_NAMES = {
	"ClientReady", -- client -> server: "my scripts are loaded, tell me about my house"
	"HouseAssigned", -- server -> client: (houseId: number)
}

local Remotes = {}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(EVENT_NAMES) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.Get(name)
	if not table.find(EVENT_NAMES, name) then
		error("Unknown remote: " .. tostring(name), 2)
	end
	return folder:WaitForChild(name)
end

return Remotes
