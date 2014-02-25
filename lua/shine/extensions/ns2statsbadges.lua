--[[
    Shine Ns2Stats Badges
]]
Script.Load( "lua/shine/core/server/playerinfohub.lua" )

local Shine = Shine

local Plugin = {}

Plugin.Version = "1.5"

Plugin.HasConfig = true

Plugin.ConfigName = "Ns2StatsBadges.json"
Plugin.DefaultConfig =
{
    Flags = true,
    SteamBadges = true,
}
Plugin.CheckConfig = true

--fix for no badge showing up
local function AvoidEmptyBadge( Client, Badge )
    if getClientBadgeEnum( Client ) == kBadges.None then
       setClientBadgeEnum( Client, kBadges[Badge] ) 
    end
end

function Plugin:OnReceiveSteamData( Client, SteamData )
    if not self.Config.SteamBadges then return end
 
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end

    local SetNormalBagde    
    if SteamData.Badges.Normal and SteamData.Badges.Normal ~= 0 then
        SetNormalBagde = GiveBadge( ClientId, SteamData.Badges.Normal )
    end    
    
    if SetNormalBagde then
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage( -1, kBadges[ SteamData.Badges.Normal ]), true )
        AvoidEmptyBadge( Client, SteamData.Badges.Normal )
        
        -- give default badge (disabled)
        GiveBadge( ClientId, "disabled" )
        Server.SendNetworkMessage( Client, "Badge", BuildBadgeMessage( -1, kBadges[ "disabled" ]), true ) 
    end
    
    local SetFoilBagde    
    if SteamData.Badges.Foil and SteamData.Badges.Foil ~= 0 then
        SetFoilBagde = GiveBadge( ClientId, SteamData.Badges.Foil )
    end    
    
    if SetFoilBagde then
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage( -1, kBadges[ SteamData.Badges.Foil ]), true )
        AvoidEmptyBadge( Client, SteamData.Badges.Foil )
        
        -- give default badge (disabled)
        GiveBadge( ClientId, "disabled" )
        Server.SendNetworkMessage( Client, "Badge", BuildBadgeMessage( -1, kBadges[ "disabled" ]), true ) 
    end
end

function Plugin:OnReceiveNs2StatsData( Client, Ns2StatsData )
    if not self.Config.Flags then return end
    
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
    
    local SetBagde
    local Nationality = type( Ns2StatsData ) == "table" and tostring( Ns2StatsData.nationality ) or "UNO"
    
    SetBagde = GiveBadge( ClientId, Nationality )
    
    if not SetBagde then
        Nationality = "UNO"
        SetBagde = GiveBadge( ClientId, Nationality )
    end
    
    if SetBagde then
        -- send bagde to Clients        
        Server.SendNetworkMessage(Client, "Badge", BuildBadgeMessage( -1, kBadges[ Nationality ]), true )
        AvoidEmptyBadge( Client, Nationality )
        
        -- give default badge (disabled)
        GiveBadge( ClientId, "disabled" )
        Server.SendNetworkMessage( Client, "Badge", BuildBadgeMessage( -1, kBadges[ "disabled" ]), true ) 
    end
end

Shine:RegisterExtension( "ns2statsbadges", Plugin )