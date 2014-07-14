local Plugin = Plugin

local Shine = Shine
local SGUI = Shine.GUI
local Round = math.Round
local StringFormat = string.format
local Unpack = unpack

local PlayerData = {}
local CaptainMenu = {}

function CaptainMenu:Create()
	local ScreenWidth = Client.GetScreenWidth()
	local ScreenHeight = Client.GetScreenHeight()
	
	local Panel = SGUI:Create("Panel")
	Panel:SetupFromTable{
		Anchor = "TopLeft",
		Size = Vector( ScreenWidth * 0.8, ScreenHeight * 0.8, 0 ),
		Pos = Vector( ScreenWidth * 0.1, ScreenHeight * 0.1, 0 )
	}
	Panel:SkinColour()
	Panel:SetIsVisible( false )
	
	self.Panel = Panel
	
	local PanelSize = Panel:GetSize()	
	local Skin = SGUI:GetSkin()
	
	local TitlePanel = SGUI:Create( "Panel", Panel )
	TitlePanel:SetSize( Vector( PanelSize.x, 40, 0 ) )
	TitlePanel:SetColour( Skin.WindowTitle )
	TitlePanel:SetAnchor( "TopLeft" )

	local TitleLabel = SGUI:Create( "Label", TitlePanel )
	TitleLabel:SetAnchor( "CentreMiddle" )
	TitleLabel:SetFont( "fonts/AgencyFB_small.fnt" )
	TitleLabel:SetText( "Captain Mode Menu" )
	TitleLabel:SetTextAlignmentX( GUIItem.Align_Center )
	TitleLabel:SetTextAlignmentY( GUIItem.Align_Center )
	TitleLabel:SetColour( Skin.BrightText )

	local CloseButton = SGUI:Create( "Button", TitlePanel )
	CloseButton:SetSize( Vector( 36, 36, 0 ) )
	CloseButton:SetText( "X" )
	CloseButton:SetAnchor( "TopRight" )
	CloseButton:SetPos( Vector( -41, 2, 0 ) )
	CloseButton.UseScheme = false
	CloseButton:SetActiveCol( Skin.CloseButtonActive )
	CloseButton:SetInactiveCol( Skin.CloseButtonInactive )
	CloseButton:SetTextColour( Skin.BrightText )

	function CloseButton.DoClick()
		self:SetIsVisible( false )
	end
	
	local ListTitles = { "Ready Room", "Team 1", "Team 2" }
	self.ListItems = {}
	for i = 0, 2 do
		local ListTitlePanel = Panel:Add( "Panel" )
		ListTitlePanel:SetSize( Vector( PanelSize.x * 0.74, PanelSize.y * 0.05, 0 ))
		ListTitlePanel:SetColour( Skin.WindowTitle )
		ListTitlePanel:SetAnchor( "TopLeft" )
		ListTitlePanel.Pos = Vector( PanelSize.x * 0.02, PanelSize.y * ( 0.1 + 0.25 * i ) + 15 * i, 0 )
		ListTitlePanel:SetPos( ListTitlePanel.Pos )
		
		local ListTitleText = ListTitlePanel:Add( "Label" )
		ListTitleText:SetAnchor( "CentreMiddle" )
		ListTitleText:SetFont( "fonts/AgencyFB_small.fnt" )
		ListTitleText:SetText( ListTitles[ i + 1 ] )
		ListTitleText:SetTextAlignmentX( GUIItem.Align_Center )
		ListTitleText:SetTextAlignmentY( GUIItem.Align_Center )
		ListTitleText:SetColour( Skin.BrightText )
		
		local List = Panel:Add( "List" )
		List:SetAnchor( "TopLeft" )
		List.Pos = Vector( PanelSize.x * 0.02, PanelSize.y * ( 0.15 + 0.25 * i ) + 15 * i, 0 )
		List:SetPos( List.Pos )
		List:SetColumns( 6, "Name", "Playtime", "Skill", "W/L", "K/D", "Score/D" )
		List:SetSpacing( 0.3, 0.15, 0.15, 0.1, 0.15, 0.15 )
		List:SetSize( Vector( PanelSize.x * 0.74, PanelSize.y * 0.2, 0 ) )
		List:SetNumericColumn( 2 )
		List:SetNumericColumn( 3 )
		List:SetNumericColumn( 4 )
		List:SetNumericColumn( 5 )
		List.ScrollPos = Vector( 0, 32, 0 )
		List.TableIds = {}
		List.SteamIds = {}
		List.Data = {}
		List.TitlePanel = ListTitlePanel
		
		self.ListItems[ i + 1 ] = List
	end
	
	local CommandPanel = Panel:Add( "Panel" )
	CommandPanel:SetupFromTable{ 
		Anchor = "TopRight",
		Size = Vector( PanelSize.x * 0.2, PanelSize.y * 0.8, 0 ),
		Pos = Vector( PanelSize.x * -0.22, PanelSize.y * 0.1, 0 )
	}
	CommandPanel:SkinColour()
	self.CommandPanel = CommandPanel
	
	local CommandPanelSize = CommandPanel:GetSize()
	
	local Label = CommandPanel:Add( "Label" )
	Label:SetFont( "fonts/AgencyFB_small.fnt" )
	Label:SetBright( true )
	Label:SetText( TextWrap( Label, "Select a player and the command to run.", 0, CommandPanelSize.y ) )
	self.Label = Label
	
	local Commands = CommandPanel:Add( "CategoryPanel")
	Commands:SetAnchor( "TopLeft" )
	Commands:SetPos( Vector( 0, Label:GetSize().y + 20, 0 ) )
	Commands:SetSize( Vector( CommandPanelSize.x , CommandPanelSize.y - Label:GetSize().y - 20, 0 ) )
	self.Commands = Commands
		
	self.Created = true
