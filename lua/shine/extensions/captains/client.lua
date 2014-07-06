local Plugin = Plugin

local Shine = Shine
local SGUI = Shine.GUI
local Round = math.Round

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
		ListTitlePanel:SetPos( Vector( PanelSize.x * 0.02, PanelSize.y * ( 0.1 + 0.25 * i ) + 15 * i, 0 ))
		
		local ListTitleText = ListTitlePanel:Add( "Label" )
		ListTitleText:SetAnchor( "CentreMiddle" )
		ListTitleText:SetFont( "fonts/AgencyFB_small.fnt" )
		ListTitleText:SetText( ListTitles[ i + 1 ] )
		ListTitleText:SetTextAlignmentX( GUIItem.Align_Center )
		ListTitleText:SetTextAlignmentY( GUIItem.Align_Center )
		ListTitleText:SetColour( Skin.BrightText )
		
		local List = Panel:Add( "List" )
		List:SetAnchor( "TopLeft" )
		List:SetPos( Vector( PanelSize.x * 0.02, PanelSize.y * ( 0.15 + 0.25 * i ) + 15 * i, 0 ))
		List:SetColumns( 6, "Name", "Playtime", "Skill", "W/L", "K/D", "Score/D" )
		List:SetSpacing( 0.3, 0.15, 0.15, 0.1, 0.15, 0.15 )
		List:SetSize( Vector( PanelSize.x * 0.74, PanelSize.y * 0.2, 0 ) )
		List:SetNumericColumn( 2 )
		List:SetNumericColumn( 3 )
		List:SetNumericColumn( 4 )
		List:SetNumericColumn( 5 )
		List:AddScrollbar()
		List:SetMultiSelect( false )
		List.TitlePanel = ListTitlePanel
		List.TableIds = {}
		
		self.ListItems[ i + 1 ] = List
	end
	
	self.Created = true
end

function CaptainMenu:UpdatePlayer( Message )
	if not self.Created then return end
	
	for i = 1, 3 do
		local List = self.ListItems[i]
		if List.TableIds[ Message.steamid ] then
			List:RemoveRow( List.TableIds[ Message.steamid ] )
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
	
	List:AddRow( Message.name, playtime, Message.skill, wl, kd, sm )
	List.TableIds[ Message.steamid ] = List.RowCount
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
	CaptainMenu:Create()
	self.Enabled = true
	return true
end

function Plugin:ChangeState( OldState, NewState )
	-- change gui menu based on state and if needed open it
end

function Plugin:ReceiveCaptainMenu()
	CaptainMenu:SetIsVisible( true )
end

function Plugin:ReceivePlayerData( Message )
	CaptainMenu:UpdatePlayer( Message )
end

function Plugin:PlayerKeyPress( Key, Down, Amount )
	return CaptainMenu:PlayerKeyPress( Key, Down )
end

function Plugin:Cleanup()
	CaptainMenu:Destroy()
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end