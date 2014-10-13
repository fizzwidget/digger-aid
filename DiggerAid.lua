------------------------------------------------------
-- DiggerAid.lua
------------------------------------------------------
local addonName, addonTable = ...; 

-- TODO: Possible features to add:
-- replace map icons for digsites with race-specific icons
-- digsite icons on flight map
-- progress summary somewhere you can see it more conveniently than a slash command?

------------------------------------------------------
-- Constants
------------------------------------------------------

FDA_LINK_TYPE = "gfwarch";
FDA_SOLVE_LINK_TYPE = "gfwsolve";
FDA_KEYSTONE_FRAGMENT_EQUIVALENT = 12;
FDA_COMMON_SKILLUP = 5;
FDA_RARE_SKILLUP = 15;

FDA_RaceForArchFragment = {
	[384] = 1,	-- Dwarf
	[398] = 2,	-- Draenei
	[393] = 3,	-- Fossil
	[394] = 4,	-- Night Elf
	[400] = 5,	-- Nerubian
	[397] = 6,	-- Orc
	[401] = 7,	-- Tol'vir
	[385] = 8,	-- Troll
	[399] = 9,	-- Vrykul
	
	[754] = 10,	-- Mantid
	[676] = 11,	-- Pandaren
	[677] = 12,	-- Mogu
	
	[829] = 13,	-- Arakkoa
	[821] = 14,	-- Draenor Clans
	[828] = 15,	-- Ogre
	
};
FDA_FragmentForRace = {};
setmetatable(FDA_FragmentForRace, {__index = function(tbl,key)
	for currencyID, raceIndex in pairs(FDA_RaceForArchFragment) do
		if (raceIndex == key) then
			return currencyID;
		end
	end
end});

------------------------------------------------------
-- Saved Variables
------------------------------------------------------

FDA_IgnoreKeystones = {};

------------------------------------------------------
-- Hooks
------------------------------------------------------

function FDA_OnTooltipSetItem(self)
	local itemName, link = self:GetItem();
	if (itemName == nil) then return; end
		
	for raceIndex = 1, GetNumArchaeologyRaces() do
		local artifactName = GetActiveArtifactByRace(raceIndex);
		if (artifactName == itemName) then
			FDA_AppendCurrentArtifactTooltipForRace(self, raceIndex);
			return;	
		end
		for projectIndex = 1, GetNumArtifactsByRace(raceIndex) do
			local name, description, rarity, icon, spellDescription, numSockets, art, firstCompletionTime, completionCount = GetArtifactInfoByRace(raceIndex, projectIndex);
			if (name == itemName) then
				if (completionCount and completionCount > 0) then
					self:AddLine(spellDescription,nil,nil,nil,true);
					self:AddLine(" ");
					local adate = date("*t", firstCompletionTime);
					self:AddLine(ARCHAEOLOGY_TIMESTAMP.." |cffffffff"..string.format(SHORTDATE, adate.day, adate.month, adate.year).." "..GameTime_GetFormattedTime(adate.hour, adate.min, true));
					self:AddLine(string.format(ARCHAEOLOGY_COMPLETION, completionCount));
					self:Show();
				end
				return;
			end
		end
	end
end

function FDA_SetItemRef(link, text, button, chatFrame, ...)
	local _, _, linkType, raceIndex = string.find(link, "^([^:]+):(%d+)");
	raceIndex = tonumber(raceIndex);
	if (linkType == FDA_LINK_TYPE and raceIndex) then
		if (IsModifiedClick("DRESSUP")) then
			-- show in archaeology window
			ArchaeologyFrame_LoadUI();
			if (ArchaeologyFrame_Show) then
				ArchaeologyFrame_Show();
				ArchaeologyFrame_ShowArtifact(raceIndex);
			end
			return;
		end
		ShowUIPanel(ItemRefTooltip);
		if ( ItemRefTooltip:IsShown() ) then
			if (FDA_ShowingArtifactTooltip == raceIndex) then
				HideUIPanel(ItemRefTooltip);
				FDA_ShowingArtifactTooltip = nil;
			end
		else
			ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE");
		end
		FDA_ShowCurrentArtifactTooltipForRace(ItemRefTooltip, raceIndex);
		FDA_ShowingArtifactTooltip = raceIndex;
	elseif (linkType == FDA_SOLVE_LINK_TYPE and raceIndex) then
		-- TODO: right click for menu: solve with/without keystones
		-- also make menu a second place to control ignoring keystones?
		SetSelectedArtifact(raceIndex);
		local raceName, raceIcon, keystoneItemID = GetArchaeologyRaceInfo(raceIndex);
		local base, adjust, totalCost = GetArtifactProgress();
		local artifactName, introText, rarity, icon, description, numSockets, art = GetActiveArtifactByRace(raceIndex);
		
		local keystones = FDA_GetKeystoneInfo(numSockets, keystoneItemID, base, totalCost);
		for i = 1, keystones do
			SocketItemToArtifact();
		end
		if CanSolveArtifact() then
			SolveArtifact();
		end
	else
		FDA_orig_SetItemRef(link,text,button,chatFrame, ...);
	end
