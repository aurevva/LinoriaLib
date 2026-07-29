--!nocheck
--!nolint
-- v0.20

local InputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")
local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RenderStepped = RunService.RenderStepped
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local SetThreadIdentity = setthreadidentity or setidentity or setthreadcontext
local GetThreadIdentity = getthreadidentity or getidentity or getthreadcontext
local SetHiddenProperty = sethiddenproperty or sethiddenprop
local SetScriptable = setscriptable
local ProtectGui = protectgui or (syn and syn.protect_gui)

local InitialViewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.zero
local IsLargeTouchDesktop = InputService.MouseEnabled
	and InputService.KeyboardEnabled
	and InitialViewport.X >= 1600
	and InitialViewport.Y >= 900
local IsMobile = InputService.TouchEnabled and not IsLargeTouchDesktop
local TouchButtonHeight = IsMobile and 42 or 22
local TouchToggleHeight = IsMobile and 40 or 17
local TouchSliderHeight = IsMobile and 40 or 14
local TouchKeyHeight = IsMobile and 40 or 17
local TouchDropdownRowHeight = IsMobile and 42 or 20
local ControlTextOffset = 1

local _clickHeld = false
local ActiveTouchInputs = {}
local ActivePointerInput = nil
local function IsClickInput(Input)
	local isClick = Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch
	if isClick and Input.UserInputState ~= Enum.UserInputState.End then
		_clickHeld = true
		if Input.UserInputType == Enum.UserInputType.Touch then
			ActiveTouchInputs[Input] = true
			ActivePointerInput = Input
		end
	end
	return isClick
end

local function IsClickHeld()
	if next(ActiveTouchInputs) ~= nil then return true end
	local MouseDown = false
	pcall(function() MouseDown = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
	return _clickHeld or MouseDown
end

local function GetPointerPosition(Input)
	local Pointer = Input or ActivePointerInput
	if Pointer and Pointer.UserInputType == Enum.UserInputType.Touch
		and (Input ~= nil or Pointer.UserInputState ~= Enum.UserInputState.End)
	then
		return Pointer.Position
	end
	return Vector2.new(Mouse.X, Mouse.Y)
end

local function IsPointerHeld(Input)
	if Input and Input.UserInputType == Enum.UserInputType.Touch then
		return ActiveTouchInputs[Input] == true
	end
	return IsClickHeld()
end

local function ReleasePointer(Input)
	if Input.UserInputType == Enum.UserInputType.Touch then
		ActiveTouchInputs[Input] = nil
		if ActivePointerInput == Input then
			ActivePointerInput = next(ActiveTouchInputs)
		end
	end
	if next(ActiveTouchInputs) == nil then
		local MouseDown = false
		pcall(function() MouseDown = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
		_clickHeld = MouseDown
	end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AurevaLinoria"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 2147483647
local MountThread = coroutine.create(function()
	local GotGuiParent, GuiParent = pcall(gethui)
	if not GotGuiParent or typeof(GuiParent) ~= "Instance" then
		error(`gethui failed: {tostring(GuiParent)}`, 0)
	end
	coroutine.yield()
	local Errors = {}
	local function Attempt(label, callback)
		local Success, Result = pcall(callback)
		if Success then return true end
		table.insert(Errors, `{label}: {tostring(Result)}`)
		return false
	end

	if Attempt("Parent", function() ScreenGui.Parent = GuiParent end) then return end
	if typeof(SetHiddenProperty) == "function"
		and Attempt("sethiddenproperty", function() SetHiddenProperty(ScreenGui, "Parent", GuiParent) end)
	then return end
	if typeof(SetScriptable) == "function" then
		pcall(SetScriptable, ScreenGui, "Parent", true)
		if Attempt("setscriptable Parent", function() ScreenGui.Parent = GuiParent end) then return end
	end
	if typeof(ProtectGui) == "function" then
		pcall(ProtectGui, ScreenGui)
		if Attempt("protect_gui Parent", function() ScreenGui.Parent = GuiParent end) then return end
	end
	error(table.concat(Errors, " | "), 0)
end)
local MountThreadReady, MountThreadError = coroutine.resume(MountThread)

-- Auto-scale UI for different resolutions (reference: 1080p)
local Library
local _uiScale = 1
local _invScale = 1
local ScaleSignal = nil
local UpdateScaleCallback = nil
local RequestScaleUpdateCallback = nil
local CameraViewportConnection = nil
local RequiredUiWidth = 580
do
	local BaseHeight = 1080

	local UIScaleObj = Instance.new("UIScale")
	UIScaleObj.Parent = ScreenGui

	local function UpdateScale()
		local Camera = workspace.CurrentCamera
		if not Camera then return end
		local ViewportSize = Camera.ViewportSize
		local HeightScale = ViewportSize.Y / BaseHeight
		local WidthScale = (ViewportSize.X - 24) / RequiredUiWidth
		-- Preserve readable mobile controls; the window is fitted to the viewport separately.
		local NewScale = if IsMobile
			then 1
			else math.clamp(math.min(HeightScale, WidthScale), 0.45, 1)
		if NewScale <= 0 then NewScale = 0.45 end
		local PreviousIdentity = nil
		if typeof(GetThreadIdentity) == "function" then
			local ReadIdentity, Identity = pcall(GetThreadIdentity)
			if ReadIdentity and typeof(Identity) == "number" then PreviousIdentity = Identity end
		end
		if typeof(SetThreadIdentity) == "function" then pcall(SetThreadIdentity, 8) end
		local Applied, ApplyError = pcall(function() UIScaleObj.Scale = NewScale end)
		if PreviousIdentity ~= nil and typeof(SetThreadIdentity) == "function" then
			pcall(SetThreadIdentity, PreviousIdentity)
		end
		if not Applied then
			if Library then Library.LastUiError = tostring(ApplyError) end
			return
		end
		_uiScale = NewScale
		_invScale = 1 / NewScale
		if Library and not Library.Unloaded then
			Library:DelayUi(0, function()
				if typeof(Library.UpdateViewportLayout) == "function" then Library:UpdateViewportLayout() end
				if typeof(Library.RepositionPopups) == "function" then Library:RepositionPopups() end
			end)
		end
	end

	local function ScheduleScaleUpdate()
		if Library and not Library.Unloaded then
			Library:DelayUi(0, UpdateScale)
		else
			UpdateScale()
		end
	end

	local function BindCamera()
		if CameraViewportConnection then
			CameraViewportConnection:Disconnect()
			CameraViewportConnection = nil
		end
		local Camera = workspace.CurrentCamera
		if Camera then
			CameraViewportConnection = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(ScheduleScaleUpdate)
		end
		ScheduleScaleUpdate()
	end

	BindCamera()
	ScaleSignal = workspace:GetPropertyChangedSignal("CurrentCamera")
	UpdateScaleCallback = BindCamera
	RequestScaleUpdateCallback = ScheduleScaleUpdate
end

-- Convert screen-space coordinates to UI offset coordinates (compensate for UIScale)
local function ScreenToOffset(x, y)
	return x * _invScale, y * _invScale
end

local function GetViewportInsets()
	if not IsMobile then return 0, 0, 0, 0 end
	local LeftInset, TopInset, RightInset, BottomInset = 0, 0, 0, 0
	pcall(function()
		local TopLeft, BottomRight = GuiService:GetGuiInset()
		LeftInset = TopLeft.X * _invScale
		TopInset = TopLeft.Y * _invScale
		RightInset = BottomRight.X * _invScale
		BottomInset = BottomRight.Y * _invScale
	end)
	return LeftInset, TopInset, RightInset, BottomInset
end

local Toggles = {}
local Options = {}

getgenv().Toggles = Toggles
getgenv().Options = Options

Library = {
	Registry = {},
	RegistryMap = {},

	HudRegistry = {},

	FontColor = Color3.fromRGB(220, 220, 224),
	MainColor = Color3.fromRGB(28, 28, 30),
	BackgroundColor = Color3.fromRGB(18, 18, 20),
	AccentColor = Color3.fromRGB(255, 215, 0),
	OutlineColor = Color3.fromRGB(48, 48, 52),
	RiskColor = Color3.fromRGB(232, 93, 117),

	Black = Color3.new(0, 0, 0),
	Font = Enum.Font.RobotoMono,

	OpenedFrames = {},
	PopupAnchors = setmetatable({}, { __mode = "k" }),
	DependencyBoxes = {},

	Signals = {},
	ScreenGui = ScreenGui,
	UiJobs = {},
	UiUpdaters = {},
	UiThreads = setmetatable({}, { __mode = "k" }),
	Mounted = false,
	Unloaded = false,
	CursorRegions = setmetatable({}, { __mode = "k" }),
	CursorOverrideActive = false,
	CursorRestore = nil,

	-- Track all windows for mobile toggle UI functionality
	Windows = {},

	-- Mobile UI lock state
	CantDragForced = false,
	IsMobile = IsMobile,
	MobileMargin = 8,
	MobileController = nil,
	MobileControllerPlaced = false,
	ViewportLayoutScheduled = false,
	LastViewportSize = nil,
}

function Library:RequestViewportLayout()
	if Library.Unloaded or Library.ViewportLayoutScheduled then return end
	Library.ViewportLayoutScheduled = true
	Library:DelayUi(0, function()
		Library.ViewportLayoutScheduled = false
		Library:UpdateViewportLayout()
	end)
end

function Library:UpdateViewportLayout()
	if Library.Unloaded then return end
	local Camera = workspace.CurrentCamera
	local Viewport = Camera and Camera.ViewportSize * _invScale or nil
	local Margin = (Library.MobileMargin or 8) * _invScale
	local LeftInset, TopInset, RightInset, BottomInset = GetViewportInsets()
	local ViewportChanged = Viewport and (not Library.LastViewportSize or Library.LastViewportSize ~= Viewport)
	for _, Window in ipairs(Library.Windows) do
		if Window and type(Window.FitToViewport) == "function" then
			Window:FitToViewport()
		end
		if Window and type(Window.ResizeTabs) == "function" then
			Window:ResizeTabs()
		end
	end
	if IsMobile and Library.NotificationArea and Viewport then
		local NotificationTop = math.max(TopInset + Margin, 48 * _invScale)
		Library.NotificationArea.Position = UDim2.fromOffset(LeftInset + Margin, NotificationTop)
		Library.NotificationArea.Size = UDim2.new(0, math.min(380, math.max(120, Viewport.X - LeftInset - RightInset - Margin * 2)), 1, -(NotificationTop + BottomInset + Margin))
	end
	if IsMobile and Library.MobileController and Library.MobileController.Parent and Viewport then
		local Controller = Library.MobileController
		local Width = Controller.AbsoluteSize.X * _invScale
		local Height = Controller.AbsoluteSize.Y * _invScale
		local X = Controller.Position.X.Scale * Viewport.X + Controller.Position.X.Offset
		local Y = Controller.Position.Y.Scale * Viewport.Y + Controller.Position.Y.Offset
		if not Library.MobileControllerPlaced or ViewportChanged then
			X = LeftInset + (Viewport.X - LeftInset - RightInset) * 0.5
			Y = Viewport.Y - BottomInset - Margin
			Library.MobileControllerPlaced = true
		else
			X = math.clamp(X, LeftInset + Margin + Width * 0.5, math.max(LeftInset + Margin + Width * 0.5, Viewport.X - RightInset - Margin - Width * 0.5))
			Y = math.clamp(Y, TopInset + Margin + Height, math.max(TopInset + Margin + Height, Viewport.Y - BottomInset - Margin))
		end
		Controller.AnchorPoint = Vector2.new(0.5, 1)
		Controller.Position = UDim2.fromOffset(X, Y)
	end
	if Library.Watermark and Library.Watermark.Visible then
		if Viewport then
			local Width = Library.Watermark.AbsoluteSize.X * _invScale
			local Height = Library.Watermark.AbsoluteSize.Y * _invScale
			local X = math.clamp(Library.Watermark.Position.X.Offset, LeftInset + Margin, math.max(LeftInset + Margin, Viewport.X - RightInset - Width - Margin))
			local Y = math.clamp(Library.Watermark.Position.Y.Offset, TopInset + Margin, math.max(TopInset + Margin, Viewport.Y - BottomInset - Height - Margin))
			Library.Watermark.Position = UDim2.fromOffset(X, Y)
		end
	end
	if Library.KeybindFrame and Library.KeybindFrame.Visible then
		if Viewport then
			local Width = Library.KeybindFrame.AbsoluteSize.X * _invScale
			local Height = Library.KeybindFrame.AbsoluteSize.Y * _invScale
			local X = math.clamp(Library.KeybindFrame.AbsolutePosition.X * _invScale, LeftInset + Margin, math.max(LeftInset + Margin, Viewport.X - RightInset - Width - Margin))
			local Y = math.clamp(Library.KeybindFrame.AbsolutePosition.Y * _invScale, TopInset + Margin, math.max(TopInset + Margin, Viewport.Y - BottomInset - Height - Margin))
			Library.KeybindFrame.Position = UDim2.fromOffset(X, Y)
			Library.KeybindFrame.AnchorPoint = Vector2.zero
		end
	end
	Library.LastViewportSize = Viewport
end

function Library:DelayUi(delaySeconds, callback)
	if Library.Unloaded then return function() end end
	local job = {
		Deadline = os.clock() + math.max(tonumber(delaySeconds) or 0, 0),
		Callback = callback,
		Cancelled = false,
	}
	table.insert(Library.UiJobs, job)
	return function()
		job.Cancelled = true
	end
end

function Library:AddUiUpdater(callback)
	if Library.Unloaded then return function() end end
	local updater = { Callback = callback, Cancelled = false }
	table.insert(Library.UiUpdaters, updater)
	return function()
		updater.Cancelled = true
	end
end

local function RunUiCallback(Callback, ...)
	local Thread = coroutine.running()
	local PreviousIdentity = nil
	if typeof(GetThreadIdentity) == "function" then
		local ReadIdentity, Identity = pcall(GetThreadIdentity)
		if ReadIdentity and typeof(Identity) == "number" then PreviousIdentity = Identity end
	end
	if typeof(SetThreadIdentity) == "function" then pcall(SetThreadIdentity, 8) end
	if Thread then Library.UiThreads[Thread] = true end
	local Results = table.pack(pcall(Callback, ...))
	if Thread then Library.UiThreads[Thread] = nil end
	if PreviousIdentity ~= nil and typeof(SetThreadIdentity) == "function" then
		pcall(SetThreadIdentity, PreviousIdentity)
	end
	return table.unpack(Results, 1, Results.n)
end

function Library:IsUiThread()
	local Thread = coroutine.running()
	return Thread ~= nil and Library.UiThreads[Thread] == true
end

function Library:RunUi(Callback, ...)
	if typeof(Callback) ~= "function" then return false, "callback must be a function" end
	if Library:IsUiThread() then return pcall(Callback, ...) end
	if Library.Unloaded then return false, "library is unloaded" end

	local Arguments = table.pack(...)
	local Results = nil
	local Completed = false
	Library:DelayUi(0, function()
		Results = table.pack(pcall(Callback, table.unpack(Arguments, 1, Arguments.n)))
		Completed = true
	end)

	while not Completed do
		if Library.Unloaded then return false, "library unloaded before UI work completed" end
		RunService.Heartbeat:Wait()
	end
	return table.unpack(Results, 1, Results.n)
end

function Library:Mount()
	if Library.Mounted then return true end
	if Library.Unloaded then return false, "library is unloaded" end
	local function FailMount(Error)
		Library.LastUiError = tostring(Error)
		Library:Unload()
		return false, Error
	end
	if not MountThreadReady then return FailMount(MountThreadError) end
	if coroutine.status(MountThread) ~= "suspended" then return FailMount("mount thread is unavailable") end
	local Mounted, MountError = coroutine.resume(MountThread)
	if not Mounted then
		return FailMount(MountError)
	end
	Library.Mounted = true
	return true
end

local UiScheduler = RunService.Heartbeat:Connect(function(Delta)
	local Now = os.clock()
	local ReadyJobs = {}

	for Idx = #Library.UiJobs, 1, -1 do
		local Job = Library.UiJobs[Idx]
		if Job.Cancelled then
			table.remove(Library.UiJobs, Idx)
		elseif Now >= Job.Deadline then
			table.remove(Library.UiJobs, Idx)
			table.insert(ReadyJobs, 1, Job)
		end
	end
	for _, Job in ReadyJobs do
		local Success, Error = RunUiCallback(Job.Callback)
		if not Success then Library.LastUiError = tostring(Error) end
	end

	for Idx = #Library.UiUpdaters, 1, -1 do
		local Updater = Library.UiUpdaters[Idx]
		if Updater.Cancelled then
			table.remove(Library.UiUpdaters, Idx)
		else
			local Success, Keep = RunUiCallback(Updater.Callback, Delta)
			if not Success or Keep == false then
				table.remove(Library.UiUpdaters, Idx)
				if not Success then Library.LastUiError = tostring(Keep) end
			end
		end
	end
end)
table.insert(Library.Signals, UiScheduler)

local function Connect(Signal, Callback)
	return Signal:Connect(function(...)
		if Library.Unloaded then return end
		local Arguments = table.pack(...)
		Library:DelayUi(0, function()
			local Success, Error = pcall(Callback, table.unpack(Arguments, 1, Arguments.n))
			if not Success then Library.LastUiError = tostring(Error) end
		end)
	end)
end

local DefaultCursorIcon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png"

function Library:SetCursorOverride(enabled)
	enabled = enabled == true
	if enabled then
		if Library.CursorOverrideActive then
			pcall(function()
				if not InputService.MouseIconEnabled then InputService.MouseIconEnabled = true end
			end)
			pcall(function()
				if InputService.MouseBehavior ~= Enum.MouseBehavior.Default then
					InputService.MouseBehavior = Enum.MouseBehavior.Default
				end
			end)
			pcall(function()
				if Mouse.Icon ~= DefaultCursorIcon then Mouse.Icon = DefaultCursorIcon end
			end)
			return
		end
		if not Library.CursorOverrideActive then
			local restore = {}
			pcall(function() restore.MouseIconEnabled = InputService.MouseIconEnabled end)
			pcall(function() restore.MouseBehavior = InputService.MouseBehavior end)
			pcall(function() restore.Icon = Mouse.Icon end)
			Library.CursorRestore = restore
			Library.CursorOverrideActive = true
		end
		pcall(function() InputService.MouseIconEnabled = true end)
		pcall(function() InputService.MouseBehavior = Enum.MouseBehavior.Default end)
		pcall(function() Mouse.Icon = DefaultCursorIcon end)
		return
	end

	if not Library.CursorOverrideActive then return end
	local restore = Library.CursorRestore or {}
	if restore.MouseIconEnabled ~= nil then pcall(function() InputService.MouseIconEnabled = restore.MouseIconEnabled end) end
	if restore.MouseBehavior ~= nil then pcall(function() InputService.MouseBehavior = restore.MouseBehavior end) end
	if restore.Icon ~= nil then pcall(function() Mouse.Icon = restore.Icon end) end
	Library.CursorOverrideActive = false
	Library.CursorRestore = nil
end

function Library:RegisterCursorRegion(region)
	if not region or Library.CursorRegions[region] ~= nil then return end
	Library.CursorRegions[region] = false
	table.insert(Library.Signals, Connect(region.MouseEnter, function()
		Library.CursorRegions[region] = true
	end))
	table.insert(Library.Signals, Connect(region.MouseLeave, function()
		Library.CursorRegions[region] = false
	end))
end

table.insert(Library.Signals, Connect(ScaleSignal, UpdateScaleCallback))

local RainbowStep = 0
local Hue = 0

table.insert(
	Library.Signals,
	RenderStepped:Connect(function(Delta)
		local cursorHovered = false
		for region, hovered in Library.CursorRegions do
			if not region.Parent then
				Library.CursorRegions[region] = nil
			elseif hovered and region.Visible then
				cursorHovered = true
			end
		end
		Library:SetCursorOverride(cursorHovered)

		RainbowStep = RainbowStep + Delta

		if RainbowStep >= (1 / 60) then
			RainbowStep = 0

			Hue = Hue + (1 / 400)

			if Hue > 1 then
				Hue = 0
			end

			Library.CurrentRainbowHue = Hue
			Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1)
		end
	end)
)

local function GetPlayersString()
	local PlayerList = Players:GetPlayers()

	for i = 1, #PlayerList do
		PlayerList[i] = PlayerList[i].Name
	end

	table.sort(PlayerList, function(str1, str2)
		return str1 < str2
	end)

	return PlayerList
end

local function GetTeamsString()
	local TeamList = Teams:GetTeams()

	for i = 1, #TeamList do
		TeamList[i] = TeamList[i].Name
	end

	table.sort(TeamList, function(str1, str2)
		return str1 < str2
	end)

	return TeamList
end

function Library:SafeCallback(f, ...)
	if type(f) ~= "function" then return end
	local Results = table.pack(pcall(f, ...))
	if Results[1] then return table.unpack(Results, 2, Results.n) end
	local Event = tostring(Results[2])
	Library.LastCallbackError = Event
	if not Library.NotifyOnError then return nil end
	local _, Index = Event:find(":%d+: ")
	return Library:Notify(Index and Event:sub(Index + 1) or Event, 3)
end

function Library:AttemptSave()
	if Library.SaveManager then
		Library.SaveManager:Save()
	end
end

function Library:Create(Class, Properties)
	local _Instance = Class

	if type(Class) == "string" then
		_Instance = Instance.new(Class)
	end

	-- Parenting into gethui protects the instance immediately. Apply every
	-- other property first so unordered table iteration cannot lock us out
	-- halfway through construction.
	local Parent = Properties.Parent
	local function ApplyProperties()
		for Property, Value in next, Properties do
			if Property == "Parent" then continue end
			_Instance[Property] = Value
		end
		if Parent ~= nil then _Instance.Parent = Parent end
	end
	local Applied, ApplyError = pcall(ApplyProperties)
	if not Applied then
		Applied, ApplyError = Library:RunUi(ApplyProperties)
		if not Applied then error(ApplyError, 0) end
	end

	return _Instance
end

function Library:ApplyTextStroke(Inst, Enabled)
	Inst.TextStrokeTransparency = 1
	if not Enabled then return end
	Library:Create("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 0.65,
		Transparency = 0.35,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Parent = Inst,
	})
