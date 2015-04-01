--[[
	Shine PlayerInfoHub
]]
local Shine = Shine

local StringFormat = string.format
local JsonDecode = json.decode

local Add = Shine.Hook.Add

Shine.PlayerInfoHub = {}
local PlayerInfoHub = Shine.PlayerInfoHub

PlayerInfoHub.Ns2StatsData = {}
PlayerInfoHub.SteamData = {}
PlayerInfoHub.GeoData = {}

local function Call( Name, Client, ... )
	if not Shine:IsValidClient( Client ) then return end
	Shine.Hook.Call( Name, Client, ... )
end

local Queue = {}
local current = 0
local last = 0
local working = false

local function ProcessQueue()
	PROFILE("PlayerInfoHub:ProcessQueue()")
	working = true
	current = current + 1

	local node = Queue[current]

	local function OnSuccess( Response )
		node[2](Response)

		if current < last then
			ProcessQueue()
		else
			working = false
		end
	end

	local function OnTimeout()
		node[3]()

		if current < last then
			ProcessQueue()
		else
			working = false
		end
	end

	Shine.TimedHTTPRequest(node[1], "GET", OnSuccess, OnTimeout)
end

local function AddToHTTPQueue( Address, OnSuccess, OnTimeout)
	last = last + 1
	Queue[last] = {
		Address,
		OnSuccess,
		OnTimeout
	}

	if not working then ProcessQueue() end
end

--[[
--Datatypes:
 - NS2STATS
 - STEAMPLAYTIME
 - STEAMBADGES
 - STEAMBANS
 - GEOIP
 ]]
PlayerInfoHub.Requests = {
	NS2STATS = {},
	STEAMPLAYTIME = {},
	STEAMBADGES = {},
	STEAMBANS = {},
	GEODATA = {}
}

PlayerInfoHub.HiveQueue = {}

function PlayerInfoHub:Request( Name, DataType)
	if not Name or not DataType then return end

	if type(DataType) == "table" then
		for _, type in ipairs(DataType) do
			table.insert(self.Requests[type], Name)
		end
	else
		table.insert(self.Requests[DataType], Name)
	end


	for _, client in ipairs(Shine.GetAllClients()) do
		self:OnConnect(client)
	end
end

function PlayerInfoHub:RemoveRequest( Name, DataType)
	if not DataType then
		for _, type in pairs(self.Requests) do
			for i, name in ipairs(type) do
				if name == Name then
					table.remove(type, i)
				end
			end
		end
	else
		for i, name in ipairs(self.Requests[DataType]) do
			if name == Name then
				table.remove(type, i)
			end
		end
	end
end

