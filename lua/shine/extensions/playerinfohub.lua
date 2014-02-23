--[[
    Shine PlayerInfoHub
]]
local Shine = Shine

local StringFormat = string.format

local HTTPRequest = Shared.SendHTTPRequest

local JsonDecode = json.decode

local Add = Shine.Hook.Add
local Call = Shine.Hook.Call

Shine.PlayerInfoHub = {}

local PlayerInfoHub = Shine.PlayerInfoHub

PlayerInfoHub.Ns2StatsData = {}
PlayerInfoHub.HiveData = {}
PlayerInfoHub.SteamData = {}

PlayerInfoHub.WaitTime = 20
PlayerInfoHub.RetryIntervall = 5

local function FindCharactersBetween( Response, OpeningCharacters, ClosingCharacters )
        local Result

        local IndexOfOpeningCharacters = Response:find( OpeningCharacters )
        
        if IndexOfOpeningCharacters then
                local FoundCharacters = Response:sub( IndexOfOpeningCharacters + #OpeningCharacters )
                local IndexOfClosingCharacters = FoundCharacters:find( ClosingCharacters )
        
                if IndexOfClosingCharacters then
                        FoundCharacters = FoundCharacters:sub( 1, IndexOfClosingCharacters - 1 )
                        FoundCharacters = StringTrim( FoundCharacters )

                        Result = FoundCharacters
                end
        end
        
        return Result
end

local function GetSteamBadgeName( Response )
        return FindCharactersBetween( Response, "<div class=\"badge_info_title\">", "</div>" )
end

function PlayerInfoHub:OnConnect( Client, Timeleft )
    if not Shine:IsValidClient( Client ) then return end
    
    if not Timeleft then Timeleft = self.WaitTime end
    
    local SteamId = Client:GetUserId()
    if not SteamId or SteamId <= 0 then return end
    local SteamId64 = StringFormat( "%s%s", 76561, SteamId + 197960265728 )
    
    if Timeleft < 0 then
        if not self.SteamData[ SteamId ].Badges.Normal then
            self.SteamData[ SteamId ].Badges.Normal = 0
        end
        
        if not self.SteamData[ SteamId ].Badges.Foil then
            self.SteamData[ SteamId ].Badges.Foil = 0
        end
        
        if not self.SteamData[ SteamId ].PlayTime then
           self.SteamData[ SteamId ].PlayTime = -1 
        end
        
        if not self.Ns2StatsData[ SteamId ] then
            self.Ns2StatsData[ SteamId ] = -1
        end
        
        if not self.HiveData[ SteamId ] then
            self.HiveData[ SteamId ] = -1
        end
        
        Call( "OnReceiveSteamData", Client, self.SteamData[ SteamId ] )
        Call( "OnReceiveHiveData", Client, self.HiveData[ SteamId ] )
        Call( "OnReceiveNs2StatsData", Client, self.Ns2StatsData[ SteamId ] )
        
        return
    end
    
    if not self.SteamData[ SteamId ] then 
        self.SteamData[ SteamId ] = {}
        self.SteamData[ SteamId ].Badges = {}
    elseif TimeLeft == self.WaitTime and self.SteamData[ SteamId ].PlayTime and self.SteamData[ SteamId ].Badges.Normal and self.SteamData[ SteamId ].Badges.Foil then
       Call( "OnReceiveSteamData", Client, self.SteamData[ SteamId ] ) 
    end
    
    if not self.SteamData[ SteamId ].PlayTime then
        HTTPRequest( StringFormat( "http://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v0001/?key=2EFCCE2AF701859CDB6BBA3112F95972&SteamId=%s&format=json", SteamId64 ), "GET", function( Response )
            local Temp = JsonDecode( Response )
            Temp = Temp and Temp.response and Temp.response.games
            if not Temp then return end
            for i = 1, #Temp do
                if Temp[ i ].appid == 4920 then
                    PlayerInfoHub.SteamData[ SteamId ].PlayTime = Temp[ i ].playtime_forever and Temp[ i ].playtime_forever * 60
                    if PlayerInfoHub.SteamData[ SteamId ].Badges.Normal and PlayerInfoHub.SteamData[ SteamId ].Badges.Foil then Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] ) end
                    return
                end
            end
        end )
    end
    
    if self.SteamData[ SteamId ].Badges then
        HTTPRequest( StringFormat( "http://steamcommunity.com/profiles/%s/gamecards/4920", SteamId64 ), "GET", function( Response )
            local BadgeName = GetSteamBadgeName( Response )        
            if BadgeName then 
                BadgeName = StringFormat( "steam_%s", BadgeName )
                PlayerInfoHub.SteamData[ SteamId ].Badges.Normal = BadgeName
            else
                PlayerInfoHub.SteamData[ SteamId ].Badges.Normal = 0                
            end
            if PlayerInfoHub.SteamData[ SteamId ].PlayTime and PlayerInfoHub.SteamData[ SteamId ].Badges.Foil then Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] ) end
       end )
    
        --foil
        HTTPRequest( StringFormat( "http://steamcommunity.com/profiles/%s/gamecards/4920?border=1", SteamId64), "GET", function(Response)
            local BadgeName = GetSteamBadgeName( Response )        
            if BadgeName then 
                BadgeName = StringFormat( "steam_%s", BadgeName )
                PlayerInfoHub.SteamData[ SteamId ].Badges.Foil = BadgeName
            else
                PlayerInfoHub.SteamData[ SteamId ].Badges.Foil = 0                
            end
            if PlayerInfoHub.SteamData[ SteamId ].PlayTime and PlayerInfoHub.SteamData[ SteamId ].Badges.Normal then Call( "OnReceiveSteamData", Client, PlayerInfoHub.SteamData[ SteamId ] ) end
        end )
    end
    
    if not self.Ns2StatsData[ SteamId ] then 
        HTTPRequest( StringFormat( "http://ns2stats.com/api/Player?ns2_id=%s", SteamId ), "GET", function( Response )
            PlayerInfoHub.Ns2StatsData[ SteamId ] = JsonDecode( Response ) and JsonDecode( Response )[ 1 ] or 0
            Call( "OnReceiveNs2StatsData", Client, PlayerInfoHub.Ns2StatsData[ SteamId ] )
        end )
    elseif TimeLeft == self.WaitTime then
        Call( "OnReceiveNs2StatsData", Client, self.Ns2StatsData[ SteamId ] )
    end
    
    if not self.HiveData[ SteamId ] then 
        local HURL = StringFormat( "http://sabot.herokuapp.com/api/get/playerData/%s", SteamId )    
        HTTPRequest( HURL, "GET", function( Response )
            PlayerInfoHub.HiveData[ SteamId ] = JsonDecode( Response ) or 0
            Call( "OnReceiveHiveData", Client, PlayerInfoHub.HiveData[ SteamId ] )
        end )    
    elseif TimeLeft == self.WaitTime then
        Call( "OnReceiveHiveData", Client, self.HiveData[ SteamId ] )
    end
  
    Shine.Timer.Simple( self.RetryIntervall, function()
        if self:GetIsRequestFinished( SteamId ) then return end 
        self:OnConnect( Client, Timeleft - 5 ) 
    end )
