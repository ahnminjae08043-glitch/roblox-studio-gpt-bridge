assert(plugin, "This script must run as a Roblox Studio plugin.")

local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local LogService = game:GetService("LogService")

local DEFAULT_URL = "https://roblox-studio-gpt-bridge.vercel.app"
local POLL_SECONDS = 1.0
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
local toggleButton = toolbar:CreateButton("GPT Bridge", "Open the GPT Bridge connection panel", "")
toggleButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	380,
	560,
	300,
	360
)
local widget = plugin:CreateDockWidgetPluginGuiAsync("RobloxGPTBridgeWidget", widgetInfo)
widget.Title = "Roblox GPT Bridge"

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

makeLabel("Bridge URL", 10)
local urlBox = makeBox(plugin:GetSetting("BridgeUrl") or DEFAULT_URL, 34, DEFAULT_URL)
makeLabel("Shared key", 72)
local keyBox = makeBox(plugin:GetSetting("BridgeKey") or "", 96, "Same value as BRIDGE_API_KEY")
keyBox.TextEditable = true

local connectButton = Instance.new("TextButton")
connectButton.Position = UDim2.fromOffset(12, 142)
connectButton.Size = UDim2.new(1, -24, 0, 36)
connectButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
connectButton.BorderSizePixel = 0
connectButton.Font = Enum.Font.SourceSansSemibold
connectButton.TextSize = 17
connectButton.TextColor3 = Color3.new(1, 1, 1)
connectButton.Text = "Connect"
connectButton.Parent = widget

local pairButton = Instance.new("TextButton")
pairButton.Position = UDim2.fromOffset(12, 188)
pairButton.Size = UDim2.new(1, -24, 0, 34)
pairButton.BackgroundColor3 = Color3.fromRGB(80, 95, 180)
pairButton.BorderSizePixel = 0
pairButton.Font = Enum.Font.SourceSansSemibold
pairButton.TextSize = 16
pairButton.TextColor3 = Color3.new(1, 1, 1)
pairButton.Text = "Create Pairing Code"
pairButton.Parent = widget

local pairingLabel = makeLabel("Not paired", 228, 34)
pairingLabel.TextWrapped = true
pairingLabel.TextColor3 = Color3.fromRGB(160, 175, 240)

local statusLabel = makeLabel("Disconnected", 266, 44)
statusLabel.TextWrapped = true
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)

local pendingLabel = makeLabel("No command awaiting approval", 312, 62)
pendingLabel.TextWrapped = true
pendingLabel.TextColor3 = Color3.fromRGB(215, 190, 120)

local approveButton = Instance.new("TextButton")
approveButton.Position = UDim2.new(0, 12, 0, 380)
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
rejectButton.Position = UDim2.new(0.5, 6, 0, 380)
rejectButton.Size = UDim2.new(0.5, -18, 0, 36)
rejectButton.BackgroundColor3 = Color3.fromRGB(170, 70, 70)
rejectButton.BorderSizePixel = 0
rejectButton.Font = Enum.Font.SourceSansSemibold
rejectButton.TextSize = 17
rejectButton.TextColor3 = Color3.new(1, 1, 1)
rejectButton.Text = "Reject"
rejectButton.Visible = false
rejectButton.Parent = widget

local alwaysAllowChanges = plugin:GetSetting("AlwaysAllowChanges") == true
local alwaysAllowButton = Instance.new("TextButton")
alwaysAllowButton.Position = UDim2.new(0, 12, 0, 426)
alwaysAllowButton.Size = UDim2.new(1, -24, 0, 36)
alwaysAllowButton.BorderSizePixel = 0
alwaysAllowButton.Font = Enum.Font.SourceSansSemibold
alwaysAllowButton.TextSize = 17
alwaysAllowButton.TextColor3 = Color3.new(1, 1, 1)
alwaysAllowButton.Parent = widget

local function refreshAlwaysAllowButton()
	alwaysAllowButton.Text = alwaysAllowChanges and "Always Allow: ON" or "Always Allow: OFF"
	alwaysAllowButton.BackgroundColor3 = alwaysAllowChanges
		and Color3.fromRGB(190, 105, 35)
		or Color3.fromRGB(70, 70, 70)
end
refreshAlwaysAllowButton()

local safetyLabel = makeLabel("Read-only commands run automatically. Always Allow automatically approves every change.", 470, 58)
safetyLabel.TextWrapped = true
safetyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)

local running = false
local pendingDecision = nil
local outputLogs = {}
local deviceId = plugin:GetSetting("BridgeDeviceId") or ""
local deviceToken = plugin:GetSetting("BridgeDeviceToken") or ""
if deviceId ~= "" then pairingLabel.Text = "Paired device: " .. string.sub(deviceId, 1, 8) end

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
	else
		headers["x-bridge-key"] = keyBox.Text
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

pairButton.Activated:Connect(function()
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
		return
	end
	deviceId = result.deviceId
	deviceToken = result.deviceToken
	plugin:SetSetting("BridgeDeviceId", deviceId)
	plugin:SetSetting("BridgeDeviceToken", deviceToken)
	pairingLabel.Text = "Pairing code: " .. result.pairingCode .. " (10 min)"
	pairButton.Text = "Refresh Pairing Code"
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

alwaysAllowButton.Activated:Connect(function()
	alwaysAllowChanges = not alwaysAllowChanges
	plugin:SetSetting("AlwaysAllowChanges", alwaysAllowChanges)
	refreshAlwaysAllowButton()
	if alwaysAllowChanges and pendingDecision == nil and approveButton.Visible then
		pendingDecision = true
	end
end)

local function pollingLoop()
	while running do
		local ok, pollResult = pcall(request, "GET", "/v1/plugin/commands/next")
		if ok then
			statusLabel.Text = "Connected — waiting for GPT commands"
			statusLabel.TextColor3 = Color3.fromRGB(110, 220, 140)
			local command = pollResult.command
			if command then
				statusLabel.Text = "Running: " .. command.action
				local approved = READ_ONLY_ACTIONS[command.action]
					or alwaysAllowChanges
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
			end
		else
			statusLabel.Text = "Connection error: " .. tostring(pollResult)
			statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
		end
		task.wait(POLL_SECONDS)
	end
end

connectButton.Activated:Connect(function()
	running = not running
	if running then
		plugin:SetSetting("BridgeUrl", urlBox.Text)
		plugin:SetSetting("BridgeKey", keyBox.Text)
		connectButton.Text = "Disconnect"
		connectButton.BackgroundColor3 = Color3.fromRGB(170, 70, 70)
		task.spawn(pollingLoop)
	else
		connectButton.Text = "Connect"
		connectButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
		statusLabel.Text = "Disconnected"
		statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	end
end)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

plugin.Unloading:Connect(function()
	running = false
end)
