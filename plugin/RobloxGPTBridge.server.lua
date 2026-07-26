assert(plugin, "This script must run as a Roblox Studio plugin.")

local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local LogService = game:GetService("LogService")

local DEFAULT_URL = "https://roblox-studio-gpt-bridge.vercel.app"
local PLUGIN_VERSION = "0.4.0"
local ACTIVE_POLL_SECONDS = 1.0
local IDLE_POLL_SECONDS = 8.0
local INACTIVE_POLL_SECONDS = 20.0
local ACTIVE_POLL_WINDOW_SECONDS = 30
local IDLE_DISCONNECT_SECONDS = 15 * 60
local MAX_TREE_CHILDREN = 300
local ALLOWED_CLASSES = {
	Part = true,
	MeshPart = true,
	SpawnLocation = true,
	Folder = true,
	Model = true,
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	BindableEvent = true,
	BindableFunction = true,
	Attachment = true,
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	Sound = true,
	ProximityPrompt = true,
	ClickDetector = true,
	PointLight = true,
	SurfaceLight = true,
	SpotLight = true,
	Atmosphere = true,
	BloomEffect = true,
	BlurEffect = true,
	ColorCorrectionEffect = true,
	DepthOfFieldEffect = true,
	Highlight = true,
	Decal = true,
	Texture = true,
	StringValue = true,
	NumberValue = true,
	IntValue = true,
	BoolValue = true,
	ObjectValue = true,
	ScreenGui = true,
	Frame = true,
	ScrollingFrame = true,
	CanvasGroup = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ViewportFrame = true,
	BillboardGui = true,
	SurfaceGui = true,
	UIListLayout = true,
	UIGridLayout = true,
	UIPageLayout = true,
	UICorner = true,
	UIStroke = true,
	UIPadding = true,
	UIGradient = true,
	UIAspectRatioConstraint = true,
	UISizeConstraint = true,
	UITextSizeConstraint = true,
}
local ALLOWED_CONSTRAINT_CLASSES = {
	BallSocketConstraint = true,
	HingeConstraint = true,
	RopeConstraint = true,
	RodConstraint = true,
	SpringConstraint = true,
	AlignPosition = true,
	AlignOrientation = true,
}

local toolbar = plugin:CreateToolbar("GPT Bridge")
local toggleButton = toolbar:CreateButton(
	"GPT Bridge",
	"Open the GPT Bridge connection panel",
	"rbxassetid://105018980707460"
)
toggleButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	380,
	680,
	300,
	460
)
local widget = plugin:CreateDockWidgetPluginGuiAsync("RobloxGPTBridgeWidget", widgetInfo)
widget.Title = "Studio Builder Bridge"

local function makeLabel(text, y, height)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, y)
	label.Size = UDim2.new(1, -24, 0, height or 22)
	label.Font = Enum.Font.SourceSans
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(225, 225, 225)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = widget
	return label
end

local function makeBox(value, y, placeholder)
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(12, y)
	box.Size = UDim2.new(1, -24, 0, 32)
	box.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Code
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(240, 240, 240)
	box.PlaceholderText = placeholder
	box.Text = value
	box.Parent = widget
	return box
end

makeLabel("Bridge service (fixed for safety)", 10)
local urlBox = makeBox(DEFAULT_URL, 34, DEFAULT_URL)
urlBox.TextEditable = false
urlBox.TextColor3 = Color3.fromRGB(170, 185, 225)

local connectButton = Instance.new("TextButton")
connectButton.Position = UDim2.fromOffset(12, 82)
connectButton.Size = UDim2.new(1, -24, 0, 36)
connectButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
connectButton.BorderSizePixel = 0
connectButton.Font = Enum.Font.SourceSansSemibold
connectButton.TextSize = 17
connectButton.TextColor3 = Color3.new(1, 1, 1)
connectButton.Text = "Connect"
connectButton.Parent = widget

local pairButton = Instance.new("TextButton")
pairButton.Position = UDim2.fromOffset(12, 128)
pairButton.Size = UDim2.new(1, -24, 0, 34)
pairButton.BackgroundColor3 = Color3.fromRGB(80, 95, 180)
pairButton.BorderSizePixel = 0
pairButton.Font = Enum.Font.SourceSansSemibold
pairButton.TextSize = 16
pairButton.TextColor3 = Color3.new(1, 1, 1)
pairButton.Text = "Create Pairing Code"
pairButton.Parent = widget

local pairingLabel = makeBox("", 174, "Pairing code appears here")
pairingLabel.TextEditable = false
pairingLabel.TextColor3 = Color3.fromRGB(160, 175, 240)

local statusLabel = makeLabel("Disconnected", 214, 44)
statusLabel.TextWrapped = true
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)

local pendingLabel = makeLabel("No command awaiting approval", 260, 62)
pendingLabel.TextWrapped = true
pendingLabel.TextColor3 = Color3.fromRGB(215, 190, 120)

local approveButton = Instance.new("TextButton")
approveButton.Position = UDim2.new(0, 12, 0, 328)
approveButton.Size = UDim2.new(0.5, -18, 0, 36)
approveButton.BackgroundColor3 = Color3.fromRGB(35, 145, 75)
approveButton.BorderSizePixel = 0
approveButton.Font = Enum.Font.SourceSansSemibold
approveButton.TextSize = 17
approveButton.TextColor3 = Color3.new(1, 1, 1)
approveButton.Text = "Approve"
approveButton.Visible = false
approveButton.Parent = widget

local rejectButton = Instance.new("TextButton")
rejectButton.Position = UDim2.new(0.5, 6, 0, 328)
rejectButton.Size = UDim2.new(0.5, -18, 0, 36)
rejectButton.BackgroundColor3 = Color3.fromRGB(170, 70, 70)
rejectButton.BorderSizePixel = 0
rejectButton.Font = Enum.Font.SourceSansSemibold
rejectButton.TextSize = 17
rejectButton.TextColor3 = Color3.new(1, 1, 1)
rejectButton.Text = "Next (Reject)"
rejectButton.Visible = false
rejectButton.Parent = widget

local safetyLabel = makeLabel("Safety mode: every change requires approval. New requests wait safely in the server queue.", 374, 58)
safetyLabel.TextWrapped = true
safetyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)