end

function FDA_UpdateArchUI(self)
	if (FDA_AutoUseFragmentsButton == nil) then
		FDA_AutoUseFragmentsButton = CreateFrame("CheckButton", "FDA_AutoUseFragmentsButton", self.solveFrame, "UICheckButtonTemplate");
		FDA_AutoUseFragmentsButton:SetPoint("TOPLEFT", self.solveFrame.solveButton, "BOTTOMLEFT", -1, -5);
		FDA_AutoUseFragmentsButton:SetWidth(24);
		FDA_AutoUseFragmentsButton:SetHeight(24);
		FDA_AutoUseFragmentsButtonText:SetText(FDA_AUTO_USE_KEYSTONES);
		FDA_AutoUseFragmentsButtonText:SetJustifyH("LEFT");
		FDA_AutoUseFragmentsButtonText:SetJustifyV("TOP");
		-- Increase click area so text is also clickable
		FDA_AutoUseFragmentsButton:SetHitRectInsets(0, -1 * FDA_AutoUseFragmentsButtonText:GetWidth() , 0, 0) 

		FDA_AutoUseFragmentsButton:SetScript("OnClick", function(checkButton)
			local raceName, raceIcon, keystoneItemID = GetArchaeologyRaceInfo(self.raceID);
			if (checkButton:GetChecked()) then
				-- was unchecked, now is checked (remove from ignore list)
				FDA_IgnoreKeystones[keystoneItemID] = nil;
			else
				-- was checked, now is unchecked (add to ignore list)
				FDA_IgnoreKeystones[keystoneItemID] = 1;
			end
			FDA_UpdateAutoUseFragments(self.raceID);
		end)   
	end
	
	local raceName, raceIcon, keystoneItemID = GetArchaeologyRaceInfo(self.raceID);
	if (keystoneItemID == 0) then
		FDA_AutoUseFragmentsButton:Hide();
	else
		local keystoneName = GetItemInfo(keystoneItemID);
		if (keystoneName == nil) then
			keystoneName = string.format(FDA_GENERIC_KEYSTONES, raceName);
		end
		FDA_AutoUseFragmentsButtonText:SetText(string.format(FDA_AUTO_USE_KEYSTONES, keystoneName));
		FDA_AutoUseFragmentsButton:Show();
		FDA_UpdateAutoUseFragments(self.raceID);
	end
		
end

function FDA_UpdateAutoUseFragments(raceIndex)
	local raceName, raceIcon, keystoneItemID = GetArchaeologyRaceInfo(raceIndex);
	if (FDA_IgnoreKeystones[keystoneItemID]) then
		FDA_AutoUseFragmentsButton:SetChecked(false);
		for i = 1, ARCHAEOLOGY_MAX_STONES do
			RemoveItemFromArtifact();
		end
	else
		FDA_AutoUseFragmentsButton:SetChecked(true);
		local base, adjust, totalCost = GetArtifactProgress();
		local artifactName, introText, rarity, icon, description, numSockets, art = GetActiveArtifactByRace(raceIndex);
		local keystones = FDA_GetKeystoneInfo(numSockets, keystoneItemID, base, totalCost);
		for i = 1, keystones do
			SocketItemToArtifact();
		end
	end
end

------------------------------------------------------
-- Other entry points
------------------------------------------------------