end

function Library:CreateLabel(Properties, IsHud)
	local _Instance = Library:Create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Library.Font,
		TextColor3 = Library.FontColor,
		TextSize = 16,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextStrokeTransparency = 1,
	})

	Library:ApplyTextStroke(_Instance, IsHud)

	Library:AddToRegistry(_Instance, {
		TextColor3 = "FontColor",
	}, IsHud)

	return Library:Create(_Instance, Properties)
end

function Library:MakeDraggable(Instance, Cutoff)
	Instance.Active = true
	local StopDragging = nil

	Instance.InputBegan:Connect(function(Input)
		if Library.Unloaded then return end
		if Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		then
			local StartPointer = Input.Position
			IsClickInput(Input)
			Library:DelayUi(0, function()
			-- Prevent dragging if UI is locked (mobile feature)
			if Library.UILocked or Library.CantDragForced then
				return
			end

			local ObjPos = Vector2.new(
				(StartPointer.X - Instance.AbsolutePosition.X) * _invScale,
				(StartPointer.Y - Instance.AbsolutePosition.Y) * _invScale
			)

			if ObjPos.Y > (Cutoff or 40) then
				return
			end

			if StopDragging then StopDragging() end
			StopDragging = Library:AddUiUpdater(function()
				if not IsPointerHeld(Input) or Library.UILocked or Library.CantDragForced or not Instance.Parent then
					StopDragging = nil
					return false
				end
				local CurrentPointer = GetPointerPosition(Input)
				local X = CurrentPointer.X * _invScale - ObjPos.X + (Instance.AbsoluteSize.X * _invScale * Instance.AnchorPoint.X)
				local Y = CurrentPointer.Y * _invScale - ObjPos.Y + (Instance.AbsoluteSize.Y * _invScale * Instance.AnchorPoint.Y)
				local Camera = workspace.CurrentCamera
				if Camera then
					local Viewport = Camera.ViewportSize * _invScale
					local LeftInset, TopInset, RightInset, BottomInset = GetViewportInsets()
					local Width = Instance.AbsoluteSize.X * _invScale
					local Height = Instance.AbsoluteSize.Y * _invScale
					local Padding = 6
					local MinX = LeftInset + Padding + Width * Instance.AnchorPoint.X
					local MaxX = Viewport.X - RightInset - Padding - Width * (1 - Instance.AnchorPoint.X)
					local MinY = TopInset + Padding + Height * Instance.AnchorPoint.Y
					local MaxY = Viewport.Y - BottomInset - Padding - Height * (1 - Instance.AnchorPoint.Y)
					X = math.clamp(X, math.min(MinX, MaxX), math.max(MinX, MaxX))
					Y = math.clamp(Y, math.min(MinY, MaxY), math.max(MinY, MaxY))
				end
				Instance.Position = UDim2.fromOffset(X, Y)
				return true
			end)
			end)
		end
	end)
end

function Library:ConnectClick(Instance, Callback)
	return Instance.InputBegan:Connect(function(Input)
		if Library.Unloaded then return end
		if Input.UserInputType ~= Enum.UserInputType.MouseButton1
			and Input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local StartPosition = Input.Position
		IsClickInput(Input)
		Library:DelayUi(0, function()
			if not Instance.Parent then return end
			if Input.UserInputType ~= Enum.UserInputType.Touch then
				Callback(Input)
				return
			end

			local Cancelled = false
			Library:AddUiUpdater(function()
				if not Instance.Parent then return false end
				if (Input.Position - StartPosition).Magnitude > 12 then Cancelled = true end
				if IsPointerHeld(Input) then return true end
				if not Cancelled then Callback(Input) end
				return false
			end)
		end)
	end)
end

function Library:AddToolTip(InfoStr, HoverInstance)
	local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14)
	local Tooltip = Library:Create("Frame", {
		BackgroundColor3 = Library.MainColor,
		BorderColor3 = Library.OutlineColor,

		Size = UDim2.fromOffset(X + 5, Y + 4),
		ZIndex = 100,
		Parent = Library.ScreenGui,

		Visible = false,
	})

	local Label = Library:CreateLabel({
		Position = UDim2.fromOffset(3, 1),
		Size = UDim2.fromOffset(X, Y),
		TextSize = 14,
		Text = InfoStr,
		TextColor3 = Library.FontColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = Tooltip.ZIndex + 1,

		Parent = Tooltip,
	})

	Library:AddToRegistry(Tooltip, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "OutlineColor",
	})

	Library:AddToRegistry(Label, {
		TextColor3 = "FontColor",
	})

	local IsHovering = false
	local StopFollowing = nil

	Connect(HoverInstance.MouseEnter, function()
		if Library:MouseIsOverOpenedFrame() then
			return
		end

		IsHovering = true

		local Pointer = GetPointerPosition()
		local XPos, YPos = Library:ClampPopupOffset(
			(Pointer.X + 15) * _invScale,
			(Pointer.Y + 12) * _invScale,
			Tooltip.Size.X.Offset,
			Tooltip.Size.Y.Offset
		)
		Tooltip.Position = UDim2.fromOffset(XPos, YPos)
		Tooltip.Visible = true

		if StopFollowing then StopFollowing() end
		StopFollowing = Library:AddUiUpdater(function()
			if not IsHovering or not Tooltip.Parent or not HoverInstance.Parent then
				Tooltip.Visible = false
				StopFollowing = nil
				return false
			end
			local Pointer = GetPointerPosition()
			local FollowX, FollowY = Library:ClampPopupOffset(
				(Pointer.X + 15) * _invScale,
				(Pointer.Y + 12) * _invScale,
				Tooltip.Size.X.Offset,
				Tooltip.Size.Y.Offset
			)
			Tooltip.Position = UDim2.fromOffset(FollowX, FollowY)
			return true
		end)
	end)

	Connect(HoverInstance.MouseLeave, function()
		IsHovering = false
		if StopFollowing then
			StopFollowing()
			StopFollowing = nil
		end
		Tooltip.Visible = false
	end)
end

local HighlightTweens = setmetatable({}, { __mode = "k" })
function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
	local function Apply(PropertiesToApply)
		local Reg = Library.RegistryMap[Instance]
		local Goals = {}
		for Property, ColorIdx in PropertiesToApply do
			local Value = Library[ColorIdx] or ColorIdx
			if typeof(Value) == "Color3" then Goals[Property] = Value else Instance[Property] = Value end
			if Reg and Reg.Properties[Property] then Reg.Properties[Property] = ColorIdx end
		end
		if next(Goals) then
			if HighlightTweens[Instance] then HighlightTweens[Instance]:Cancel() end
			local Tween = TweenService:Create(
				Instance,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				Goals
			)
			HighlightTweens[Instance] = Tween
			Tween:Play()
		end
	end
	Connect(HighlightInstance.MouseEnter, function() Apply(Properties) end)
	Connect(HighlightInstance.MouseLeave, function() Apply(PropertiesDefault) end)
end

function Library:MouseIsOverOpenedFrame(Input)
	local Pointer = GetPointerPosition(Input)
	for Frame, _ in next, Library.OpenedFrames do
		local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize

		if
			Pointer.X >= AbsPos.X
			and Pointer.X <= AbsPos.X + AbsSize.X
			and Pointer.Y >= AbsPos.Y
			and Pointer.Y <= AbsPos.Y + AbsSize.Y
		then
			return true
		end
	end
end

function Library:IsMouseOverFrame(Frame, Input)
	local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize
	local Pointer = GetPointerPosition(Input)

	if
		Pointer.X >= AbsPos.X
		and Pointer.X <= AbsPos.X + AbsSize.X
		and Pointer.Y >= AbsPos.Y
		and Pointer.Y <= AbsPos.Y + AbsSize.Y
	then
		return true
	end
end

function Library:UpdateDependencyBoxes()
	for _, Depbox in next, Library.DependencyBoxes do
		Depbox:Update()
	end
end

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
	return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB
end

function Library:GetTextBounds(Text, Font, Size, Resolution)
	local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
	return Bounds.X, Bounds.Y
end

function Library:GetDarkerColor(Color)
	local H, S, V = Color3.toHSV(Color)
	return Color3.fromHSV(H, S, V / 1.5)
end
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor)

function Library:ClampPopupOffset(X, Y, Width, Height, Padding)
	local Camera = workspace.CurrentCamera
	if not Camera then return X, Y end
	local Viewport = Camera.ViewportSize * _invScale
	local LeftInset, TopInset, RightInset, BottomInset = GetViewportInsets()
	Padding = Padding or 6
	local MinX = LeftInset + Padding
	local MinY = TopInset + Padding
	local MaxX = math.max(MinX, Viewport.X - RightInset - Width - Padding)
	local MaxY = math.max(MinY, Viewport.Y - BottomInset - Height - Padding)
	return math.clamp(X, MinX, MaxX), math.clamp(Y, MinY, MaxY)
end

function Library:PositionPopup(Popup, Anchor, Placement, Gap)
	if not Popup or not Anchor then return end
	Gap = Gap or 3
	Placement = Placement or "Below"
	local PopupData = Library.PopupAnchors[Popup] or {}
	PopupData.Anchor = Anchor
	PopupData.Placement = Placement
	PopupData.Gap = Gap
	Library.PopupAnchors[Popup] = PopupData
	local AnchorX = Anchor.AbsolutePosition.X * _invScale
	local AnchorY = Anchor.AbsolutePosition.Y * _invScale
	local AnchorWidth = Anchor.AbsoluteSize.X * _invScale
	local AnchorHeight = Anchor.AbsoluteSize.Y * _invScale
	local PopupWidth = math.max(Popup.AbsoluteSize.X * _invScale, Popup.Size.X.Offset)
	local PopupHeight = math.max(Popup.AbsoluteSize.Y * _invScale, Popup.Size.Y.Offset)
	local X = if Placement == "Right" then AnchorX + AnchorWidth + Gap else AnchorX
	local Y = if Placement == "Right" then AnchorY else AnchorY + AnchorHeight + Gap
	local Camera = workspace.CurrentCamera
	if Camera then
		local Viewport = Camera.ViewportSize * _invScale
		local _, TopInset, RightInset, BottomInset = GetViewportInsets()
		if Placement == "Right" and X + PopupWidth > Viewport.X - RightInset - 6 then X = AnchorX - PopupWidth - Gap end
		if Placement ~= "Right" and Y + PopupHeight > Viewport.Y - BottomInset - 6 then Y = math.max(TopInset + 6, AnchorY - PopupHeight - Gap) end
	end
	X, Y = Library:ClampPopupOffset(X, Y, PopupWidth, PopupHeight)
	Popup.Position = UDim2.fromOffset(X, Y)
end

function Library:RepositionPopups()
	for Popup, Data in Library.PopupAnchors do
		local Anchor = Data.Anchor
		if not Popup.Parent or not Anchor or not Anchor.Parent then
			Library.PopupAnchors[Popup] = nil
		elseif Popup.Visible then
			Library:PositionPopup(Popup, Anchor, Data.Placement, Data.Gap)
		end
	end
end

function Library:ClosePopupsFor(Root)
	for Popup, Data in Library.PopupAnchors do
		local Anchor = Data.Anchor
		local IsOwned = false
		if Anchor and Anchor.Parent then
			pcall(function() IsOwned = Anchor:IsDescendantOf(Root) end)
		end
		if IsOwned then
			if not Popup.Parent then
				Library.PopupAnchors[Popup] = nil
			elseif type(Data.Close) == "function" then
				local Closed, Error = pcall(Data.Close)
				if not Closed then Library.LastUiError = tostring(Error) end
			else
				Popup.Visible = false
				Library.OpenedFrames[Popup] = nil
			end
		end
	end
end

function Library:AddToRegistry(Instance, Properties, IsHud)
	local Existing = Library.RegistryMap[Instance]
	if Existing then
		for Property, Value in Properties do Existing.Properties[Property] = Value end
		if IsHud and not Existing.HudIdx then
			Existing.HudIdx = #Library.HudRegistry + 1
			table.insert(Library.HudRegistry, Existing)
		end
		return Existing
	end
	local Idx = #Library.Registry + 1
	local Data = {
		Instance = Instance,
		Properties = Properties,
		Idx = Idx,
	}

	table.insert(Library.Registry, Data)
	Library.RegistryMap[Instance] = Data

	if IsHud then
		Data.HudIdx = #Library.HudRegistry + 1
		table.insert(Library.HudRegistry, Data)
	end
	return Data
end

function Library:RemoveFromRegistry(Instance)
	local Data = Library.RegistryMap[Instance]

	if Data then
		local Last = table.remove(Library.Registry)
		if Last and Last ~= Data then
			Library.Registry[Data.Idx] = Last
			Last.Idx = Data.Idx
		end
		if Data.HudIdx then
			local LastHud = table.remove(Library.HudRegistry)
			if LastHud and LastHud ~= Data then
				Library.HudRegistry[Data.HudIdx] = LastHud
				LastHud.HudIdx = Data.HudIdx
			end
		end

		Library.RegistryMap[Instance] = nil
	end
end

function Library:UpdateColorsUsingRegistry()
	if not Library:IsUiThread() then
		local Success, Result = Library:RunUi(function() return Library:UpdateColorsUsingRegistry() end)
		if not Success then Library.LastUiError = tostring(Result) end
		return Success
	end
	Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor)
	-- TODO: Could have an 'active' list of objects
	-- where the active list only contains Visible objects.

	-- IMPL: Could setup .Changed events on the AddToRegistry function
	-- that listens for the 'Visible' propert being changed.
	-- Visible: true => Add to active list, and call UpdateColors function
	-- Visible: false => Remove from active list.

	-- The above would be especially efficient for a rainbow menu color or live color-changing.

	for Idx = #Library.Registry, 1, -1 do
		local Object = Library.Registry[Idx]
		if not Object.Instance or Object.Instance.Parent == nil then
			Library:RemoveFromRegistry(Object.Instance)
		else
			for Property, ColorIdx in Object.Properties do
				local Value = if type(ColorIdx) == "string" then Library[ColorIdx]
					elseif type(ColorIdx) == "function" then ColorIdx()
					else nil
				if Value ~= nil then
					local Applied, Error = pcall(function() Object.Instance[Property] = Value end)
					if not Applied then Library.LastUiError = tostring(Error) end
				end
			end
		end
	end
	return true
end

function Library:GiveSignal(Signal)
	-- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
	table.insert(Library.Signals, Signal)
	return Signal
end

function Library:ForgetSignal(Signal)
	for Index = #Library.Signals, 1, -1 do
		if Library.Signals[Index] == Signal then
			table.remove(Library.Signals, Index)
			return true
		end
	end
	return false
end