local queueLabel = makeLabel("Queue: 0", 434, 22)
queueLabel.TextColor3 = Color3.fromRGB(180, 200, 235)

local usageLabel = makeLabel("Limits: loading...", 458, 22)
usageLabel.TextColor3 = Color3.fromRGB(180, 200, 180)

local historyLabel = makeLabel("Recent: no completed commands", 482, 48)
historyLabel.TextWrapped = true
historyLabel.TextColor3 = Color3.fromRGB(165, 165, 165)

local reconnectButton = Instance.new("TextButton")
reconnectButton.Position = UDim2.new(0, 12, 0, 536)
reconnectButton.Size = UDim2.new(0.5, -18, 0, 34)
reconnectButton.BackgroundColor3 = Color3.fromRGB(55, 110, 175)
reconnectButton.BorderSizePixel = 0
reconnectButton.Font = Enum.Font.SourceSansSemibold
reconnectButton.TextSize = 16
reconnectButton.TextColor3 = Color3.new(1, 1, 1)
reconnectButton.Text = "Reconnect"
reconnectButton.Parent = widget

local resetButton = Instance.new("TextButton")
resetButton.Position = UDim2.new(0.5, 6, 0, 536)
resetButton.Size = UDim2.new(0.5, -18, 0, 34)
resetButton.BackgroundColor3 = Color3.fromRGB(145, 70, 70)
resetButton.BorderSizePixel = 0
resetButton.Font = Enum.Font.SourceSansSemibold
resetButton.TextSize = 16
resetButton.TextColor3 = Color3.new(1, 1, 1)
resetButton.Text = "Reset Device"
resetButton.Parent = widget

local rejectAllButton = Instance.new("TextButton")
rejectAllButton.Position = UDim2.new(0, 12, 0, 578)
rejectAllButton.Size = UDim2.new(1, -24, 0, 34)
rejectAllButton.BackgroundColor3 = Color3.fromRGB(105, 65, 65)
rejectAllButton.BorderSizePixel = 0
rejectAllButton.Font = Enum.Font.SourceSansSemibold
rejectAllButton.TextSize = 16
rejectAllButton.TextColor3 = Color3.new(1, 1, 1)
rejectAllButton.Text = "Reject All Queued Commands"
rejectAllButton.Parent = widget

local running = false
local connectionGeneration = 0
local pendingDecision = nil
local commandBuffer = {}
local outputLogs = {}
local deviceId = plugin:GetSetting("BridgeDeviceId") or ""
local deviceToken = plugin:GetSetting("BridgeDeviceToken") or ""
if deviceId ~= "" then pairingLabel.Text = "Paired: " .. string.sub(deviceId, 1, 8) end

LogService.MessageOut:Connect(function(message, messageType)
	table.insert(outputLogs, {
		message = tostring(message),
		messageType = tostring(messageType),
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	})
	if #outputLogs > 300 then table.remove(outputLogs, 1) end
end)

local function normalizeBaseUrl(value)
	return string.gsub(value, "/+$", "")
end

local function request(method, path, body)
	local headers = { ["content-type"] = "application/json" }
	if deviceId ~= "" and deviceToken ~= "" then
		headers["x-device-id"] = deviceId
		headers["x-device-token"] = deviceToken
	end
	local response = HttpService:RequestAsync({
		Url = normalizeBaseUrl(urlBox.Text) .. path,
		Method = method,
		Headers = headers,
		Body = body and HttpService:JSONEncode(body) or nil,
	})
	if not response.Success then
		error(("Bridge returned HTTP %d: %s"):format(response.StatusCode, response.Body))
	end
	return HttpService:JSONDecode(response.Body)
end

local function createPairingCode()
	local ok, result = pcall(function()
		local response = HttpService:RequestAsync({
			Url = normalizeBaseUrl(urlBox.Text) .. "/v1/plugin/pairings",
			Method = "POST",
			Headers = { ["content-type"] = "application/json" },
			Body = "{}",
		})
		if not response.Success then error(("Pairing failed: HTTP %d"):format(response.StatusCode)) end
		return HttpService:JSONDecode(response.Body)
	end)
	if not ok then
		pairingLabel.Text = tostring(result)
		return false
	end
	deviceId = result.deviceId
	deviceToken = result.deviceToken
	plugin:SetSetting("BridgeDeviceId", deviceId)
	plugin:SetSetting("BridgeDeviceToken", deviceToken)
	pairingLabel.Text = result.pairingCode
	pairButton.Text = "Refresh Pairing Code"
	return true
end

pairButton.Activated:Connect(function()
	createPairingCode()
end)