function FDA_OnEvent(self, event, ...)
	
	if (event == "ADDON_LOADED" and select(1,...) == "Blizzard_ArchaeologyUI") then
		hooksecurefunc("ArchaeologyFrame_CurrentArtifactUpdate", FDA_UpdateArchUI);
		return;
	end
	
	if (event == "ARTIFACT_COMPLETE" or event == "ARTIFACT_UPDATE" or event == "CHAT_MSG_CURRENCY") then
		RequestArtifactCompletionHistory();
		if (FDA_NeedUpdateForRaceIndex) then
			FDA_PrintArchUpdateForRaceIndex(FDA_NeedUpdateForRaceIndex);
		end
	end	
	if (event == "CHAT_MSG_CURRENCY") then
		FDA_PrintArchUpdateForCurrency(...);
	end
	if (event == "ARTIFACT_COMPLETE") then
		local completedArtifact = ...;
		for raceIndex = 1, GetNumArchaeologyRaces() do
			local artifactName, introText, rarity, icon, description, numSockets, art = GetActiveArtifactByRace(raceIndex);
			if (artifactName == completedArtifact) then
				FDA_NeedUpdateForRaceIndex = raceIndex;
				break;
			end
		end
	end
	
end

function FDA_ChatCommandHandler(msg)
	
	-- spam update to chat
	for raceIndex = 1, GetNumArchaeologyRaces() do
		if (GetNumArtifactsByRace(raceIndex) > 0) then
			FDA_PrintArchUpdateForRaceIndex(raceIndex, true);
		end
	end
end

------------------------------------------------------
-- Tooltips
------------------------------------------------------

function FDA_ShowCurrentArtifactTooltipForRace(tooltip, raceIndex)
	local artifactName, introText, rarity, icon, description, numSockets, art = GetActiveArtifactByRace(raceIndex);

	-- name
	local r,g,b = GetItemQualityColor(1);
	if (rarity > 0) then
		r,g,b = GetItemQualityColor(3);
	end
	tooltip:SetText(artifactName, r,g,b);
	FDA_AppendCurrentArtifactTooltipForRace(tooltip, raceIndex);
end

function FDA_AppendCurrentArtifactTooltipForRace(tooltip, raceIndex)
	local raceName, raceIcon, keystoneItemID = GetArchaeologyRaceInfo(raceIndex);
	SetSelectedArtifact(raceIndex);
	local base, adjust, totalCost = GetArtifactProgress();
	local artifactName, introText, rarity, icon, description, numSockets, art = GetActiveArtifactByRace(raceIndex);
	local _, firstCompletionTime, completionCount;
	for projectIndex = 1, GetNumArtifactsByRace(raceIndex) do
		local name;
		name, _, _, _, _, _, _, firstCompletionTime, completionCount = GetArtifactInfoByRace(raceIndex, projectIndex);
		if (name == artifactName) then
			break;
		end
	end
	local fragmentID = FDA_FragmentForRace[raceIndex];
	local fragmentName = GetCurrencyInfo(fragmentID);

	-- name (and intro text for rares)
	local c = HIGHLIGHT_FONT_COLOR;
	if (rarity > 0) then
		tooltip:AddLine(introText, nil, nil, nil, true);
	end
	tooltip:AddLine(" ");
	
	-- fragment type, count, total needed, keystones if applicable
	local usableKeystones, adjust, inBank = FDA_GetKeystoneInfo(numSockets, keystoneItemID, base, totalCost);
	if (usableKeystones > 0) then
		tooltip:AddDoubleLine(fragmentName..":", string.format("%d(+%d)/%d", base + adjust, adjust, totalCost),
			nil,nil,nil, c.r,c.g,c.b);
		tooltip:AddDoubleLine(GetItemInfo(keystoneItemID)..":", usableKeystones	,
			nil,nil,nil, c.r,c.g,c.b);
	else
		tooltip:AddDoubleLine(fragmentName..":", string.format("%d/%d", base, totalCost),
			nil,nil,nil, c.r,c.g,c.b);
	end
	if (inBank > 0) then
		tooltip:AddLine(string.format(FDA_KEYSTONES_IN_BANK, inBank, GetItemInfo(keystoneItemID)));
	end
	
	-- past completion info for previously completed artifacts
	if (completionCount ~= nil and completionCount > 0) then
		local adate = date("*t", firstCompletionTime);
		local dateTimeText = string.format(SHORTDATE, adate.day, adate.month, adate.year).." "..GameTime_GetFormattedTime(adate.hour, adate.min, true);
		tooltip:AddDoubleLine(ARCHAEOLOGY_TIMESTAMP, dateTimeText, nil,nil,nil, c.r,c.g,c.b);
		local _, _, completionLabel = string.find(ARCHAEOLOGY_COMPLETION, "([^:]+:)"); 
		tooltip:AddDoubleLine(completionLabel, completionCount, nil,nil,nil, c.r,c.g,c.b);
	end

	tooltip:Show();