function Library:Unload()
	if Library.CleanupComplete then return Library.CleanupError == nil, Library.CleanupError end
	if not Library:IsUiThread() then
		local Success, Cleaned, CleanupError = Library:RunUi(function() return Library:Unload() end)
		if Success then return Cleaned, CleanupError end
		Library.LastUiError = tostring(Cleaned)
		return false, Cleaned
	end
	local WasMounted = Library.Mounted
	Library.Unloaded = true
	Library.Mounted = false
	local FirstError = nil
	local function Protect(Callback)
		local Success, Error = pcall(Callback)
		if not Success and not FirstError then FirstError = tostring(Error) end
		return Success, Error
	end
	Protect(function() Library:SetCursorOverride(false) end)

	local UnloadCallback = Library.UnloadCallback
	Library.UnloadCallback = nil
	if UnloadCallback then Protect(UnloadCallback) end
	local ScreenDestroyed = ScreenGui == nil
	if ScreenGui then
		ScreenDestroyed = Protect(function() ScreenGui:Destroy() end)
	end
	if not ScreenDestroyed then
		Library.Unloaded = false
		Library.Mounted = WasMounted
		Library.CleanupComplete = false
		Library.CleanupError = FirstError
		if FirstError then Library.LastUiError = FirstError end
		return false, FirstError
	end

	table.clear(Library.CursorRegions)
	table.clear(Library.UiJobs)
	table.clear(Library.UiUpdaters)
	if CameraViewportConnection then
		Protect(function() CameraViewportConnection:Disconnect() end)
		CameraViewportConnection = nil
	end
	for Idx = #Library.Signals, 1, -1 do
		local Connection = table.remove(Library.Signals, Idx)
		Protect(function() Connection:Disconnect() end)
	end
	table.clear(Library.Registry)
	table.clear(Library.RegistryMap)
	table.clear(Library.HudRegistry)
	table.clear(Library.OpenedFrames)
	table.clear(Library.PopupAnchors)
	table.clear(Library.DependencyBoxes)
	table.clear(Library.Windows)
	table.clear(ActiveTouchInputs)
	ActivePointerInput = nil
	_clickHeld = false
	table.clear(Toggles)
	table.clear(Options)
	local Environment = getgenv()
	if Environment.Toggles == Toggles then Environment.Toggles = nil end
	if Environment.Options == Options then Environment.Options = nil end
	Library.PrimaryWindow = nil
	Library.NotificationArea = nil
	Library.Watermark = nil
	Library.WatermarkText = nil
	Library.KeybindFrame = nil
	Library.KeybindContainer = nil
	Library.ToggleKeybind = nil
	Library.MobileController = nil
	Library.MobileControllerPlaced = false
	Library.ViewportLayoutScheduled = false
	Library.LastViewportSize = nil
	Library.ScreenGui = nil
	if Environment.Library == Library then Environment.Library = nil end
	ScreenGui = nil
	ScaleSignal = nil
	UpdateScaleCallback = nil
	RequestScaleUpdateCallback = nil
	Library.CleanupComplete = true
	Library.CleanupError = FirstError
	if FirstError then Library.LastUiError = FirstError end
	return FirstError == nil, FirstError
end

function Library:OnUnload(Callback)
	Library.UnloadCallback = Callback
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
	if Library.RegistryMap[Instance] then
		Library:RemoveFromRegistry(Instance)
	end
end))

Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
	if Library.Unloaded then return end
	if Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch
	then
		IsClickInput(Input)
	end
end))

Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
	if Library.Unloaded then return end
	if Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch
	then
		ReleasePointer(Input)
	end
end))

local BaseAddons = {}

do
	local Funcs = {}

	function Funcs:AddColorPicker(Idx, Info)
		local ToggleLabel = self.TextLabel
		-- local Container = self.Container;

		assert(Info.Default, "AddColorPicker: Missing default value.")

		local ColorPicker = {
			Value = Info.Default,
			Transparency = Info.Transparency or 0,
			Type = "ColorPicker",
			Title = type(Info.Title) == "string" and Info.Title or "Color picker",
			Callback = Info.Callback or function(Color) end,
		}

		function ColorPicker:SetHSVFromRGB(Color)
			local H, S, V = Color3.toHSV(Color)

			ColorPicker.Hue = H
			ColorPicker.Sat = S
			ColorPicker.Vib = V
		end

		ColorPicker:SetHSVFromRGB(ColorPicker.Value)

		local DisplayFrame = Library:Create("Frame", {
			BackgroundColor3 = ColorPicker.Value,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(0, 28, 0, 14),
			ZIndex = 6,
			Parent = ToggleLabel,
		})
		Library:AddToRegistry(DisplayFrame, { BorderColor3 = "OutlineColor" })

		-- Transparency image taken from https://github.com/matas3535/SplixPrivateDrawingLibrary/blob/main/Library.lua cus i'm lazy
		local CheckerFrame = Library:Create("ImageLabel", {
			BorderSizePixel = 0,
			Size = UDim2.new(0, 27, 0, 13),
			ZIndex = 5,
			Image = "http://www.roblox.com/asset/?id=12977615774",
			Visible = not not Info.Transparency,
			Parent = DisplayFrame,
		})

		-- 1/16/23
		-- Rewrote this to be placed inside the Library ScreenGui
		-- There was some issue which caused RelativeOffset to be way off
		-- Thus the color picker would never show

		local PickerFrameOuter = Library:Create("Frame", {
			Name = "Color",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(230, Info.Transparency and 271 or 253),
			Visible = false,
			ZIndex = 15,
			Parent = ScreenGui,
		})
		Library:RegisterCursorRegion(PickerFrameOuter)

		local function UpdatePickerPosition() Library:PositionPopup(PickerFrameOuter, DisplayFrame, "Below", 4) end
		Connect(DisplayFrame:GetPropertyChangedSignal("AbsolutePosition"), UpdatePickerPosition)
		Connect(DisplayFrame:GetPropertyChangedSignal("AbsoluteSize"), UpdatePickerPosition)
		UpdatePickerPosition()

		local PickerFrameInner = Library:Create("Frame", {
			BackgroundColor3 = Library.BackgroundColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 16,
			Parent = PickerFrameOuter,
		})

		local Highlight = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = 17,
			Parent = PickerFrameInner,
		})

		local SatVibMapOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.new(0, 4, 0, 25),
			Size = UDim2.new(0, 200, 0, 200),
			ZIndex = 17,
			Parent = PickerFrameInner,
		})

		local SatVibMapInner = Library:Create("Frame", {
			BackgroundColor3 = Library.BackgroundColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 18,
			Parent = SatVibMapOuter,
		})

		local SatVibMap = Library:Create("ImageLabel", {
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 18,
			Image = "rbxassetid://4155801252",
			Parent = SatVibMapInner,
		})

		local CursorOuter = Library:Create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0, 6, 0, 6),
			BackgroundTransparency = 1,
			Image = "http://www.roblox.com/asset/?id=9619665977",
			ImageColor3 = Color3.new(0, 0, 0),
			ZIndex = 19,
			Parent = SatVibMap,
		})

		local CursorInner = Library:Create("ImageLabel", {
			Size = UDim2.new(0, CursorOuter.Size.X.Offset - 2, 0, CursorOuter.Size.Y.Offset - 2),
			Position = UDim2.new(0, 1, 0, 1),
			BackgroundTransparency = 1,
			Image = "http://www.roblox.com/asset/?id=9619665977",
			ZIndex = 20,
			Parent = CursorOuter,
		})

		local HueSelectorOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.new(0, 208, 0, 25),
			Size = UDim2.new(0, 15, 0, 200),
			ZIndex = 17,
			Parent = PickerFrameInner,
		})

		local HueSelectorInner = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 18,
			Parent = HueSelectorOuter,
		})

		local HueCursor = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0, 0.5),
			BorderColor3 = Color3.new(0, 0, 0),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 18,
			Parent = HueSelectorInner,
		})

		local HueBoxOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.fromOffset(4, 228),
			Size = UDim2.new(0.5, -6, 0, 20),
			ZIndex = 18,
			Parent = PickerFrameInner,
		})

		local HueBoxInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 18,
			Parent = HueBoxOuter,
		})

		Library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
			}),
			Rotation = 90,
			Parent = HueBoxInner,
		})

		local HueBox = Library:Create("TextBox", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 5, 0, 0),
			Size = UDim2.new(1, -5, 1, 0),
			Font = Library.Font,
			PlaceholderColor3 = Color3.fromRGB(190, 190, 190),
			PlaceholderText = "Hex color",
			Text = "#FFFFFF",
			TextColor3 = Library.FontColor,
			TextSize = 14,
			TextStrokeTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 20,
			Parent = HueBoxInner,
		})

		Library:ApplyTextStroke(HueBox)

		local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
			Position = UDim2.new(0.5, 2, 0, 228),
			Size = UDim2.new(0.5, -6, 0, 20),
			Parent = PickerFrameInner,
		})

		local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild("TextBox"), {
			Text = "255, 255, 255",
			PlaceholderText = "RGB color",
			TextColor3 = Library.FontColor,
		})

		local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor

		if Info.Transparency then
			TransparencyBoxOuter = Library:Create("Frame", {
				BorderColor3 = Color3.new(0, 0, 0),
				Position = UDim2.fromOffset(4, 251),
				Size = UDim2.new(1, -8, 0, 15),
				ZIndex = 19,
				Parent = PickerFrameInner,
			})

			TransparencyBoxInner = Library:Create("Frame", {
				BackgroundColor3 = ColorPicker.Value,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 19,
				Parent = TransparencyBoxOuter,
			})

			Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = "OutlineColor" })

			Library:Create("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Image = "http://www.roblox.com/asset/?id=12978095818",
				ZIndex = 20,
				Parent = TransparencyBoxInner,
			})

			TransparencyCursor = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(0.5, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(0, 1, 1, 0),
				ZIndex = 21,
				Parent = TransparencyBoxInner,
			})
		end

		local DisplayLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromOffset(5, 5),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
			Text = ColorPicker.Title, --Info.Default;
			TextWrapped = false,
			ZIndex = 16,
			Parent = PickerFrameInner,
		})

		local ContextMenu = {}
		do
			ContextMenu.Options = {}
			ContextMenu.Container = Library:Create("Frame", {
				BorderColor3 = Color3.new(),
				ZIndex = 14,

				Visible = false,
				Parent = ScreenGui,
			})
			Library:RegisterCursorRegion(ContextMenu.Container)

			ContextMenu.Inner = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 15,
				Parent = ContextMenu.Container,
			})

			Library:Create("UIListLayout", {
				Name = "Layout",
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = ContextMenu.Inner,
			})

			Library:Create("UIPadding", {
				Name = "Padding",
				PaddingLeft = UDim.new(0, 4),
				Parent = ContextMenu.Inner,
			})

			local function updateMenuPosition()
				Library:PositionPopup(ContextMenu.Container, DisplayFrame, "Right", 4)
			end

			local updatingMenuSize = false
			local function updateMenuSize()
				if updatingMenuSize then
					return
				end
				updatingMenuSize = true

				local menuWidth = 60
				for i, label in next, ContextMenu.Inner:GetChildren() do
					if label:IsA("TextLabel") then
						menuWidth = math.max(menuWidth, label.TextBounds.X)
					end
				end

				ContextMenu.Container.Size =
					UDim2.fromOffset(menuWidth + 8, ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4)
				updateMenuPosition()
				updatingMenuSize = false
			end

			Connect(DisplayFrame:GetPropertyChangedSignal("AbsolutePosition"), updateMenuPosition)
			Connect(ContextMenu.Inner.Layout:GetPropertyChangedSignal("AbsoluteContentSize"), updateMenuSize)

			updateMenuPosition()
			updateMenuSize()

			Library:AddToRegistry(ContextMenu.Inner, {
				BackgroundColor3 = "BackgroundColor",
				BorderColor3 = "OutlineColor",
			})

			function ContextMenu:Show()
				updateMenuPosition()
				self.Container.Visible = true
			end

			function ContextMenu:Hide()
				self.Container.Visible = false
			end

			function ContextMenu:AddOption(Str, Callback)
				if type(Callback) ~= "function" then
					Callback = function() end
				end

				local Button = Library:CreateLabel({
					Active = false,
					Size = UDim2.new(1, 0, 0, 15),
					TextSize = 13,
					Text = Str,
					ZIndex = 16,
					Parent = self.Inner,
					TextXAlignment = Enum.TextXAlignment.Left,
				})

				Library:OnHighlight(Button, Button, { TextColor3 = "AccentColor" }, { TextColor3 = "FontColor" })

				Library:ConnectClick(Button, function()
					Callback()
				end)
			end

			ContextMenu:AddOption("Copy color", function()
				Library.ColorClipboard = ColorPicker.Value
				Library:Notify("Copied color!", 2)
			end)

			ContextMenu:AddOption("Paste color", function()
				if not Library.ColorClipboard then
					return Library:Notify("You have not copied a color!", 2)
				end
				ColorPicker:SetValueRGB(Library.ColorClipboard)
			end)

			ContextMenu:AddOption("Copy HEX", function()
				pcall(setclipboard, ColorPicker.Value:ToHex())
				Library:Notify("Copied hex code to clipboard!", 2)
			end)

			ContextMenu:AddOption("Copy RGB", function()
				pcall(
					setclipboard,
					table.concat({
						math.floor(ColorPicker.Value.R * 255),
						math.floor(ColorPicker.Value.G * 255),
						math.floor(ColorPicker.Value.B * 255),
					}, ", ")
				)
				Library:Notify("Copied RGB values to clipboard!", 2)
			end)
		end

		Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" })
		Library:AddToRegistry(Highlight, { BackgroundColor3 = "AccentColor" })
		Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" })

		Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
		Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
		Library:AddToRegistry(RgbBox, { TextColor3 = "FontColor" })
		Library:AddToRegistry(HueBox, { TextColor3 = "FontColor" })

		local SequenceTable = {}

		for Hue = 0, 1, 0.1 do
			table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)))
		end

		local HueSelectorGradient = Library:Create("UIGradient", {
			Color = ColorSequence.new(SequenceTable),
			Rotation = 90,
			Parent = HueSelectorInner,
		})

		Connect(HueBox.FocusLost, function(enter)
			if enter then
				local success, result = pcall(Color3.fromHex, HueBox.Text)
				if success and typeof(result) == "Color3" then
					ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
				end
			end

			ColorPicker:Display()
		end)

		Connect(RgbBox.FocusLost, function(enter)
			if enter then
				local r, g, b = RgbBox.Text:match("(%d+),%s*(%d+),%s*(%d+)")
				if r and g and b then
					ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
				end
			end

			ColorPicker:Display()
		end)

		function ColorPicker:Display()
			ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib)
			SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1)

				Library:Create(DisplayFrame, {
					BackgroundColor3 = ColorPicker.Value,
					BackgroundTransparency = ColorPicker.Transparency,
					BorderColor3 = Library.OutlineColor,
				})

			if TransparencyBoxInner then
				TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value
				TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0)
			end

			CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0)
			HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0)

			HueBox.Text = "#" .. ColorPicker.Value:ToHex()
			RgbBox.Text = table.concat({
				math.floor(ColorPicker.Value.R * 255),
				math.floor(ColorPicker.Value.G * 255),
				math.floor(ColorPicker.Value.B * 255),
			}, ", ")

			Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value)
			Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value)
		end

		function ColorPicker:OnChanged(Func)
			assert(type(Func) == "function", "OnChanged callback must be a function")
			ColorPicker.Changed = Func
			Library:SafeCallback(Func, ColorPicker.Value)
		end

		function ColorPicker:Show()
			for Frame, Val in next, Library.OpenedFrames do
				if Frame.Name == "Color" then
					Frame.Visible = false
					Library.OpenedFrames[Frame] = nil
				end
			end

			UpdatePickerPosition()
			PickerFrameOuter.Visible = true
			Library.OpenedFrames[PickerFrameOuter] = true
		end

		function ColorPicker:Hide()
			PickerFrameOuter.Visible = false
			Library.OpenedFrames[PickerFrameOuter] = nil
		end

		function ColorPicker:SetValue(HSV, Transparency)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return ColorPicker:SetValue(HSV, Transparency) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3])

			ColorPicker.Transparency = Transparency or 0
			ColorPicker:SetHSVFromRGB(Color)
			ColorPicker:Display()
		end

		function ColorPicker:SetValueRGB(Color, Transparency)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return ColorPicker:SetValueRGB(Color, Transparency) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			ColorPicker.Transparency = Transparency or 0
			ColorPicker:SetHSVFromRGB(Color)
			ColorPicker:Display()
		end

		local StopSatVibUpdate = nil
		Connect(SatVibMap.InputBegan, function(Input)
			if IsClickInput(Input) then
				local PointerInput = Input
				if StopSatVibUpdate then StopSatVibUpdate() end
				StopSatVibUpdate = Library:AddUiUpdater(function()
					if not IsPointerHeld(PointerInput) or not SatVibMap.Parent then
						StopSatVibUpdate = nil
						Library:AttemptSave()
						return false
					end
					local MinX = SatVibMap.AbsolutePosition.X
					local MaxX = MinX + SatVibMap.AbsoluteSize.X
					local Pointer = GetPointerPosition(PointerInput)
					local MouseX = math.clamp(Pointer.X, MinX, MaxX)

					local MinY = SatVibMap.AbsolutePosition.Y
					local MaxY = MinY + SatVibMap.AbsoluteSize.Y
					local MouseY = math.clamp(Pointer.Y, MinY, MaxY)

					ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX)
					ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY))
					ColorPicker:Display()
					return true
				end)
			end
		end)

		local StopHueUpdate = nil
		Connect(HueSelectorInner.InputBegan, function(Input)
			if IsClickInput(Input) then
				local PointerInput = Input
				if StopHueUpdate then StopHueUpdate() end
				StopHueUpdate = Library:AddUiUpdater(function()
					if not IsPointerHeld(PointerInput) or not HueSelectorInner.Parent then
						StopHueUpdate = nil
						Library:AttemptSave()
						return false
					end
					local MinY = HueSelectorInner.AbsolutePosition.Y
					local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y
					local Pointer = GetPointerPosition(PointerInput)
					local MouseY = math.clamp(Pointer.Y, MinY, MaxY)

					ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY))
					ColorPicker:Display()
					return true
				end)
			end
		end)

		Library:ConnectClick(DisplayFrame, function(Input)
			if not Library:MouseIsOverOpenedFrame(Input) then
				if PickerFrameOuter.Visible then
					ColorPicker:Hide()
				else
					ContextMenu:Hide()
					ColorPicker:Show()
				end
			end
		end)
		Connect(DisplayFrame.InputBegan, function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame(Input) then
				ContextMenu:Show()
				ColorPicker:Hide()
			end
		end)

		if TransparencyBoxInner then
			local StopTransparencyUpdate = nil
			Connect(TransparencyBoxInner.InputBegan, function(Input)
				if IsClickInput(Input) then
					local PointerInput = Input
					if StopTransparencyUpdate then StopTransparencyUpdate() end
					StopTransparencyUpdate = Library:AddUiUpdater(function()
						if not IsPointerHeld(PointerInput) or not TransparencyBoxInner.Parent then
							StopTransparencyUpdate = nil
							Library:AttemptSave()
							return false
						end
						local MinX = TransparencyBoxInner.AbsolutePosition.X
						local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X
						local Pointer = GetPointerPosition(PointerInput)
						local MouseX = math.clamp(Pointer.X, MinX, MaxX)

						ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX))

						ColorPicker:Display()
						return true
					end)
				end
			end)
		end

		Library:GiveSignal(Connect(InputService.InputBegan, function(Input)
			if IsClickInput(Input) then
				local Pointer = GetPointerPosition(Input)
				local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize

				if
					Pointer.X < AbsPos.X
					or Pointer.X > AbsPos.X + AbsSize.X
					or Pointer.Y < (AbsPos.Y - 20 - 1)
					or Pointer.Y > AbsPos.Y + AbsSize.Y
				then
					ColorPicker:Hide()
				end

				if not Library:IsMouseOverFrame(ContextMenu.Container) then
					ContextMenu:Hide()
				end
			end

			if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
				if
					not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame)
				then
					ContextMenu:Hide()
				end
			end
		end))

		ColorPicker:Display()
		ColorPicker.DisplayFrame = DisplayFrame

		Options[Idx] = ColorPicker

		return self
	end

	function Funcs:AddKeyPicker(Idx, Info)
		local ParentObj = self
		local ToggleLabel = self.TextLabel
		local Container = self.Container
		local KeyAliases = { MouseButton = "MB1", MouseButton1 = "MB1", MouseButton2 = "MB2" }

		assert(Info.Default, "AddKeyPicker: Missing default value.")

		local KeyPicker = {
			Value = KeyAliases[Info.Default] or Info.Default,
			Toggled = false,
			Mode = Info.Mode or "Toggle", -- Always, Toggle, Hold
			Type = "KeyPicker",
			Callback = Info.Callback or function(Value) end,
			ChangedCallback = Info.ChangedCallback or function(New) end,

			SyncToggleState = Info.SyncToggleState or false,
		}

		if KeyPicker.SyncToggleState then
			Info.Modes = { "Toggle" }
			Info.Mode = "Toggle"
			KeyPicker.Mode = "Toggle"
		end
		local Modes = Info.Modes or { "Always", "Toggle", "Hold" }

		local PickOuter = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderColor3 = Color3.new(0, 0, 0),
			Size = UDim2.new(0, 34, 0, TouchKeyHeight),
			ZIndex = 6,
			Parent = ToggleLabel,
		})

		local PickInner = Library:Create("Frame", {
			BackgroundColor3 = Library.BackgroundColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 7,
			Parent = PickOuter,
		})

		Library:AddToRegistry(PickInner, {
			BackgroundColor3 = "BackgroundColor",
			BorderColor3 = "OutlineColor",
		})

		local DisplayLabel = Library:CreateLabel({
			Position = UDim2.fromOffset(0, ControlTextOffset),
			Size = UDim2.new(1, 0, 1, -ControlTextOffset),
			TextSize = 13,
			Text = KeyPicker.Value,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 8,
			Parent = PickInner,
		})

		local ModeSelectOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(0, IsMobile and 104 or 76, 0, (#Modes * (IsMobile and 42 or 18)) + 2),
			Visible = false,
			ZIndex = 14,
			Parent = ScreenGui,
		})
		Library:RegisterCursorRegion(ModeSelectOuter)

		local function UpdateModePosition() Library:PositionPopup(ModeSelectOuter, PickOuter, "Below", 3) end
		Connect(PickOuter:GetPropertyChangedSignal("AbsolutePosition"), UpdateModePosition)
		Connect(PickOuter:GetPropertyChangedSignal("AbsoluteSize"), UpdateModePosition)
		UpdateModePosition()

		local ModeSelectInner = Library:Create("Frame", {
			BackgroundColor3 = Library.BackgroundColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 15,
			Parent = ModeSelectOuter,
		})

		Library:AddToRegistry(ModeSelectInner, {
			BackgroundColor3 = "BackgroundColor",
			BorderColor3 = "OutlineColor",
		})

		Library:Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = ModeSelectInner,
		})

		local ContainerLabel = Library:CreateLabel({
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, IsMobile and 42 or 18),
			TextSize = 13,
			Visible = false,
			ZIndex = 224,
			Parent = Library.KeybindContainer,
		}, true)

		local ModeButtons = {}

		for Idx, Mode in next, Modes do
			local ModeButton = {}

			local Label = Library:CreateLabel({
				Active = false,
				Position = UDim2.fromOffset(6, ControlTextOffset),
				Size = UDim2.new(1, -12, 0, IsMobile and 42 or 18),
				TextSize = 13,
				Text = Mode,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 16,
				Parent = ModeSelectInner,
			})

			function ModeButton:Select()
				for _, Button in next, ModeButtons do
					Button:Deselect()
				end

				KeyPicker.Mode = Mode

				Label.TextColor3 = Library.AccentColor
				Library.RegistryMap[Label].Properties.TextColor3 = "AccentColor"

				ModeSelectOuter.Visible = false
				Library.OpenedFrames[ModeSelectOuter] = nil
			end

			function ModeButton:Deselect()
				KeyPicker.Mode = nil

				Label.TextColor3 = Library.FontColor
				Library.RegistryMap[Label].Properties.TextColor3 = "FontColor"
			end

			Library:ConnectClick(Label, function()
				ModeButton:Select()
				Library:AttemptSave()
			end)

			if Mode == KeyPicker.Mode then
				ModeButton:Select()
			end

			ModeButtons[Mode] = ModeButton
		end

		function KeyPicker:Update()
			if Info.NoUI then
				return
			end

			local State = KeyPicker:GetState()
			local KeyWidth = select(1, Library:GetTextBounds(tostring(KeyPicker.Value), Library.Font, 13))
			PickOuter.Size = UDim2.fromOffset(math.clamp(KeyWidth + 12, 34, 92), TouchKeyHeight)
			UpdateModePosition()

			-- Only show in keybind list if the associated toggle/feature is active
			local parentIsActive = true
			if ParentObj and ParentObj.Type == "Toggle" then
				parentIsActive = ParentObj.Value == true
			end

			ContainerLabel.Text = string.format("[%s] %s (%s)", KeyPicker.Value, Info.Text, KeyPicker.Mode)

			ContainerLabel.Visible = parentIsActive
			ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor

			Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and "AccentColor" or "FontColor"

			local YSize = 0
			local XSize = 0

			for _, Label in next, Library.KeybindContainer:GetChildren() do
				if Label:IsA("TextLabel") and Label.Visible then
					YSize = YSize + (IsMobile and 42 or 18)
					if Label.TextBounds.X > XSize then
						XSize = Label.TextBounds.X
					end
				end
			end

			local MaxWidth = math.huge
			if IsMobile and workspace.CurrentCamera then
				local LeftInset, _, RightInset = GetViewportInsets()
				MaxWidth = math.max(120, workspace.CurrentCamera.ViewportSize.X * _invScale - LeftInset - RightInset - (Library.MobileMargin * 2))
			end
			local NewSize = UDim2.new(0, math.min(math.max(XSize + 18, 160), MaxWidth), 0, YSize + 27)
			if Library.KeybindFrame.Size ~= NewSize then
				Library.KeybindFrame.Size = NewSize
				if Library.KeybindFrame.Visible then Library:RequestViewportLayout() end
			end
		end

		function KeyPicker:GetState()
			if KeyPicker.Mode == "Always" then
				return true
			elseif KeyPicker.Mode == "Hold" then
				if KeyPicker.Value == "None" then
					return false
				end

				local Key = KeyPicker.Value

				if Key == "MB1" or Key == "MB2" then
					return Key == "MB1" and IsClickHeld()
						or Key == "MB2" and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
				else
					local ValidKey, KeyCode = pcall(function() return Enum.KeyCode[KeyPicker.Value] end)
					return ValidKey and KeyCode ~= nil and InputService:IsKeyDown(KeyCode)
				end
			else
				return KeyPicker.Toggled
			end
		end

		function KeyPicker:SetValue(Data)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return KeyPicker:SetValue(Data) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			local Key, Mode = Data[1], Data[2]
			Key = KeyAliases[Key] or Key
			DisplayLabel.Text = Key
			KeyPicker.Value = Key
			local ModeButton = ModeButtons[Mode] or ModeButtons[KeyPicker.Mode] or ModeButtons[Modes[1]]
			if ModeButton then ModeButton:Select() end
			KeyPicker:Update()
		end

		function KeyPicker:OnClick(Callback)
			KeyPicker.Clicked = Callback
		end

		function KeyPicker:OnChanged(Callback)
			assert(type(Callback) == "function", "OnChanged callback must be a function")
			KeyPicker.Changed = Callback
			Library:SafeCallback(Callback, KeyPicker.Value)
		end

		if ParentObj.Addons then
			table.insert(ParentObj.Addons, KeyPicker)
		end

		function KeyPicker:DoClick()
			if ParentObj.Type == "Toggle" and KeyPicker.SyncToggleState then
				ParentObj:SetValue(not ParentObj.Value)
			end

			Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
			Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
		end

		local Picking = false
		local StopPickingAnimation = nil
		local CaptureEvent = nil
		local function CancelPicking()
			Picking = false
			if StopPickingAnimation then
				StopPickingAnimation()
				StopPickingAnimation = nil
			end
			if CaptureEvent then
				CaptureEvent:Disconnect()
				Library:ForgetSignal(CaptureEvent)
				CaptureEvent = nil
			end
			if DisplayLabel.Parent then DisplayLabel.Text = tostring(KeyPicker.Value) end
		end

		Library:ConnectClick(PickOuter, function(Input)
			if not Library:MouseIsOverOpenedFrame(Input) then
				if IsMobile and Input.UserInputType == Enum.UserInputType.Touch then
					if KeyPicker.Mode == "Hold" then
						KeyPicker.Toggled = true
						KeyPicker:DoClick()
						Library:DelayUi(0.12, function()
							KeyPicker.Toggled = false
							KeyPicker:DoClick()
							KeyPicker:Update()
						end)
					elseif KeyPicker.Mode == "Toggle" then
						KeyPicker.Toggled = not KeyPicker.Toggled
						KeyPicker:DoClick()
					else
						KeyPicker:DoClick()
					end
					KeyPicker:Update()
					return
				end
				if Picking then return end
				Picking = true
				DisplayLabel.Text = "."
				local AnimationStarted = os.clock()
				local AcceptInputAfter = AnimationStarted + 0.15

				if StopPickingAnimation then StopPickingAnimation() end
				StopPickingAnimation = Library:AddUiUpdater(function()
					if not Picking or not DisplayLabel.Parent then
						StopPickingAnimation = nil
						return false
					end
					local DotCount = (math.floor((os.clock() - AnimationStarted) / 0.4) % 3) + 1
					DisplayLabel.Text = string.rep(".", DotCount)
					return true
				end)

				CaptureEvent = Connect(InputService.InputBegan, function(NewInput)
					if not Picking then return end
					if os.clock() < AcceptInputAfter then return end
					local Key

					if NewInput.UserInputType == Enum.UserInputType.Keyboard then
						Key = NewInput.KeyCode.Name
					elseif NewInput.UserInputType == Enum.UserInputType.MouseButton1 then
						Key = "MB1"
					elseif NewInput.UserInputType == Enum.UserInputType.MouseButton2 then
						Key = "MB2"
					end
					if not Key then return end

					DisplayLabel.Text = Key
					KeyPicker.Value = Key
					CancelPicking()

					Library:SafeCallback(KeyPicker.ChangedCallback, NewInput.KeyCode or NewInput.UserInputType)
					Library:SafeCallback(KeyPicker.Changed, KeyPicker.Value)

					Library:AttemptSave()
				end)
				Library:GiveSignal(CaptureEvent)
			end
		end)
		Connect(PickOuter.InputBegan, function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame(Input) then
				ModeSelectOuter.Visible = true
				Library.OpenedFrames[ModeSelectOuter] = true
				UpdateModePosition()
			end
		end)
		Connect(PickOuter.Destroying, CancelPicking)

		Library:GiveSignal(Connect(InputService.InputBegan, function(Input, Processed)
			if not Picking then
				if Processed then return end
				if KeyPicker.Mode == "Toggle" then
					local Key = KeyPicker.Value

					if Key == "MB1" or Key == "MB2" then
						if
							Key == "MB1" and IsClickInput(Input)
							or Key == "MB2" and Input.UserInputType == Enum.UserInputType.MouseButton2
						then
							KeyPicker.Toggled = not KeyPicker.Toggled
							KeyPicker:DoClick()
						end
					elseif Input.UserInputType == Enum.UserInputType.Keyboard then
						if Input.KeyCode.Name == Key then
							KeyPicker.Toggled = not KeyPicker.Toggled
							KeyPicker:DoClick()
						end
					end
				end

				KeyPicker:Update()
			end

			if IsClickInput(Input) then
				local Pointer = GetPointerPosition(Input)
				local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize

				if
					Pointer.X < AbsPos.X
					or Pointer.X > AbsPos.X + AbsSize.X
					or Pointer.Y < (AbsPos.Y - 20 - 1)
					or Pointer.Y > AbsPos.Y + AbsSize.Y
				then
					ModeSelectOuter.Visible = false
					Library.OpenedFrames[ModeSelectOuter] = nil
				end
			end
		end))

		Library:GiveSignal(Connect(InputService.InputEnded, function(Input)
			if Picking or KeyPicker.Mode ~= "Hold" then return end
			local Key = KeyPicker.Value
			local MatchesMouse = Key == "MB1" and Input.UserInputType == Enum.UserInputType.MouseButton1
				or Key == "MB2" and Input.UserInputType == Enum.UserInputType.MouseButton2
			local MatchesKeyboard = Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Key
			if MatchesMouse or MatchesKeyboard then KeyPicker:Update() end
		end))

		KeyPicker:Update()

		Options[Idx] = KeyPicker

		return self
	end

	BaseAddons.__index = Funcs
	BaseAddons.__namecall = function(Table, Key, ...)
		return Funcs[Key](...)
	end
