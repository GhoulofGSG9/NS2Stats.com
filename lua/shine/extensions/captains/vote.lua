local TableSort = table.sort
local TableShuffle = table.Shuffle
local TableRemove = table.remove

class 'Vote'

function Vote:Setup( Name, VoteOptions, VoteTime, OnSucess, OnFailure, WinnerNum, Team )
	self.Name = Name
	
	self.VoteOptions = {}
	self.VoteOptionIds = {}
	for i, name in ipairs( VoteOptions ) do
		self.VoteOptions[ i ] = {
			Name = name,
			Count = 0
		}
		self.VoteOptionIds[ name ] = i
	end
	
	self.VotesCount = 0
	self.Voted = {}
	
	self:SetVoteTime( VoteTime )
	self.Team = Team or 0
	self.WinnersNeeded = WinnerNum
	
	self:SetOnSucess( OnSucess )
	self:SetOnFailure( OnFailure )
end

function Vote:Start()
	self:Reset()
	self.Started = true
end

function Vote:AddVote( Client, Vote )
	local botCount = 0
	local Gamerules = GetGamerules()
	
	if self.Team > 0 then
		local Player = Client:GetControllingPlayer()
		if not Player then		
			local TeamNumber = Player.GetTeamNumber and Player:GetTeamNumber() 
			if not TeamNumber or TeamNumber ~= self.Team then return end
		end
		
		local function CountBots( Player )
			local Client = Player:GetClient()
			if Client and Client:GetIsVirtual() then
				botCount = botCount + 1
			end
		end
		Gamerules:GetTeam( self.Team ):ForEachPlayer( CountBots ) 
	end
	
	if self.Voted[ Client ] then self:RemoveVote( Client ) end
	
	self.Voted[ Client ] = Vote
	
	if not self.VoteOptions[ Vote ] then
		local text = string.format( "Invalid Vote: %s\nTable: %s", Vote, table.ToString( self.VoteOptions ))
		Print( text )
		return
	end
	
	self.VoteOptions[ Vote ].Count = self.VoteOptions[ Vote ].Count + 1
	self.VotesCount = self.VotesCount + 1
	
	local MaxVotes = self.Team == 0 and Server.GetNumPlayers() - Server.GetBotPlayerCount() or Gamerules:GetTeam( self.Team ):GetNumPlayers() - botCount
	if self.VotesCount >= MaxVotes then
		self:OnEnd()
	end
end

function Vote:RemoveVote( Client )
	local Vote = self.Voted[ Client ]
	if not Vote then return end
	
	self.VoteOptions[ Vote ].Count = self.VoteOptions[ Vote ].Count - 1
	self.VotesCount = self.VotesCount - 1
	self.Voted[ Client ] = nil
end

function Vote:Reset()
	self.VotesCount = 0
	self.Voted = {}
	for i = 1, #self.VoteOptions do
		self.VoteOptions[ i ].Count = 0
	end
	
	self.EndAt = self.VoteTime + Shared.GetTime()
end

function Vote:OnUpdate()
	if not self:GetIsStarted() then return end
	
	if self.EndAt <= Shared.GetTime() then
		self:OnEnd()
	end
end

function Vote:OnEnd()
	self.Started = false
	local Winners = self:GetWinners( self.WinnersNeeded )
	
	if Winners and #Winners == self.WinnersNeeded then
		self.Winners = Winners
		self:OnSucess( Winners )
	else
		self:OnFailure()
	end
end

function Vote:SetOnSucess( OnSucess )
	self.OnSucess = OnSucess
end

function Vote:SetOnFailure( OnFailure )
	self.OnFailure = OnFailure
end

function Vote:SetVoteTime( Time )
	self.VoteTime = Time
end

function Vote:GetTotalVotes()
	return self.VotesCount
end

function Vote:GetVotes( VoteOption )
	return self.VoteOptions[ VoteOption ] and self.VoteOptions[ VoteOption ].Count
end

function Vote:GetVote( Client )
	return self.Voted[ Client ]
end

function Vote:GetOptionName( OptionId )
	return self.VoteOptions[ OptionId ] and self.VoteOptions[ OptionId ].Name
end

function Vote:OptionToId( OptionName )
	return self.VoteOptionIds[ OptionName ]
end

function Vote:GetIsStarted()
	return self.Started
end

function Vote:GetTimeLeft()
	if not self.Started then return 0 end
	
	return self.EndAt - Shared.GetTime()
end

function Vote:GetWinners( num )
	if #self.VoteOptions < num then return end
	
	TableSort( self.VoteOptions, function( a,b )
		return a.Count > b.Count 
	end)
	
	local Winners = {}
	for i = 1, num do
		Winners[ i ] = self.VoteOptions[ i ]
	end
	
	local lastCount = self.VoteOptions[ num ].Count
	if lastCount == 0 then return end
	
	if self.VoteOptions[ num + 1 ].Count == lastCount then
		for i = num, 1, -1 do
			if Winners[ i ].Count == lastCount then
				Winners[ i ] = nil
			else
				break
			end
		end
		local ShuffleTable = {}
		local j = 1
		for i = #Winners + 1, #self.VoteOptions do
			if self.VoteOptions[ i ].Count == lastCount then
				ShuffleTable[ j ] = self.VoteOptions[ i ]
				j = j + 1
			else
				break
			end
		end
		
		TableShuffle( ShuffleTable )
		
		for i = 1, num - #Winners do
			Winners[ #Winners + 1 ] = ShuffleTable[ i ]
		end
	end
	
	return Winners		
end

function Vote:AddVoteOption( OptionName )
	local i = #self.VoteOptions + 1
	self.VoteOptions[ i ] = {
		Name = OptionName,
		Count = 0
	}
	self.VoteOptionIds[ OptionName ] = i
end

function Vote:RemoveOption( OptionName )
	local OptionId = self.VoteOptionIds[ OptionName ]
	if not OptionId then return end
	
	local count = 0
	for Client, Vote in ipairs( self.Voted ) do
		if Vote == OptionId then
			count = count + 1
			self.Voted[ Client ] = nil
		end
	end
	self.VotesCount = self.VotesCount - count
	
	for i = OptionId + 1, #self.VoteOptions do
		self.VoteOptionIds[ self.VoteOptions[ i ].Name ] = i - 1
	end
	
	TableRemove( self.VoteOptions, OptionId )
	self.VoteOptionIds[ OptionName ] = nil
end