local Plugin = Plugin

local Shine = Shine
local SGUI = Shine.GUI
local Round = math.Round
local StringFormat = string.format
local Unpack = unpack
local ToString = tostring
local ToNumber = tonumber
local TableInsert = table.insert
local TableRemove = table.remove

local PlayerData = {}
local CaptainMenu = {}

local LocalId
local LocalTeam = 0
local Loaded = false

function CaptainMenu:Create()
	if self.Created then return end
	
	self.Windows = {}
	
	local ScreenWidth = Client.GetScreenWidth()
	local ScreenHeight = Client.GetScreenHeight()
	
	local Panel = SGUI:Create("Panel")
	Panel:SetupFromTable{
		Anchor = "TopLeft",
		Size = Vector( ScreenWidth * 0.8, ScreenHeight * 0.8, 0 ),
		Pos = Vector( ScreenWidth * 0.1, ScreenHeight * 0.1, 0 )
	}
	Panel:SkinColour()
	
	self.Panel = Panel
	
	local PanelSize = Panel:GetSize()	
	local Skin = SGUI:GetSkin()
	
	local TitlePanel = SGUI:Create( "Panel", Panel )
	TitlePanel:SetSize( Vector( PanelSize.x, 40, 0 ) )
	TitlePanel:SetColour( Skin.WindowTitle )
	TitlePanel:SetAnchor( "TopLeft" )

	local TitleLabel = SGUI:Create( "Label", TitlePanel )
	TitleLabel:SetAnchor( "CentreMiddle" )
	TitleLabel:SetFont( Fonts.kAgencyFB_Small )
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
		ListTitleText:SetFont( Fonts.kAgencyFB_Small )
		ListTitleText:SetText( ListTitles[ i + 1 ] )
		ListTitleText:SetTextAlignmentX( GUIItem.Align_Center )
		ListTitleText:SetTextAlignmentY( GUIItem.Align_Center )
		ListTitleText:SetColour( Skin.BrightText )
		
		local List = Panel:Add( "List" )
		List:SetAnchor( "TopLeft" )
		List.Pos = Vector( PanelSize.x * 0.02, PanelSize.y * ( 0.15 + 0.25 * i ) + 15 * i, 0 )
		List:SetPos( List.Pos )
		List:SetColumns( 8, "SteamId", "Name", "Playtime", "Skill", "W/L", "K/D", "Score/D", "Votes" )
		List:SetSpacing( 0.15, 0.2, 0.15, 0.1, 0.1, 0.1, 0.1, 0.1 )
		List:SetSize( Vector( PanelSize.x * 0.74, PanelSize.y * 0.2, 0 ) )
		List:SetNumericColumn( 1 )
		List:SetNumericColumn( 3 )
		List:SetNumericColumn( 4 )
		List:SetNumericColumn( 5 )
		List:SetNumericColumn( 6 )
		List:SetNumericColumn( 7 )
		List:SetNumericColumn( 8 )
		List.ScrollPos = Vector( 0, 32, 0 )
		List.TitlePanel = ListTitlePanel
		List.TitleText = ListTitleText
		
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
	Label:SetFont( Fonts.kAgencyFB_Small )
	Label:SetBright( true )
	Label:SetText( WordWrap( Label, "Select a player and the command to run.", 0, CommandPanelSize.x ) )
	self.Label = Label
	
	self.Categories = {}
	local Commands = CommandPanel:Add( "CategoryPanel")
	Commands:SetAnchor( "TopLeft" )
	Commands:SetPos( Vector( 0, Label:GetSize().y + 20, 0 ) )
	Commands:SetSize( Vector( CommandPanelSize.x , CommandPanelSize.y - Label:GetSize().y - 20, 0 ) )
	self.Commands = Commands
	
	Panel:SetIsVisible( false )
	
	self.Created = true
end