end

local BaseGroupbox = {}

do
	local Funcs = {}

	function Funcs:AddBlank(Size)
		local Groupbox = self
		local Container = Groupbox.Container

		Library:Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Size),
			ZIndex = 1,
			Parent = Container,
		})
	end

	function Funcs:AddLabel(Text, DoesWrap)
		local Label = {}

		local Groupbox = self
		local Container = Groupbox.Container

		local TextLabel = Library:CreateLabel({
			Size = UDim2.new(1, -4, 0, 15),
			TextSize = 14,
			Text = Text,
			TextWrapped = DoesWrap or false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
			Parent = Container,
		})

		if DoesWrap then
			local Y = select(
				2,
				Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge))
			)
			TextLabel.Size = UDim2.new(1, -4, 0, Y)
		else
			Library:Create("UIListLayout", {
				Padding = UDim.new(0, 4),
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = TextLabel,
			})
		end

		Label.TextLabel = TextLabel
		Label.Container = Container

		function Label:SetText(Text)
			TextLabel.Text = Text

			if DoesWrap then
				local Y = select(
					2,
					Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge))
				)
				TextLabel.Size = UDim2.new(1, -4, 0, Y)
			end

			Groupbox:Resize()
		end

		if not DoesWrap then
			setmetatable(Label, BaseAddons)
		end

		Groupbox:AddBlank(5)
		Groupbox:Resize()

		return Label
	end

	function Funcs:AddButton(...)
		-- TODO: Eventually redo this
		local Button = {}
		local function ProcessButtonParams(Class, Obj, ...)
			local Props = select(1, ...)
			if type(Props) == "table" then
				Obj.Text = Props.Text
				Obj.Func = Props.Func
				Obj.DoubleClick = Props.DoubleClick
				Obj.Tooltip = Props.Tooltip
			else
				Obj.Text = select(1, ...)
				Obj.Func = select(2, ...)
			end

			assert(type(Obj.Func) == "function", "AddButton: `Func` callback is missing.")
		end

		ProcessButtonParams("Button", Button, ...)

		local Groupbox = self
		local Container = Groupbox.Container

		local function CreateBaseButton(Button)
			local Outer = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(1, -4, 0, TouchButtonHeight),
				ZIndex = 5,
			})

			local Inner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 6,
				Parent = Outer,
			})

			local Label = Library:CreateLabel({
				Position = UDim2.fromOffset(0, ControlTextOffset),
				Size = UDim2.new(1, 0, 1, 0),
				TextSize = 14,
				Text = Button.Text,
				ZIndex = 6,
				Parent = Inner,
			})

			Library:Create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
				}),
				Rotation = 90,
				Parent = Inner,
			})

			Library:AddToRegistry(Outer, {
				BorderColor3 = "Black",
			})

			Library:AddToRegistry(Inner, {
				BackgroundColor3 = "MainColor",
				BorderColor3 = "OutlineColor",
			})

			Library:OnHighlight(Outer, Outer, { BorderColor3 = "AccentColor" }, { BorderColor3 = "Black" })

			return Outer, Inner, Label
		end

		local function InitEvents(Button)
			local function ValidateClick(Input)
				if Library:MouseIsOverOpenedFrame(Input) then
					return false
				end
				return true
			end

			local Confirming = false
			local ConfirmationVersion = 0
			local function ResetConfirmation()
				Confirming = false
				Button.Locked = false
				Library:RemoveFromRegistry(Button.Label)
				Library:AddToRegistry(Button.Label, { TextColor3 = "FontColor" })
				Button.Label.TextColor3 = Library.FontColor
				Button.Label.Text = Button.Text
			end

			Library:ConnectClick(Button.Outer, function(Input)
				if not ValidateClick(Input) then
					return
				end
				if Button.Locked and not Confirming then
					return
				end

				if Button.DoubleClick then
					if Confirming then
						ConfirmationVersion += 1
						ResetConfirmation()
						Library:SafeCallback(Button.Func)
						return
					end

					Library:RemoveFromRegistry(Button.Label)
					Library:AddToRegistry(Button.Label, { TextColor3 = "AccentColor" })

					Button.Label.TextColor3 = Library.AccentColor
					Button.Label.Text = "Are you sure?"
					Button.Locked = true
					Confirming = true
					ConfirmationVersion += 1
					local CurrentVersion = ConfirmationVersion
					Library:DelayUi(0.5, function()
						if Confirming and CurrentVersion == ConfirmationVersion then ResetConfirmation() end
					end)

					return
				end

				Library:SafeCallback(Button.Func)
			end)
		end

		Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
		Button.Outer.Parent = Container

		InitEvents(Button)

		function Button:AddTooltip(tooltip)
			if type(tooltip) == "string" then
				Library:AddToolTip(tooltip, self.Outer)
			end
			return self
		end

		function Button:AddButton(...)
			local SubButton = {}

			ProcessButtonParams("SubButton", SubButton, ...)

			self.Outer.Size = UDim2.new(0.5, -2, 0, TouchButtonHeight)

			SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

			SubButton.Outer.Position = UDim2.new(1, 4, 0, 0)
			SubButton.Outer.Size = UDim2.new(1, 0, 1, 0)
			SubButton.Outer.Parent = self.Outer

			function SubButton:AddTooltip(tooltip)
				if type(tooltip) == "string" then
					Library:AddToolTip(tooltip, self.Outer)
				end
				return SubButton
			end

			if type(SubButton.Tooltip) == "string" then
				SubButton:AddTooltip(SubButton.Tooltip)
			end

			InitEvents(SubButton)
			return SubButton
		end

		if type(Button.Tooltip) == "string" then
			Button:AddTooltip(Button.Tooltip)
		end

		Groupbox:AddBlank(5)
		Groupbox:Resize()

		return Button
	end

	function Funcs:AddDivider()
		local Groupbox = self
		local Container = self.Container

		local Divider = {
			Type = "Divider",
		}

		Groupbox:AddBlank(2)
		local DividerOuter = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderColor3 = Color3.new(0, 0, 0),
			Size = UDim2.new(1, -4, 0, 5),
			ZIndex = 5,
			Parent = Container,
		})

		local DividerInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 6,
			Parent = DividerOuter,
		})

		Library:AddToRegistry(DividerOuter, {
			BorderColor3 = "Black",
		})

		Library:AddToRegistry(DividerInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})

		Groupbox:AddBlank(9)
		Groupbox:Resize()
	end

	function Funcs:AddInput(Idx, Info)
		assert(Info.Text, "AddInput: Missing `Text` string.")

		local Textbox = {
			Value = Info.Default or "",
			Numeric = Info.Numeric or false,
			Finished = Info.Finished or false,
			Type = "Input",
			Callback = Info.Callback or function(Value) end,
		}

		local Groupbox = self
		local Container = Groupbox.Container

		local InputLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 0, 15),
			TextSize = 14,
			Text = Info.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
			Parent = Container,
		})

		Groupbox:AddBlank(1)

		local TextBoxOuter = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderColor3 = Color3.new(0, 0, 0),
			Size = UDim2.new(1, -4, 0, TouchButtonHeight),
			ZIndex = 5,
			Parent = Container,
		})

		local TextBoxInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 6,
			Parent = TextBoxOuter,
		})

		Library:AddToRegistry(TextBoxInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})

		Library:OnHighlight(TextBoxOuter, TextBoxOuter, { BorderColor3 = "AccentColor" }, { BorderColor3 = "Black" })

		if type(Info.Tooltip) == "string" then
			Library:AddToolTip(Info.Tooltip, TextBoxOuter)
		end

		Library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
			}),
			Rotation = 90,
			Parent = TextBoxInner,
		})

		local Container = Library:Create("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,

			Position = UDim2.new(0, 5, 0, 0),
			Size = UDim2.new(1, -5, 1, 0),

			ZIndex = 7,
			Parent = TextBoxInner,
		})

		local Box = Library:Create("TextBox", {
			BackgroundTransparency = 1,

			Position = UDim2.fromOffset(0, ControlTextOffset),
			Size = UDim2.new(5, 0, 1, -ControlTextOffset),

			Font = Library.Font,
			PlaceholderColor3 = Color3.fromRGB(190, 190, 190),
			PlaceholderText = Info.Placeholder or "",

			Text = Info.Default or "",
			TextColor3 = Library.FontColor,
			TextSize = 14,
			TextStrokeTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,

			ZIndex = 7,
			Parent = Container,
		})

		Library:ApplyTextStroke(Box)

		function Textbox:SetValue(Text)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return Textbox:SetValue(Text) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			if Info.MaxLength and #Text > Info.MaxLength then
				Text = Text:sub(1, Info.MaxLength)
			end

			if Textbox.Numeric then
				if (not tonumber(Text)) and Text:len() > 0 then
					Text = Textbox.Value
				end
			end

			Textbox.Value = Text
			Box.Text = Text

			Library:SafeCallback(Textbox.Callback, Textbox.Value)
			Library:SafeCallback(Textbox.Changed, Textbox.Value)
		end

		if Textbox.Finished then
			Connect(Box.FocusLost, function(enter)
				if not enter then
					return
				end

				Textbox:SetValue(Box.Text)
				Library:AttemptSave()
			end)
		else
			Connect(Box:GetPropertyChangedSignal("Text"), function()
				Textbox:SetValue(Box.Text)
				Library:AttemptSave()
			end)
		end

		-- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
		-- thank you nicemike40 :)

		local function Update()
			local PADDING = 2
			local reveal = Container.AbsoluteSize.X

			if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
				-- we aren't focused, or we fit so be normal
				Box.Position = UDim2.new(0, PADDING, 0, 0)
			else
				-- we are focused and don't fit, so adjust position
				local cursor = Box.CursorPosition
				if cursor ~= -1 then
					-- calculate pixel width of text from start to cursor
					local subtext = string.sub(Box.Text, 1, cursor - 1)
					local width =
						TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

					-- check if we're inside the box with the cursor
					local currentCursorPos = Box.Position.X.Offset + width

					-- adjust if necessary
					if currentCursorPos < PADDING then
						Box.Position = UDim2.fromOffset(PADDING - width, 0)
					elseif currentCursorPos > reveal - PADDING - 1 then
						Box.Position = UDim2.fromOffset(reveal - width - PADDING - 1, 0)
					end
				end
			end
		end

		Update()

		Connect(Box:GetPropertyChangedSignal("Text"), Update)
		Connect(Box:GetPropertyChangedSignal("CursorPosition"), Update)
		Connect(Box.FocusLost, Update)
		Connect(Box.Focused, Update)

		Library:AddToRegistry(Box, {
			TextColor3 = "FontColor",
		})

		function Textbox:OnChanged(Func)
			assert(type(Func) == "function", "OnChanged callback must be a function")
			Textbox.Changed = Func
			Library:SafeCallback(Func, Textbox.Value)
		end

		Groupbox:AddBlank(5)
		Groupbox:Resize()

		Options[Idx] = Textbox

		return Textbox
	end

	function Funcs:AddToggle(Idx, Info)
		assert(Info.Text, "AddInput: Missing `Text` string.")

		local Toggle = {
			Value = Info.Default or false,
			Type = "Toggle",

			Callback = Info.Callback or function(Value) end,
			Addons = {},
			Risky = Info.Risky,
		}

		local Groupbox = self
		local Container = Groupbox.Container

		local ToggleOuter = Library:Create("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -4, 0, TouchToggleHeight),
			ZIndex = 5,
			Parent = Container,
		})

		local ToggleBoxOuter = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.fromOffset(0, IsMobile and 4 or 1),
			Size = UDim2.fromOffset(IsMobile and 32 or 15, IsMobile and 32 or 15),
			ZIndex = 5,
			Parent = ToggleOuter,
		})

		Library:AddToRegistry(ToggleBoxOuter, {
			BorderColor3 = "Black",
		})

		local ToggleInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 6,
			Parent = ToggleBoxOuter,
		})

		Library:AddToRegistry(ToggleInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})
		local ToggleLabel = Library:CreateLabel({
			Size = UDim2.new(1, -(IsMobile and 40 or 21), 1, 0),
			Position = UDim2.fromOffset(IsMobile and 40 or 21, ControlTextOffset),
			TextSize = 14,
			Text = Info.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 6,
			Parent = ToggleOuter,
		})

		local AddonContainer = Library:Create("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(0, TouchToggleHeight),
			ZIndex = 7,
			Parent = ToggleOuter,
		})
		local AddonLayout = Library:Create("UIListLayout", {
			Padding = UDim.new(0, 4),
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = AddonContainer,
		})
		local ToggleRegion
		local function ResizeToggleText()
			local AddonWidth = AddonLayout.AbsoluteContentSize.X
			local LabelOffset = IsMobile and 40 or 21
			AddonContainer.Size = UDim2.fromOffset(AddonWidth, TouchToggleHeight)
			ToggleLabel.Size = UDim2.new(1, -(LabelOffset + (AddonWidth > 0 and AddonWidth + 5 or 0)), 1, 0)
			if ToggleRegion then
				ToggleRegion.Size = UDim2.new(1, -(AddonWidth > 0 and AddonWidth + 4 or 0), 1, 0)
			end
		end
		Connect(AddonLayout:GetPropertyChangedSignal("AbsoluteContentSize"), ResizeToggleText)
		ResizeToggleText()

		ToggleRegion = Library:Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Parent = ToggleOuter,
		})
		ResizeToggleText()

		local Hovered = false
		Connect(ToggleRegion.MouseEnter, function()
			Hovered = true
			Toggle:Display()
		end)
		Connect(ToggleRegion.MouseLeave, function()
			Hovered = false
			Toggle:Display()
		end)

		function Toggle:UpdateColors()
			Toggle:Display()
		end

		if type(Info.Tooltip) == "string" then
			Library:AddToolTip(Info.Tooltip, ToggleRegion)
		end

		function Toggle:Display()
			ToggleInner.BackgroundColor3 = Toggle.Value and Library.AccentColor or Library.MainColor
			local BorderColor = if Hovered then Library.AccentColor
				elseif Toggle.Value then Library.AccentColorDark
				else Library.OutlineColor
			ToggleInner.BorderColor3 = BorderColor

			Library.RegistryMap[ToggleInner].Properties.BackgroundColor3 = Toggle.Value and "AccentColor" or "MainColor"
			Library.RegistryMap[ToggleInner].Properties.BorderColor3 = if Hovered then "AccentColor"
				elseif Toggle.Value then "AccentColorDark"
				else "OutlineColor"
		end

		function Toggle:OnChanged(Func)
			assert(type(Func) == "function", "OnChanged callback must be a function")
			Toggle.Changed = Func
			Library:SafeCallback(Func, Toggle.Value)
		end

		function Toggle:SetValue(Bool)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return Toggle:SetValue(Bool) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			Bool = not not Bool

			Toggle.Value = Bool
			Toggle:Display()

			for _, Addon in next, Toggle.Addons do
				if Addon.Type == "KeyPicker" and Addon.SyncToggleState then
					Addon.Toggled = Bool
					Addon:Update()
				end
			end

			Library:SafeCallback(Toggle.Callback, Toggle.Value)
			Library:SafeCallback(Toggle.Changed, Toggle.Value)
			Library:UpdateDependencyBoxes()
		end

		Library:ConnectClick(ToggleRegion, function(Input)
			if not Library:MouseIsOverOpenedFrame(Input) then
				Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
				Library:AttemptSave()
			end
		end)

		if Toggle.Risky then
			Library:RemoveFromRegistry(ToggleLabel)
			ToggleLabel.TextColor3 = Library.RiskColor
			Library:AddToRegistry(ToggleLabel, { TextColor3 = "RiskColor" })
		end

		Toggle:Display()
		Groupbox:AddBlank(Info.BlankSize or 5 + 2)
		Groupbox:Resize()

		Toggle.TextLabel = AddonContainer
		Toggle.Label = ToggleLabel
		Toggle.Container = Container
		setmetatable(Toggle, BaseAddons)

		Toggles[Idx] = Toggle

		Library:UpdateDependencyBoxes()

		return Toggle
	end

	function Funcs:AddSlider(Idx, Info)
		assert(Info.Default, "AddSlider: Missing default value.")
		assert(Info.Text, "AddSlider: Missing slider text.")
		assert(Info.Min, "AddSlider: Missing minimum value.")
		assert(Info.Max, "AddSlider: Missing maximum value.")
		assert(Info.Rounding, "AddSlider: Missing rounding value.")

		local Slider = {
			Value = Info.Default,
			Min = Info.Min,
			Max = Info.Max,
			Rounding = Info.Rounding,
			Increment = Info.Increment,
			Type = "Slider",
			Callback = Info.Callback or function(Value) end,
		}

		local Groupbox = self
		local Container = Groupbox.Container

		if not Info.Compact then
			Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 10),
				TextSize = 14,
				Text = Info.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				ZIndex = 5,
				Parent = Container,
			})

			Groupbox:AddBlank(3)
		end

		local SliderOuter = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderColor3 = Color3.new(0, 0, 0),
			Size = UDim2.new(1, -4, 0, TouchSliderHeight),
			ZIndex = 5,
			Parent = Container,
		})

		Library:AddToRegistry(SliderOuter, {
			BorderColor3 = "Black",
		})

		local SliderInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 6,
			Parent = SliderOuter,
		})

		Library:AddToRegistry(SliderInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})

		local Fill = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderColor3 = Library.AccentColorDark,
			ClipsDescendants = true,
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 7,
			Parent = SliderInner,
		})

		Library:AddToRegistry(Fill, {
			BackgroundColor3 = "AccentColor",
			BorderColor3 = "AccentColorDark",
		})

		local HideBorderRight = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderSizePixel = 0,
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 1, 1, 0),
			ZIndex = 8,
			Parent = Fill,
		})

		Library:AddToRegistry(HideBorderRight, {
			BackgroundColor3 = "AccentColor",
		})

		local DisplayLabel = Library:CreateLabel({
			Position = UDim2.fromOffset(0, ControlTextOffset),
			Size = UDim2.new(1, 0, 1, -ControlTextOffset),
			TextSize = 14,
			Text = "Infinite",
			ZIndex = 9,
			Parent = SliderInner,
		})
		local FillDisplayLabel = Library:CreateLabel({
			Position = UDim2.fromOffset(0, ControlTextOffset),
			Size = UDim2.fromOffset(0, TouchSliderHeight - ControlTextOffset),
			TextColor3 = Library.Black,
			TextSize = 14,
			Text = "Infinite",
			ZIndex = 10,
			Parent = Fill,
		})
		Library.RegistryMap[FillDisplayLabel].Properties.TextColor3 = "Black"
		local function ResizeFillLabel()
			FillDisplayLabel.Size = UDim2.fromOffset(
				math.max(SliderInner.AbsoluteSize.X * _invScale, 1),
				TouchSliderHeight - ControlTextOffset
			)
		end
		Connect(SliderInner:GetPropertyChangedSignal("AbsoluteSize"), ResizeFillLabel)
		ResizeFillLabel()

		Library:OnHighlight(SliderOuter, SliderOuter, { BorderColor3 = "AccentColor" }, { BorderColor3 = "Black" })

		if type(Info.Tooltip) == "string" then
			Library:AddToolTip(Info.Tooltip, SliderOuter)
		end

		function Slider:UpdateColors()
			Fill.BackgroundColor3 = Library.AccentColor
			Fill.BorderColor3 = Library.AccentColorDark
		end

		function Slider:Display()
			local Suffix = Info.Suffix or ""

			if Info.Compact then
				DisplayLabel.Text = Info.Text .. ": " .. Slider.Value .. Suffix
			elseif Info.HideMax then
				DisplayLabel.Text = string.format("%s", Slider.Value .. Suffix)
			else
				DisplayLabel.Text = string.format("%s/%s", Slider.Value .. Suffix, Slider.Max .. Suffix)
			end
			FillDisplayLabel.Text = DisplayLabel.Text

			local Range = Slider.Max - Slider.Min
			local Ratio = if Range == 0 then 0 else math.clamp((Slider.Value - Slider.Min) / Range, 0, 1)
			Fill.Size = UDim2.new(Ratio, 0, 1, 0)
			HideBorderRight.Visible = Ratio > 0 and Ratio < 1
		end

		function Slider:OnChanged(Func)
			assert(type(Func) == "function", "OnChanged callback must be a function")
			Slider.Changed = Func
			Library:SafeCallback(Func, Slider.Value)
		end

		local function Round(Value)
			if Slider.Increment then
				local snapped = math.round(Value / Slider.Increment) * Slider.Increment
				return tonumber(string.format("%." .. Slider.Rounding .. "f", snapped))
			end

			if Slider.Rounding == 0 then
				return math.floor(Value)
			end

			return tonumber(string.format("%." .. Slider.Rounding .. "f", Value))
		end

		function Slider:GetValueFromXOffset(X)
			local MaxSize = math.max(SliderInner.AbsoluteSize.X * _invScale, 1)
			return Round(Library:MapValue(math.clamp(X, 0, MaxSize), 0, MaxSize, Slider.Min, Slider.Max))
		end

		function Slider:SetValue(Str)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return Slider:SetValue(Str) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			local Num = tonumber(Str)

			if not Num then
				return
			end

			Num = math.clamp(Num, Slider.Min, Slider.Max)

			Slider.Value = Num
			Slider:Display()

			Library:SafeCallback(Slider.Callback, Slider.Value)
			Library:SafeCallback(Slider.Changed, Slider.Value)
		end

		local StopSliderUpdate = nil
		Connect(SliderInner.InputBegan, function(Input)
			if IsClickInput(Input) and not Library:MouseIsOverOpenedFrame() then
				local PointerInput = Input
				if StopSliderUpdate then StopSliderUpdate() end
				StopSliderUpdate = Library:AddUiUpdater(function()
					if not IsPointerHeld(PointerInput) or not SliderInner.Parent then
						StopSliderUpdate = nil
						Library:AttemptSave()
						return false
					end
					local MaxSize = math.max(SliderInner.AbsoluteSize.X * _invScale, 1)
					local Pointer = GetPointerPosition(PointerInput)
					local nX = math.clamp((Pointer.X - SliderInner.AbsolutePosition.X) * _invScale, 0, MaxSize)

					local nValue = Slider:GetValueFromXOffset(nX)
					local OldValue = Slider.Value
					Slider.Value = nValue

					Slider:Display()

					if nValue ~= OldValue then
						Library:SafeCallback(Slider.Callback, Slider.Value)
						Library:SafeCallback(Slider.Changed, Slider.Value)
					end
					return true
				end)
			end
		end)
		Connect(SliderInner:GetPropertyChangedSignal("AbsoluteSize"), function() Slider:Display() end)

		Slider:Display()
		Groupbox:AddBlank(Info.BlankSize or 6)
		Groupbox:Resize()

		Options[Idx] = Slider

		return Slider
	end

	function Funcs:AddDropdown(Idx, Info)
		if Info.SpecialType == "Player" then
			Info.Values = GetPlayersString()
			Info.AllowNull = true
		elseif Info.SpecialType == "Team" then
			Info.Values = GetTeamsString()
			Info.AllowNull = true
		end

		assert(Info.Values, "AddDropdown: Missing dropdown value list.")
		assert(
			Info.AllowNull or Info.Default,
			"AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional."
		)

		if not Info.Text then
			Info.Compact = true
		end

		local Dropdown = {
			Values = Info.Values,
			Value = Info.Multi and {},
			Multi = Info.Multi,
			Type = "Dropdown",
			SpecialType = Info.SpecialType, -- can be either 'Player' or 'Team'
			Callback = Info.Callback or function(Value) end,
		}

		local Groupbox = self
		local Container = Groupbox.Container

		local RelativeOffset = 0

		if not Info.Compact then
			local DropdownLabel = Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 10),
				TextSize = 14,
				Text = Info.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				ZIndex = 5,
				Parent = Container,
			})

			Groupbox:AddBlank(3)
		end

		for _, Element in next, Container:GetChildren() do
			if not Element:IsA("UIListLayout") then
				RelativeOffset = RelativeOffset + Element.Size.Y.Offset
			end
		end

		local DropdownOuter = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderColor3 = Color3.new(0, 0, 0),
			Size = UDim2.new(1, -4, 0, TouchButtonHeight),
			ZIndex = 5,
			Parent = Container,
		})

		Library:AddToRegistry(DropdownOuter, {
			BorderColor3 = "Black",
		})

		local DropdownInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 6,
			Parent = DropdownOuter,
		})

		Library:AddToRegistry(DropdownInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})

		Library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
			}),
			Rotation = 90,
			Parent = DropdownInner,
		})

		local DropdownArrow = Library:Create("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.new(0, 12, 0, 12),
			Image = "http://www.roblox.com/asset/?id=6282522798",
			ZIndex = 8,
			Parent = DropdownInner,
		})

		local ItemList = Library:CreateLabel({
			Position = UDim2.new(0, 5, 0, ControlTextOffset),
			Size = UDim2.new(1, -26, 1, 0),
			TextSize = 14,
			Text = "--",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 7,
			Parent = DropdownInner,
		})

		Library:OnHighlight(DropdownOuter, DropdownOuter, { BorderColor3 = "AccentColor" }, { BorderColor3 = "Black" })

		if type(Info.Tooltip) == "string" then
			Library:AddToolTip(Info.Tooltip, DropdownOuter)
		end

		local MAX_DROPDOWN_ITEMS = 8

		local ListOuter = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderColor3 = Color3.new(0, 0, 0),
			ZIndex = 20,
			Visible = false,
			Parent = ScreenGui,
		})
		Library:RegisterCursorRegion(ListOuter)

		local function RecalculateListPosition()
			Library:PositionPopup(ListOuter, DropdownOuter, "Below", 3)
		end

		local function RecalculateListSize(YSize)
			ListOuter.Size =
				UDim2.fromOffset(DropdownOuter.AbsoluteSize.X * _invScale, YSize or (MAX_DROPDOWN_ITEMS * TouchDropdownRowHeight + 2))
		end

		RecalculateListPosition()
		RecalculateListSize()

		Connect(DropdownOuter:GetPropertyChangedSignal("AbsolutePosition"), RecalculateListPosition)
		Connect(DropdownOuter:GetPropertyChangedSignal("AbsoluteSize"), function()
			RecalculateListSize(ListOuter.Size.Y.Offset)
			RecalculateListPosition()
		end)

		local ListInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 21,
			Parent = ListOuter,
		})

		Library:AddToRegistry(ListInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})

		local Scrolling = Library:Create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 21,
			Parent = ListInner,

			TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",

			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Library.AccentColor,
		})

		Library:AddToRegistry(Scrolling, {
			ScrollBarImageColor3 = "AccentColor",
		})

		Library:Create("UIListLayout", {
			Padding = UDim.new(0, 0),
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = Scrolling,
		})

		function Dropdown:Display()
			local Values = Dropdown.Values
			local Str = ""

			if Info.Multi then
				for Idx, Value in next, Values do
					if Dropdown.Value[Value] then
						Str = Str .. Value .. ", "
					end
				end

				Str = Str:sub(1, #Str - 2)
			else
				Str = Dropdown.Value or ""
			end

			ItemList.Text = (Str == "" and "--" or Str)
		end

		function Dropdown:GetActiveValues()
			if Info.Multi then
				local T = {}

				for Value, Bool in next, Dropdown.Value do
					if Bool == true then table.insert(T, Value) end
				end

				return T
			else
				return Dropdown.Value and 1 or 0
			end
		end

		function Dropdown:BuildDropdownList()
			local Values = Dropdown.Values
			local Buttons = {}

			for _, Element in next, Scrolling:GetChildren() do
				if not Element:IsA("UIListLayout") then
					Element:Destroy()
				end
			end

			local Count = 0

			for Idx, Value in next, Values do
				local Table = {}

				Count = Count + 1

				local Button = Library:Create("Frame", {
					BackgroundColor3 = Library.MainColor,
					BorderColor3 = Library.OutlineColor,
					BorderMode = Enum.BorderMode.Middle,
					Size = UDim2.new(1, -1, 0, TouchDropdownRowHeight),
					ZIndex = 23,
					Active = true,
					Parent = Scrolling,
				})

				Library:AddToRegistry(Button, {
					BackgroundColor3 = "MainColor",
					BorderColor3 = "OutlineColor",
				})

				local ButtonLabel = Library:CreateLabel({
					Active = false,
					Size = UDim2.new(1, -6, 1, 0),
					Position = UDim2.new(0, 6, 0, ControlTextOffset),
					TextSize = 14,
					Text = Value,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 25,
					Parent = Button,
				})

				Library:OnHighlight(
					Button,
					Button,
					{ BorderColor3 = "AccentColor", ZIndex = 24 },
					{ BorderColor3 = "OutlineColor", ZIndex = 23 }
				)

				local Selected

				if Info.Multi then
					Selected = Dropdown.Value[Value]
				else
					Selected = Dropdown.Value == Value
				end

				function Table:UpdateButton()
					if Info.Multi then
						Selected = Dropdown.Value[Value]
					else
						Selected = Dropdown.Value == Value
					end

					ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor
					Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and "AccentColor" or "FontColor"
				end

				Library:ConnectClick(ButtonLabel, function()
					local Try = not Selected

					local ActiveCount = Info.Multi and #Dropdown:GetActiveValues() or Dropdown:GetActiveValues()
					if ActiveCount == 1 and not Try and not Info.AllowNull then
					else
						if Info.Multi then
							Selected = Try

							if Selected then
								Dropdown.Value[Value] = true
							else
								Dropdown.Value[Value] = nil
							end
						else
							Selected = Try

							if Selected then
								Dropdown.Value = Value
							else
								Dropdown.Value = nil
							end

							for _, OtherButton in next, Buttons do
								OtherButton:UpdateButton()
							end
						end

						Table:UpdateButton()
						Dropdown:Display()

						Library:SafeCallback(Dropdown.Callback, Dropdown.Value)
						Library:SafeCallback(Dropdown.Changed, Dropdown.Value)

						Library:AttemptSave()
					end
				end)

				Table:UpdateButton()
				Dropdown:Display()

				Buttons[Button] = Table
			end

			Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * TouchDropdownRowHeight) + 1)

			local Y = math.clamp(Count * TouchDropdownRowHeight, 0, MAX_DROPDOWN_ITEMS * TouchDropdownRowHeight) + 1
			RecalculateListSize(Y)
			RecalculateListPosition()
		end

		function Dropdown:SetValues(NewValues)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return Dropdown:SetValues(NewValues) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			if NewValues then
				Dropdown.Values = NewValues
			end
			local SelectionChanged = false
			if Dropdown.Multi then
				local Sanitized = {}
				for Value, Selected in Dropdown.Value do
					if Selected == true and table.find(Dropdown.Values, Value) then Sanitized[Value] = true end
				end
				if not Info.AllowNull and next(Sanitized) == nil and #Dropdown.Values > 0 then
					Sanitized[Dropdown.Values[1]] = true
				end
				for Value, Selected in Dropdown.Value do
					if Selected == true and Sanitized[Value] ~= true then SelectionChanged = true break end
				end
				if not SelectionChanged then
					for Value, Selected in Sanitized do
						if Selected == true and Dropdown.Value[Value] ~= true then SelectionChanged = true break end
					end
				end
				Dropdown.Value = Sanitized
			elseif Dropdown.Value ~= nil and not table.find(Dropdown.Values, Dropdown.Value) then
				local Replacement = if not Info.AllowNull then Dropdown.Values[1] else nil
				SelectionChanged = Dropdown.Value ~= Replacement
				Dropdown.Value = Replacement
			elseif Dropdown.Value == nil and not Info.AllowNull and #Dropdown.Values > 0 then
				Dropdown.Value = Dropdown.Values[1]
				SelectionChanged = true
			end

			Dropdown:BuildDropdownList()
			Dropdown:Display()
			if SelectionChanged then
				Library:SafeCallback(Dropdown.Callback, Dropdown.Value)
				Library:SafeCallback(Dropdown.Changed, Dropdown.Value)
				Library:AttemptSave()
			end
		end

		function Dropdown:OpenDropdown()
			RecalculateListPosition()
			ListOuter.Visible = true
			Library.OpenedFrames[ListOuter] = true
			DropdownArrow.Rotation = 180
		end

		function Dropdown:CloseDropdown()
			ListOuter.Visible = false
			Library.OpenedFrames[ListOuter] = nil
			DropdownArrow.Rotation = 0
		end
		Library.PopupAnchors[ListOuter].Close = function() Dropdown:CloseDropdown() end

		function Dropdown:OnChanged(Func)
			assert(type(Func) == "function", "OnChanged callback must be a function")
			Dropdown.Changed = Func
			Library:SafeCallback(Func, Dropdown.Value)
		end

		function Dropdown:SetValue(Val)
			if Library.Mounted and not Library:IsUiThread() then
				local Success, Result = Library:RunUi(function() return Dropdown:SetValue(Val) end)
				if not Success then Library.LastUiError = tostring(Result) end
				return Result
			end
			if Dropdown.Multi then
				local nTable = {}

				if type(Val) == "table" then
					for Value, Bool in next, Val do
						local Candidate = if type(Value) == "number" then Bool else Value
						local Selected = if type(Value) == "number" then true else Bool == true
						if Selected and table.find(Dropdown.Values, Candidate) then
							nTable[Candidate] = true
						end
					end
				end
				if not Info.AllowNull and next(nTable) == nil and #Dropdown.Values > 0 then
					nTable[Dropdown.Values[1]] = true
				end

				Dropdown.Value = nTable
			else
				if Val ~= nil and table.find(Dropdown.Values, Val) then
					Dropdown.Value = Val
				else
					Dropdown.Value = if not Info.AllowNull then Dropdown.Values[1] else nil
				end
			end

			Dropdown:BuildDropdownList()
			Dropdown:Display()

			Library:SafeCallback(Dropdown.Callback, Dropdown.Value)
			Library:SafeCallback(Dropdown.Changed, Dropdown.Value)
		end

		Library:ConnectClick(DropdownOuter, function(Input)
			if not Library:MouseIsOverOpenedFrame(Input) then
				if ListOuter.Visible then
					Dropdown:CloseDropdown()
				else
					Dropdown:OpenDropdown()
				end
			end
		end)

		Library:GiveSignal(Connect(InputService.InputBegan, function(Input)
			if IsClickInput(Input) then
				local Pointer = GetPointerPosition(Input)
				local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize

				if
					Pointer.X < AbsPos.X
					or Pointer.X > AbsPos.X + AbsSize.X
					or Pointer.Y < (AbsPos.Y - 20 - 1)
					or Pointer.Y > AbsPos.Y + AbsSize.Y
				then
					Dropdown:CloseDropdown()
				end
			end
		end))

		Dropdown:BuildDropdownList()
		Dropdown:Display()

		local Defaults = {}

		if type(Info.Default) == "string" then
			local Idx = table.find(Dropdown.Values, Info.Default)
			if Idx then
				table.insert(Defaults, Idx)
			end
		elseif type(Info.Default) == "table" then
			for _, Value in next, Info.Default do
				local Idx = table.find(Dropdown.Values, Value)
				if Idx then
					table.insert(Defaults, Idx)
				end
			end
		elseif type(Info.Default) == "number" and Dropdown.Values[Info.Default] ~= nil then
			table.insert(Defaults, Info.Default)
		end

		if next(Defaults) then
			for i = 1, #Defaults do
				local Index = Defaults[i]
				if Info.Multi then
					Dropdown.Value[Dropdown.Values[Index]] = true
				else
					Dropdown.Value = Dropdown.Values[Index]
				end

				if not Info.Multi then
					break
				end
			end

			Dropdown:BuildDropdownList()
			Dropdown:Display()
		end

		Groupbox:AddBlank(Info.BlankSize or 5)
		Groupbox:Resize()

		Options[Idx] = Dropdown

		return Dropdown
	end

	function Funcs:AddDependencyBox()
		local Depbox = {
			Dependencies = {},
		}

		local Groupbox = self
		local Container = Groupbox.Container

		local Holder = Library:Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			Visible = false,
			Parent = Container,
		})

		local Frame = Library:Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Visible = true,
			Parent = Holder,
		})

		local Layout = Library:Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = Frame,
		})

		function Depbox:Resize()
			Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y)
			Groupbox:Resize()
		end

		Connect(Layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Depbox:Resize()
		end)

		Connect(Holder:GetPropertyChangedSignal("Visible"), function()
			Depbox:Resize()
		end)

		function Depbox:Update()
			for _, Dependency in next, Depbox.Dependencies do
				local Elem = Dependency[1]
				local Value = Dependency[2]

				if Elem.Type == "Toggle" and Elem.Value ~= Value then
					Holder.Visible = false
					Depbox:Resize()
					return
				end
			end

			Holder.Visible = true
			Depbox:Resize()
		end

		function Depbox:SetupDependencies(Dependencies)
			for _, Dependency in next, Dependencies do
				assert(type(Dependency) == "table", "SetupDependencies: Dependency is not of type `table`.")
				assert(Dependency[1], "SetupDependencies: Dependency is missing element argument.")
				assert(Dependency[2] ~= nil, "SetupDependencies: Dependency is missing value argument.")
			end

			Depbox.Dependencies = Dependencies
			Depbox:Update()
		end

		Depbox.Container = Frame

		setmetatable(Depbox, BaseGroupbox)

		table.insert(Library.DependencyBoxes, Depbox)

		return Depbox
	end

	BaseGroupbox.__index = Funcs
	BaseGroupbox.__namecall = function(Table, Key, ...)
		return Funcs[Key](...)
	end
