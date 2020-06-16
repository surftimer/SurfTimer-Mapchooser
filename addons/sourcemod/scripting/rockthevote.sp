/*
 * =============================================================================
 * SourceMod Rock The Vote Plugin
 * Creates a map vote when the required number of players have requested one.
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#include <sourcemod>
#include <mapchooser>
#include <nextmap>
#include <SurfTimer>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "SurfTimer Rock The Vote",
	author = "AlliedModders LLC & SurfTimer Contributors",
	description = "Provides RTV Map Voting",
	version = "1.2",
	url = "http://www.sourcemod.net/"
};

ConVar g_Cvar_Needed;
ConVar g_Cvar_MinPlayers;
ConVar g_Cvar_InitialDelay;
ConVar g_Cvar_Interval;
ConVar g_Cvar_ChangeTime;
ConVar g_Cvar_RTVPostVoteAction;
ConVar g_Cvar_PointsRequirement;
ConVar g_Cvar_RankRequirement;

bool g_RTVAllowed = false;	// True if RTV is available to players. Used to delay rtv votes.
int g_Voters = 0;				// Total voters connected. Doesn't include fake clients.
int g_Votes = 0;				// Total number of "say rtv" votes
int g_VotesNeeded = 0;			// Necessary votes before map vote begins. (voters * percent_needed)
bool g_Voted[MAXPLAYERS+1] = {false, ...};

bool g_InChange = false;
bool g_bCanVote[MAXPLAYERS + 1];

// SQL Connection
Handle g_hDb = null;
#define PERCENT 0x25

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("rockthevote.phrases");

	db_setupDatabase();
	
	g_Cvar_Needed = CreateConVar("sm_rtv_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0);
	g_Cvar_MinPlayers = CreateConVar("sm_rtv_minplayers", "0", "Number of players required before RTV will be enabled.", 0, true, 0.0, true, float(MAXPLAYERS));
	g_Cvar_InitialDelay = CreateConVar("sm_rtv_initialdelay", "30.0", "Time (in seconds) before first RTV can be held", 0, true, 0.00);
	g_Cvar_Interval = CreateConVar("sm_rtv_interval", "240.0", "Time (in seconds) after a failed RTV before another can be held", 0, true, 0.00);
	g_Cvar_ChangeTime = CreateConVar("sm_rtv_changetime", "0", "When to change the map after a succesful RTV: 0 - Instant, 1 - RoundEnd, 2 - MapEnd", _, true, 0.0, true, 2.0);
	g_Cvar_RTVPostVoteAction = CreateConVar("sm_rtv_postvoteaction", "0", "What to do with RTV's after a mapvote has completed. 0 - Allow, success = instant change, 1 - Deny", _, true, 0.0, true, 1.0);
	g_Cvar_PointsRequirement = CreateConVar("sm_rtv_point_requirement", "0", "Amount of points required to use the rtv command, 0 to disable");
	g_Cvar_RankRequirement = CreateConVar("sm_rtv_rank_requirement", "0", "Rank required to use the rtv command, 0 to disable");
	
	RegConsoleCmd("sm_rtv", Command_RTV);
	
	AutoExecConfig(true, "rtv");

	OnMapEnd();

	/* Handle late load */
	for (int i=1; i<=MaxClients; i++)
	{
		if (IsClientConnected(i))
		{
			OnClientPostAdminCheck(i);	
		}	
	}
}

public void OnMapEnd()
{
	g_RTVAllowed = false;
	g_Voters = 0;
	g_Votes = 0;
	g_VotesNeeded = 0;
	g_InChange = false;
}

public void OnConfigsExecuted()
{
	CreateTimer(g_Cvar_InitialDelay.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsFakeClient(client))
	{
		g_bCanVote[client] = false;

		if (GetConVarInt(g_Cvar_PointsRequirement) > 0 || GetConVarInt(g_Cvar_RankRequirement) > 0)
		{
			db_selectPlayerData(client);
			return;
		}

		g_bCanVote[client] = true;
		g_Voters++;
		g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
	}
}

public void OnClientDisconnect(int client)
{
	if (g_Voted[client])
	{
		g_Votes--;
		g_Voted[client] = false;
	}
	
	if (!IsFakeClient(client) && g_bCanVote[client])
	{
		g_Voters--;
		g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
	}
	
	if (g_Votes && 
		g_Voters && 
		g_Votes >= g_VotesNeeded && 
		g_RTVAllowed ) 
	{
		if (g_Cvar_RTVPostVoteAction.IntValue == 1 && HasEndOfMapVoteFinished())
		{
			return;
		}
		
		StartRTV();
	}	
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!client || IsChatTrigger())
	{
		return;
	}
	
	if (strcmp(sArgs, "rtv", false) == 0 || strcmp(sArgs, "rockthevote", false) == 0)
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		AttemptRTV(client);
		
		SetCmdReplySource(old);
	}
}

public Action Command_RTV(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	AttemptRTV(client);
	
	return Plugin_Handled;
}

