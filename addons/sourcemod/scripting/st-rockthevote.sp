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
#include <surftimer>
#include <autoexecconfig>
#include <colorlib>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "SurfTimer Rock The Vote",
	author = "AlliedModders LLC & SurfTimer Contributors",
	description = "Provides RTV Map Voting",
	version = "2.0.0",
	url = "https://github.com/1zc/surftimer-mapchooser"
};

ConVar g_Cvar_Needed;
ConVar g_Cvar_MinPlayers;
ConVar g_Cvar_InitialDelay;
ConVar g_Cvar_Interval;
ConVar g_Cvar_ChangeTime;
ConVar g_Cvar_RTVPostVoteAction;
ConVar g_Cvar_PointsRequirement;
ConVar g_Cvar_RankRequirement;
ConVar g_Cvar_VIPOverwriteRequirements;
ConVar g_PlayerOne;

// Chat prefix
char g_szChatPrefix[256];
ConVar g_ChatPrefix = null;

bool g_RTVAllowed = false;	// True if RTV is available to players. Used to delay rtv votes.
int g_Voters = 0;				// Total voters connected. Doesn't include fake clients.
int g_Votes = 0;				// Total number of "say rtv" votes
int g_VotesNeeded = 0;			// Necessary votes before map vote begins. (voters * percent_needed)
bool g_Voted[MAXPLAYERS+1] = {false, ...};

bool g_PointsREQ[MAXPLAYERS+1] = {false, ...};
bool g_RankREQ[MAXPLAYERS+1] = {false, ...};

bool g_InChange = false;

Handle g_hDb = null;
char sql_SelectRank[] = "SELECT COUNT(*) FROM ck_playerrank WHERE style = 0 AND points >= (SELECT points FROM ck_playerrank WHERE steamid = '%s' AND style = 0);";
char sql_SelectPoints[] = "SELECT points FROM ck_playerrank WHERE steamid = '%s' AND style = 0";