end

-- < Create other UI elements >
do
	Library.NotificationArea = Library:Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 48),
		Size = UDim2.new(0, 380, 1, -64),
		ZIndex = 300,
		Parent = ScreenGui,
	})

	Library:Create("UIListLayout", {
		Padding = UDim.new(0, 8),
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = Library.NotificationArea,
	})

	local WatermarkOuter = Library:Create("Frame", {
		BorderColor3 = Color3.new(0, 0, 0),
		Position = UDim2.new(0, 10, 0, 10),
		Size = UDim2.new(0, 213, 0, 20),
		ZIndex = 200,
		Visible = false,
		Parent = ScreenGui,
	})

	local WatermarkInner = Library:Create("Frame", {
		BackgroundColor3 = Library.MainColor,
		BorderColor3 = Library.OutlineColor,
		BorderMode = Enum.BorderMode.Inset,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 201,
		Parent = WatermarkOuter,
	})

	Library:AddToRegistry(WatermarkInner, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "OutlineColor",
	})
	local WatermarkAccent = Library:Create("Frame", {
		BackgroundColor3 = Library.AccentColor,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 204,
		Parent = WatermarkInner,
	})
	Library:AddToRegistry(WatermarkAccent, { BackgroundColor3 = "AccentColor" }, true)

	local InnerFrame = Library:Create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 1, 0, 1),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 202,
		Parent = WatermarkInner,
	})

	local Gradient = Library:Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
			ColorSequenceKeypoint.new(1, Library.MainColor),
		}),
		Rotation = -90,
		Parent = InnerFrame,
	})

	Library:AddToRegistry(Gradient, {
		Color = function()
			return ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
				ColorSequenceKeypoint.new(1, Library.MainColor),
			})
		end,
	})

	local WatermarkLabel = Library:CreateLabel({
		Position = UDim2.new(0, 7, 0, 1),
		Size = UDim2.new(1, -14, 1, -1),
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 203,
		Parent = InnerFrame,
	})

	Library.Watermark = WatermarkOuter
	Library.WatermarkText = WatermarkLabel
	Library:MakeDraggable(Library.Watermark)
	Library:RegisterCursorRegion(WatermarkOuter)

	local KeybindOuter = Library:Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BorderColor3 = Color3.new(0, 0, 0),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.new(0, 210, 0, 20),
		Visible = false,
		ZIndex = 220,
		Parent = ScreenGui,
	})

	local KeybindInner = Library:Create("Frame", {
		BackgroundColor3 = Library.MainColor,
		BorderColor3 = Library.OutlineColor,
		BorderMode = Enum.BorderMode.Inset,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 221,
		Parent = KeybindOuter,
	})

	Library:AddToRegistry(KeybindInner, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "OutlineColor",
	}, true)

	local ColorFrame = Library:Create("Frame", {
		BackgroundColor3 = Library.AccentColor,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 222,
		Parent = KeybindInner,
	})

	Library:AddToRegistry(ColorFrame, {
		BackgroundColor3 = "AccentColor",
	}, true)

	local KeybindLabel = Library:CreateLabel({
		Size = UDim2.new(1, -14, 0, 20),
		Position = UDim2.fromOffset(7, 2),
		TextXAlignment = Enum.TextXAlignment.Left,

		Text = "Keybinds",
		ZIndex = 224,
		Parent = KeybindInner,
	})

	local KeybindContainer = Library:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -23),
		Position = UDim2.new(0, 0, 0, 23),
		ZIndex = 223,
		Parent = KeybindInner,
	})

	Library:Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = KeybindContainer,
	})

	Library:Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		Parent = KeybindContainer,
	})

	Library.KeybindFrame = KeybindOuter
	Library.KeybindContainer = KeybindContainer
	Library:MakeDraggable(KeybindOuter)
	Library:RegisterCursorRegion(KeybindOuter)

	-- Add keybind frame to draggable list if it exists
	if Library.DraggableFrames then
		table.insert(Library.DraggableFrames, KeybindOuter)
	end