end

local Categories = {
	["Vote Captain"] = {
		{ "Vote", function( self, SteamId )
				Shared.ConsoleCommand( StringFormat( "sh_votecaptain %s", SteamId ) )
			end
		}
	},
	["Team Organization"] = {
		{ "Add Player", function( self, SteamId )
				Shared.ConsoleCommand( StringFormat( "sh_captain_addplayer %s", SteamId ) )
			end
		},
		{ "Remove Player", function( self, SteamId )
				Shared.ConsoleCommand( StringFormat( "sh_captain_removeplayer %s", SteamId ) )
			end
		},
		{ "Set Ready!", function( self )
				Shared.ConsoleCommand( "sh_ready" )
				self:SetText( self:GetText() == "Set Ready!" and "Set Not Ready!" or "Set Ready!" )
			end
		}
	}
}

function CaptainMenu:AddCategory( Name )
	local Commands = self.Commands
	local CommandPanel = self.CommandPanel
	local Lists = self.ListItems
	
	local function GenerateButton( Text, DoClick )
		local Button = SGUI:Create( "Button" )
		Button:SetSize( Vector( CommandPanel:GetSize().x, 32, 0 ) )
		Button:SetText( Text )
		Button:SetFont( "fonts/AgencyFB_small.fnt" )
		Button.DoClick = function( Button )
			local SteamId 
			for i = 1, #Lists do
				local List = Lists[ i ]
				local ListRow = List:GetSelectedRow()
				if ListRow then					
					SteamId = List.SteamIds[ ListRow:GetColumnText( 1 ) ]
					break
				end
			end
			DoClick( Button, SteamId )
		end

		return Button
	end
	
	if not Categories[ Name ] then return end
	
	Commands:AddCategory( Name )
	for i = 1, #Categories[ Name ] do
		local CategoryEntry = Categories[ Name ][ i ]
		Commands:AddObject( Name, GenerateButton( CategoryEntry[ 1 ], CategoryEntry[ 2 ] ) )
	end