local Categories = {
	["Vote Captain"] = {
		{ "Vote", function( self, SteamId )
				Shared.ConsoleCommand( StringFormat( "sh_votecaptain %s", SteamId ) )
			end, 1
		}
	},
	["Team Organization"] = {
		{ "Add Player", function( self, SteamId )
				Shared.ConsoleCommand( StringFormat( "sh_captain_addplayer %s", SteamId ) )
			end, 1
		},
		{ "Remove Player", function( self, SteamId )
				Shared.ConsoleCommand( StringFormat( "sh_captain_removeplayer %s", SteamId ) )
			end, 1
		},
		{ "Set Teamname", function( self )
			end, 2
		},
		{ "Set Ready!", function( self )
				Shared.ConsoleCommand( "sh_ready" )
				self:SetText( self:GetText() == "Set Ready!" and "Set Not Ready!" or "Set Ready!" )
			end, 0
		}
	}
}

function CaptainMenu:DestroyOnClose( Window )
	TableInsert( self.Windows, Window )
	return #self.Windows
end

function CaptainMenu:DontDestroyOnClose( Window )
	if not Window.Id then return end
	TableRemove( self.Windows, Window.Id )
end

function CaptainMenu:UpdateTeam( TeamNumber, Name, Wins )
	if not self.Created then 
		Plugin:SimpleTimer( 1, function() self:UpdateTeam( TeamNumber, Name, Wins ) end )
		return
	end
	
	local TextItem = self.ListItems[ TeamNumber + 1 ].TitleText
	
	local Text = StringFormat( "%s (Wins: %s)", Name, Wins )
	TextItem:SetText( Text )
end

function CaptainMenu:AskForPlayer()
	local Window = SGUI:Create( "Panel" )
	Window:SetAnchor( "CentreMiddle" )
	Window:SetSize( Vector( 400, 200, 0 ) )
	Window:SetPos( Vector( -200, -100, 0 ) )

	Window:AddTitleBar( "Error" )

	Window.Id = self:DestroyOnClose( Window )

	function Window.CloseButton.DoClick()
		Shine.AdminMenu:DontDestroyOnClose( Window )
		Window:Destroy()
	end

	Window:SkinColour()

	local Label = SGUI:Create( "Label", Window )
	Label:SetAnchor( "CentreMiddle" )
	Label:SetFont( Fonts.kAgencyFB_Small )
	Label:SetBright( true )
	Label:SetText( "Please select a single player." )
	Label:SetPos( Vector( 0, -40, 0 ) )
	Label:SetTextAlignmentX( GUIItem.Align_Center )
	Label:SetTextAlignmentY( GUIItem.Align_Center )

	local OK = SGUI:Create( "Button", Window )
	OK:SetAnchor( "CentreMiddle" )
	OK:SetSize( Vector( 128, 32, 0 ) )
	OK:SetPos( Vector( -64, 40, 0 ) )
	OK:SetFont( Fonts.kAgencyFB_Small )
	OK:SetText( "OK" )

	function OK.DoClick()
		Shine.AdminMenu:DontDestroyOnClose( Window )
		Window:Destroy()
	end
end