end

function Library:SetWatermarkVisibility(Bool)
	if Library.Unloaded or not Library.Watermark then return false end
	if not Library:IsUiThread() then
		local Success, Result = Library:RunUi(function() return Library:SetWatermarkVisibility(Bool) end)
		if Success then return Result end
		Library.LastUiError = tostring(Result)
		return false
	end
	Library.Watermark.Visible = Bool
	if Bool then Library:UpdateViewportLayout() end
	return true
end

function Library:SetWatermark(Text)
	if Library.Unloaded or not Library.Watermark or not Library.WatermarkText then return false end
	if not Library:IsUiThread() then
		local Success, Result = Library:RunUi(function() return Library:SetWatermark(Text) end)
		if Success then return Result end
		Library.LastUiError = tostring(Result)
		return false
	end
	local X, Y = Library:GetTextBounds(Text, Library.Font, 14)
	local Width = X + 20
	if IsMobile and workspace.CurrentCamera then
		local LeftInset, _, RightInset = GetViewportInsets()
		Width = math.min(Width, math.max(120, workspace.CurrentCamera.ViewportSize.X * _invScale - LeftInset - RightInset - (Library.MobileMargin * 2)))
	end
	Library.Watermark.Size = UDim2.new(0, Width, 0, (Y * 1.5) + 5)
	Library:SetWatermarkVisibility(true)

	Library.WatermarkText.Text = Text
	Library:UpdateViewportLayout()
	return true
end

