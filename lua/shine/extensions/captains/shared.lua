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
	self:AddNetworkMessage("VoteState", { team = "integer (0 to 3)", start = "boolean" }, "Client" )
	
	self:AddDTVar( "integer (0 to 10)", "State", 0 )
end

function Plugin:NetworkUpdate( Key, OldValue, NewValue )
	if OldValue == NewValue then return end
	self:ChangeState( OldValue, NewValue )
end

Shine:RegisterExtension( "captains", Plugin )