end

function FDA_ShowSolveTooltipForRace(raceIndex)
	GameTooltip:SetText(FDA_CLICK_TO_SOLVE);
	
	-- what will solving do? pt. 1: artifact to be solved
	local raceName, raceIcon, keystoneItemID = GetArchaeologyRaceInfo(raceIndex);
	SetSelectedArtifact(raceIndex);
	local base, adjust, totalCost = GetArtifactProgress();
	local artifactName, introText, rarity, icon, description, numSockets, art = GetActiveArtifactByRace(raceIndex);
	local r,g,b = GetItemQualityColor(1);
	local skillups = FDA_COMMON_SKILLUP;
	if (rarity == 1) then
		r,g,b = GetItemQualityColor(3);
		skillups = FDA_RARE_SKILLUP;
	end
	GameTooltip:AddLine(artifactName, r,g,b);

	-- what will solving do? pt. 2: how many of which items will be used
	GameTooltip:AddLine(" ");
	GameTooltip:AddLine(FDA_COST);
	local c = HIGHLIGHT_FONT_COLOR;
	local fragmentID = FDA_FragmentForRace[raceIndex];
	local fragmentName = GetCurrencyInfo(fragmentID);
	local usableKeystones, adjust = FDA_GetKeystoneInfo(numSockets, keystoneItemID, base, totalCost);
	if (base + adjust > totalCost) then
		base = totalCost - adjust;
	end
	GameTooltip:AddDoubleLine("  "..fragmentName..":", base, nil,nil,nil, c.r,c.g,c.b);
	if (usableKeystones > 0) then
		GameTooltip:AddDoubleLine("  "..GetItemInfo(keystoneItemID)..":", usableKeystones, nil,nil,nil, c.r,c.g,c.b);
	end
	
	-- what will solving do? pt. 3: skillups
	local _, _, arch = GetProfessions();
	local name, texture, rank, maxRank, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset = GetProfessionInfo(arch);
	local topRank = PROFESSION_RANKS[#PROFESSION_RANKS][1];
	local newSkill = rank + skillups;
	if (rank ~= topRank) then
		local skillSummary = string.format("%d/%d", newSkill, maxRank);
		if (maxRank < topRank and newSkill > maxRank) then
			c = RED_FONT_COLOR;
			skillSummary = string.format("%d/%d", maxRank, maxRank);
			skillSummary = skillSummary.." "..string.format(FDA_SKILL_WASTE, newSkill - maxRank);
		end
		GameTooltip:AddLine(" ");
		GameTooltip:AddDoubleLine(FDA_SKILLUP, skillSummary, nil,nil,nil, c.r,c.g,c.b);
	end
	GameTooltip:Show()
end

------------------------------------------------------
-- Other Internal functions
------------------------------------------------------

function FDA_PrintArchUpdateForCurrency(msg)
	local _, _, currencyID = string.find(msg, "currency:(%d+)");
	local raceIndex = FDA_RaceForArchFragment[tonumber(currencyID)];
	if (raceIndex) then
		FDA_PrintArchUpdateForRaceIndex(raceIndex);
	end
end

function FDA_PrintArchUpdateForRaceIndex(raceIndex, noErrorFrame)
	if (GetNumArtifactsByRace(raceIndex) == 0) then
		FDA_NeedUpdateForRaceIndex = raceIndex;
		return;
	end
	local raceName, raceIcon, keystoneItemID = GetArchaeologyRaceInfo(raceIndex);
	SetSelectedArtifact(raceIndex);
	local base, adjust, totalCost = GetArtifactProgress();
	local artifactName, introText, rarity, icon, description, numSockets, art = GetActiveArtifactByRace(raceIndex);
	local _, link = GetItemInfo(artifactName);
	if (link) then
		artifactName = link;
	else
		-- fake link for items we don't know about
		local _, _, _, colorCode = GetItemQualityColor(1);
		if (rarity == 1) then
			_, _, _, colorCode = GetItemQualityColor(3);
		end
		artifactName = string.format("|c%s|H%s:%d|h[%s]|h|r", colorCode, FDA_LINK_TYPE, raceIndex, artifactName);
	end
	local message = string.format(FDA_STATUS_BASIC, raceName, artifactName, base, totalCost);

	-- query item info even if we don't need it so it's likelier cached once we do
	local keystoneName = GetItemInfo(keystoneItemID);

	local usableKeystones, adjust, inBank = FDA_GetKeystoneInfo(numSockets, keystoneItemID, base, totalCost);
	if (usableKeystones > 0) then
		local _, _, _, colorCode = GetItemQualityColor(2);
		message = message .. " |c"..colorCode.. string.format(FDA_STATUS_KEYSTONES, usableKeystones, keystoneName, base + adjust, totalCost).."|r";
	end
	if (inBank > 0) then
		message = message .." ".. string.format(FDA_KEYSTONES_IN_BANK, inBank, GetItemInfo(keystoneItemID));
	end
	
	if (not noErrorFrame) then
		UIErrorsFrame:AddMessage(message, 0, 1, 1, 1);
	end
	-- add solve "button" (if applicable) as another hyperlink 
	if (base + adjust >= totalCost) then
		message = message .. string.format(" %s|H%s:%d|h[%s]|h|r", NORMAL_FONT_COLOR_CODE, FDA_SOLVE_LINK_TYPE, raceIndex, SOLVE);
	end
	
	DEFAULT_CHAT_FRAME:AddMessage(message, 0, 1, 1, 1);
	
	FDA_NeedUpdateForRaceIndex = nil;
end

function FDA_GetKeystoneInfo(numSockets, keystoneItemID, base, totalCost)
	local keystoneCount = GetItemCount(keystoneItemID);
	local countIncludingBank = GetItemCount(keystoneItemID, true);
	local usableKeystones = math.min(numSockets, keystoneCount);
	local keystonesNeeded = math.ceil((totalCost - base) / FDA_KEYSTONE_FRAGMENT_EQUIVALENT); 
	if (FDA_IgnoreKeystones == nil) then
		FDA_IgnoreKeystones = {};
	end
	if (FDA_IgnoreKeystones[keystoneItemID]) then
		usableKeystones = math.min(usableKeystones, keystonesNeeded);
	end
	return usableKeystones, usableKeystones * FDA_KEYSTONE_FRAGMENT_EQUIVALENT, countIncludingBank - keystoneCount;
end
	
------------------------------------------------------
-- Run-time loading
------------------------------------------------------
		
FDA_EventFrame = CreateFrame("Frame", nil, nil);
FDA_EventFrame:SetScript("OnEvent", FDA_OnEvent);
FDA_EventFrame:RegisterEvent("ADDON_LOADED");
FDA_EventFrame:RegisterEvent("ARTIFACT_COMPLETE");
FDA_EventFrame:RegisterEvent("ARTIFACT_UPDATE");
FDA_EventFrame:RegisterEvent("CHAT_MSG_CURRENCY");
FDA_EventFrame:RegisterEvent("ARTIFACT_HISTORY_READY");

GameTooltip:HookScript("OnTooltipSetItem", FDA_OnTooltipSetItem);
ItemRefTooltip:HookScript("OnTooltipSetItem", FDA_OnTooltipSetItem);

FDA_orig_SetItemRef = SetItemRef;
SetItemRef = FDA_SetItemRef;

RequestArtifactCompletionHistory();

-- Register Slash Commands
SLASH_GFW_DIGGERAID1 = "/diggeraid";
SLASH_GFW_DIGGERAID2 = "/dig";
SlashCmdList["GFW_DIGGERAID"] = function(msg)
	FDA_ChatCommandHandler(msg);
end