function CaptainMenu:AskforTeamName()
	local Window = SGUI:Create( "Panel" )
	Window:SetAnchor( "CentreMiddle" )
	Window:SetSize( Vector( 400, 200, 0 ) )
	Window:SetPos( Vector( -200, -100, 0 ) )

	Window:AddTitleBar( "Teamname Needed" )

	Window.Id = self:DestroyOnClose( Window )

	function Window.CloseButton.DoClick()
		Shine.AdminMenu:DontDestroyOnClose( Window )
		Window:Destroy()
	end

	Window:SkinColour()

	local Label = SGUI:Create( "Label", Window )
	Label:SetAnchor( "CentreMiddle" )
	Label:SetFont( Fonts.kAgencyFB_Small )
	Label:SetBright( true )
	Label:SetText( "Please type in your new teamname." )
	Label:SetPos( Vector( 0, -40, -25 ) )
	Label:SetTextAlignmentX( GUIItem.Align_Center )
	Label:SetTextAlignmentY( GUIItem.Align_Center )
	
	local Input = SGUI:Create( "TextEntry", Window )
	Input:SetAnchor( "CentreMiddle" )
	Input:SetFont( Fonts.kAgencyFB_Small )
	Input:SetPos( Vector( -160, -5, 0 ) )
	Input:SetSize( Vector( 320, 32, 0 ) )
	
	local OK = SGUI:Create( "Button", Window )
	OK:SetAnchor( "CentreMiddle" )
	OK:SetSize( Vector( 128, 32, 0 ) )
	OK:SetPos( Vector( -64, 40, 0 ) )
	OK:SetFont( Fonts.kAgencyFB_Small )
	OK:SetText( "OK" )

	function OK.DoClick()
		Shine.AdminMenu:DontDestroyOnClose( Window )
		local Text = Input:GetText()
		if Text and Text:len() > 0 then
			Shared.ConsoleCommand( StringFormat( "sh_setteamname %s %s", LocalTeam, Text ) )
		else
			Plugin:Notify( "You have to enter a team name!" )
		end
		Window:Destroy()
	end
end

function CaptainMenu:AddCategory( Name )
	if not self.Created then 
		Plugin:SimpleTimer( 1, function() self:AddCategory( Name ) end )
		return
	end
	
	if self.Categories[ Name ] then return end
	
	self.Categories[ Name ] = true
	local Commands = self.Commands
	local CommandPanel = self.CommandPanel
	local Lists = self.ListItems
	
	local function GenerateButton( Text, DoClick, NeedsSteamId )
		local Button = SGUI:Create( "Button" )
		Button:SetSize( Vector( CommandPanel:GetSize().x, 32, 0 ) )
		Button:SetText( Text )
		Button:SetFont( Fonts.kAgencyFB_Small )
		Button.DoClick = function( Button )
			local SteamId 
			for i = 1, #Lists do
				local List = Lists[ i ]
				local ListRow = List:GetSelectedRow()
				if ListRow then					
					SteamId = ToNumber( ListRow:GetColumnText( 1 ) )
					break
				end
			end
			if NeedsSteamId == 1 and not SteamId then
				self:AskForPlayer()
				return
			end
			if NeedsSteamId == 2 then
				self:AskforTeamName()
				return
			end
			
			DoClick( Button, SteamId )
		end

		return Button
	end
	
	if not Categories[ Name ] then return end
	
	Commands:AddCategory( Name )
	for i = 1, #Categories[ Name ] do
		local CategoryEntry = Categories[ Name ][ i ]
		Commands:AddObject( Name, GenerateButton( CategoryEntry[ 1 ], CategoryEntry[ 2 ], CategoryEntry[ 3 ] ) )
	end
end

function CaptainMenu:RemoveCategory( Name )
	if not self.Created then return end
	if not self.Categories[ Name ] then return end
	
	self.Categories[ Name ] = false
	self.Commands:RemoveCategory( Name )
end

function CaptainMenu:UpdatePlayer( Message )
	if not self.Created then 
		Plugin:SimpleTimer( 1, function() self:UpdatePlayer( Message ) end )
		return
	end
	
	local Row
	for i = 1, 3 do
		local List = self.ListItems[ i ]
		local Rows = List.Rows
		for j = 1, List.RowCount do
			if Rows[ j ]:GetColumnText( 1 ) == Message.steamid then
				if i ~= Message.team + 1 then
					List:RemoveRow( j )
				else
					Row = Rows[ j ]
				end
				
				break
			end
		end
	end
	
	if Message.team > 2 then return end
	
	local playtime = Round( Message.playtime / 3600, 2 )
	local kd = Message.deaths > 0 and Round( Message.kills / Message.deaths, 2 ) or 0
	local sm = Message.deaths > 0 and Round( Message.score / Message.deaths, 2 ) or 0
	local wl = Message.loses > 0 and Round( Message.wins / Message.loses, 2 ) or 0
	
	local RowData = { Message.steamid, Message.name, playtime, Message.skill, wl, kd, sm, Message.votes }
	
	if Row then
		for i = 1, 8 do
			Row:SetColumnText( i, ToString( RowData[ i ] ) )
		end
	else
		local List = self.ListItems[ Message.team + 1 ]
		List:AddRow( Unpack( RowData ) )
	end
