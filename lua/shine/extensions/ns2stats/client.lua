--[[
Shine ns2stats plugin. - Client
]]

local Plugin = Plugin

local Shine = Shine
local Notify = Shared.Message

local SendMapData
local WebsiteApiUrl

--Get Mapdata
Shine.Hook.Add( "Think", "MinimapHook", function()
    if GUIMinimap then
        --wait for Config from Server
        if SendMapData then                
            Shine.Hook.SetupClassHook("GUIMinimap","ShowMap","Mapdata","PassivePost" ) 
            Shine.Hook.Remove( "Think", "MinimapHook" )
        end    
    end
end )

function Plugin:Initialise()
    self.Enabled = true
    Shine.AddStartupMessage("Shine NS2Stats.com Plugin is running. Please use sh_verify to set yourself as server admin at NS2Stats.com")   
    return true 
end

function Plugin:ReceiveStatsConfig( Message )
     WebsiteApiUrl = Message.WebsiteApiUrl
     SendMapData = Message.SendMapData    
end

function Plugin:ReceiveStatsAwards( Message )
    local AwardMessage = Message.message
    local Duration = Message.duration
    local ScreenText = Shine:AddMessageToQueue( 2, 0.95, 0.4, AwardMessage, Duration, Message.colourr, Message.colourg, Message.colourb, 2 )
    ScreenText.Obj:SetText(ScreenText.Text)
end

local a
function Plugin:Mapdata(GUIMinimap)
    if a then return end
    a = true   
    if SendMapData or math.random(1,100) == 50 then
                    
        local jsonvalues = {
            scaleX = Client.minimapExtentScale.x,
            scaleY = Client.minimapExtentScale.y,
            scaleZ = Client.minimapExtentScale.z,
            originX = Client.minimapExtentOrigin.x,
            originY = Client.minimapExtentOrigin.y,
            originZ = Client.minimapExtentOrigin.z,
            plotToMapLin_X = GUIMinimap.plotToMapLinX,
            plotToMapLin_Y = GUIMinimap.plotToMapLinY,
            plotToMapConst_x = GUIMinimap.plotToMapConstX,
            plotToMapConst_y = GUIMinimap.plotToMapConstY,
            backgroundWidth = GUIMinimap.kBackgroundWidth,
            backgroundHeight = GUIMinimap.kBackgroundHeight,
            scale = GUIMinimap.scale
        }
        if not jsonvalues.plotToMapLin_X or not jsonvalues.scale or not jsonvalues.scaleX then a = false return end --check if datas are valid        
        local params =
        {
            secret = "jokukovasalasana",
            mapName = Shared.GetMapName(),
            jsonvalues = json.encode(jsonvalues)
        }
        Shared.SendHTTPRequest(WebsiteApiUrl .."/updatemapdata", "POST", params, function() end)       
    end
 end
 
--Votemenu    
Shine.VoteMenu:AddPage( "Stats", function( self )
    self:AddSideButton( "Show my Stats", function()
       Shared.ConsoleCommand("sh_showplayerstats")
       self:SetPage( "Main" )
       self:SetIsVisible( false )
    end )
    self:AddSideButton( "Show extended Scoreboard", function()
       Shared.ConsoleCommand("sh_showlivestats")
       self:SetPage( "Main" )
       self:SetIsVisible( false )
    end )      
    self:AddSideButton( "Show Server Stats", function()
        Shared.ConsoleCommand("sh_showserverstats")
        self:SetPage( "Main" )
        self:SetIsVisible( false )
    end )
    self:AddSideButton( "Show Last Round Stats", function()
        Shared.ConsoleCommand("sh_showlastround")
        self:SetPage( "Main" )
        self:SetIsVisible( false )
    end )  
    self:AddTopButton( "Back", function()
        self:SetPage( "Main" )
    end )
end )

Shine.VoteMenu:EditPage( "Main", function( self )
    if Plugin.Enabled then
    	self:AddSideButton( "NS2Stats", function()
        self:SetPage( "Stats" ) 
        end)       
    end
end )

function Plugin:Cleanup()
    self.Enabled = false
end