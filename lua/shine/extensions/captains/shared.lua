local Plugin = {}
local Shine = Shine

function Plugin:SetupDataTable()
	self:AddNetworkMessage("CaptainMenu", {}, "Client")
	
	local PlayerData = {
		steamid = "string (255)",
		name = "string (255)",
		kills = "integer",
		deaths = "integer",
		playtime = "integer",
		score = "integer",
		skill = "integer",
		votes = "integer (0 to 200)",
		team = "integer (0 to 3)",
		wins = "integer",
		loses = "integer"
	}
	self:AddNetworkMessage("PlayerData", PlayerData, "Client")
	self:AddNetworkMessage("SetCaptain", { steamid = "string (255)", team = "integer (1 to 2)",  add = "boolean" }, "Client" )
	self:AddNetworkMessage("VoteState", { team = "integer (0 to 3)", start = "boolean", timeleft = "integer (0 to 3600)" }, "Client" )
	
	local Messages =
	{
		text = "string (255)",
		id = "integer (1 to 7)",
	}
	self:AddNetworkMessage( "InfoMsgs", Messages, "Client" )
	
	local Config =
	{
		x = "float (0 to 1 by 0.01)",
		y = "float (0 to 1 by 0.01)",
		r = "integer (0 to 255)",
		g = "integer (0 to 255)",
		b = "integer (0 to 255)",
	}
	self:AddNetworkMessage( "MessageConfig", Config, "Client" )
	
	local TeamInfo = {
		number = "integer (1 to 2)",
		teamnumber = "integer (1 to 2)",
		name = "string (255)",
		wins = "integer",
	}
	self:AddNetworkMessage( "TeamInfo", TeamInfo, "Client" )
	
	self:AddNetworkMessage( "OnResolutionChanged", {}, "Server")
	
	self:AddDTVar( "integer (0 to 10)", "State", 0 )
end

Shine:RegisterExtension( "captains", Plugin )

--noinspection UnusedDef
function Plugin:NetworkUpdate( Key, OldValue, NewValue )
	if OldValue == NewValue then return end
	self:ChangeState( OldValue, NewValue )
end