local function splitPath(path)
	local parts = {}
	for part in string.gmatch(path or "", "[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

local function resolvePath(path)
	local parts = splitPath(path)
	if #parts == 0 then
		error("A non-empty instance path is required.")
	end
	if string.lower(parts[1]) == "game" then
		if #parts == 1 then return game end
		table.remove(parts, 1)
	end
	local current = game:FindFirstChild(parts[1])
	if not current then
		error("Unknown root service: " .. parts[1])
	end
	for index = 2, #parts do
		current = current:FindFirstChild(parts[index])
		if not current then
			error("Instance path not found: " .. path)
		end
	end
	return current
end

local function instancePath(instance)
	local parts = {}
	local current = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

local function jsonSafe(value)
	local valueType = typeof(value)
	if valueType == "Vector3" then
		return { value.X, value.Y, value.Z }
	elseif valueType == "Vector2" then
		return { value.X, value.Y }
	elseif valueType == "Color3" then
		return {
			math.round(value.R * 255),
			math.round(value.G * 255),
			math.round(value.B * 255),
		}
	elseif valueType == "CFrame" then
		return { value:GetComponents() }
	elseif valueType == "BrickColor" then
		return value.Name
	elseif valueType == "EnumItem" then
		return tostring(value)
	elseif valueType == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif valueType == "UDim" then
		return { value.Scale, value.Offset }
	elseif valueType == "Rect" then
		return { value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }
	elseif valueType == "NumberRange" then
		return { value.Min, value.Max }
	elseif valueType == "ColorSequence" or valueType == "NumberSequence" then
		return tostring(value)
	elseif valueType == "Instance" then
		return instancePath(value)
	elseif valueType == "string" or valueType == "number" or valueType == "boolean" or value == nil then
		return value
	end
	return tostring(value)
end

local function encodePropertyValue(currentValue, value)
	local valueType = typeof(currentValue)
	if type(value) == "table" and value.instancePath then
		return resolvePath(value.instancePath)
	end
	if valueType == "Vector3" then
		return Vector3.new(value[1], value[2], value[3])
	elseif valueType == "Vector2" then
		return Vector2.new(value[1], value[2])
	elseif valueType == "Color3" then
		return Color3.fromRGB(value[1], value[2], value[3])
	elseif valueType == "CFrame" then
		return CFrame.new(table.unpack(value))
	elseif valueType == "UDim2" then
		return UDim2.new(value[1], value[2], value[3], value[4])
	elseif valueType == "UDim" then
		return UDim.new(value[1], value[2])
	elseif valueType == "Rect" then
		return Rect.new(value[1], value[2], value[3], value[4])
	elseif valueType == "NumberRange" then
		return NumberRange.new(value[1], value[2] or value[1])
	elseif valueType == "ColorSequence" then
		local keypoints = {}
		for _, point in value do
			table.insert(keypoints, ColorSequenceKeypoint.new(
				point.time,
				Color3.fromRGB(point.color[1], point.color[2], point.color[3])
			))
		end
		return ColorSequence.new(keypoints)
	elseif valueType == "NumberSequence" then
		local keypoints = {}
		for _, point in value do
			table.insert(keypoints, NumberSequenceKeypoint.new(
				point.time,
				point.value,
				point.envelope or 0
			))
		end
		return NumberSequence.new(keypoints)
	elseif valueType == "BrickColor" then
		return BrickColor.new(value)
	elseif valueType == "EnumItem" then
		local enumTypeName, enumItemName = string.match(value, "^Enum%.([^.]+)%.([^.]+)$")
		if not enumTypeName or not Enum[enumTypeName] or not Enum[enumTypeName][enumItemName] then
			error("Invalid enum value: " .. tostring(value))
		end
		return Enum[enumTypeName][enumItemName]
	end
	return value
end

local function summarize(instance, depth, maxDepth, count)
	count.value += 1
	local item = {
		name = instance.Name,
		className = instance.ClassName,
		path = instancePath(instance),
	}
	if depth < maxDepth and count.value < MAX_TREE_CHILDREN then
		item.children = {}
		for _, child in instance:GetChildren() do
			if count.value >= MAX_TREE_CHILDREN then break end
			table.insert(item.children, summarize(child, depth + 1, maxDepth, count))
		end
	end
	return item
end

local handlers = {}
local READ_ONLY_ACTIONS = {
	get_tree = true,
	search_instances = true,
	get_properties = true,
	get_selection = true,
	search_code = true,
	get_output_logs = true,
}

function handlers.get_tree(args)
	local root = resolvePath(args.path or "Workspace")
	local maxDepth = math.clamp(tonumber(args.maxDepth) or 3, 0, 6)
	return summarize(root, 0, maxDepth, { value = 0 })
end

function handlers.search_instances(args)
	local root = resolvePath(args.rootPath or "Workspace")
	local nameNeedle = string.lower(tostring(args.nameContains or ""))
	local className = args.className
	local maxResults = math.clamp(tonumber(args.maxResults) or 50, 1, 200)
	local results = {}
	local candidates = { root }
	for _, descendant in root:GetDescendants() do
		table.insert(candidates, descendant)
	end
	for _, instance in candidates do
		local nameMatches = nameNeedle == "" or string.find(string.lower(instance.Name), nameNeedle, 1, true) ~= nil
		local classMatches = not className or className == "" or instance.ClassName == className
		if nameMatches and classMatches then
			table.insert(results, {
				name = instance.Name,
				className = instance.ClassName,
				path = instancePath(instance),
			})
			if #results >= maxResults then break end
		end
	end
	return { matches = results, count = #results }
end

function handlers.get_properties(args)
	local instance = resolvePath(args.path)
	local requested = args.properties or {
		"Name", "ClassName", "Parent", "Position", "Size", "Color",
		"Anchored", "CanCollide", "Transparency", "Material", "Enabled",
	}
	local properties = {}
	for _, property in requested do
		local ok, value = pcall(function() return instance[property] end)
		if ok then properties[property] = jsonSafe(value) end
	end
	local attributes = {}
	for name, value in pairs(instance:GetAttributes()) do
		attributes[name] = jsonSafe(value)
	end
	return {
		path = instancePath(instance),
		className = instance.ClassName,
		properties = properties,
		attributes = attributes,
	}
end

function handlers.get_selection(_args)
	local items = {}
	for _, instance in Selection:Get() do
		table.insert(items, {
			path = instancePath(instance),
			name = instance.Name,
			className = instance.ClassName,
		})
	end
	return { items = items, count = #items }
end

function handlers.search_code(args)
	local root = resolvePath(args.rootPath or "game")
	local query = tostring(args.query or "")
	if query == "" then error("query is required.") end
	local caseSensitive = args.caseSensitive == true
	local needle = caseSensitive and query or string.lower(query)
	local maxResults = math.clamp(tonumber(args.maxResults) or 50, 1, 200)
	local results = {}
	local candidates = root == game and game:GetDescendants() or root:GetDescendants()
	for _, instance in candidates do
		if instance:IsA("LuaSourceContainer") then
			local source = instance.Source
			local haystack = caseSensitive and source or string.lower(source)
			local position = string.find(haystack, needle, 1, true)
			if position then
				local line = 1
				for _ in string.gmatch(string.sub(source, 1, position), "\n") do line += 1 end
				table.insert(results, {
					path = instancePath(instance),
					line = line,
					preview = string.sub(source, math.max(1, position - 80), math.min(#source, position + #query + 120)),
				})
				if #results >= maxResults then break end
			end
		end
	end
	return { matches = results, count = #results }
end

function handlers.get_output_logs(args)
	local limit = math.clamp(tonumber(args.limit) or 100, 1, 300)
	local contains = string.lower(tostring(args.contains or ""))
	local results = {}
	for index = #outputLogs, 1, -1 do
		local entry = outputLogs[index]
		if contains == "" or string.find(string.lower(entry.message), contains, 1, true) then
			table.insert(results, 1, entry)
			if #results >= limit then break end
		end
	end
	return { logs = results, count = #results }
end

function handlers.create_instance(args)
	if not ALLOWED_CLASSES[args.className] then
		error("Class is not allowed: " .. tostring(args.className))
	end
	local parent = resolvePath(args.parentPath or "Workspace")
	local instance = Instance.new(args.className)
	instance.Name = args.name or args.className
	for property, value in pairs(args.properties or {}) do
		local ok, currentValue = pcall(function() return instance[property] end)
		if not ok or property == "Parent" or property == "Source" then
			instance:Destroy()
			error("Property is not writable here: " .. property)
		end
		instance[property] = encodePropertyValue(currentValue, value)
	end
	instance.Parent = parent
	return { path = instancePath(instance), className = instance.ClassName }
end

function handlers.duplicate_instance(args)
	local source = resolvePath(args.path)
	if not source.Archivable then error("Instance is not archivable.") end
	local clone = source:Clone()
	clone.Name = args.name or (source.Name .. "Copy")
	clone.Parent = args.parentPath and resolvePath(args.parentPath) or source.Parent
	return { path = instancePath(clone), className = clone.ClassName }
end

function handlers.move_instance(args)
	local instance = resolvePath(args.path)
	local newParent = resolvePath(args.newParentPath)
	if instance == newParent or newParent:IsDescendantOf(instance) then
		error("Cannot move an instance into itself or its descendant.")
	end
	instance.Parent = newParent
	return { path = instancePath(instance), moved = true }
end

function handlers.rename_instance(args)
	local instance = resolvePath(args.path)
	if type(args.newName) ~= "string" or args.newName == "" or #args.newName > 100 then
		error("newName must contain 1 to 100 characters.")
	end
	instance.Name = args.newName
	return { path = instancePath(instance), renamed = true }
end

function handlers.batch_create(args)
	if type(args.items) ~= "table" or #args.items < 1 or #args.items > 100 then
		error("items must contain between 1 and 100 entries.")
	end
	local created = {}
	local ok, result = pcall(function()
		for _, item in args.items do
			local creationResult = handlers.create_instance(item)
			table.insert(created, resolvePath(creationResult.path))
		end
		local paths = {}
		for _, instance in created do table.insert(paths, instancePath(instance)) end
		return { paths = paths, count = #paths }
	end)
	if not ok then
		for _, instance in created do instance:Destroy() end
		error(result)
	end
	return result
end

function handlers.set_properties(args)
	local instance = resolvePath(args.path)
	for property, value in pairs(args.properties or {}) do
		if property == "Parent" or property == "Source" then
			error("Use a dedicated action for property: " .. property)
		end
		local currentValue = instance[property]
		instance[property] = encodePropertyValue(currentValue, value)
	end
	return { path = instancePath(instance), updated = true }
end

function handlers.set_attributes(args)
	local instance = resolvePath(args.path)
	if type(args.attributes) ~= "table" then error("attributes must be an object.") end
	for name, value in pairs(args.attributes) do
		if type(name) ~= "string" or #name > 100 then error("Invalid attribute name.") end
		instance:SetAttribute(name, value)
	end
	return { path = instancePath(instance), updated = true }
end

function handlers.set_script_source(args)
	local instance = resolvePath(args.path)
	if not instance:IsA("LuaSourceContainer") then
		error("Target is not a script.")
	end
	if type(args.source) ~= "string" or #args.source > 200000 then
		error("Script source must be a string of at most 200,000 characters.")
	end
	instance.Source = args.source
	return { path = instancePath(instance), updated = true }
end

function handlers.patch_script(args)
	local instance = resolvePath(args.path)
	if not instance:IsA("LuaSourceContainer") then error("Target is not a script.") end
	local findText = args.find
	local replacement = args.replace
	if type(findText) ~= "string" or findText == "" or type(replacement) ~= "string" then
		error("find and replace must be strings, and find cannot be empty.")
	end
	local source = instance.Source
	local positions = {}
	local cursor = 1
	while true do
		local startPosition, endPosition = string.find(source, findText, cursor, true)
		if not startPosition then break end
		table.insert(positions, { startPosition, endPosition })
		cursor = endPosition + 1
	end
	if #positions == 0 then error("The exact text to patch was not found.") end
	if args.replaceAll ~= true and #positions ~= 1 then
		error(("Expected one match but found %d. Use a more specific find value."):format(#positions))
	end
	if args.replaceAll == true then
		local pieces = {}
		local last = 1
		for _, position in positions do
			table.insert(pieces, string.sub(source, last, position[1] - 1))
			table.insert(pieces, replacement)
			last = position[2] + 1
		end
		table.insert(pieces, string.sub(source, last))
		instance.Source = table.concat(pieces)
	else
		local position = positions[1]
		instance.Source = string.sub(source, 1, position[1] - 1) .. replacement .. string.sub(source, position[2] + 1)
	end
	return { path = instancePath(instance), replacements = args.replaceAll == true and #positions or 1 }
end

function handlers.set_selection(args)
	if type(args.paths) ~= "table" or #args.paths > 100 then error("paths must be an array of at most 100 paths.") end
	local items = {}
	for _, path in args.paths do table.insert(items, resolvePath(path)) end
	Selection:Set(items)
	return { count = #items }
end

function handlers.set_model_pivot(args)
	local instance = resolvePath(args.path)
	if not instance:IsA("PVInstance") then error("Target must be a Model or BasePart.") end
	if type(args.cframe) ~= "table" or (#args.cframe ~= 3 and #args.cframe ~= 12) then
		error("cframe must contain 3 position numbers or 12 CFrame component numbers.")
	end
	instance:PivotTo(CFrame.new(table.unpack(args.cframe)))
	if instance:IsA("Model") and args.scale then
		instance:ScaleTo(tonumber(args.scale))
	end
	return { path = instancePath(instance), pivoted = true }
end

function handlers.set_tags(args)
	local instance = resolvePath(args.path)
	for _, tag in args.add or {} do
		if type(tag) ~= "string" or tag == "" then error("Tags must be non-empty strings.") end
		instance:AddTag(tag)
	end
	for _, tag in args.remove or {} do instance:RemoveTag(tag) end
	return { path = instancePath(instance), tags = instance:GetTags() }
end

function handlers.delete_instance(args)
	local instance = resolvePath(args.path)
	if instance == game or instance.Parent == game then
		error("Services and the DataModel cannot be deleted.")
	end
	local oldPath = instancePath(instance)
	instance:Destroy()
	return { path = oldPath, deleted = true }
end

local function createGuiNode(spec, parent, created)
	if type(spec) ~= "table" or not ALLOWED_CLASSES[spec.className] then
		error("GUI class is not allowed: " .. tostring(spec and spec.className))
	end
	local instance = Instance.new(spec.className)
	instance.Name = spec.name or spec.className
	for property, value in pairs(spec.properties or {}) do
		if property == "Parent" or property == "Source" then error("Invalid GUI property: " .. property) end
		local currentValue = instance[property]
		instance[property] = encodePropertyValue(currentValue, value)
	end
	instance.Parent = parent
	table.insert(created, instance)
	local style = spec.style
	if type(style) == "table" and instance:IsA("GuiObject") then
		local function gradientColor(value)
			local color = value
			if type(value) == "table" and value.color ~= nil then color = value.color end
			if type(color) == "table" then
				return Color3.fromRGB(
					math.clamp(tonumber(color[1]) or 255, 0, 255),
					math.clamp(tonumber(color[2]) or 255, 0, 255),
					math.clamp(tonumber(color[3]) or 255, 0, 255)
				)
			end
			if type(color) == "string" then
				local hex = string.match(color, "^#?(%x%x)(%x%x)(%x%x)$")
				if hex then
					local r, g, b = string.match(color, "^#?(%x%x)(%x%x)(%x%x)$")
					return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
				end
			end
			return Color3.new(1, 1, 1)
		end
		local function gradientTime(stop, index, count)
			local value = type(stop) == "table" and stop.time or nil
			return math.clamp(tonumber(value) or ((index - 1) / math.max(1, count - 1)), 0, 1)
		end
		local function safeColorSequence(stops)
			local keypoints = {}
			for index, stop in ipairs(stops) do
				local stopTable = type(stop) == "table" and stop or { color = stop }
				table.insert(keypoints, ColorSequenceKeypoint.new(
					gradientTime(stopTable, index, #stops),
					gradientColor(stopTable.color or stopTable)
				))
			end
			local ok, sequence = pcall(ColorSequence.new, keypoints)
			return ok and sequence or nil
		end
		local function safeNumberSequence(stops)
			local keypoints = {}
			for index, stop in ipairs(stops) do
				local stopTable = type(stop) == "table" and stop or {}
				local value = stopTable.value or stopTable.transparency or stopTable[1] or stop
				table.insert(keypoints, NumberSequenceKeypoint.new(
					gradientTime(stopTable, index, #stops),
					math.clamp(tonumber(value) or 0, 0, 1)
				))
			end
			local ok, sequence = pcall(NumberSequence.new, keypoints)
			return ok and sequence or nil
		end
		local gradientTarget = instance
		local shadowSpec = style.shadow
		if type(shadowSpec) == "table" and shadowSpec.enabled ~= false then
			local shadow = Instance.new("ImageLabel")
			shadow.Name = instance.Name .. "__GPTShadow"
			shadow.BackgroundTransparency = 1
			shadow.BorderSizePixel = 0
			shadow.Image = tostring(shadowSpec.image or "rbxassetid://1316045217")
			shadow.ImageColor3 = encodePropertyValue(Color3.new(), shadowSpec.color or { 0, 0, 0 })
			shadow.ImageTransparency = math.clamp(tonumber(shadowSpec.transparency) or 0.45, 0, 1)
			shadow.ScaleType = Enum.ScaleType.Slice
			shadow.SliceCenter = Rect.new(10, 10, 118, 118)
			shadow.AnchorPoint = instance.AnchorPoint
			local offsetX = tonumber(shadowSpec.offsetX) or 0
			local offsetY = tonumber(shadowSpec.offsetY) or 6
			local spread = math.max(0, tonumber(shadowSpec.spread) or 12)
			shadow.Position = instance.Position + UDim2.fromOffset(offsetX - spread, offsetY - spread)
			shadow.Size = instance.Size + UDim2.fromOffset(spread * 2, spread * 2)
			shadow.ZIndex = math.max(0, instance.ZIndex - 1)
			shadow.Parent = parent
			table.insert(created, shadow)
		end

		local textureSpec = style.texture
		if type(textureSpec) == "table" and textureSpec.image then
			local texture = Instance.new("ImageLabel")
			texture.Name = instance.Name .. "__GPTTexture"
			texture.BackgroundTransparency = 1
			texture.BorderSizePixel = 0
			texture.Size = UDim2.fromScale(1, 1)
			texture.Image = tostring(textureSpec.image)
			texture.ImageColor3 = encodePropertyValue(Color3.new(1, 1, 1), textureSpec.color or { 1, 1, 1 })
			texture.ImageTransparency = math.clamp(tonumber(textureSpec.transparency) or 0.55, 0, 1)
			texture.ScaleType = Enum.ScaleType.Tile
			local tileWidth = math.max(1, tonumber(textureSpec.tileWidth) or tonumber(textureSpec.tileSize) or 128)
			local tileHeight = math.max(1, tonumber(textureSpec.tileHeight) or tonumber(textureSpec.tileSize) or 128)
			texture.TileSize = UDim2.fromOffset(tileWidth, tileHeight)
			texture.ZIndex = instance.ZIndex
			texture.Parent = instance
			table.insert(created, texture)
			gradientTarget = texture
		end

		local gradientSpec = style.gradient
		if type(gradientSpec) == "table" then
			local gradient = Instance.new("UIGradient")
			gradient.Name = "__GPTGradient"
			gradient.Rotation = tonumber(gradientSpec.rotation) or 90
			local offset = gradientSpec.offset
			if type(offset) == "table" and tonumber(offset[1]) and tonumber(offset[2]) then
				gradient.Offset = Vector2.new(tonumber(offset[1]), tonumber(offset[2]))
			end
			local colors = gradientSpec.colors or gradientSpec.colorStops
			if type(colors) == "table" and #colors >= 2 then
				local sequence = safeColorSequence(colors)
				if sequence then gradient.Color = sequence end
			end
			local transparencies = gradientSpec.transparency or gradientSpec.transparencyStops
			if type(transparencies) == "table" and #transparencies >= 2 then
				local sequence = safeNumberSequence(transparencies)
				if sequence then gradient.Transparency = sequence end
			end
			gradient.Parent = gradientTarget
			table.insert(created, gradient)
		end

		local corners = style.corners
		if type(corners) == "table" then
			local topLeft = math.max(0, tonumber(corners.topLeft) or 0)
			local topRight = math.max(0, tonumber(corners.topRight) or 0)
			local bottomRight = math.max(0, tonumber(corners.bottomRight) or 0)
			local bottomLeft = math.max(0, tonumber(corners.bottomLeft) or 0)
			local fillColor = instance.BackgroundColor3
			local fillTransparency = instance.BackgroundTransparency
			instance.BackgroundTransparency = 1

			local decoration = Instance.new("Frame")
			decoration.Name = "__GPTCornerFill"
			decoration.BackgroundTransparency = 1
			decoration.BorderSizePixel = 0
			decoration.Size = UDim2.fromScale(1, 1)
			decoration.ZIndex = instance.ZIndex
			decoration.Parent = instance
			table.insert(created, decoration)

			local function fill(name, position, size)
				local frame = Instance.new("Frame")
				frame.Name = name
				frame.BorderSizePixel = 0
				frame.BackgroundColor3 = fillColor
				frame.BackgroundTransparency = fillTransparency
				frame.Position = position
				frame.Size = size
				frame.ZIndex = instance.ZIndex
				frame.Parent = decoration
				table.insert(created, frame)
				return frame
			end

			local maxLeft = math.max(topLeft, bottomLeft)
			local maxRight = math.max(topRight, bottomRight)
			fill("CenterHorizontal", UDim2.fromOffset(maxLeft, 0), UDim2.new(1, -maxLeft - maxRight, 1, 0))
			fill("CenterVertical", UDim2.fromOffset(0, math.max(topLeft, topRight)),
				UDim2.new(1, 0, 1, -math.max(topLeft, topRight) - math.max(bottomLeft, bottomRight)))

			local function corner(name, radius, position)
				local diameter = radius * 2
				local frame = fill(name, position, UDim2.fromOffset(math.max(1, diameter), math.max(1, diameter)))
				frame.AnchorPoint = Vector2.new(0.5, 0.5)
				if radius > 0 then
					local uiCorner = Instance.new("UICorner")
					uiCorner.CornerRadius = UDim.new(1, 0)
					uiCorner.Parent = frame
					table.insert(created, uiCorner)
				end
			end

			corner("TopLeft", topLeft, UDim2.fromOffset(topLeft, topLeft))
			corner("TopRight", topRight, UDim2.new(1, -topRight, 0, topRight))
			corner("BottomRight", bottomRight, UDim2.new(1, -bottomRight, 1, -bottomRight))
			corner("BottomLeft", bottomLeft, UDim2.new(0, bottomLeft, 1, -bottomLeft))
		elseif style.cornerRadius ~= nil then
			local uiCorner = Instance.new("UICorner")
			uiCorner.Name = "__GPTCorner"
			uiCorner.CornerRadius = UDim.new(0, math.max(0, tonumber(style.cornerRadius) or 0))
			uiCorner.Parent = instance
			table.insert(created, uiCorner)
		end
	end
	for _, childSpec in spec.children or {} do
		createGuiNode(childSpec, instance, created)
	end
	return instance
end

function handlers.create_gui(args)
	local parent = resolvePath(args.parentPath or "StarterGui")
	local created = {}
	local ok, root = pcall(createGuiNode, args.tree, parent, created)
	if not ok then
		for index = #created, 1, -1 do created[index]:Destroy() end
		error(root)
	end
	return { path = instancePath(root), count = #created }
end

function handlers.create_weld(args)
	local part0 = resolvePath(args.part0Path)
	local part1 = resolvePath(args.part1Path)
	if not part0:IsA("BasePart") or not part1:IsA("BasePart") then
		error("Both weld targets must be BaseParts.")
	end
	local weld = Instance.new("WeldConstraint")
	weld.Name = args.name or "GPTWeld"
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = args.parentPath and resolvePath(args.parentPath) or part0
	return {
		path = instancePath(weld),
		part0 = instancePath(part0),
		part1 = instancePath(part1),
	}
end

function handlers.create_constraint(args)
	if not ALLOWED_CONSTRAINT_CLASSES[args.className] then
		error("Constraint class is not allowed: " .. tostring(args.className))
	end
	local attachment0 = resolvePath(args.attachment0Path)
	local attachment1 = resolvePath(args.attachment1Path)
	if not attachment0:IsA("Attachment") or not attachment1:IsA("Attachment") then
		error("Both targets must be Attachments.")
	end
	local constraint = Instance.new(args.className)
	constraint.Name = args.name or args.className
	for property, value in pairs(args.properties or {}) do
		if property == "Parent" or property == "Attachment0" or property == "Attachment1" then
			error("Invalid constraint property: " .. property)
		end
		local currentValue = constraint[property]
		constraint[property] = encodePropertyValue(currentValue, value)
	end
	constraint.Attachment0 = attachment0
	constraint.Attachment1 = attachment1
	constraint.Parent = args.parentPath and resolvePath(args.parentPath) or attachment0.Parent
	return { path = instancePath(constraint), className = constraint.ClassName }
end

local function materialFromName(value)
	if typeof(value) == "EnumItem" and value.EnumType == Enum.Material then return value end
	local name = string.match(tostring(value), "([^.]+)$")
	local material = Enum.Material[name]
	if not material then error("Invalid terrain material: " .. tostring(value)) end
	return material
end

function handlers.terrain_fill_block(args)
	local terrain = workspace.Terrain
	local cframe = args.cframe
	local size = args.size
	if type(cframe) ~= "table" or (#cframe ~= 3 and #cframe ~= 12) then error("cframe requires 3 or 12 numbers.") end
	if type(size) ~= "table" or #size ~= 3 then error("size requires 3 numbers.") end
	terrain:FillBlock(
		CFrame.new(table.unpack(cframe)),
		Vector3.new(size[1], size[2], size[3]),
		materialFromName(args.material)
	)
	return { filled = true, shape = "block" }
end

function handlers.terrain_fill_ball(args)
	local position = args.position
	if type(position) ~= "table" or #position ~= 3 then error("position requires 3 numbers.") end
	local radius = tonumber(args.radius)
	if not radius or radius <= 0 or radius > 2048 then error("radius must be between 0 and 2048.") end
	workspace.Terrain:FillBall(
		Vector3.new(position[1], position[2], position[3]),
		radius,
		materialFromName(args.material)
	)
	return { filled = true, shape = "ball" }
end

function handlers.terrain_clear_region(args)
	local cframe = args.cframe
	local size = args.size
	if type(cframe) ~= "table" or (#cframe ~= 3 and #cframe ~= 12) then error("cframe requires 3 or 12 numbers.") end
	if type(size) ~= "table" or #size ~= 3 then error("size requires 3 numbers.") end
	workspace.Terrain:FillBlock(
		CFrame.new(table.unpack(cframe)),
		Vector3.new(size[1], size[2], size[3]),
		Enum.Material.Air
	)
	return { cleared = true }
end

function handlers.set_studio_camera(args)
	local camera = workspace.CurrentCamera
	if not camera then error("Workspace has no CurrentCamera.") end
	local cframe = args.cframe
	if type(cframe) ~= "table" or (#cframe ~= 3 and #cframe ~= 12) then error("cframe requires 3 or 12 numbers.") end
	camera.CFrame = CFrame.new(table.unpack(cframe))
	if args.focus then
		local focus = args.focus
		camera.Focus = CFrame.new(focus[1], focus[2], focus[3])
	end
	return { updated = true }
end

function handlers.execute_plan(args)
	if type(args.operations) ~= "table" or #args.operations < 1 or #args.operations > 50 then
		error("operations must contain between 1 and 50 entries.")
	end
	local results = {}
	for index, operation in args.operations do
		if operation.action == "execute_plan" then error("Nested execute_plan is not allowed.") end
		local handler = handlers[operation.action]
		if not handler then error(("Unsupported operation %d: %s"):format(index, tostring(operation.action))) end
		local ok, result = pcall(handler, operation.args or {})
		if not ok then
			error(("Operation %d (%s) failed: %s"):format(index, operation.action, tostring(result)))
		end
		table.insert(results, { index = index, action = operation.action, result = result })
	end
	return { completed = #results, results = results }
end

local function runCommand(command)
	local handler = handlers[command.action]
	if not handler then
		error("Unsupported action: " .. tostring(command.action))
	end

	if READ_ONLY_ACTIONS[command.action] then
		return handler(command.args or {})
	end

	local recording = ChangeHistoryService:TryBeginRecording("GPT Bridge: " .. command.action)
	local ok, result = pcall(handler, command.args or {})
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			Enum.FinishRecordingOperation.Commit
		)
	end
	if not ok then error(result) end
	return result
end

local function commandSummary(command)
	local args = command.args or {}
	local target = args.path or args.parentPath or args.rootPath or ""
	if command.action == "delete_instance" then
		return ("WARNING: DELETE INSTANCE\nTarget: %s\nThis cannot be restored except with Studio Undo."):format(target)
	end
	if command.action == "set_script_source" then
		local source = tostring(args.source or "")
		local preview = string.gsub(string.sub(source, 1, 180), "\n", " ")
		return ("WARNING: REPLACE SCRIPT\nTarget: %s\n%d characters\nPreview: %s"):format(
			target,
			#source,
			preview
		)
	end
	if command.action == "patch_script" then
		local findPreview = string.gsub(string.sub(tostring(args.find or ""), 1, 100), "\n", " ")
		local replacePreview = string.gsub(string.sub(tostring(args.replace or ""), 1, 100), "\n", " ")
		return ("PATCH SCRIPT\nTarget: %s\nFind: %s\nReplace: %s"):format(
			target,
			findPreview,
			replacePreview
		)
	end
	if target ~= "" then
		return ("%s\nTarget: %s"):format(command.action, target)
	end
	return command.action
end

local function awaitApproval(command)
	pendingDecision = nil
	pendingLabel.Text = commandSummary(command)
	approveButton.Visible = true
	rejectButton.Visible = true
	widget.Enabled = true
	while running and pendingDecision == nil do task.wait(0.1) end
	approveButton.Visible = false
	rejectButton.Visible = false
	pendingLabel.Text = "No command awaiting approval"
	return pendingDecision == true
end

approveButton.Activated:Connect(function()
	if pendingDecision == nil then pendingDecision = true end
end)

rejectButton.Activated:Connect(function()
	if pendingDecision == nil then pendingDecision = false end
end)

local function updateBridgeStats(pollResult)
	local serverQueue = tonumber(pollResult.queueCount) or 0
	queueLabel.Text = ("Queue: %d waiting, %d buffered"):format(serverQueue, #commandBuffer)
	local usage = pollResult.usage or {}
	usageLabel.Text = ("Limits remaining: %s / 10 min, %s / day"):format(
		tostring(usage.shortRemaining or "?"),
		tostring(usage.dailyRemaining or "?")
	)
	if pollResult.version and pollResult.version ~= PLUGIN_VERSION then
		statusLabel.Text = ("Update available: plugin %s / server %s"):format(
			PLUGIN_VERSION,
			tostring(pollResult.version)
		)
		statusLabel.TextColor3 = Color3.fromRGB(240, 185, 75)
	end
	local history = pollResult.history or {}
	if history[1] then
		local latest = history[1]
		historyLabel.Text = ("%s: %s - %s"):format(
			latest.ok and "Recent OK" or "Recent FAILED",
			tostring(latest.action or "command"),
			tostring(latest.completedAt or "")
		)
	end
end

local function reportBufferedRejection(command)
	pcall(request, "POST", "/v1/plugin/commands/" .. command.id .. "/result", {
		ok = false,
		error = "Rejected by Reject All in Roblox Studio.",
	})
end

rejectAllButton.Activated:Connect(function()
	if pendingDecision == nil and approveButton.Visible then pendingDecision = false end
	for _, command in ipairs(commandBuffer) do
		reportBufferedRejection(command)
	end
	table.clear(commandBuffer)
	local ok, result = pcall(request, "POST", "/v1/plugin/commands/reject-all", {})
	queueLabel.Text = ok
		and ("Queue cleared: %d rejected"):format(tonumber(result.rejected) or 0)
		or ("Could not clear queue: " .. tostring(result))
end)

local function pollingLoop(generation)
	local lastCommandAt = os.clock()
	local fastPollingUntil = os.clock() + ACTIVE_POLL_WINDOW_SECONDS
	local consecutiveErrors = 0
	while running and generation == connectionGeneration do
		local pollResult = nil
		local ok = true
		if #commandBuffer == 0 then
			ok, pollResult = pcall(request, "GET", "/v1/plugin/commands/next?limit=5")
		end
		if ok then
			consecutiveErrors = 0
			if pollResult then
				updateBridgeStats(pollResult)
				local commands = pollResult.commands or {}
				if #commands == 0 and pollResult.command then commands = { pollResult.command } end
				for _, queuedCommand in ipairs(commands) do
					table.insert(commandBuffer, queuedCommand)
				end
			end
			local now = os.clock()
			local pollSeconds = not widget.Enabled and INACTIVE_POLL_SECONDS
				or (now < fastPollingUntil and ACTIVE_POLL_SECONDS or IDLE_POLL_SECONDS)
			statusLabel.Text = ("Connected - checking every %ds"):format(pollSeconds)
			statusLabel.TextColor3 = Color3.fromRGB(110, 220, 140)
			local command = table.remove(commandBuffer, 1)
			if command then
				queueLabel.Text = ("Queue: %d buffered"):format(#commandBuffer)
				lastCommandAt = now
				fastPollingUntil = now + ACTIVE_POLL_WINDOW_SECONDS
				statusLabel.Text = "Running: " .. command.action
				local approved = READ_ONLY_ACTIONS[command.action]
					or awaitApproval(command)
				local commandOk, result
				if approved then
					commandOk, result = pcall(runCommand, command)
				else
					commandOk, result = false, "Rejected by the user in Roblox Studio."
				end
				local reportOk, reportError = pcall(request, "POST", "/v1/plugin/commands/" .. command.id .. "/result", {
					ok = commandOk,
					result = commandOk and result or nil,
					error = commandOk and nil or tostring(result),
				})
				if not reportOk then
					warn("GPT Bridge could not report the command result:", reportError)
				end
				historyLabel.Text = commandOk
					and ("Recent: OK - " .. command.action)
					or ("Recent: FAILED - " .. command.action .. " - " .. string.sub(tostring(result), 1, 100))
			end
			if os.clock() - lastCommandAt >= IDLE_DISCONNECT_SECONDS then
				running = false
				connectButton.Text = "Connect"
				connectButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
				statusLabel.Text = "Paused after 15 minutes idle - click Connect to resume"
				statusLabel.TextColor3 = Color3.fromRGB(215, 190, 120)
				break
			end
		else
			consecutiveErrors += 1
			statusLabel.Text = "Connection error: " .. tostring(pollResult)
			statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
		end
		local pollSeconds
		if consecutiveErrors > 0 then
			pollSeconds = consecutiveErrors == 1 and 2 or (consecutiveErrors == 2 and 5 or 15)
			statusLabel.Text = ("Offline - retrying in %ds"):format(pollSeconds)
		elseif not widget.Enabled then
			pollSeconds = INACTIVE_POLL_SECONDS
		else
			pollSeconds = os.clock() < fastPollingUntil and ACTIVE_POLL_SECONDS or IDLE_POLL_SECONDS
		end
		task.wait(pollSeconds)
	end
end

local function stopConnection(message)
	running = false
	connectionGeneration += 1
	connectButton.Text = "Connect"
	connectButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
	statusLabel.Text = message or "Disconnected"
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
end

local function startConnection()
	if running then stopConnection("Reconnecting...") end
	connectionGeneration += 1
	local generation = connectionGeneration
	running = true
	task.spawn(function()
		if deviceId == "" or deviceToken == "" then
			statusLabel.Text = "Creating pairing code..."
			if not createPairingCode() then
				stopConnection("Pairing failed - check HTTP Requests and Bridge URL")
				statusLabel.Text = "Pairing failed - check HTTP Requests and Bridge URL"
				statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
				return
			end
		end
		connectButton.Text = "Disconnect"
		connectButton.BackgroundColor3 = Color3.fromRGB(170, 70, 70)
		local statusOk, bridgeStatus = pcall(request, "GET", "/v1/plugin/status")
		if statusOk then updateBridgeStats(bridgeStatus) end
		pollingLoop(generation)
	end)
end

connectButton.Activated:Connect(function()
	if running then
		stopConnection("Disconnected")
	else
		startConnection()
	end
end)

reconnectButton.Activated:Connect(startConnection)

resetButton.Activated:Connect(function()
	if deviceId ~= "" and deviceToken ~= "" then
		pcall(request, "DELETE", "/v1/plugin/device")
	end
	stopConnection("Device reset - create a new pairing code")
	deviceId = ""
	deviceToken = ""
	commandBuffer = {}
	plugin:SetSetting("BridgeDeviceId", "")
	plugin:SetSetting("BridgeDeviceToken", "")
	pairingLabel.Text = ""
	pairButton.Text = "Create Pairing Code"
	queueLabel.Text = "Queue: 0"
	usageLabel.Text = "Limits: pair again to load"
end)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

if deviceId ~= "" and deviceToken ~= "" then
	statusLabel.Text = "Restoring saved device connection..."
	task.defer(startConnection)
end

plugin.Unloading:Connect(function()
	stopConnection("Plugin unloaded")
end)