end

function CaptainMenu:SetIsVisible( Bool )	
	self.Panel:SetIsVisible( Bool )
	
	if Bool and not self.Visible then
		SGUI:EnableMouse( true )
	elseif not Bool and self.Visible then
		SGUI:EnableMouse( false )
		for i = 1, #self.Windows do
			local Window = self.Windows[ i ]
			Window:Destroy()
		end
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
	self.Created = false
	
	if self.Visible then
		self:SetIsVisible( false )
	end
	
	self.Panel:Destroy()
	for i = 1, #self.Windows do
		local Window = self.Windows[ i ]
		Window:Destroy()
	end
end

function Plugin:Initialise()
	CaptainMenu:Create()
	
	self.Enabled = true
	
	self:SetupAdminMenuCommands()
	
	if not Loaded then 
		Shine.VoteMenu:EditPage( "Main", function( self )
			local MenuButton = self:AddSideButton( "Captain Mode Menu", function()
				Shared.ConsoleCommand( "sh_captainmenu" )
				self:SetIsVisible( false )
			end )
			MenuButton:SetIsVisible( Plugin.Enabled and Plugin.dt.State > 0 )
		end )
		Loaded = true
	end
	
	return true
end

function Plugin:SetupAdminMenuCommands()
    local Category = "Captains Mode"

    self:AddAdminMenuCommand( Category, "Set Captain", "sh_setcaptain", false, {
		"Team 1", "1",
		"Team 2", "2",
	} )
    self:AddAdminMenuCommand( Category, "Remove Captain", "sh_removecaptain", false, {
		"Team 1", "1",
		"Team 2", "2",
	} )
	self:AddAdminMenuCommand( Category, "Reset Captain Mode", "sh_resetcaptainmode", true )
end

local Messages = {	
	"Captain Mode enabled",
	"Waiting for %s Players to join the Server before starting a Vote for Captains",
	"Vote for Captains is currently running",
	"Waiting for Captains to set up the teams.\nThe round will start once both teams are ready!",
	"Currently a round has been started.\nPlease wait for a Captain to pick you up",
	"",
	"The current vote will end in %s minutes\nPress %s to access the Captain Mode Menu.\nOr type !captainmenu into the chat."
}

function Plugin:StartMessage()
	self:CreateTextMessage()
	self:CreateTimer( "TextMessage", 1800, -1, function() self:CreateTextMessage() end )
end

Plugin.MessageConfig =
{
	x = 0.05,
	y = 0.55,
	r = 51,
	g = 153,
	b = 0,
}
function Plugin:CreateTextMessage()
	Shine:AddMessageToQueue( 16, self.MessageConfig.x, self.MessageConfig.y, StringFormat("%s\n%s\n%s", Messages[ 1 ], Messages[ self.dt.State + 2 ], Messages[ 6 ] ), 1800, self.MessageConfig.r, self.MessageConfig.g, self.MessageConfig.b, 0, 1, 0 )
end

function Plugin:UpdateTextMessage( VoteTime )
	if not self:TimerExists( "TextMessage" ) then
		self:StartMessage()
	elseif VoteTime then
		local TimeMsg = StringFormat( Messages[ 7 ], string.DigitalTime( VoteTime ), Shine.VoteButton or "M" )
		Shine:UpdateMessageText{ ID = 16, Message = StringFormat("%s\n%s\n%s\n%s", Messages[ 1 ], Messages[ self.dt.State + 2 ], Messages[ 6 ], TimeMsg ) }
	else
		Shine:UpdateMessageText{ ID = 16, Message = StringFormat("%s\n%s\n%s", Messages[ 1 ], Messages[ self.dt.State + 2 ], Messages[ 6 ] ) }
	end