function PlayerInfoHub:OnConnect( Client )
	PROFILE("PlayerInfoHub:OnConnect()")
	if not Shine:IsValidClient( Client ) then return end

	local SteamId = Client:GetUserId()
	if not SteamId or SteamId <= 0 then return end
	local SteamId64 = StringFormat( "%s%s", 76561, SteamId + 197960265728 )

	if not self.SteamData[ SteamId ] then
		self.SteamData[ SteamId ] = {}
		self.SteamData[ SteamId ].Badges = {}
	end

	if not Shine.IsNS2Combat and not self:GetHiveData( SteamId ) then
		self.HiveQueue[ SteamId ] = true
		Shine.Timer.Create( StringFormat("HiveRequest%s", SteamId), 5, 1, function()
			PlayerInfoHub.HiveQueue[ SteamId ] = nil
		end )
	end

	--[[
	-- Status:
	 - -2 = Fetching
	 - -1 = Timeout
	 ]]
	if not self.SteamData[ SteamId ].PlayTime and self.Requests.STEAMPLAYTIME[1] then
		PlayerInfoHub.SteamData[ SteamId ].PlayTime = -2

		AddToHTTPQueue( StringFormat( "http://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=2EFCCE2AF701859CDB6BBA3112F95972&SteamId=%s&appids_filter[0]=4920", SteamId64 ), function( Response )
			local Temp = JsonDecode( Response )

			Temp = Temp and Temp.response and Temp.response.games and Temp.response.games[1]
			if not Temp then
				PlayerInfoHub.SteamData[ SteamId ].PlayTime = 0
				return
			else
				PlayerInfoHub.SteamData[ SteamId ].PlayTime = Temp.playtime_forever and Temp.playtime_forever * 60 or 0
			end

			if not PlayerInfoHub.Requests.STEAMBADGES[1] or PlayerInfoHub.SteamData[ SteamId ].Badges.Normal ~= -2 and
					(not PlayerInfoHub.Requests.STEAMBANS[1] or PlayerInfoHub.SteamData[ SteamId ].Bans ~= -2) then
				Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] )
			end
		end, function()
			PlayerInfoHub.SteamData[ SteamId ].PlayTime = -1
			if not PlayerInfoHub.Requests.STEAMBADGES[1] or PlayerInfoHub.SteamData[ SteamId ].Badges.Normal ~= -2 and
					(not PlayerInfoHub.Requests.STEAMBANS[1] or PlayerInfoHub.SteamData[ SteamId ].Bans ~= -2) then
				Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] )
			end
		end )
	end

	if not self.SteamData[ SteamId ].Bans and self.Requests.STEAMBANS[1] then
		self.SteamData[ SteamId ].Bans = -2
		AddToHTTPQueue( StringFormat( "http://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=2EFCCE2AF701859CDB6BBA3112F95972&steamids=%s", SteamId64 ),function( Response )
			local data = JsonDecode( Response )
			PlayerInfoHub.SteamData[ SteamId ].Bans = data and data.players and data.players[1] or 0

			if (not PlayerInfoHub.Requests.STEAMPLAYTIME[1] or PlayerInfoHub.SteamData[ SteamId ].Playtime ~= -2) and
					(not PlayerInfoHub.Requests.STEAMBADGES[1] or PlayerInfoHub.SteamData[ SteamId ].Badges.Normal ~= -2) then
				Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] )
			end
		end, function()
			PlayerInfoHub.SteamData[ SteamId ].Bans = -1

			if (not PlayerInfoHub.Requests.STEAMPLAYTIME[1] or PlayerInfoHub.SteamData[ SteamId ].Playtime ~= -2) and
					(not PlayerInfoHub.Requests.STEAMBADGES[1] or PlayerInfoHub.SteamData[ SteamId ].Badges.Normal ~= -2) then
				Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] )
			end
		end)
	end

	if not self.GeoData[ SteamId ] and self.Requests.GEODATA[1] then
		self.GeoData[ SteamId ] = -2

		AddToHTTPQueue( StringFormat( "https://freegeoip.net/json/%s", IPAddressToString( Server.GetClientAddress( Client ) ) ), function( Response )
			local data = JsonDecode( Response )
			PlayerInfoHub.GeoData[ SteamId ] = data or 0

			Call( "OnReceiveGeoData", Client, PlayerInfoHub.GeoData[ SteamId ] )
		end, function()
			PlayerInfoHub.GeoData[ SteamId ] = -1

			Call( "OnReceiveGeoData", Client, PlayerInfoHub.GeoData[ SteamId ] )
		end)
	end

	if not self.SteamData[ SteamId ].Badges.Normal and self.Requests.STEAMBADGES[1] then
		PlayerInfoHub.SteamData[ SteamId ].Badges.Normal = -2

		AddToHTTPQueue( StringFormat( "http://api.steampowered.com/IPlayerService/GetBadges/v1/?key=2EFCCE2AF701859CDB6BBA3112F95972&SteamId=%s", SteamId64 ),function( Response )
			PlayerInfoHub.SteamData[ SteamId ].Badges.Normal = 0
			PlayerInfoHub.SteamData[ SteamId ].Badges.Foil = 0

			local data = JsonDecode( Response )
			local badgedata = data and data.response.badges
			if badgedata then
				for _, badge in ipairs(badgedata) do
					if badge.appid == 4920 then
						if badge.border_color == 1 then
							PlayerInfoHub.SteamData[ SteamId ].Badges.Foil = 1
						else
							PlayerInfoHub.SteamData[ SteamId ].Badges.Normal = badge.level
						end
					end
				end
			end

			if not PlayerInfoHub.Requests.STEAMPLAYTIME[1] or PlayerInfoHub.SteamData[ SteamId ].Playtime ~= -2 and
					(not PlayerInfoHub.Requests.STEAMBANS[1] or PlayerInfoHub.SteamData[ SteamId ].Bans ~= -2) then
				Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] )
			end
		end, function()
			PlayerInfoHub.SteamData[ SteamId ].Badges.Normal = -1
			PlayerInfoHub.SteamData[ SteamId ].Badges.Foil = -1

			if not PlayerInfoHub.Requests.STEAMPLAYTIME[1] or PlayerInfoHub.SteamData[ SteamId ].Playtime ~= -2 and
					(not PlayerInfoHub.Requests.STEAMBANS[1] or PlayerInfoHub.SteamData[ SteamId ].Bans ~= -2) then
				Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] )
			end
		end )
	elseif self.Requests.STEAMBADGES[1] and PlayerInfoHub.SteamData[ SteamId ].Badges.Normal ~= -2 then
		Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] )
	end

	if not self.Ns2StatsData[ SteamId ] and self.Requests.NS2STATS[1] then
		PlayerInfoHub.Ns2StatsData[ SteamId ] = -2
		AddToHTTPQueue( StringFormat( "http://ns2stats.com/api/Player?ns2_id=%s", SteamId ), function( Response )
			local data = JsonDecode( Response )
			PlayerInfoHub.Ns2StatsData[ SteamId ] = data and data[ 1 ] or 0
			Call( "OnReceiveNs2StatsData", Client, PlayerInfoHub.Ns2StatsData[ SteamId ] )
		end, function()
			PlayerInfoHub.Ns2StatsData[ SteamId ] = -1
			Call( "OnReceiveNs2StatsData", Client, PlayerInfoHub.Ns2StatsData[ SteamId ] )
		end )
	elseif self.Requests.NS2STATS[1] and  self.Ns2StatsData[ SteamId ] ~= -2 then
		Call( "OnReceiveNs2StatsData", Client, PlayerInfoHub.Ns2StatsData[ SteamId ] )
	end