end

function CaptainMenu:RemoveCategory( Name )
	self.Commands:RemoveCategory( Name )
end

function CaptainMenu:UpdatePlayer( Message )
	if not self.Created then return end
	
	for i = 1, 3 do
		local List = self.ListItems[i]
		if List.TableIds[ Message.steamid ] then
			List:RemoveRow( List.TableIds[ Message.steamid ] )
			List.TableIds[ Message.steamid ] = nil
			List.SteamIds[ Message.name ] = nil
			break
		end
	end
	
	if Message.team > 2 then return end 
	
	local List = self.ListItems[ Message.team + 1 ]
	if Message.deaths < 1 then Message.deaths = 1 end
	if Message.loses < 1 then Message.loose = 1 end
	
	local playtime = Round( Message.playtime / 3600, 2 )
	local kd = Round( Message.kills / Message.deaths, 2 )
	local sm = Round( Message.score / Message.deaths, 2 )
	local wl = Round( Message.wins / Message.loses, 2 )
	
	List.Data[ List.RowCount + 1 ] = { Message.name, playtime, Message.skill, wl, kd, sm, Message.votes }
	List:AddRow( Unpack( List.Data[ List.RowCount + 1 ] ) )
	List.TableIds[ Message.steamid ] = List.RowCount
	List.SteamIds[ Message.name ] = Message.steamid
end

function CaptainMenu:SetIsVisible( Bool )	
	self.Panel:SetIsVisible( Bool )
	
	if Bool and not self.Visible then
		SGUI:EnableMouse( true )
	elseif not Bool and self.Visible then
		SGUI:EnableMouse( false )
	end

	self.Visible = Bool
end

function CaptainMenu:PlayerKeyPress( Key, Down )
	if not self.Visible then return end
	
	if Key == InputKey.Escape and Down then
		self:SetIsVisible( false )
		return true
	end
end

function CaptainMenu:Destroy()
	self.Panel:Destroy()
end

function Plugin:Initialise()
	self.Enabled = true
	CaptainMenu:Create()
	self:SetupAdminMenuCommands()
	return true
end

function Plugin:SetupAdminMenuCommands()
    local Category = "Captains Mode"

    self:AddAdminMenuCommand( Category, "Set Captain", "sh_setcaptain", false )
    self:AddAdminMenuCommand( Category, "Remove Captain", "sh_removecaptain", false, {
		"Team 1", "1",
		"Team 2", "2",
	} )
end

local Messages = {	
	"Captain Mode enabled",
	"Waiting for %s Player to join the Server before starting a Vote for Captains",
	"Vote for Captains is currently running",
	"Waiting for Captains to set up Teams.\n And to set their Teams to be ready",
	"Currently a round has been started.\n Please Wait for a Captain to pick you up"
}

function Plugin:StartMessage()
	self:CreateTextMessage
	self:CreateTimer( "TextMessage", 1800, -1, function() self:CreateTextMessage end )
end

function Plugin:CreateTextMessage()
	Shine:AddMessageToQueue( 16, 0.05, 0.25, StringFormat("%s\n%s" Messages[ 1 ], Message[ self.dt.State + 2 ] ), 1800, r, g, b, 0, 1, 0 )
end

function Plugin:UpdateTextMessage()
	if not self:TimerExists( "TextMessage" ) then
		self:StartMessage()
	else
		Shine:UpdateMessageText( { ID = 16, Message = StringFormat("%s\n%s" Messages[ 1 ], Message[ self.dt.State + 2 ] ) } )
	end
end

function Plugin:RemoveTextMessage()
	Shine:RemoveMessage( 16 )
	self:DestroyTimer( "TextMessage" )
end