end

function Plugin:RemoveTextMessage()
	Shine:RemoveMessage( 16 )
	self:DestroyTimer( "TextMessage" )
end

function Plugin:ChangeState( OldState, NewState )
	if not CaptainMenu.Created then
		CaptainMenu:Create()
	end
	
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
	elseif not self:TimerExists( "VoteMessage" ) then
		self:SimpleTimer( 0.5, function() self:UpdateTextMessage() end)
	end
	
end

function Plugin:ReceiveCaptainMenu()
	CaptainMenu:SetIsVisible( true )
end

function Plugin:ReceiveTeamInfo( Message )
	Shared.ConsoleCommand( StringFormat( "score%s %s", Message.teamnumber, Message.wins ) )
	Shared.ConsoleCommand( StringFormat( "team%s %s", Message.teamnumber, Message.name ) )
	CaptainMenu:UpdateTeam( Message.number, Message.name, Message.wins )
end

function Plugin:ReceivePlayerData( Message )
	if not LocalId then
		LocalId = ToString(Client.GetSteamId())
	end
	
	if Message.steamid == LocalId then
		LocalTeam = Message.team
	end
	
	CaptainMenu:UpdatePlayer( Message )
end

function Plugin:PlayerKeyPress( Key, Down, Amount )	
	return CaptainMenu:PlayerKeyPress( Key, Down )
end

function Plugin:Notify( Message, Format, ... )
	Message = Format and StringFormat( Message, ... ) or Message 
	Shine.AddChatText( 100, 255, 100, "[Captains Mode]", 1, 1, 1, Message )
end

function Plugin:ReceiveSetCaptain( Message )
	local SteamId = Message.steamid
	local TeamNumber = Message.team
	
	if not LocalId then
		LocalId = ToString(Client.GetSteamId())
	end
	
	if Message.add then
		local List = CaptainMenu.ListItems[ TeamNumber + 1 ]
		local RowId
		for j, Row in ipairs( List.Rows ) do
			if Row:GetColumnText( 1 ) == SteamId then
				RowId = j
				break
			end
		end
		
		if not RowId then return end
		local Row = List.Rows[ RowId ]
		for i = 1, Row.Columns do
			local Object = Row.TextObjs[ i ]
			Object:SetColor( Colour( 1, 215/255, 0, 1 ) )
		end
		if LocalId == SteamId then CaptainMenu:AddCategory( "Team Organization" ) end
	else
		if LocalId == SteamId then CaptainMenu:RemoveCategory( "Team Organization" ) end
	end
	
end

function Plugin:ReceiveVoteState( Message )
	if Message.team > 0 and Message.team ~= LocalTeam then return end
	
	if Message.start then
		if Message.timeleft > 1 then
			CaptainMenu:AddCategory( "Vote Captain" )
			self:CreateTimer( "VoteMessage", 1, Message.timeleft - 1, function( Timer )
				self:UpdateTextMessage( Timer:GetReps() )
			end )			
		end
	else
		self:DestroyTimer( "VoteMessage" )
		self:UpdateTextMessage()
		
		local List = CaptainMenu.ListItems and CaptainMenu.ListItems[ Message.team + 1 ]
		if not List then return end
		
		for _, Row in ipairs( List.Rows ) do
			Row:SetColumnText( 8, "0" )
		end

		CaptainMenu:RemoveCategory( "Vote Captain" )
	end
end

function Plugin:ReceiveInfoMsgs( Message )
	Messages[ Message.id ] = Message.text
	if Message.id == 6 then
		self:StartMessage()
	end
end

function Plugin:ReceiveMessageConfig( Message )
	self.MessageConfig = Message
end

function Plugin:OnResolutionChanged()
	CaptainMenu:Destroy()
	CaptainMenu:Create()
	self:SendNetworkMessage( "OnResolutionChanged", {}, true )
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )
	 
	CaptainMenu:Destroy()
	self:RemoveTextMessage()
end