end

Add( "ClientConnect", "GetPlayerInfo", function( Client )
	PlayerInfoHub:OnConnect( Client )
end )

Shine.Hook.SetupClassHook("ScoringMixin", "SetPlayerLevel", "OnSetPlayerLevel", "PassivePost")
Add("OnSetPlayerLevel", "HiveRequestFinished", function(Player)
	local Client = Player.GetClient and Player:GetClient()
	local SteamId = Client and Client:GetUserId()

	if SteamId then
		Shine.Timer.Destroy(StringFormat("HiveRequest%s", SteamId))
		PlayerInfoHub.HiveQueue[ SteamId ] = nil
		Call( "OnReceiveHiveData", Client, GetHiveDataBySteamId(SteamId) )
	end
end)

function PlayerInfoHub:GetNs2StatsData( SteamId )
	return self.Ns2StatsData[ SteamId ]
end

function PlayerInfoHub:GetHiveData( SteamId )
	return GetHiveDataBySteamId(SteamId)
end

function PlayerInfoHub:GetSteamData( SteamId )
	return self.SteamData[ SteamId ]
end

function PlayerInfoHub:GetIsRequestFinished( SteamId )
	return (not self.Requests.STEAMPLAYTIME[1] or self.SteamData[ SteamId ].Playtime ~= -2 ) and
			(not self.Requests.STEAMBADGES[1] or self.SteamData[ SteamId ].Badges.Normal ~= -2) and
			(not self.Requests.NS2STATS[1] or self.Ns2StatsData[ SteamId ] ~= -2) and
			(not self.Requests.GEODATA[1] or self.GeoData[ SteamId ] ~= -2) and not self.HiveQueue[ SteamId ]
end