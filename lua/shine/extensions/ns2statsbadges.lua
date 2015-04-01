--[[
    Shine Ns2Stats Badges
]]

local Shine = Shine
local InfoHub = Shine.PlayerInfoHub

local Plugin = {}

local Notify = Shared.Message

Plugin.Version = "1.5"

Plugin.HasConfig = true

Plugin.ConfigName = "Ns2StatsBadges.json"
Plugin.DefaultConfig =
{
    Flags = true,
    SteamBadges = true,
}
Plugin.CheckConfig = true

function Plugin:Initialise()
	self.Enabled = true
	
    if self.Config.Flags then
        InfoHub:Request("NS2StatsBadges", "GEODATA")
    end

    if self.Config.SteamBadges then
        InfoHub:Request("NS2StatsBadges", "STEAMBADGES")
    end
	
	return true
end

function Plugin:SetBadge( Client, Badge, Row )
    if not ( Badge or Client ) then return end
    
    if not GiveBadge then
		if self.Enabled then
			Notify( "[ERROR]: The Ns2StatsBadge plugin does not work without the Badges+ Mod !" )
            Shine:UnloadExtension( "ns2statsbadges" )
        end
        return
    end
 
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
    
    local SetBadge = GiveBadge( ClientId, Badge, Row )
    if not SetBadge then return end
    
    GiveBadge( ClientId, "disabled", Row )
    
    return true
end

local SteamBadges = {
    "steam_Rookie",
    "steam_Squad Leader",
    "steam_Veteran",
    "steam_Commander",
    "steam_Special Ops"
}

function Plugin:OnReceiveSteamData( Client, SteamData )
    if not self.Config.SteamBadges then return end
    
    if SteamData.Badges.Normal and SteamData.Badges.Normal > 0 then
        self:SetBadge( Client, SteamBadges[SteamData.Badges.Normal] )
    end
        
    if SteamData.Badges.Foil and SteamData.Badges.Foil == 1 then
        self:SetBadge( Client, "steam_Sanji Survivor" )
    end
end

function Plugin:OnReceiveGeoData( Client, GeoData )
    if not self.Config.Flags then return end
    
    local Nationality = GeoData.country_code or "UNO"
    local SetBagde = self:SetBadge( Client, Nationality, 2 )
    
    if not SetBagde then
        Nationality = "UNO"
        self:SetBadge( Client, Nationality, 2 )
    end
end

function Plugin:CleanUp()
    InfoHub:RemoveRequest("NS2StatsBadges")

    self.BaseClass.Cleanup( self )

    self.Enabled = false
end

Shine:RegisterExtension( "ns2statsbadges", Plugin )