public void OnPluginStart()
{
	LoadTranslations("st-rockthevote.phrases");
	db_setupDatabase();

	AutoExecConfig_SetCreateDirectory(true);
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("st-rtv");
	
	g_Cvar_Needed = AutoExecConfig_CreateConVar("sm_rtv_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0);
	g_Cvar_MinPlayers = AutoExecConfig_CreateConVar("sm_rtv_minplayers", "0", "Number of players required before RTV will be enabled.", 0, true, 0.0, true, float(MAXPLAYERS));
	g_Cvar_InitialDelay = AutoExecConfig_CreateConVar("sm_rtv_initialdelay", "30.0", "Time (in seconds) before first RTV can be held", 0, true, 0.00);
	g_Cvar_Interval = AutoExecConfig_CreateConVar("sm_rtv_interval", "240.0", "Time (in seconds) after a failed RTV before another can be held", 0, true, 0.00);
	g_Cvar_ChangeTime = AutoExecConfig_CreateConVar("sm_rtv_changetime", "0", "When to change the map after a succesful RTV: 0 - Instant, 1 - RoundEnd, 2 - MapEnd", _, true, 0.0, true, 2.0);
	g_Cvar_RTVPostVoteAction = AutoExecConfig_CreateConVar("sm_rtv_postvoteaction", "0", "What to do with RTV's after a mapvote has completed. 0 - Allow, success = instant change, 1 - Deny", _, true, 0.0, true, 1.0);
	g_Cvar_PointsRequirement = AutoExecConfig_CreateConVar("sm_rtv_point_requirement", "0", "Amount of points required to use the rtv command, 0 to disable");
	g_Cvar_RankRequirement = AutoExecConfig_CreateConVar("sm_rtv_rank_requirement", "0", "Rank required to use the rtv command, 0 to disable");
	g_Cvar_VIPOverwriteRequirements = AutoExecConfig_CreateConVar("sm_rtv_vipoverwrite", "0", "1 - VIP's bypass Rank and/or Points requirement, 0 - VIP's need to meet the Rank and/or Points requirement", _, true, 0.0, true, 1.0);
	g_PlayerOne = AutoExecConfig_CreateConVar("sm_rtv_oneplayer", "1", "If there is  only one player in the server allow him to rtv 1-allow 0-no", _, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_rtv", Command_RTV);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();

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

public void db_setupDatabase()
{
	char szError[255];
	g_hDb = SQL_Connect("surftimer", false, szError, 255);

	if (g_hDb == null)
		SetFailState("[RTV] Unable to connect to database (%s)", szError);
	
	char szIdent[8];
	SQL_ReadDriver(g_hDb, szIdent, 8);

	if (!StrEqual(szIdent, "mysql", false))
	{
		SetFailState("[RTV] Invalid database type");
		return;
	}
}

public void OnMapEnd()
{
	g_RTVAllowed = false;
	g_Voters = 0;
	g_Votes = 0;
	g_VotesNeeded = 0;
	g_InChange = false;
	for ( int i=1 ; i<=MAXPLAYERS ; i++ )
	{
		g_RankREQ[i] = false;
		g_PointsREQ[i] = false;
	}
}

public void OnConfigsExecuted()
{
	g_ChatPrefix = FindConVar("ck_chat_prefix");
	GetConVarString(g_ChatPrefix, g_szChatPrefix, sizeof(g_szChatPrefix));
	
	CreateTimer(g_Cvar_InitialDelay.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}

	GetPlayerRank(client);
	GetPlayerPoints(client);

	g_Voters++;
	CalcVotesNeeded();
}

public void CalcVotesNeeded()
{
	if ( GetConVarInt(g_Cvar_RankRequirement) > 0 || GetConVarInt(g_Cvar_PointsRequirement) > 0 )
	{
		int RealVoters = 0;
		for ( int i=1 ; i<= MAXPLAYERS ; i++ )
		{
			if (g_RankREQ[i] == true || g_PointsREQ[i] == true)
			{
				RealVoters++;
			}
		}
		g_VotesNeeded = RoundToCeil(float(RealVoters) * g_Cvar_Needed.FloatValue);
	}
	else
	{
		g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
	}
}
	

public void OnClientDisconnect(int client)
{
	if (g_Voted[client])
	{
		g_Voted[client] = false;
    }
	
	if (IsFakeClient(client))
	{
		return;
	}
	
	g_RankREQ[client] = false;
	g_PointsREQ[client] = false;

	g_Voters--;
	CalcVotesNeeded();
	
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
	if (PlayerOne())
	{
		return;
	}
	
	if (!g_RTVAllowed || (g_Cvar_RTVPostVoteAction.IntValue == 1 && HasEndOfMapVoteFinished()))
	{
		CReplyToCommand(client, "%t", "RTV Not Allowed", g_szChatPrefix);
		return;
	}
		
	if (!CanMapChooserStartVote())
	{
		CReplyToCommand(client, "%t", "RTV Started", g_szChatPrefix);
		return;
	}
	
	if (GetClientCount(true) < g_Cvar_MinPlayers.IntValue)
	{
		CReplyToCommand(client, "%t", "Minimal Players Not Met", g_szChatPrefix);
		return;			
	}
	
	if (g_Voted[client])
	{
		CReplyToCommand(client, "%t", "Already Voted", g_szChatPrefix, g_Votes, g_VotesNeeded);
		return;
	}

	if (GetConVarInt(g_Cvar_PointsRequirement) > 0 && !g_PointsREQ[client])
	{
		CPrintToChat(client, "%t", "Point Requirement", g_szChatPrefix);
		return;
	}
	if (GetConVarInt(g_Cvar_RankRequirement) > 0 && !g_RankREQ[client])
	{
		CPrintToChat(client, "%t", "Rank Requirement", g_szChatPrefix, GetConVarInt(g_Cvar_RankRequirement));
		return;
	}

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	g_Votes++;
	g_Voted[client] = true;

	CPrintToChatAll("%t", "RTV Requested", g_szChatPrefix, name, g_Votes, g_VotesNeeded);

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
			
			CPrintToChatAll("%t", "Changing Maps", g_szChatPrefix, map);
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

stock bool VIPBypass(int client)
{
	if (surftimer_IsClientVip(client) && GetConVarBool(g_Cvar_VIPOverwriteRequirements))
	{
		return true;
	}
	else
	{
		return false;
	}
}

stock bool PlayerOne()
{
	if ( g_Voters == 1 && GetConVarBool(g_PlayerOne) )
	{
		StartRTV();
		return true;
	}
	else
	{
		return false;
	}
}


void GetPlayerRank(int client)
{
	if (!(GetConVarInt(g_Cvar_RankRequirement) > 0))
	{
		return;
	}

	char szQuery[256], steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, MAX_NAME_LENGTH, true);

	FormatEx(szQuery, sizeof(szQuery), sql_SelectRank, steamid);
	SQL_TQuery(g_hDb, GetPlayerRankCallBack, szQuery, client, DBPrio_Normal);
}

void GetPlayerRankCallBack(Handle owner, Handle hndl, const char[] error, any client)
{
	if (hndl == null){
		LogError("[RTV] SQL Error (GetPlayerRankCallBack): %s", error);
		return;
	}

	if(!IsValidClient(client))
	{
		return;
	}

	if (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		int rank = SQL_FetchInt(hndl,0);
		if(rank <= 0)
		{
			g_RankREQ[client] = false;
			return;
		}

		if(rank < GetConVarInt(g_Cvar_RankRequirement))
		{
			g_RankREQ[client] = true;
		}
		else if (VIPBypass(client))
		{
			g_RankREQ[client] = true;
		}
		else
		{
			g_RankREQ[client] = false;
		}

	}
}

void GetPlayerPoints(int client)
{
	if (!(GetConVarInt(g_Cvar_PointsRequirement) > 0))
	{
		return;
	}

	char szQuery[256], steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, MAX_NAME_LENGTH, true);

	FormatEx(szQuery, sizeof(szQuery), sql_SelectPoints, steamid);
	SQL_TQuery(g_hDb, GetPlayerPointsCallBack, szQuery, client, DBPrio_Normal);
}

void GetPlayerPointsCallBack(Handle owner, Handle hndl, const char[] error, any client)
{
	if (hndl == null){
		LogError("[RTV] SQL Error (GetPlayerPointsCallBack): %s", error);
		return;
	}

	if(!IsValidClient(client))
	{
		return;
	}

	if (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		int points = SQL_FetchInt(hndl,0);
		if(points <= 0)
		{
			g_PointsREQ[client] = false;
			return;
		}

		if(points > GetConVarInt(g_Cvar_PointsRequirement))
		{
			g_PointsREQ[client] = true;
		}
		else if (VIPBypass(client))
		{
			g_PointsREQ[client] = true;
		}
		else
		{
			g_PointsREQ[client] = false;
		}

	}
}