function Library:Notify(Text, Time)
	if Library.Unloaded or not Library.NotificationArea then return nil end
	if not Library:IsUiThread() then
		local Success, Result = Library:RunUi(function() return Library:Notify(Text, Time) end)
		if Success then return Result end
		Library.LastUiError = tostring(Result)
		return nil
	end
	Text = tostring(Text or "")
	local ViewportWidth = 800
	pcall(function()
		ViewportWidth = workspace.CurrentCamera.ViewportSize.X * _invScale
	end)
	local TextSize = 13
	local MaxWidth = math.clamp(ViewportWidth - 24, 160, 360)
	local MaxTextWidth = MaxWidth - 32
	local WidestLine = 0
	for _, Line in string.split(Text, "\n") do
		local LineBounds = TextService:GetTextSize(Line, TextSize, Library.Font, Vector2.new(10000, 10000))
		WidestLine = math.max(WidestLine, LineBounds.X)
	end
	local WrappedWidth = math.max(math.min(WidestLine, MaxTextWidth), 1)
	local TextBounds = TextService:GetTextSize(Text, TextSize, Library.Font, Vector2.new(WrappedWidth, 10000))
	local XSize = math.clamp(WidestLine + 32, 140, MaxWidth)
	local YSize = math.max(TextBounds.Y + 12, 28)
	local ReadTime = math.min(12, 2.5 + (#Text / 32) + math.max(0, YSize - 22) / 24)
	local DisplayTime = math.max(tonumber(Time) or 5, ReadTime)

	local NotifyOuter = Library:Create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(XSize, YSize),
		ClipsDescendants = true,
		ZIndex = 300,
		Parent = Library.NotificationArea,
	})
	local NotifyCard = Library:Create("Frame", {
		BackgroundColor3 = Library.Black,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-XSize, 0),
		Size = UDim2.fromOffset(XSize, YSize),
		ZIndex = 301,
		Parent = NotifyOuter,
	})

	local NotifyInner = Library:Create("Frame", {
		BackgroundColor3 = Library.MainColor,
		BorderColor3 = Library.OutlineColor,
		BorderMode = Enum.BorderMode.Inset,
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 302,
		Parent = NotifyCard,
	})

	Library:AddToRegistry(NotifyInner, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "OutlineColor",
	}, true)

	local InnerFrame = Library:Create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 1, 0, 1),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 303,
		Parent = NotifyInner,
	})

	local Gradient = Library:Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
			ColorSequenceKeypoint.new(1, Library.MainColor),
		}),
		Rotation = -90,
		Parent = InnerFrame,
	})

	Library:AddToRegistry(Gradient, {
		Color = function()
			return ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
				ColorSequenceKeypoint.new(1, Library.MainColor),
			})
		end,
	})

	local NotifyLabel = Library:CreateLabel({
		Position = UDim2.new(0, 20, 0, 3),
		Size = UDim2.new(1, -28, 1, -6),
		Text = Text,
		TextSize = TextSize,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 305,
		Parent = InnerFrame,
	}, true)

	local LeftColor = Library:Create("Frame", {
		BackgroundColor3 = Library.AccentColor,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0),
		Size = UDim2.fromOffset(2, 11),
		ZIndex = 306,
		Parent = InnerFrame,
	})

	Library:AddToRegistry(LeftColor, {
		BackgroundColor3 = "AccentColor",
	}, true)
	local TopColor = Library:Create("Frame", {
		BackgroundColor3 = Library.AccentColor,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 0, 1),
		ZIndex = 306,
		Parent = NotifyInner,
	})
	Library:AddToRegistry(TopColor, { BackgroundColor3 = "AccentColor" }, true)
	local Progress = Library:Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Library.AccentColor,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 1, 1, -1),
		Size = UDim2.new(1, -2, 0, 1),
		ZIndex = 306,
		Parent = NotifyInner,
	})
	Library:AddToRegistry(Progress, { BackgroundColor3 = "AccentColor" }, true)

	TweenService:Create(
		NotifyCard,
		TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, 0) }
	):Play()
	TweenService:Create(Progress, TweenInfo.new(DisplayTime, Enum.EasingStyle.Linear), {
		Size = UDim2.fromOffset(0, 1),
	}):Play()

	Library:DelayUi(DisplayTime, function()
		if not NotifyOuter.Parent then return end
		TweenService:Create(
			NotifyCard,
			TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Position = UDim2.fromOffset(-XSize, 0) }
		):Play()
		Library:DelayUi(0.25, function()
			if NotifyOuter.Parent then NotifyOuter:Destroy() end
		end)
	end)

	return NotifyOuter
end