void AttemptRTV(int client)
{
	if (!g_RTVAllowed || (g_Cvar_RTVPostVoteAction.IntValue == 1 && HasEndOfMapVoteFinished()))
	{
		ReplyToCommand(client, "[SM] %t", "RTV Not Allowed");
		return;
	}
		
	if (!CanMapChooserStartVote())
	{
		ReplyToCommand(client, "[SM] %t", "RTV Started");
		return;
	}
	
	if (GetClientCount(true) < g_Cvar_MinPlayers.IntValue)
	{
		ReplyToCommand(client, "[SM] %t", "Minimal Players Not Met");
		return;			
	}
	
	if (g_Voted[client])
	{
		ReplyToCommand(client, "[SM] %t", "Already Voted", g_Votes, g_VotesNeeded);
		return;
	}

	if (GetConVarInt(g_Cvar_PointsRequirement) > 0)
	{
		if (surftimer_GetPlayerPoints(client) < GetConVarInt(g_Cvar_PointsRequirement))
		{
			PrintToChat(client, "[SM] %t", "Point Requirement");
			return;
		}
	}

	if (GetConVarInt(g_Cvar_RankRequirement) > 0)
	{
		if (surftimer_GetPlayerRank(client) > GetConVarInt(g_Cvar_RankRequirement) || surftimer_GetPlayerRank(client) == 0)
		{
			PrintToChat(client, "[SM] %t", "Rank Requirement", GetConVarInt(g_Cvar_RankRequirement));
			return;
		}
	}
	
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	
	g_Votes++;
	g_Voted[client] = true;
	
	PrintToChatAll("[SM] %t", "RTV Requested", name, g_Votes, g_VotesNeeded);
	
	if (g_Votes >= g_VotesNeeded)
	{
		StartRTV();
	}	
}

public Action Timer_DelayRTV(Handle timer)
{
	g_RTVAllowed = true;
}

void StartRTV()
{
	if (g_InChange)
	{
		return;	
	}
	
	if (EndOfMapVoteEnabled() && HasEndOfMapVoteFinished())
	{
		/* Change right now then */
		char map[PLATFORM_MAX_PATH];
		if (GetNextMap(map, sizeof(map)))
		{
			GetMapDisplayName(map, map, sizeof(map));
			
			PrintToChatAll("[SM] %t", "Changing Maps", map);
			CreateTimer(5.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
			g_InChange = true;
			
			ResetRTV();
			
			g_RTVAllowed = false;
		}
		return;	
	}
	
	if (CanMapChooserStartVote())
	{
		MapChange when = view_as<MapChange>(g_Cvar_ChangeTime.IntValue);
		InitiateMapChooserVote(when);
		
		ResetRTV();
		
		g_RTVAllowed = false;
		CreateTimer(g_Cvar_Interval.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void ResetRTV()
{
	g_Votes = 0;
			
	for (int i=1; i<=MAXPLAYERS; i++)
	{
		g_Voted[i] = false;
	}
}

public Action Timer_ChangeMap(Handle hTimer)
{
	g_InChange = false;
	
	LogMessage("RTV changing map manually");
	
	char map[PLATFORM_MAX_PATH];
	if (GetNextMap(map, sizeof(map)))
	{	
		ForceChangeLevel(map, "RTV after mapvote");
	}
	
	return Plugin_Stop;
}

stock bool IsValidClient(int client)
{
	if (client >= 1 && client <= MaxClients && IsValidEntity(client) && IsClientConnected(client) && IsClientInGame(client))
		return true;
	return false;
}

public void db_setupDatabase()
{
	char szError[255];
	g_hDb = SQL_Connect("surftimer", false, szError, 255);

	if (g_hDb == null)
		SetFailState("[Nominations] Unable to connect to database (%s)", szError);
	
	return;
}

public void db_selectPlayerData(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	char szSteamID[32], szQuery[256];
	GetClientAuthId(client, AuthId_Steam2, szSteamID, sizeof(szSteamID), true);

	Format(szQuery, sizeof(szQuery), "SELECT name, points FROM ck_playerrank WHERE style = 0 AND points >= (SELECT points FROM ck_playerrank WHERE steamid = '%s' AND style = 0) ORDER BY points;", szSteamID);
	SQL_TQuery(g_hDb, db_selectPlayersDataCallback, szQuery, client, DBPrio_Low);
}

public void db_selectPlayersDataCallback(Handle owner, Handle hndl, const char[] error, any client)
{
	if (hndl == null)
	{
		LogError("[RockTheVote] SQL Error (db_selectPlayersDataCallback): %s", error);
		return;
	}

	int rank, points;
	if (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		rank = SQL_GetRowCount(hndl);
		points = SQL_FetchInt(hndl, 0);
	}
	else
		rank = 99999;
	
	bool bNewVoter = true;
	if (GetConVarInt(g_Cvar_PointsRequirement) > 0)
	{
		if (points < GetConVarInt(g_Cvar_PointsRequirement))
		{
			bNewVoter = false;
			g_bCanVote[client] = false;
		}
	}

	if (GetConVarInt(g_Cvar_RankRequirement) > 0)
	{
		if (rank > GetConVarInt(g_Cvar_RankRequirement))
		{
			bNewVoter = false;
			g_bCanVote[client] = false;
		}
	}

	if (bNewVoter)
	{
		g_bCanVote[client] = true;
		g_Voters++;
		g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
	}
}