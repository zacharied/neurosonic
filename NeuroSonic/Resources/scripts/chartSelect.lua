
include "layerLayout";
include "util.textures";

local textInput = include "util.textInput";

local bgName = "bgHighContrast";

local timer;

--------------------------------------------------
-- Layer Data ------------------------------------
--------------------------------------------------
-- Can be 0 for the default state, 1 thru 4 for each of the BT sub menus,
--  5 or 6 for the FX sub menus, and 7 for the double-tapped-FX sub menu.
-- Some of the states likely will never be used.
-- Some string values are also accepted for more specific cases like
--  "text" for searching with text input.
local currentState = 0;

local stateData = { };
--------------------------------------------------


--------------------------------------------------
-- Chart Data ------------------------------------
--------------------------------------------------
-- the collective of charts the player can select from
-- Whenever the player selects new filters etc., this is what's updated;
--  a full refresh of the render data (and a resync of the camera position)
--  is needed when this is updated.
local charts;
local chartsCache;

-- which grouping the cursor is currently within
local groupIndex = 1;
-- which set the cursor is on within the group
local cellIndex = 1;
-- which category slot (each of the 5 difficulties) is currently selected
local slotIndex = 1;
-- which chart in a slot, if there are multiple, is selected
local slotChildIndex = 1;

local autoPlay = AutoPlayTargets.None;
--------------------------------------------------


--------------------------------------------------
-- Display Data ----------------------------------
--------------------------------------------------
-- the number of columns to display in the grid
local gridColumnCount = 3;
-- the amount of stepping to apply to each grid row
-- Stepping, here, refers to the percentage of the height to step over
--  the entire row, so 1 row will have each cell vertically offset an
--  increasing amount up to the given percentage.
-- This is not this much per column, but a total for every column.
local gridRowStepping = 0.5;

-- the percentage of the size of a cell that is taken up by the group header
local gridGroupHeaderSize = 0.25;

-- where the camera is along the y axis
local gridCameraPos = 0;
local gridCameraPosTarget = 0;

local infoBounceTimer = 0;
local selectedSongTitleScrollTimer = 0;

local fontSlant;
--------------------------------------------------


--------------------------------------------------
-- Textures --------------------------------------
--------------------------------------------------
local textures =
{
	noise = { },
	numbers = { },
	legend = { },
	badges = { },
	chartFrame = { },
	infoPanel =
	{
		landscape = { },
		portrait = { },
	},
};

local currentNoiseTexture;
--------------------------------------------------


--------------------------------------------------
-- Audio -----------------------------------------
--------------------------------------------------
local audio =
{
	clicks = { },
};
--------------------------------------------------


--------------------------------------------------
-- Database Filters ------------------------------
--------------------------------------------------
local currentChartCollectionName, searchText = nil, nil;
local filterName, groupName, sortName = "*", "level", "title";