function Library:Toggle()
	local Window = Library.PrimaryWindow or Library.Windows[#Library.Windows]
	if Window and type(Window.Toggle) == "function" then return Window:Toggle() end
	return false
end

function Library:CreateWindow(...)
	local Arguments = { ... }
	local Config = { AnchorPoint = Vector2.zero }

	if type(...) == "table" then
		Config = ...
	else
		Config.Title = Arguments[1]
		Config.AutoShow = Arguments[2] or false
	end

	if type(Config.Title) ~= "string" then
		Config.Title = "No title"
	end
	if type(Config.TabPadding) ~= "number" then
		Config.TabPadding = 0
	end
	if type(Config.MenuFadeTime) ~= "number" then
		Config.MenuFadeTime = 0.2
	end

	local HasConfiguredPosition = typeof(Config.Position) == "UDim2"
	if not HasConfiguredPosition then
		Config.Position = UDim2.fromOffset(175, 50)
	end
	if typeof(Config.Size) ~= "UDim2" then
		Config.Size = UDim2.fromOffset(550, 600)
	end
	if Config.Size.X.Offset > 0 then
		local PreviousRequiredWidth = RequiredUiWidth
		RequiredUiWidth = math.max(RequiredUiWidth, Config.Size.X.Offset + 30)
		if RequiredUiWidth ~= PreviousRequiredWidth and RequestScaleUpdateCallback then
			Library:DelayUi(0, RequestScaleUpdateCallback)
		end
	end
	local NeedsWidthCenter = false
	if not HasConfiguredPosition and Config.Size.X.Offset > 0 then
		local Camera = workspace.CurrentCamera
		if Camera then
			NeedsWidthCenter = Config.Position.X.Offset + Config.Size.X.Offset + 12 > Camera.ViewportSize.X
		end
	end

	-- Auto-center on small viewports (mobile) so the window isn't off-screen
	if Config.Center or _uiScale < 1 or NeedsWidthCenter then
		Config.AnchorPoint = Vector2.new(0.5, 0.5)
		Config.Position = UDim2.fromScale(0.5, 0.5)
	end

	local Window = {
		Tabs = {},
		TabOrder = {},
		Outer = nil, -- Will be set below
		DesiredSize = Config.Size,
		ConfiguredPosition = HasConfiguredPosition,
		MobilePlaced = false,
	}
	Library.PrimaryWindow = Library.PrimaryWindow or Window

	local Outer = Library:Create("CanvasGroup", {
		AnchorPoint = Config.AnchorPoint,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Position = Config.Position,
		Size = Config.Size,
		Visible = false,
		ZIndex = 1,
		Parent = ScreenGui,
	})
	Library:RegisterCursorRegion(Outer)

	Library:MakeDraggable(Outer, 29)

	-- Store reference to Outer for mobile toggle UI
	Window.Outer = Outer

	function Window:FitToViewport()
		if not IsMobile or not Outer.Parent then return end
		local Camera = workspace.CurrentCamera
		if not Camera then return end
		local Viewport = Camera.ViewportSize * _invScale
		local Margin = (Library.MobileMargin or 8) * _invScale
		local LeftInset, TopInset, RightInset, BottomInset = GetViewportInsets()
		local ViewportChanged = Library.LastViewportSize and Library.LastViewportSize ~= Viewport
		local DesiredWidth = self.DesiredSize.X.Scale * Viewport.X + self.DesiredSize.X.Offset
		local DesiredHeight = self.DesiredSize.Y.Scale * Viewport.Y + self.DesiredSize.Y.Offset
		if DesiredWidth <= 0 then DesiredWidth = Outer.AbsoluteSize.X * _invScale end
		if DesiredHeight <= 0 then DesiredHeight = Outer.AbsoluteSize.Y * _invScale end
		local ControllerReserve = if Library.MobileController
			then math.max(54, Library.MobileController.AbsoluteSize.Y * _invScale + Margin)
			else 54
		local AvailableWidth = math.max(180, Viewport.X - LeftInset - RightInset - Margin * 2)
		local UsableTop = TopInset + Margin
		local UsableBottom = Viewport.Y - BottomInset - Margin - ControllerReserve
		local AvailableHeight = math.max(180, UsableBottom - UsableTop)
		local Width = math.min(DesiredWidth, AvailableWidth)
		local Height = math.min(DesiredHeight, AvailableHeight)
		local CenterX = Outer.AbsolutePosition.X * _invScale + Outer.AbsoluteSize.X * _invScale * 0.5
		local CenterY = Outer.AbsolutePosition.Y * _invScale + Outer.AbsoluteSize.Y * _invScale * 0.5
		if not self.MobilePlaced or ViewportChanged then
			CenterX = LeftInset + (Viewport.X - LeftInset - RightInset) * 0.5
			CenterY = UsableTop + math.max(AvailableHeight - Height, 0) * 0.5 + Height * 0.5
			self.MobilePlaced = true
		else
			CenterX = math.clamp(CenterX, LeftInset + Margin + Width * 0.5, math.max(LeftInset + Margin + Width * 0.5, Viewport.X - RightInset - Margin - Width * 0.5))
			CenterY = math.clamp(CenterY, UsableTop + Height * 0.5, math.max(UsableTop + Height * 0.5, UsableBottom - Height * 0.5))
		end
		Outer.AnchorPoint = Vector2.new(0.5, 0.5)
		Outer.Position = UDim2.fromOffset(CenterX, CenterY)
		Outer.Size = UDim2.fromOffset(Width, Height)
	end

	local Inner = Library:Create("Frame", {
		BackgroundColor3 = Library.MainColor,
		BorderColor3 = Library.OutlineColor,
		BorderMode = Enum.BorderMode.Inset,
		Position = UDim2.new(0, 1, 0, 1),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 1,
		Parent = Outer,
	})

	Library:AddToRegistry(Inner, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "OutlineColor",
	})
	local TopAccent = Library:Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Library.AccentColor,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 1),
		Size = UDim2.new(1, -2, 0, 2),
		ZIndex = 4,
		Parent = Inner,
	})
	Library:AddToRegistry(TopAccent, { BackgroundColor3 = "AccentColor" })
	local TopAccentGradient = Library:Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Library.AccentColorDark),
			ColorSequenceKeypoint.new(0.5, Library.AccentColor),
			ColorSequenceKeypoint.new(1, Library.AccentColorDark),
		}),
		Parent = TopAccent,
	})
	Library:AddToRegistry(TopAccentGradient, {
		Color = function()
			return ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library.AccentColorDark),
				ColorSequenceKeypoint.new(0.5, Library.AccentColor),
				ColorSequenceKeypoint.new(1, Library.AccentColorDark),
			})
		end,
	})

	local WindowLabel = Library:CreateLabel({
		Position = UDim2.new(0, 8, 0, 2),
		Size = UDim2.new(1, -16, 0, 27),
		Text = Config.Title or "",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = Inner,
	})

	local MainSectionOuter = Library:Create("Frame", {
		BackgroundColor3 = Library.BackgroundColor,
		BorderColor3 = Library.OutlineColor,
		Position = UDim2.new(0, 8, 0, 29),
		Size = UDim2.new(1, -16, 1, -37),
		ZIndex = 1,
		Parent = Inner,
	})

	Library:AddToRegistry(MainSectionOuter, {
		BackgroundColor3 = "BackgroundColor",
		BorderColor3 = "OutlineColor",
	})

	local MainSectionInner = Library:Create("Frame", {
		BackgroundColor3 = Library.BackgroundColor,
		BorderColor3 = Color3.new(0, 0, 0),
		BorderMode = Enum.BorderMode.Inset,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 1,
		Parent = MainSectionOuter,
	})

	Library:AddToRegistry(MainSectionInner, {
		BackgroundColor3 = "BackgroundColor",
	})

	local TabAreaProperties = {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 0, IsMobile and 42 or 24),
		ZIndex = 1,
		Parent = MainSectionInner,
	}
	if IsMobile then
		TabAreaProperties.CanvasSize = UDim2.fromOffset(0, 0)
		TabAreaProperties.ScrollingDirection = Enum.ScrollingDirection.X
		TabAreaProperties.ScrollBarThickness = 2
		TabAreaProperties.ScrollBarImageColor3 = Library.AccentColor
		TabAreaProperties.ElasticBehavior = Enum.ElasticBehavior.Always
		TabAreaProperties.ScrollingEnabled = true
	end
	local TabArea = Library:Create(IsMobile and "ScrollingFrame" or "Frame", TabAreaProperties)
	if IsMobile then Library:AddToRegistry(TabArea, { ScrollBarImageColor3 = "AccentColor" }) end

	local TabListLayout = Library:Create("UIListLayout", {
		Padding = UDim.new(0, Config.TabPadding),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = TabArea,
	})

	local TabContainer = Library:Create("Frame", {
		BackgroundColor3 = Library.MainColor,
		BorderColor3 = Library.OutlineColor,
		Position = UDim2.new(0, 8, 0, IsMobile and 50 or 33),
		Size = UDim2.new(1, -16, 1, -(IsMobile and 58 or 41)),
		ZIndex = 2,
		Parent = MainSectionInner,
	})

	Library:AddToRegistry(TabContainer, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "OutlineColor",
	})

	function Window:SetWindowTitle(Title)
		if Library.Unloaded or not WindowLabel.Parent then return false end
		if Library.Mounted and not Library:IsUiThread() then
			local Success, Result = Library:RunUi(function() return Window:SetWindowTitle(Title) end)
			if Success then return Result end
			Library.LastUiError = tostring(Result)
			return false
		end
		WindowLabel.Text = Title
		return true
	end

	function Window:ResizeTabs()
		local Count = #Window.TabOrder
		if Count == 0 then return end
		table.sort(Window.TabOrder, function(Left, Right)
			local LeftOrder = Left.TabButton and Left.TabButton.LayoutOrder or 0
			local RightOrder = Right.TabButton and Right.TabButton.LayoutOrder or 0
			if LeftOrder == RightOrder then return Left.InsertionOrder < Right.InsertionOrder end
			return LeftOrder < RightOrder
		end)
		local AvailableWidth = math.floor(TabArea.AbsoluteSize.X * _invScale + 0.5)
		if AvailableWidth <= 0 then
			local Offset = -((Config.TabPadding * math.max(Count - 1, 0)) / Count)
			for _, ExistingTab in Window.TabOrder do
				ExistingTab.TabButton.Size = UDim2.new(1 / Count, Offset, 1, 0)
			end
			return
		end
		local Padding = Config.TabPadding
		local TotalPadding = Padding * math.max(Count - 1, 0)
		if IsMobile then
			local MinimumWidths = {}
			local MinimumTotal = TotalPadding
			for Index, ExistingTab in Window.TabOrder do
				local TextWidth = select(1, Library:GetTextBounds(ExistingTab.Name, Library.Font, 14))
				local Minimum = math.max(68, TextWidth + 18)
				MinimumWidths[Index] = Minimum
				MinimumTotal += Minimum
			end
			local RemainingWidth = math.max(AvailableWidth - MinimumTotal, 0)
			local ExtraPerTab = math.floor(RemainingWidth / Count)
			local ExtraPixels = RemainingWidth - (ExtraPerTab * Count)
			local TotalWidth = TotalPadding
			for Index, ExistingTab in Window.TabOrder do
				local Width = MinimumWidths[Index]
				if MinimumTotal <= AvailableWidth then
					Width += ExtraPerTab + (Index <= ExtraPixels and 1 or 0)
				end
				ExistingTab.TabButton.Size = UDim2.fromOffset(Width, IsMobile and 42 or 24)
				TotalWidth += Width
			end
			if IsMobile and TabArea:IsA("ScrollingFrame") then
				TabArea.CanvasSize = UDim2.fromOffset(math.max(TotalWidth, AvailableWidth), 0)
			end
		else
			local PhysicalPadding = math.floor((Config.TabPadding * _uiScale) + 0.5)
			local TotalPhysicalPadding = PhysicalPadding * math.max(Count - 1, 0)
			local ContentWidth = math.max(math.floor(TabArea.AbsoluteSize.X + 0.5) - TotalPhysicalPadding, Count)
			local BaseWidth = math.floor(ContentWidth / Count)
			local ExtraPixels = math.floor(ContentWidth - (BaseWidth * Count) + 0.5)
			for Index, ExistingTab in Window.TabOrder do
				local Width = (BaseWidth + (Index <= ExtraPixels and 1 or 0)) * _invScale
				ExistingTab.TabButton.Size = UDim2.new(0, Width, 1, 0)
			end
		end
	end
	Connect(TabArea:GetPropertyChangedSignal("AbsoluteSize"), function() Window:ResizeTabs() end)

	function Window:AddTab(Name)
		local Tab = {
			Groupboxes = {},
			Tabboxes = {},
			Selected = false,
			Name = Name,
		}

		local TabButton = Library:Create("Frame", {
			BackgroundColor3 = Library.BackgroundColor,
			BorderColor3 = Library.OutlineColor,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = TabArea,
		})

		Library:AddToRegistry(TabButton, {
			BackgroundColor3 = "BackgroundColor",
			BorderColor3 = "OutlineColor",
		})

		local TabButtonLabel = Library:CreateLabel({
			Position = UDim2.new(0, 0, 0, ControlTextOffset),
			Size = UDim2.new(1, 0, 1, -1),
			Text = Name,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 1,
			Parent = TabButton,
		})
		local Blocker = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, IsMobile and -1 or 0),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = TabButton,
		})

		Library:AddToRegistry(Blocker, {
			BackgroundColor3 = "MainColor",
		})

		local TabFrame = Library:Create("Frame", {
			Name = "TabFrame",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, 0),
			Visible = false,
			ZIndex = 2,
			Parent = TabContainer,
		})

		local LeftSide = Library:Create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8 - 1, 0, 8 - 1),
			Size = UDim2.new(0.5, -11, 1, -14),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			BottomImage = IsMobile and "rbxasset://textures/ui/Scroll/scroll-middle.png" or "",
			TopImage = IsMobile and "rbxasset://textures/ui/Scroll/scroll-middle.png" or "",
			ScrollBarThickness = IsMobile and 3 or 0,
			ScrollBarImageColor3 = Library.AccentColor,
			ElasticBehavior = Enum.ElasticBehavior.Always,
			ScrollingEnabled = true,
			ZIndex = 2,
			Parent = TabFrame,
		})

		local RightSide = Library:Create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 4, 0, 8 - 1),
			Size = UDim2.new(0.5, -11, 1, -14),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			BottomImage = IsMobile and "rbxasset://textures/ui/Scroll/scroll-middle.png" or "",
			TopImage = IsMobile and "rbxasset://textures/ui/Scroll/scroll-middle.png" or "",
			ScrollBarThickness = IsMobile and 3 or 0,
			ScrollBarImageColor3 = Library.AccentColor,
			ElasticBehavior = Enum.ElasticBehavior.Always,
			ScrollingEnabled = true,
			ZIndex = 2,
			Parent = TabFrame,
		})
		if IsMobile then
			RightSide.Visible = false
			LeftSide.Position = UDim2.new(0, 8 - 1, 0, 8 - 1)
			LeftSide.Size = UDim2.new(1, -16, 1, -14)
		end
		Library:AddToRegistry(LeftSide, { ScrollBarImageColor3 = "AccentColor" })
		Library:AddToRegistry(RightSide, { ScrollBarImageColor3 = "AccentColor" })

		Library:Create("UIListLayout", {
			Padding = UDim.new(0, 8),
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = LeftSide,
		})

		Library:Create("UIListLayout", {
			Padding = UDim.new(0, 8),
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = RightSide,
		})

		for _, Side in next, { LeftSide, RightSide } do
			Connect(Side:WaitForChild("UIListLayout"):GetPropertyChangedSignal("AbsoluteContentSize"), function()
				Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y)
			end)
		end

		function Tab:ShowTab()
			for _, Tab in next, Window.Tabs do
				Tab:HideTab()
			end

			Blocker.BackgroundTransparency = 0
			Tab.Selected = true
			TabButton.BackgroundColor3 = Library.MainColor
			Library.RegistryMap[TabButton].Properties.BackgroundColor3 = "MainColor"
			TabButton.BorderColor3 = Library.AccentColor
			Library.RegistryMap[TabButton].Properties.BorderColor3 = "AccentColor"
			TabButtonLabel.TextColor3 = Library.AccentColor
			Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = "AccentColor"
			TabFrame.Visible = true
		end

		function Tab:HideTab()
			Blocker.BackgroundTransparency = 1
			Tab.Selected = false
			TabButton.BackgroundColor3 = Library.BackgroundColor
			Library.RegistryMap[TabButton].Properties.BackgroundColor3 = "BackgroundColor"
			TabButton.BorderColor3 = Library.OutlineColor
			Library.RegistryMap[TabButton].Properties.BorderColor3 = "OutlineColor"
			TabButtonLabel.TextColor3 = Library.FontColor
			Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = "FontColor"
			TabFrame.Visible = false
		end

		function Tab:SetLayoutOrder(Position)
			TabButton.LayoutOrder = Position
			TabListLayout:ApplyLayout()
			Window:ResizeTabs()
		end

		function Tab:AddGroupbox(Info)
			local Groupbox = {}
			local ParentSide = if IsMobile then LeftSide elseif Info.Side == 1 then LeftSide else RightSide

			local BoxOuter = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 0, 507 + 2),
				ZIndex = 2,
				Parent = ParentSide,
			})

			Library:AddToRegistry(BoxOuter, {
				BackgroundColor3 = "BackgroundColor",
				BorderColor3 = "OutlineColor",
			})

			local BoxInner = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Color3.new(0, 0, 0),
				-- BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, -2, 1, -2),
				Position = UDim2.new(0, 1, 0, 1),
				ZIndex = 4,
				Parent = BoxOuter,
			})

			Library:AddToRegistry(BoxInner, {
				BackgroundColor3 = "BackgroundColor",
			})

			local Highlight = Library:Create("Frame", {
				BackgroundColor3 = Library.AccentColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 5,
				Parent = BoxInner,
			})

			Library:AddToRegistry(Highlight, {
				BackgroundColor3 = "AccentColor",
			})

			local GroupboxLabel = Library:CreateLabel({
				Size = UDim2.new(1, -16, 0, 18),
				Position = UDim2.new(0, 8, 0, 3),
				TextSize = 13,
				Text = Info.Name,
				TextColor3 = Library.AccentColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 5,
				Parent = BoxInner,
			})
			Library:AddToRegistry(GroupboxLabel, { TextColor3 = "AccentColor" })

			local Container = Library:Create("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 6, 0, 22),
				Size = UDim2.new(1, -12, 1, -22),
				ZIndex = 1,
				Parent = BoxInner,
			})

			local ContainerLayout = Library:Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = Container,
			})

			function Groupbox:Resize()
				BoxOuter.Size = UDim2.new(1, 0, 0, 24 + ContainerLayout.AbsoluteContentSize.Y)
			end
			Connect(ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function() Groupbox:Resize() end)

			Groupbox.Container = Container
			setmetatable(Groupbox, BaseGroupbox)

			Groupbox:AddBlank(3)
			Groupbox:Resize()

			Tab.Groupboxes[Info.Name] = Groupbox

			return Groupbox
		end

		function Tab:AddLeftGroupbox(Name)
			return Tab:AddGroupbox({ Side = 1, Name = Name })
		end

		function Tab:AddRightGroupbox(Name)
			return Tab:AddGroupbox({ Side = 2, Name = Name })
		end

		function Tab:AddTabbox(Info)
			local Tabbox = {
				Tabs = {},
				TabOrder = {},
			}

			local ParentSide = if IsMobile then LeftSide elseif Info.Side == 1 then LeftSide else RightSide
			local BoxOuter = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 0, 0),
				ZIndex = 2,
				Parent = ParentSide,
			})

			Library:AddToRegistry(BoxOuter, {
				BackgroundColor3 = "BackgroundColor",
				BorderColor3 = "OutlineColor",
			})

			local BoxInner = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Color3.new(0, 0, 0),
				-- BorderMode = Enum.BorderMode.Inset;
				Size = UDim2.new(1, -2, 1, -2),
				Position = UDim2.new(0, 1, 0, 1),
				ZIndex = 4,
				Parent = BoxOuter,
			})

			Library:AddToRegistry(BoxInner, {
				BackgroundColor3 = "BackgroundColor",
			})

			local Highlight = Library:Create("Frame", {
				BackgroundColor3 = Library.AccentColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 10,
				Parent = BoxInner,
			})

			Library:AddToRegistry(Highlight, {
				BackgroundColor3 = "AccentColor",
			})

			local TabboxButtonProperties = {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 0, 0, 1),
				Size = UDim2.new(1, 0, 0, IsMobile and 40 or 18),
				ZIndex = 5,
				Parent = BoxInner,
			}
			if IsMobile then
				TabboxButtonProperties.CanvasSize = UDim2.fromOffset(0, 0)
				TabboxButtonProperties.ScrollingDirection = Enum.ScrollingDirection.X
				TabboxButtonProperties.ScrollBarThickness = 2
				TabboxButtonProperties.ScrollBarImageColor3 = Library.AccentColor
				TabboxButtonProperties.ElasticBehavior = Enum.ElasticBehavior.Always
				TabboxButtonProperties.ScrollingEnabled = true
			end
			local TabboxButtons = Library:Create(IsMobile and "ScrollingFrame" or "Frame", TabboxButtonProperties)
			if IsMobile then Library:AddToRegistry(TabboxButtons, { ScrollBarImageColor3 = "AccentColor" }) end

			Library:Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = TabboxButtons,
			})

			function Tabbox:ResizeButtons()
				local Count = #Tabbox.TabOrder
				if Count == 0 then return end
				local AvailableWidth = math.floor(TabboxButtons.AbsoluteSize.X * _invScale + 0.5)
				if AvailableWidth <= 0 then
					for _, ExistingTab in Tabbox.TabOrder do
						ExistingTab.Button.Size = UDim2.new(1 / Count, 0, 1, 0)
					end
					return
				end
				local TotalWidth = 0
				if IsMobile then
					local MinimumWidths = {}
					local MinimumTotal = 0
					for Index, ExistingTab in Tabbox.TabOrder do
						local TextWidth = select(1, Library:GetTextBounds(ExistingTab.Name, Library.Font, 13))
						local Width = math.max(64, TextWidth + 16)
						MinimumWidths[Index] = Width
						MinimumTotal += Width
					end
					local RemainingWidth = math.max(AvailableWidth - MinimumTotal, 0)
					local ExtraPerTab = math.floor(RemainingWidth / Count)
					local ExtraPixels = RemainingWidth - (ExtraPerTab * Count)
					TotalWidth = 0
					for Index, ExistingTab in Tabbox.TabOrder do
						local Width = MinimumWidths[Index]
						if MinimumTotal <= AvailableWidth then
							Width += ExtraPerTab + (Index <= ExtraPixels and 1 or 0)
						end
						ExistingTab.Button.Size = UDim2.fromOffset(Width, IsMobile and 40 or 18)
						TotalWidth += Width
					end
					if TabboxButtons:IsA("ScrollingFrame") then
						TabboxButtons.CanvasSize = UDim2.fromOffset(math.max(TotalWidth, AvailableWidth), 0)
					end
				else
					local PhysicalWidth = math.floor(TabboxButtons.AbsoluteSize.X + 0.5)
					local BaseWidth = math.floor(PhysicalWidth / Count)
					local ExtraPixels = PhysicalWidth - (BaseWidth * Count)
					for Index, ExistingTab in Tabbox.TabOrder do
						local Width = (BaseWidth + (Index <= ExtraPixels and 1 or 0)) * _invScale
						ExistingTab.Button.Size = UDim2.new(0, Width, 1, 0)
					end
				end
			end
			Connect(TabboxButtons:GetPropertyChangedSignal("AbsoluteSize"), function() Tabbox:ResizeButtons() end)

			function Tabbox:AddTab(Name)
				local Tab = { Selected = false, Name = Name }

				local Button = Library:Create("Frame", {
					BackgroundColor3 = Library.BackgroundColor,
					BorderColor3 = Library.OutlineColor,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 6,
					Parent = TabboxButtons,
				})

				Library:AddToRegistry(Button, {
					BackgroundColor3 = "BackgroundColor",
					BorderColor3 = "OutlineColor",
				})

				local ButtonLabel = Library:CreateLabel({
					Position = UDim2.new(0, 0, 0, ControlTextOffset),
					Size = UDim2.new(1, 0, 1, 0),
					TextSize = 14,
					Text = Name,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 7,
					Parent = Button,
				})
				local Block = Library:Create("Frame", {
					BackgroundColor3 = Library.BackgroundColor,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 0, 1, IsMobile and -1 or 0),
					Size = UDim2.new(1, 0, 0, 1),
					Visible = false,
					ZIndex = 9,
					Parent = Button,
				})

				Library:AddToRegistry(Block, {
					BackgroundColor3 = "BackgroundColor",
				})

				local Container = Library:Create("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 6, 0, IsMobile and 41 or 22),
					Size = UDim2.new(1, -12, 1, -(IsMobile and 41 or 22)),
					Visible = false,
					ZIndex = 1,
					Parent = BoxInner,
				})

				local ContainerLayout = Library:Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = Container,
				})

				function Tab:Show()
					for _, Tab in next, Tabbox.Tabs do
						Tab:Hide()
					end

					Container.Visible = true
					Block.Visible = true
					Tab.Selected = true

					Button.BackgroundColor3 = Library.BackgroundColor
					Library.RegistryMap[Button].Properties.BackgroundColor3 = "BackgroundColor"
					Button.BorderColor3 = Library.AccentColor
					Library.RegistryMap[Button].Properties.BorderColor3 = "AccentColor"
					ButtonLabel.TextColor3 = Library.AccentColor
					Library.RegistryMap[ButtonLabel].Properties.TextColor3 = "AccentColor"
					Tab:Resize()
				end

				function Tab:Hide()
					Container.Visible = false
					Block.Visible = false
					Tab.Selected = false

					Button.BackgroundColor3 = Library.BackgroundColor
					Library.RegistryMap[Button].Properties.BackgroundColor3 = "BackgroundColor"
					Button.BorderColor3 = Library.OutlineColor
					Library.RegistryMap[Button].Properties.BorderColor3 = "OutlineColor"
					ButtonLabel.TextColor3 = Library.FontColor
					Library.RegistryMap[ButtonLabel].Properties.TextColor3 = "FontColor"
				end

				function Tab:Resize()
					Tabbox:ResizeButtons()

					if not Container.Visible then
						return
					end

					BoxOuter.Size = UDim2.new(1, 0, 0, (IsMobile and 43 or 24) + ContainerLayout.AbsoluteContentSize.Y)
				end
				Connect(ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function() Tab:Resize() end)

				Library:ConnectClick(Button, function()
					Tab:Show()
					Tab:Resize()
				end)
				Connect(Button.MouseEnter, function()
					if not Tab.Selected then Button.BorderColor3 = Library.AccentColor end
				end)
				Connect(Button.MouseLeave, function()
					if not Tab.Selected then Button.BorderColor3 = Library.OutlineColor end
				end)

				Tab.Container = Container
				Tab.Button = Button
				Tab.InsertionOrder = #Tabbox.TabOrder + 1
				table.insert(Tabbox.TabOrder, Tab)
				Tabbox.Tabs[Name] = Tab

				setmetatable(Tab, BaseGroupbox)

				Tab:AddBlank(3)
				Tab:Resize()

				-- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
				if #TabboxButtons:GetChildren() == 2 then
					Tab:Show()
				end

				return Tab
			end

			Tab.Tabboxes[Info.Name or ""] = Tabbox

			return Tabbox
		end

		function Tab:AddLeftTabbox(Name)
			return Tab:AddTabbox({ Name = Name, Side = 1 })
		end

		function Tab:AddRightTabbox(Name)
			return Tab:AddTabbox({ Name = Name, Side = 2 })
		end

		Library:ConnectClick(TabButton, function()
			Tab:ShowTab()
		end)
		Connect(TabButton.MouseEnter, function()
			if not Tab.Selected then TabButton.BorderColor3 = Library.AccentColor end
		end)
		Connect(TabButton.MouseLeave, function()
			if not Tab.Selected then TabButton.BorderColor3 = Library.OutlineColor end
		end)

		-- This was the first tab added, so we show it by default.
		if #TabContainer:GetChildren() == 1 then
			Tab:ShowTab()
		end

		Tab.TabButton = TabButton
		Tab.InsertionOrder = #Window.TabOrder + 1
		table.insert(Window.TabOrder, Tab)
		Window.Tabs[Name] = Tab
		Window:ResizeTabs()
		return Tab
	end

	local ModalElement = Library:Create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 0),
		Visible = true,
		Text = "",
		Modal = false,
		Parent = ScreenGui,
	})

	local Toggled = false
	local Fading = false

	function Window:Toggle()
		if Library.Unloaded or not Outer.Parent then return false end
		if Library.Mounted and not Library:IsUiThread() then
			local Success, Result = Library:RunUi(function() return Window:Toggle() end)
			if Success then return Result end
			Library.LastUiError = tostring(Result)
			return false
		end
		if Fading then
			return false
		end

		local FadeTime = Config.MenuFadeTime
		Fading = true
		Toggled = not Toggled
		ModalElement.Modal = Toggled

		if Toggled then
			-- A bit scuffed, but if we're going from not toggled -> toggled we want to show the frame immediately so that the fade is visible.
			Outer.Visible = true
		else
			Library:ClosePopupsFor(Outer)
		end

		TweenService:Create(
			Outer,
			TweenInfo.new(FadeTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ GroupTransparency = Toggled and 0 or 1 }
		):Play()

		local ExpectedVisibility = Toggled
		Library:DelayUi(FadeTime, function()
			if Outer.Parent then Outer.Visible = ExpectedVisibility end
			Fading = false
		end)
		return true
	end

	if not Library.ToggleSignalRegistered then
		Library.ToggleSignalRegistered = true
		Library:GiveSignal(Connect(InputService.InputBegan, function(Input, Processed)
			if Processed then return end
			if type(Library.ToggleKeybind) == "table" and Library.ToggleKeybind.Type == "KeyPicker" then
				if
					Input.UserInputType == Enum.UserInputType.Keyboard
					and Input.KeyCode.Name == Library.ToggleKeybind.Value
				then
					Library:Toggle()
				end
			elseif Input.KeyCode == Enum.KeyCode.RightControl or Input.KeyCode == Enum.KeyCode.RightShift then
				Library:Toggle()
			end
		end))
	end

	if Config.AutoShow then
		Library:DelayUi(0, function() Window:Toggle() end)
	end

	-- Mobile sidebar (Toggle UI / Lock UI) - combined into one frame
	if IsMobile and not Library.MobileControllerCreated then
		Library.MobileControllerCreated = true
		-- Container frame for both buttons (stacked vertically)
		local MobileContainerOuter = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 1);
			BorderColor3 = Color3.new(0, 0, 0);
			Position = UDim2.new(0.5, 0, 1, -8);
			Size = UDim2.new(0, 144, 0, 48);
			ZIndex = 200;
			Visible = true;
			Parent = ScreenGui;
		})
		Library.MobileController = MobileContainerOuter
		Library.MobileControllerPlaced = true

		local MobileContainerInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderColor3 = Library.OutlineColor;
			BorderMode = Enum.BorderMode.Inset;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 201;
			Parent = MobileContainerOuter;
		})

		Library:AddToRegistry(MobileContainerInner, {
			BorderColor3 = 'OutlineColor';
		})

		local MobileContainerGradientFrame = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(1, 1, 1);
			BorderSizePixel = 0;
			Position = UDim2.new(0, 1, 0, 1);
			Size = UDim2.new(1, -2, 1, -2);
			ZIndex = 202;
			Parent = MobileContainerInner;
		})

		local MobileContainerGradient = Library:Create('UIGradient', {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
				ColorSequenceKeypoint.new(1, Library.MainColor),
			});
			Rotation = -90;
			Parent = MobileContainerGradientFrame;
		})

		Library:AddToRegistry(MobileContainerGradient, {
			Color = function()
				return ColorSequence.new({
					ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
					ColorSequenceKeypoint.new(1, Library.MainColor),
				})
			end
		})

		-- Keep the controls compact and horizontal so they do not cover tab content.
		local ToggleUIButton = Library:Create('TextButton', {
			Position = UDim2.new(0, 2, 0, 2);
			Size = UDim2.new(0.5, -3, 1, -4);
			BackgroundTransparency = 1;
			Font = Library.Font;
			Text = "Toggle UI";
			TextColor3 = Library.FontColor;
			TextSize = 14;
			TextStrokeTransparency = 1;
			ZIndex = 203;
			Parent = MobileContainerGradientFrame;
		})

		-- Divider line between buttons
		Library:Create('Frame', {
			BackgroundColor3 = Library.OutlineColor;
			BorderSizePixel = 0;
			Position = UDim2.new(0.5, -1, 0, 3);
			Size = UDim2.new(0, 1, 1, -6);
			ZIndex = 203;
			Parent = MobileContainerGradientFrame;
		})

		-- Lock UI button (bottom half)
		local LockUIButton = Library:Create('TextButton', {
			Position = UDim2.new(0.5, 1, 0, 2);
			Size = UDim2.new(0.5, -3, 1, -4);
			BackgroundTransparency = 1;
			Font = Library.Font;
			Text = "Lock UI";
			TextColor3 = Library.FontColor;
			TextSize = 14;
			TextStrokeTransparency = 1;
			ZIndex = 203;
			Parent = MobileContainerGradientFrame;
		})

		Library:MakeDraggable(MobileContainerOuter)
		Library:RegisterCursorRegion(MobileContainerOuter)

		-- Initialize CantDragForced state
		Library.CantDragForced = false

		Connect(ToggleUIButton.Activated, function()
			Window:Toggle()
		end)

		Connect(LockUIButton.Activated, function()
			Library.CantDragForced = not Library.CantDragForced

			-- Update button text to show state
			LockUIButton.Text = Library.CantDragForced and "Unlock UI" or "Lock UI"

			-- Toggle dragging for the sidebar itself
			MobileContainerOuter.Active = not Library.CantDragForced
		end)
	end

	-------

	Window.Holder = Outer

	-- Register window in Library.Windows for mobile toggle UI
	table.insert(Library.Windows, Window)
	Window:FitToViewport()
	Window:ResizeTabs()
	if IsMobile then Library:RequestViewportLayout() end

	return Window
end

local function OnPlayerChange()
	local PlayerList = GetPlayersString()

	for _, Value in next, Options do
		if Value.Type == "Dropdown" and Value.SpecialType == "Player" then
			Value:SetValues(PlayerList)
		end
	end
end

Library:GiveSignal(Connect(Players.PlayerAdded, OnPlayerChange))
Library:GiveSignal(Connect(Players.PlayerRemoving, OnPlayerChange))

getgenv().Library = Library
return Library