function Plugin:ChangeState( OldState, NewState )
	local PanelSize = CaptainMenu.Panel:GetSize()
	if NewState == 1 then
		CaptainMenu.ListItems[ 1 ]:SetSize( Vector( PanelSize.x * 0.74, PanelSize.y * 0.8, 0 ) )
		for i = 2, 3 do
			local List = CaptainMenu.ListItems[ i ]
			List:SetPos( Vector( PanelSize.x * 2, PanelSize.y * 2, 0 ) )
			List.TitlePanel:SetPos( Vector( PanelSize.x * 2, PanelSize.y * 2, 0 ) )
		end
	else
		CaptainMenu.ListItems[ 1 ]:SetSize( Vector( PanelSize.x * 0.74, PanelSize.y * 0.2, 0 ) )
		for i = 2, 3 do
			local List = CaptainMenu.ListItems[ i ]
			List:SetPos( List.Pos )
			List.TitlePanel:SetPos( List.TitlePanel.Pos )
		end
	end
	
	local Player = Client.GetLocalPlayer()
	local TeamNumber = Player and Player:GetTeamNumber() or 0
	if NewState == 3 and ( TeamNumber == 1 or TeamNumber == 2 ) then
		self:RemoveTextMessage()
	else
		self:UpdateMessageText()
	end
	
end

function Plugin:ReceiveCaptainMenu()
	CaptainMenu:SetIsVisible( true )
end

local LocalId
local LocalTeam = 0
function Plugin:ReceivePlayerData( Message )
	if not LocalId then
		LocalId = tostring(Client.GetSteamId())
	end
	
	if Message.steamid == LocalId then
		LocalTeam = Message.team
	end
	
	CaptainMenu:UpdatePlayer( Message )
end

local first
function Plugin:PlayerKeyPress( Key, Down, Amount )
	if not first then
		self:StartMessage()
		first = true
	end
	
	return CaptainMenu:PlayerKeyPress( Key, Down )
end

function Plugin:ReceiveSetCaptain( Message )
	local SteamId = Message.steamid
	local TeamNumber = Message.team
	
	if not LocalId then
		LocalId = tostring(Client.GetSteamId())
	end
	
	if LocalId == SteamId then
		if Message.add then
			CaptainMenu:AddCategory( "Team Organization" )
		else
			CaptainMenu:RemoveCategory( "Team Organization" )
		end
	end
end

function Plugin:ReceiveVoteState( Message )
	if Message.team > 0 and Message.team ~= LocalTeam then return end
	
	local List = CaptainMenu.ListItems[ Message.team + 1 ]
	if Message.start then
		CaptainMenu:AddCategory( "Vote Captain" )
		
		local Data = List.Data
		local RowCount = #Data 
		for i = 0, RowCount - 1 do
			List:RemoveRow( RowCount - i ) 
		end
		List:SetSpacing( 0.3, 0.15, 0.15, 0.1, 0.1, 0.1, 0.1 )
		List:SetColumns( 7, "Name", "Playtime", "Skill", "W/L", "K/D", "Score/D", "Votes" )
		for i = 1, RowCount do
			List:AddRow( Unpack( Data[i] ) ) 
		end
	else
		
		local Data = List.Data
		local RowCount = #Data 
		for i = 0, RowCount - 1 do
			List:RemoveRow( RowCount - i ) 
		end
		List:SetColumns( 6, "Name", "Playtime", "Skill", "W/L", "K/D", "Score/D" )
		List:SetSpacing( 0.3, 0.15, 0.15, 0.1, 0.15, 0.15 )
		for i = 1, RowCount do
			List:AddRow( Unpack( Data[i] ) ) 
		end
		
		CaptainMenu:RemoveCategory( "Vote Captain" )
	end
end

function Plugin:Cleanup()
	CaptainMenu:Destroy()
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end

--Shine Vote Menu
Shine.VoteMenu:EditPage( "Main", function( self )
    self:AddSideButton( "Captain Mode Menu", function()
		Shared.ConsoleCommand( "sh_captainmenu" )
        self:SetIsVisible( false )
    end )
end )