local function verifySearch(chart)
	if (searchText and #searchText > 0) then
		return string.find(string.lower(chart.songTitle), string.lower(searchText)) or
				string.find(string.lower(chart.songArtist), string.lower(searchText)) or
				string.find(string.lower(chart.songFileName), string.lower(searchText)) or
				string.find(string.lower(chart.charter), string.lower(searchText));
	end
	return true;
end

local function checkTopDir(s, m)
	if (string.sub(s, 1, #m) ~= m) then
		return false;
	end

	if (#s > #m) then
		local sep = string.sub(s, #m + 1, #m + 1);
		return sep == '/' or sep == '\\';
	end

	return true;
end

local chartListFilters =
{
	["*"] = function(chart) return verifySearch(chart); end,
};

for _, v in next, theori.charts.getFolderNames() do
	chartListFilters[v] = function(chart) return checkTopDir(chart.set.filePath, v) and verifySearch(chart); end;
end

for i = 1, 20 do
	chartListFilters[i] = function(chart) return chart.difficultyLevel == i and verifySearch(chart); end;
end

local chartListGroupings =
{
	level = function(chart) return chart.difficultyLevel; end,
};

local chartListSortings =
{
	title = function(chart) return chart.songTitle; end,
};

local cachedFilteredCharts = { };
--------------------------------------------------


--------------------------------------------------
-- Chart Grid Functions --------------------------
--------------------------------------------------
local function getSizeOfGroup(chartGroupIndex)
	if (#charts == 0) then return 0; end

	local chartGroup = charts[chartGroupIndex];

	local rowCount = math.floor((#chartGroup - 1) / gridColumnCount) + 1;
	local steppedColsAtEnd = (#chartGroup - 1) % gridColumnCount;

	return rowCount + gridGroupHeaderSize +
		(steppedColsAtEnd * gridRowStepping / (gridColumnCount - 1));
end

local function getGridCellPosition(gi, si)
	local result = 0;
	
	local colIndex = (si - 1) % gridColumnCount;
	local rowIndex = math.floor((si - 1) / gridColumnCount);

	result = result + rowIndex + 0.5 + gridGroupHeaderSize +
		(colIndex * gridRowStepping / (gridColumnCount - 1));
	for i = 1, gi - 1 do
		result = result + getSizeOfGroup(i);
	end
	return 0.5 + colIndex, result;
end

local function getGridCameraPosition()
	local x, y = getGridCellPosition(groupIndex, cellIndex);
	return y;
end

local function lerpAnimTo(from, to, delta, speed)
	local absDif = math.abs(from - to);
    if (absDif > 10 or absDif < 0.01) then
        return to;
    else
        speed = speed or 20;
        return from + (to - from) * speed * delta;
    end
end

local function getSetChartRefs(setId)
	local cached = chartsCache[setId];
	if (not cached) then
		chartsCache[setId] = { };
		cached = chartsCache[setId];
	end

	if (cached.relatedSets) then
		return cached.relatedSets;
	end

	local related = { };
	for gi, group in next, charts do
		for ci, chart in next, group do
			if (chart.setID == setId) then
				table.insert(related, { groupIndex = gi, cellIndex = ci, chart = chart });
			end
		end
	end

	cached.relatedSets = related;
	return related;
end

local function ref(chart)
	local setChartRefs = getSetChartRefs(chart.setID);
	for _, c in next, setChartRefs do
		if (c.chart.ID == chart.ID) then
			return c;
		end
	end
	-- ono bad
end

local function getScores(chart)
	local setId = chart.set.ID;

	local cachedSet = chartsCache[setId];
	if (not cachedSet) then
		chartsCache[setId] = { };
		cachedSet = chartsCache[setId];
	end

	local cached = cachedSet[chart.ID];
	if (not cached) then
		cachedSet[chart.ID] = { };
		cached = cachedSet[chart.ID];
	end

	if (not cached.scores) then
		cached.scores = theori.charts.getScores(chart);
	end

	return cached.scores;
end

local function getSetSlots(set)
	local cached = chartsCache[set.ID];
	if (not cached) then
		chartsCache[set.ID] = { };
		cached = chartsCache[set.ID];
	end

	if (cached.slots) then
		return cached.slots;
	end

	local slots = { };
	for i = 1, 5 do slots[i] = { }; end;

	for _, chart in next, set.charts do
		table.insert(slots[chart.difficultyIndex], ref(chart));
	end

	cached.slots = slots;
	return slots;
end

local function nearestSlotIndex(setSlots, slotIndex)
	local slot = slotIndex;

	while (#setSlots[slot] == 0) do
		if (slot == 1) then break; end
		slot = slot - 1;
	end
	while (#setSlots[slot] == 0) do
		if (slot == 5) then break; end -- OH NO
		slot = slot + 1;
	end

	return slot;
end

local function nearestSlot(setSlots, slotIndex)
	return setSlots[nearestSlotIndex(setSlots, slotIndex)];
end

local function nearestSlotChildIndex(slot, slotChildIndex)
	return math.min(#slot, slotChildIndex);
end

local function nearestSlotChild(slot, slotChildIndex)
	return slot[nearestSlotChildIndex(slot, slotChildIndex)];
end
--------------------------------------------------


--------------------------------------------------
-- Chart Filter Utility --------------------------
--------------------------------------------------
local function getFilteredChartsForConfiguration(filter, grouping, sorting)
	local collectionId = currentChartCollectionName or "";
	local cacheKey = (collectionId or "") .. '|' .. (searchText or "") .. '|' .. filter .. '|' .. grouping .. '|' .. sorting;

	print("Asking for charts with key \"" .. cacheKey .. "\"");
	if (cachedFilteredCharts[cacheKey]) then
		print("  Found");
		local cache = cachedFilteredCharts[cacheKey];
		return cache.charts, cache.chartsCache;
	end
	
	print("  Not Found");

	local charts = theori.charts.getChartSetsFiltered(currentChartCollectionName, chartListFilters[filter], chartListGroupings[grouping], chartListSortings[sorting]);
	local chartsCache = { };

	cachedFilteredCharts[cacheKey] =
	{
		charts = charts,
		chartsCache = chartsCache,
	};
	return charts, chartsCache;
end

local function jumpToChartIfExists(setId, chartId)
	if (#charts == 0) then return false; end

	local chartRefs = getSetChartRefs(setId);
	if (not chartRefs or #chartRefs == 0) then return false; end
	
	for _, cref in next, chartRefs do
		if (cref.chart.ID == chartId) then
			groupIndex = cref.groupIndex;
			cellIndex = cref.cellIndex;

			slotIndex = 1;
			slotChildIndex = 1;

			local slots = getSetSlots(cref.chart.set);
			for i, diffs in next, slots do
				for j, cref in next, diffs do
					if (cref.chart.ID == chartId) then
						slotIndex = i;
						slotChildIndex = j;
					end
				end
			end

			gridCameraPosTarget = getGridCameraPosition();

			return true;
		end
	end

	return false;
end

local lastChart;
local function updateChartConfiguration()
	if (charts and #charts > 0) then
		lastChart = charts[groupIndex][cellIndex];
	end

	local checkSetId, checkChartId;
	if (lastChart) then
		checkSetId = lastChart.setID;
		checkChartId = lastChart.ID;
	else
		checkSetId = theori.config.get("lastSetId") or -1;
		checkChartId = theori.config.get("lastChartId") or -1;
	end
	
	theori.config.set("lastSetId", checkSetId);
	theori.config.set("lastChartId", checkChartId);

	theori.config.save();

	charts, chartsCache = getFilteredChartsForConfiguration(filterName, groupName, sortName);
	if (not jumpToChartIfExists(checkSetId, checkChartId)) then
		groupIndex = 1;
		cellIndex = 1;

		gridCameraPosTarget = getGridCameraPosition();
	end
end

local function createFolderFilterFunctions()
	--
end
--------------------------------------------------


--------------------------------------------------
-- Sub Menu State Functions ----------------------
--------------------------------------------------
local function setState(nextState)
	textInput.stop();
	currentState = nextState;
end

local function setTextInput()
	if (currentState == "text" or textInput.isActive()) then return; end

	setState("text");
	textInput.start(searchText);
end
--------------------------------------------------


--------------------------------------------------
-- Delegate Functions ----------------------------
--------------------------------------------------
local function onKeyPressed(key)
	if (stateData[currentState].keyPressed) then
		stateData[currentState]:keyPressed(key);
	end
end

local function onAxisTicked(controller, axis, dir)
	if (stateData[currentState].axisTicked) then
		stateData[currentState]:axisTicked(controller, axis, dir);
	end
end

local function onButtonPressed(controller, button)
	if (stateData[currentState].buttonPressed) then
		stateData[currentState]:buttonPressed(controller, button);
	end
end

local function onButtonReleased(controller, button)
	if (stateData[currentState].buttonReleased) then
		stateData[currentState]:buttonReleased(controller, button);
	end
end
--------------------------------------------------


--------------------------------------------------
-- Theori Layer Functions ------------------------
--------------------------------------------------
function theori.layer.construct()
end

function theori.layer.doAsyncLoad()
	updateChartConfiguration();

	-- TODO(local): save the selected chart/slot and gather the indices afterward
	-- TODO(local): make sure there's slots in the selected set
	
	for i = 0, 9 do
		textures.numbers[i] = theori.graphics.queueTextureLoad("spritenums/slant/" .. i);
	end
	for i = 0, 9 do
		textures.noise[i] = theori.graphics.queueTextureLoad("noise/" .. i);
	end

	--[[
    textures.legend.a = theori.graphics.getStaticTexture("legend/bt/a");
    textures.legend.b = theori.graphics.getStaticTexture("legend/bt/b");
    textures.legend.c = theori.graphics.getStaticTexture("legend/bt/c");
    textures.legend.d = theori.graphics.getStaticTexture("legend/bt/d");
    textures.legend.l = theori.graphics.getStaticTexture("legend/fx/l");
    textures.legend.r = theori.graphics.getStaticTexture("legend/fx/r");
    textures.legend.lr = theori.graphics.getStaticTexture("legend/fx/lr");
    textures.legend.start = theori.graphics.getStaticTexture("legend/start");
    
	textures.badges.Perfect = theori.graphics.getStaticTexture("badges/Perfect");
	textures.badges.S = theori.graphics.getStaticTexture("badges/S");
	textures.badges.AAAX = theori.graphics.getStaticTexture("badges/AAAX");
	textures.badges.AAA = theori.graphics.getStaticTexture("badges/AAA");
	textures.badges.AAX = theori.graphics.getStaticTexture("badges/AAX");
	textures.badges.AA = theori.graphics.getStaticTexture("badges/AA");
	textures.badges.AX = theori.graphics.getStaticTexture("badges/AX");
	textures.badges.A = theori.graphics.getStaticTexture("badges/A");
	textures.badges.B = theori.graphics.getStaticTexture("badges/B");
	textures.badges.C = theori.graphics.getStaticTexture("badges/C");
	textures.badges.F = theori.graphics.getStaticTexture("badges/F");
	--]]

    textures.cursor = theori.graphics.queueTextureLoad("chartSelect/cursor");
    textures.cursorOuter = theori.graphics.queueTextureLoad("chartSelect/cursorOuter");
    textures.levelBadge = theori.graphics.queueTextureLoad("chartSelect/levelBadge");
    textures.levelBadgeBorder = theori.graphics.queueTextureLoad("chartSelect/levelBadgeBorder");
    textures.levelBar = theori.graphics.queueTextureLoad("chartSelect/levelBar");
    textures.levelBarBorder = theori.graphics.queueTextureLoad("chartSelect/levelBarBorder");
    textures.levelText = theori.graphics.queueTextureLoad("chartSelect/levelText");

	local frameTextures = { "background", "border", "fill", "storageDevice", "trackDataLabel" };
	for _, texName in next, frameTextures do
		textures.chartFrame[texName] = theori.graphics.queueTextureLoad("chartSelect/chartFrame/" .. texName);
	end
	
	local infoPanelPortrait = { "border", "fill", "jacketBorder" };
	for _, texName in next, infoPanelPortrait do
		textures.infoPanel.portrait[texName] = theori.graphics.queueTextureLoad("chartSelect/infoPanel/portrait/" .. texName);
	end

    textures.noJacket = theori.graphics.queueTextureLoad("chartSelect/noJacket");
    textures.noJacketOverlay = theori.graphics.queueTextureLoad("chartSelect/noJacketOverlay");

    textures.infoPanel.landscape.background = theori.graphics.queueTextureLoad("chartSelect/landscapeInfoPanelBackground");

    textures.infoPanel.portrait.tempBackground = theori.graphics.queueTextureLoad("chartSelect/tempPortraitInfoPanelBackground");

	audio.clicks.primary = theori.audio.queueAudioLoad("chartSelect/click0");

    Layouts.Landscape.Background = theori.graphics.queueTextureLoad(bgName .. "_LS");
    Layouts.Portrait.Background = theori.graphics.queueTextureLoad(bgName .. "_PR");

    return true;
end

function theori.layer.onClientSizeChanged(w, h)
    Layout.CalculateLayout();
end

function theori.layer.resumed()
	theori.graphics.openCurtain();
end

function theori.layer.init()
	getLegends(textures.legend);
	getLegends(textures.badges);

    theori.charts.setDatabaseToClean(function()
        theori.charts.setDatabaseToPopulate(function() print("Populate (from chart select) finished."); end);
    end);

	audio.clicks.primary.volume = 0.5;
	gridCameraPosTarget = getGridCameraPosition();

    fontSlant = theori.graphics.getStaticFont("slant");

    theori.graphics.openCurtain();
	
	theori.input.keyboard.pressed.connect(onKeyPressed);
    theori.input.controller.pressed.connect(onButtonPressed);
    theori.input.controller.released.connect(onButtonReleased);
    theori.input.controller.axisTicked.connect(onAxisTicked);
end

function theori.layer.update(delta, total)
	timer = total;

	currentNoiseTexture = textures.noise[math.floor((timer * 24) % 10)];
	selectedSongTitleScrollTimer = selectedSongTitleScrollTimer + delta;

    Layout.Update(delta, total);
	for _, v in next, stateData do
		if (v.update) then
			v:update(delta, total);
		end
	end

	-- layout agnostic functions
	gridCameraPos = lerpAnimTo(gridCameraPos, gridCameraPosTarget, delta);
end

function theori.layer.render()
    Layout.CheckLayout();
    Layout.DoTransform();

    Layout.Render();
end
--------------------------------------------------


--------------------------------------------------
-- Layout Rendering Functions --------------------
--------------------------------------------------
local function renderSpriteNumCenteredNumDigits(num, dig, x, y, h, r, g, b, a)
	local w = 0;
	local digInfos = { };
	for i = dig, 1, -1 do
		local tento, tentom1 = math.pow(10, i), math.pow(10, i - 1);
		local tex = textures.numbers[math.floor((num % tento) / tentom1)];
		local texWidth = h * tex.aspectRatio;

		table.insert(digInfos, { texture = tex, width = texWidth });
		w = w + texWidth;
	end

	local xPos, yPos = x - w / 2, y - h / 2;
	for _, info in next, digInfos do
		theori.graphics.setFillToTexture(info.texture, r, g, b, a);
		theori.graphics.fillRect(xPos, yPos, info.width, h);
		xPos = xPos + info.width;
	end
end

local function renderCursor(x, y, size)
	local s0 = size * (1 + 0.05 * (math.abs(math.sin(timer * 6))));
	local s1 = size * (1 + 0.12 * (math.abs(math.sin(timer * 6))));

	local alpha = 170 + 60 * (math.abs(math.sin(timer * 3)));
	theori.graphics.setFillToTexture(textures.cursor, 0, 255, 255, alpha);
	theori.graphics.fillRect(x - s0 / 2, y - s0 / 2, s0, s0);
	theori.graphics.setFillToTexture(textures.cursorOuter, 0, 255, 255, alpha);
	theori.graphics.fillRect(x - s1 / 2, y - s1 / 2, s1, s1);
end

local function renderCell(chart, x, y, w, h, partial)
	--if (not chart) then return; end
	partial = partial and true or false; -- not necessary but explicit

	local isSelected = chart and (charts[groupIndex][cellIndex] == chart) or false;

	local r, g, b = 180, 180, 180;
	if (chart) then
		r, g, b = chart.difficultyColor;
	end
	local diffLvl = chart and chart.difficultyLevel or 0;
	
	theori.graphics.setFillToTexture(textures.chartFrame.fill, 80, 80, 80, 210);
	theori.graphics.fillRect(x, y, w, h);
	theori.graphics.setFillToTexture(textures.chartFrame.background, 50, 50, 50, 255);
	theori.graphics.fillRect(x, y, w, h);
	theori.graphics.setFillToTexture(textures.chartFrame.border, r, g, b, 255);
	theori.graphics.fillRect(x, y, w, h);
	theori.graphics.setFillToTexture(textures.chartFrame.trackDataLabel, 255, 255, 255, 255);
	theori.graphics.fillRect(x, y, w, h);
	
	local jx, jy, jw, jh = x + 0.1 * w, y + 0.155 * h, w * 0.6, h * 0.6;
	if (not chart or not chart.hasJacketTexture) then
		theori.graphics.setFillToTexture(textures.noJacket, 255, 255, 255, 255);
		theori.graphics.fillRect(jx, jy, jw, jh);
		theori.graphics.setFillToTexture(currentNoiseTexture, 255, 255, 255, 70);
		theori.graphics.fillRect(jx, jy, jw, jh);
		if (isSelected) then
			theori.graphics.setFillToTexture(textures.noJacketOverlay, 255, 255, 255, 175 + 60 * math.abs(math.sin(timer * 3)));
		else
			theori.graphics.setFillToTexture(textures.noJacketOverlay, 255, 255, 255, 205);
		end
		theori.graphics.fillRect(jx, jy, jw, jh);
	else
		theori.graphics.setFillToTexture(chart.getJacketTexture(), 255, 255, 255, 255);
		theori.graphics.fillRect(jx, jy, jw, jh);
	end
	
	theori.graphics.setFillToTexture(textures.levelBadgeBorder, r, g, b, 255);
	theori.graphics.fillRect(x + w * 0.73, y + h * 0.55, w * 0.22, h * 0.22);
	theori.graphics.setFillToTexture(textures.levelBadge, 50, 50, 50, 170);
	theori.graphics.fillRect(x + w * 0.73, y + h * 0.55, w * 0.22, h * 0.22);

	renderSpriteNumCenteredNumDigits(diffLvl,
		2, x + w * 0.835, y + h * 0.665, h * 0.09,
		0, 0, 0, 255);
	renderSpriteNumCenteredNumDigits(diffLvl,
		2, x + w * 0.84, y + h * 0.66, h * 0.09,
		255, 255, 255, 255);
	
	theori.graphics.saveTransform();
	if (isSelected) then
		theori.graphics.rotate(timer * 180);
	end
	theori.graphics.translate(LayoutScale * (x + w * (79 / 1028)), LayoutScale * (y + h * (75 / 1028)));
	theori.graphics.setFillToTexture(textures.chartFrame.storageDevice, 255, 255, 255, 255);
	local sdw, sdh = w * (100 / 1028), h * (100 / 1028);
	theori.graphics.fillRect(-sdw / 2, -sdh / 2, sdw, sdh);
	theori.graphics.restoreTransform();

	if (chart) then
		local scores = getScores(chart);
		if (#scores > 0) then
			local score = scores[#scores];

			local rankTexture = textures.badges[tostring(score.rank)];
			if (rankTexture) then
				theori.graphics.setFillToTexture(rankTexture, 255, 255, 255, 255);
				theori.graphics.fillRect(x + w * (761 / 1028), y + h * (155 / 1028), w * 210 / 1028, h * 179 / 1028);
			end

			local gaugeString = string.format("%d%%", math.floor(score.fVal1 * 100 + 0.5));
			
			theori.graphics.setFont(nil);
			theori.graphics.setFontSize(h * 0.1);
			theori.graphics.setTextAlign(Anchor.MiddleCenter);
			theori.graphics.setFillToColor(255, 255, 255, 255);
			theori.graphics.fillString(gaugeString, x + w * (866 / 1028), y + h * (439 / 1028));
		end
	end

	if (chart and not partial) then
		theori.graphics.setFontSize(h * 0.075);

		local titleBoundsX, _ = theori.graphics.measureString(chart.songTitle);

		local centerTitle = titleBoundsX < w * 0.8;
		local expectedScrollTime = (titleBoundsX - w * 0.8) / 40;
		local relativeTime = math.max(0, math.min(1, ((selectedSongTitleScrollTimer % (4 + expectedScrollTime)) - 2) / expectedScrollTime));
		local titleOffsetX = centerTitle and w * 0.4 or - relativeTime * (titleBoundsX - w * 0.8 + 1);

		if (not centerTitle) then
			theori.graphics.saveScissor();
			theori.graphics.scissor(x * LayoutScale + w * LayoutScale * 0.1, y * LayoutScale + h * LayoutScale * 0.7 + 0.5, w * LayoutScale * 0.8, h * LayoutScale * 0.3 + 0.5);
		end

		theori.graphics.setFont(nil);
		theori.graphics.setTextAlign(centerTitle and Anchor.MiddleCenter or Anchor.MiddleLeft);
		theori.graphics.setFillToColor(255, 255, 255, 255);
		theori.graphics.fillString(chart.songTitle, x + w * 0.1 + titleOffsetX, y + h * 0.825);

		if (not centerTitle) then
			theori.graphics.restoreScissor();
		end
	end
end

local function renderChartGridPanel(x, y, w, h)
	if (#charts == 0) then return; end

	local cellSize = w / gridColumnCount;
	local hUnits = h / cellSize;
	local totalGroupsHeight = 0;
	for i = 1, #charts do
		totalGroupsHeight = totalGroupsHeight + getSizeOfGroup(i);
	end

	local camPosUnits = math.max(hUnits / 2, math.min(totalGroupsHeight - hUnits / 2, gridCameraPos));

	local minCamera = camPosUnits - hUnits / 2;
	local maxCamera = camPosUnits + hUnits / 2;

	local yOffset = y - minCamera * cellSize;
	local margin = cellSize * 0.05;

	local yPosRel = 0;
	for gi = 1, #charts do
		if (yPosRel > maxCamera) then break; end
		local group = charts[gi];

		local groupHeight = getSizeOfGroup(gi);
		-- if the bottom of this group is in view, we start checking cell rendering
		if (yPosRel + groupHeight > minCamera) then
			if (yPosRel + gridGroupHeaderSize > minCamera) then
				theori.graphics.setFillToColor(50, 160, 255, 200);
				theori.graphics.fillRect(x, yOffset + yPosRel * cellSize, w, gridGroupHeaderSize * cellSize);
			end

			for ci = 1, #group do
				local chart = group[ci];
				local selected = gi == groupIndex and ci == cellIndex;

				local rowIndex = math.floor((ci - 1) / gridColumnCount);
				local colIndex = (ci - 1) % gridColumnCount;

				local yPosRelSet = yPosRel + gridGroupHeaderSize + rowIndex +
					(colIndex * gridRowStepping / (gridColumnCount - 1));

				if (yPosRelSet < maxCamera and yPosRelSet + 1 > minCamera) then;
					local cx, cy = margin + x + colIndex * cellSize, margin + yOffset + yPosRelSet * cellSize;
					local cs = cellSize - 2 * margin;

					renderCell(chart, cx, cy, cs, cs);
				end
			end
		end

		yPosRel = yPosRel + groupHeight;
	end

	local cursorCenterX, cursorCenterY = getGridCellPosition(groupIndex, cellIndex);
	renderCursor(x + cellSize * cursorCenterX, yOffset + cellSize * cursorCenterY, cellSize);
end

local function renderChartLevelBar(set, x, y, w, h)
	local setSlots = set and getSetSlots(set) or { { }, { }, { }, { }, { } };
	local cSlotIndex = set and nearestSlotIndex(setSlots, slotIndex);

	local chart = set and nearestSlotChild(setSlots[cSlotIndex], slotChildIndex).chart;
	local r, g, b = 180, 180, 180;
	if (chart) then
		r, g, b = chart.difficultyColor;
	end
	
	theori.graphics.setFillToTexture(textures.levelBarBorder, r, g, b, 255);
	theori.graphics.fillRect(x, y, w, h);
	theori.graphics.setFillToTexture(textures.levelBar, 50, 50, 50, 170);
	theori.graphics.fillRect(x, y, w, h);

	theori.graphics.setFillToTexture(textures.levelText, 255, 255, 255, 255);
	theori.graphics.fillRect(x, y, h, h);

	for i = 1, 5 do
		local slot = setSlots[i];

		local r, g, b = 100, 100, 100;
		local childIndex;

		if (#slot > 0) then
			childIndex = nearestSlotChildIndex(slot, slotChildIndex);
			r, g, b = slot[childIndex].chart.difficultyColor;
		end

		local s = h * 0.7;
		local o = (h - s) / 2;

		theori.graphics.setFillToTexture(textures.levelBadgeBorder, r, g, b, 255);
		theori.graphics.fillRect(x + h * i + o, y + o, s, s);
		theori.graphics.setFillToTexture(textures.levelBadge, 50, 50, 50, 255);
		theori.graphics.fillRect(x + h * i + o, y + o, s, s);
		
		if (#slot > 0) then
			local diffLvl = slot[childIndex].chart.difficultyLevel;
			renderSpriteNumCenteredNumDigits(diffLvl,
				2, x + h * i + h / 2 - 2, y + h / 2 + 2, s * 0.4,
				0, 0, 0, 255);
			renderSpriteNumCenteredNumDigits(diffLvl,
				2, x + h * i + h / 2, y + h / 2, s * 0.4,
				255, 255, 255, 255);
		end
	end

	if (set) then
		renderCursor(x + h * cSlotIndex + h / 2, y + h / 2, h);
	end
end

local function renderLandscapeInfoPanel(chart, x, y, w, h)
	renderCell(chart, x + w * 0.1, y, w * 0.8, h * 0.8, true);

	theori.graphics.setFillToTexture(textures.infoPanel.landscape.background, 50, 50, 50, 255);
	theori.graphics.fillRect(x, y, w, h);

	renderChartLevelBar(chart and chart.set, x + w * 0.25, y + h * 0.875, w * 0.75, h * 0.125);
end

function renderPortraitInfoPanel(chart, x, y, w, h)
	theori.graphics.setFillToTexture(textures.infoPanel.portrait.border, 255, 255, 255, 255);
	theori.graphics.fillRect(x, y, w, h);
	theori.graphics.setFillToTexture(textures.infoPanel.portrait.fill, 50, 50, 50, 170);
	theori.graphics.fillRect(x, y, w, h);
	theori.graphics.setFillToTexture(textures.infoPanel.portrait.jacketBorder, 255, 255, 255, 255);
	theori.graphics.fillRect(x, y, w, h);

	local chartLevelBarWidth = w * (1006 / 1440);
	local chartLevelBarHeight = chartLevelBarWidth / 6;
	renderChartLevelBar(chart.set, w - chartLevelBarWidth, 7 + h - chartLevelBarHeight, chartLevelBarWidth, chartLevelBarHeight);
end

function Layouts.Landscape.Update(self, delta, total)
	infoBounceTimer = math.max(0, infoBounceTimer - delta * 5);
end

function Layouts.Landscape.Render(self)
    Layout.DrawBackgroundFilled(self.Background);

	local howtoScale = 0.85;

	gridColumnCount = 3;
	local chartGridPanelWidth = math.min(LayoutWidth * 0.5, LayoutHeight);
	local infoPanelWidth = math.min(LayoutHeight * howtoScale, LayoutWidth - chartGridPanelWidth);

	while (LayoutWidth - (chartGridPanelWidth + infoPanelWidth) > (chartGridPanelWidth / (gridColumnCount - 1))) do
		chartGridPanelWidth = chartGridPanelWidth + chartGridPanelWidth / (gridColumnCount - 1);
		gridColumnCount = gridColumnCount + 1;

		infoPanelWidth = math.min(LayoutHeight, LayoutWidth - chartGridPanelWidth);
	end

	local infoPanelX = (infoBounceTimer * infoPanelWidth * 0.01) + ((LayoutWidth - chartGridPanelWidth) - infoPanelWidth) / 2;
	local infoPanelY = (infoBounceTimer * infoPanelWidth * 0.01) + (LayoutHeight * howtoScale - infoPanelWidth) / 2;

    renderChartGridPanel(LayoutWidth - chartGridPanelWidth, 0, chartGridPanelWidth, LayoutHeight);
	
	local chart = #charts > 0 and charts[groupIndex][cellIndex] or nil;
	renderLandscapeInfoPanel(chart, infoPanelX, infoPanelY, infoPanelWidth, infoPanelWidth);

	for k, v in next, stateData do
		if (k ~= 0 and stateData[k].renderLandscape) then
			stateData[k]:renderLandscape();
		end
	end

	theori.graphics.setFillToTexture(textures.legend.l, 255, 255, 255, 255);
	theori.graphics.fillRect(0.25 * infoPanelWidth - LayoutHeight * 0.0625, LayoutHeight * howtoScale, LayoutHeight * 0.125, LayoutHeight * 0.125);

	theori.graphics.setFillToTexture(textures.legend.lr, 255, 255, 255, 255);
	theori.graphics.fillRect(0.75 * infoPanelWidth - LayoutHeight * 0.0625, LayoutHeight * howtoScale, LayoutHeight * 0.125, LayoutHeight * 0.125);

	theori.graphics.setFont(nil);
	theori.graphics.setFillToColor(255, 255, 255, 255);
	theori.graphics.setFontSize(LayoutHeight * 0.02);
	theori.graphics.setTextAlign(Anchor.MiddleCenter);

	theori.graphics.fillString("Chart Filter / Sort", 0.25 * infoPanelWidth, LayoutHeight * 0.97);
	theori.graphics.fillString("Gameplay Settings", 0.75 * infoPanelWidth, LayoutHeight * 0.97);
end

function Layouts.Portrait.Render(self)
    Layout.DrawBackgroundFilled(self.Background);

	gridColumnCount = 3;

	local infoPanelHeight = LayoutWidth * (275 / 720);
	local consolePanelHeight = LayoutWidth * 0.285;

	local chartGridPanelHeight = LayoutHeight - infoPanelHeight - consolePanelHeight;
	
	local chart = #charts > 0 and charts[groupIndex][cellIndex] or nil;
	renderPortraitInfoPanel(chart, 0, 0, LayoutWidth, infoPanelHeight);

	theori.graphics.scissor(0, infoPanelHeight * LayoutScale, LayoutWidth * LayoutScale, chartGridPanelHeight * LayoutScale);
    renderChartGridPanel(0, infoPanelHeight, LayoutWidth, chartGridPanelHeight);
	theori.graphics.resetScissor();

	for k, v in next, stateData do
		if (k ~= 0 and stateData[k].renderPortrait) then
			stateData[k]:renderPortrait();
		end
	end
end
--------------------------------------------------


--------------------------------------------------
-- Default State Functions -----------------------
--------------------------------------------------
local defaultState = { };
stateData[0] = defaultState;

function defaultState.update(self, delta, total)
	-- updates specific to this state
end

function defaultState.keyPressed(self, key)
	if (key == KeyCode.TAB) then
		setTextInput();
	end
end

function defaultState.buttonPressed(self, controller, button)
    if (button == "back") then
        theori.graphics.closeCurtain(0.2, theori.layer.pop);
    elseif (button == "start") then
		if (#charts == 0) then return; end

		local chart = charts[groupIndex][cellIndex];
        theori.graphics.closeCurtain(0.2, function() nsc.pushGameplay(chart, autoPlay); end);
	elseif (button == 3) then -- TEMP TEMP TEMP
		if (charts and #charts > 0) then
			local chart = charts[groupIndex][cellIndex];
			theori.charts.addChartToCollection("Favorites", chart);
		end
	elseif (button >= 0 and button <= 3 and stateData[button + 1]) then
		setState(button + 1);
	elseif (button == 4 or button == 5) then
		if (controller.isDown(4) and controller.isDown(5) and stateData[7]) then
			setState(7);
		end
    end
end

function defaultState.buttonReleased(self, controller, button)
    if (button == 4 or button == 5) then
		setState(button + 1);
    end
end

function defaultState.axisTicked(self, controller, axis, dir)
	if (#charts == 0) then return; end

    if (axis == 0) then
		local chart = charts[groupIndex][cellIndex];
		local set = chart.set;
			
		local setSlots = getSetSlots(set);
		local cSlotIndex = nearestSlotIndex(setSlots, slotIndex);
		local cSlotChildIndex = nearestSlotChildIndex(setSlots[cSlotIndex], slotChildIndex);

		local newSlotIndex = cSlotIndex;

		while (true) do
			newSlotIndex = newSlotIndex + dir;
			if (newSlotIndex < 1 or newSlotIndex > 5) then break; end
				
			if (#setSlots[newSlotIndex] > 0) then
				break;
			end
		end

		if (newSlotIndex == cSlotIndex or newSlotIndex < 1 or newSlotIndex > 5) then return; end
			
		slotIndex = newSlotIndex;
		slotChildIndex = nearestSlotChildIndex(setSlots[slotIndex], cSlotChildIndex);

		local nextChartRef = setSlots[slotIndex][slotChildIndex];
		groupIndex = nextChartRef.groupIndex;
		cellIndex = nextChartRef.cellIndex;
	
		chart = charts[groupIndex][cellIndex];

		theori.config.set("lastSetId", chart.setID);
		theori.config.set("lastChartId", chart.ID);

		theori.config.save();
				
		gridCameraPosTarget = getGridCameraPosition();
		infoBounceTimer = 1;

		audio.clicks.primary.playFromStart();
    elseif (axis == 1) then
		cellIndex = cellIndex + dir;
		if (cellIndex < 1) then
			groupIndex = groupIndex - 1;
			if (groupIndex < 1) then
				groupIndex = #charts;
			end
			cellIndex = #charts[groupIndex];
		elseif (cellIndex > #charts[groupIndex]) then
			groupIndex = groupIndex + 1;
			if (groupIndex > #charts) then
				groupIndex = 1;
			end
			cellIndex = 1;
		end

		local chart = charts[groupIndex][cellIndex];
		slotIndex = chart.difficultyIndex;
		slotChildIndex = 1;
	
		theori.config.set("lastSetId", chart.setID);
		theori.config.set("lastChartId", chart.ID);

		theori.config.save();

		gridCameraPosTarget = getGridCameraPosition();
		infoBounceTimer = 1;
		
		audio.clicks.primary.playFromStart();
    end
end
--------------------------------------------------


--------------------------------------------------
-- FX L State Functions --------------------------
--------------------------------------------------
local fxlState =
{
	inoutTransition = 0,

	defaultEntries =
	{
		{
			name = "All Charts",
			onSelected = function(self)
				currentChartCollectionName = nil;
				filterName = "*";
			end,
		},

		{
			name = "Collections",
			onSelected = function()
				local subFolder = { };
				for _, col in next, theori.charts.getCollectionNames() do
					table.insert(subFolder, {
						name = col,
						onSelected = function(self)
							currentChartCollectionName = self.name;
							filterName = "*";
						end,
					});
				end
				return subFolder;
			end,
		},

		{
			name = "Folders",
			onSelected = function(self)
				local subFolder = { };
				for _, fol in next, theori.charts.getFolderNames() do
					table.insert(subFolder, {
						name = fol,
						onSelected = function(self)
							currentChartCollectionName = nil;
							filterName = self.name;
						end,
					});
				end
				return subFolder;
			end,
		},

		{
			name = "Levels",
			onSelected = function(self)
				local subFolder = { };
				for i = 1, 20 do
					table.insert(subFolder, {
						name = "Level " .. tostring(i),
						onSelected = function(self)
							--currentChartCollectionName = nil;
							filterName = i;
						end,
					});
				end
				return subFolder;
			end,
		},
	},

	previousEntries = { },
};
fxlState.entries = { entryIndex = 1, entries = fxlState.defaultEntries };
stateData[5] = fxlState;

function fxlState.update(self, delta, total)
	if (currentState == 5) then
		self.inoutTransition = math.min(1, self.inoutTransition + delta * 10);
	else
		self.inoutTransition = math.max(0, self.inoutTransition - delta * 10);
	end
end

function fxlState.navigateUp(self)
	if (#self.previousEntries == 0) then
		setState(0);
	else
		local previous = self.previousEntries[#self.previousEntries];
		table.remove(self.previousEntries, #self.previousEntries);

		self.entries = previous;
	end
end

function fxlState.buttonPressed(self, controller, button)
	if (button == "back") then
		self:navigateUp();
	elseif (button == "start") then
		if (#self.entries.entries == 0) then return; end

		local result = self.entries.entries[self.entries.entryIndex]:onSelected();
		if (result) then
			table.insert(self.previousEntries, self.entries);
			self.entries = { entryIndex = 1, entries = result };
		else
			if (#self.previousEntries > 0) then
				self.entries = self.previousEntries[1];
			end
			self.previousEntries = { };

			--print(currentChartCollectionName);

			updateChartConfiguration();
			setState(0);
		end
	elseif (button == 6) then
		local menuTitle = nil;

		if (#self.previousEntries > 0) then
			--menuTitle = 
			self.entries = self.previousEntries[1];
		end
		self.previousEntries = { };
		
		setTextInput();
	end
end

function fxlState.buttonReleased(self, controller, button)
	if (button == 4) then
		self:navigateUp();
	end
end

function fxlState.axisTicked(self, controller, axis, dir)
	audio.clicks.primary.playFromStart();

	local entries = self.entries;

	entries.entryIndex = entries.entryIndex + dir;
	if (entries.entryIndex < 1) then entries.entryIndex = #entries.entries; end
	if (entries.entryIndex > #entries.entries) then entries.entryIndex = 1; end
end

function fxlState.renderDim(self)
	theori.graphics.setFillToColor(0, 0, 0, 127 * self.inoutTransition);
	theori.graphics.fillRect(0, 0, LayoutWidth, LayoutHeight);
end

function fxlState.renderEntries(self, x, y, w, h)
	theori.graphics.setFillToColor(50, 50, 50, 170);
	theori.graphics.fillRect(x, y, w / 2, h);

	theori.graphics.setFont(nil);
	theori.graphics.setTextAlign(Anchor.MiddleCenter);
	theori.graphics.setFontSize(24);

	for coli, entry in next, self.entries.entries do
		local col = entry.name;
		local offs = 30 * (coli - self.entries.entryIndex);

		if (coli == self.entries.entryIndex) then
			theori.graphics.setFillToColor(255, 255, 0, 255);
		else
			theori.graphics.setFillToColor(255, 255, 255, 200);
		end
		theori.graphics.fillString(col, x + w * 0.25, offs + y + h * 0.5);
	end
end

function fxlState.renderLandscape(self)
	if (self.inoutTransition == 0) then return; end

	self:renderDim();
	self:renderEntries(-(1 - self.inoutTransition) * LayoutWidth * 0.25, LayoutHeight * 0.125, LayoutWidth * 0.5, LayoutHeight * 0.75);

	theori.graphics.setFillToTexture(textures.legend.r, 255, 255, 255, 255);
	theori.graphics.fillRect(LayoutWidth - LayoutHeight * 0.15, LayoutHeight - LayoutHeight * 0.15 * self.inoutTransition, LayoutHeight * 0.125, LayoutHeight * 0.125);
	
	theori.graphics.setFont(nil);
	theori.graphics.setFillToColor(255, 255, 255, 255);
	theori.graphics.setFontSize(LayoutHeight * 0.02);
	theori.graphics.setTextAlign(Anchor.MiddleRight);

	theori.graphics.fillString("Search Charts", LayoutWidth * 0.95, LayoutHeight * 0.97);
end

function fxlState.renderPortrait(self)
	if (self.inoutTransition == 0) then return; end

	self:renderDim();
	self:renderEntries(-(1 - self.inoutTransition) * LayoutWidth * 0.375, LayoutHeight * 0.25, LayoutWidth * 0.75, LayoutHeight * 0.5);
end
--------------------------------------------------


--------------------------------------------------
-- Text State Functions --------------------------
--------------------------------------------------
local textState = { };
stateData["text"] = textState;

function textState.keyPressed(self, key)
	if (key == KeyCode.ESCAPE) then
		setState(0);
	elseif (key == KeyCode.RETURN) then
		searchText = textInput.getText();
		
		updateChartConfiguration();
		setState(0);
	end
end

function textState.buttonPressed(self, controller, button)
	if (button == "back") then
		setState(0);
	elseif (button == "start") then
		searchText = textInput.getText();
		
		updateChartConfiguration();
		setState(0);
	end
end

function textState.renderLandscape(self)
	if (not textInput.isActive()) then return; end

	local w, h = LayoutWidth, LayoutHeight;

	theori.graphics.setFillToColor(0, 0, 0, 127);
	theori.graphics.fillRect(0, 0, w, h);

	local text = textInput.getText();
	if (text and #text > 0) then
		theori.graphics.setFont(nil);
		theori.graphics.setTextAlign(Anchor.MiddleCenter);
		theori.graphics.setFontSize(h * 0.07);
		theori.graphics.setFillToColor(255, 255, 255, 255);

		theori.graphics.fillString(text, w / 2, h / 2);
	end
end

function textState.renderPortrait(self)
	if (not textInput.isActive()) then return; end

	local w, h = LayoutWidth, LayoutHeight;

	theori.graphics.setFillToColor(0, 0, 0, 127);
	theori.graphics.fillRect(0, 0, w, h);

	local text = textInput.getText();
	if (text and #text > 0) then
		theori.graphics.setFont(nil);
		theori.graphics.setTextAlign(Anchor.MiddleCenter);
		theori.graphics.setFontSize(h * 0.03);
		theori.graphics.setFillToColor(255, 255, 255, 255);

		theori.graphics.fillString(text, w / 2, h / 2);
	end
end
--------------------------------------------------