end

Add( "ClientConnect", "GetPlayerInfo", function( Client )
    PlayerInfoHub:OnConnect( Client ) 
end )


function PlayerInfoHub:GetNs2StatsData( SteamId )
    return self.Ns2StatsData[ SteamId ]
end

function PlayerInfoHub:GetHiveData( SteamId )
    return self.HiveData[ SteamId ]
end

function PlayerInfoHub:GetSteamData( SteamId )
    return self.SteamData[ SteamId ]
end

function PlayerInfoHub:GetWaitTime()
    return self.WaitTime
end

function PlayerInfoHub:SetWaitTime( WaitTime )
    if WaitTime < 1 then return end
    self.WaitTime = WaitTime
end

function PlayerInfoHub:GetRetryIntervall()
    return self.RetryIntervall
end

function PlayerInfoHub:SetRetryIntervall( RetryIntervall )
    if RetryIntervall < 1 then return end
    self.RetryIntervall = RetryIntervall
end

function PlayerInfoHub:GetIsRequestFinished( SteamId )
    return self.SteamData[ SteamId ].PlayTime and self.SteamData[ SteamId ].Badges.Normal and self.SteamData[ SteamId ].Badges.Foil and self.HiveData[ SteamId ] and self.Ns2StatsData[ SteamId ]
end