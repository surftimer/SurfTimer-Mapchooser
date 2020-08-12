/*
    The credit goes to User LESAC4 - https://pastebin.com/u/lesac4
    Original Code - https://pastebin.com/6uWxRxkX
    Found by - https://github.com/surftimer/Surftimer-olokos/issues/31#issuecomment-617615860
    Modified by SurfTimer Contributors
*/

#include <sourcemod>
#include <SurfTimer>
#include <autoexecconfig>

#pragma newdecls required
#pragma semicolon 1

ConVar g_hVoteExtendTime; 										// Extend time CVar
ConVar g_hMaxVoteExtends; 										// Extend max count CVar
ConVar g_fInitialVoteDelay;
ConVar g_bOneVotePerPlayer;
ConVar g_VipFeature;
ConVar g_fInterval;

bool g_bVEAllowed = false;
int g_VoteExtends = 0; 											// How many extends have happened in current map
char g_szSteamID[MAXPLAYERS + 1][32];							// Client's steamID
char g_szUsedVoteExtend[MAXPLAYERS+1][32]; 						// SteamID's which triggered extend vote

public Plugin myinfo = 
{
	name = "SurfTimer Vote Extend",
	author = "SurfTimer Contributors",
	description = "Allows players to vote extend the map",
	version = "1.3",
	url = "https://github.com/qawery-just-sad/surftimer-mapchooser"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_ve", Command_VoteExtend, "SurfTimer | Vote to extend the map");
	RegConsoleCmd("sm_voteextend", Command_VoteExtend, "SurfTimer | Vote to extend the map");
	RegConsoleCmd("sm_extend", Command_VoteExtend, "SurfTimer | Vote to extend the map");

	AutoExecConfig_SetCreateDirectory(true);
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("vote-extend");
	
	g_hMaxVoteExtends = AutoExecConfig_CreateConVar("ck_max_vote_extends", "2", "The max number of VIP vote extends", FCVAR_NOTIFY, true, 0.0);
	g_hVoteExtendTime = AutoExecConfig_CreateConVar("ck_vote_extend_time", "10.0", "The time in minutes that is added to the remaining map time if a vote extend is successful.", FCVAR_NOTIFY, true, 0.0);
	g_fInitialVoteDelay = AutoExecConfig_CreateConVar("ck_ve_initialdelay", "300", "The time in seconds when first vote can take place", FCVAR_NOTIFY, true, 0.0);
	g_fInterval = AutoExecConfig_CreateConVar("ck_ve_interval", "240.0", "Time in seconds after a failed VE before another can be held", 0, true, 0.00);
	g_bOneVotePerPlayer = AutoExecConfig_CreateConVar("ck_ve_onevote", "0", "Can vote be started again from the same person. 0 - Yes, 1 - No.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_VipFeature = AutoExecConfig_CreateConVar("ck_ve_vip", "1", "Is command only for vips? 1-Yes, 0-No.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
}

public void OnMapEnd()
{
	g_bVEAllowed = false;
	g_VoteExtends = 0;
	
	for (int i = 0; i < MAXPLAYERS+1; i++)
		g_szUsedVoteExtend[i][0] = '\0';
}

public void OnClientPostAdminCheck(int client)
{
	GetClientAuthId(client, AuthId_Steam2, g_szSteamID[client], MAX_NAME_LENGTH, true);
}

public void OnConfigsExecuted()
{
	CreateTimer(g_fInitialVoteDelay.FloatValue, Timer_Delay, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Delay(Handle timer)
{
	g_bVEAllowed = true;
}

public Action Command_VoteExtend(int client, int args)
{
	if(!IsValidClient(client))
		return Plugin_Handled;

	if(g_VipFeature)
	{
		if(!surftimer_IsClientVip(client))
		{
			ReplyToCommand(client, "SurfTimer | This is a VIP feature.");
			return Plugin_Handled;
		}
	}
	
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "SurfTimer | Please wait until the current vote has finished.");
		return Plugin_Handled;
	}

	if (g_VoteExtends >= GetConVarInt(g_hMaxVoteExtends))
	{
		ReplyToCommand(client, "SurfTimer | There have been too many extends this map.");
		return Plugin_Handled;
	}

	if (!g_bVEAllowed)
	{
		ReplyToCommand(client, "SurfTimer | Vote Extend is not allowed yet.");
		return Plugin_Handled;
	}
	
	int timeleft;
	GetMapTimeLeft(timeleft);

	// Here we go through and make sure this user has not already voted. This persists throughout map.
	if (GetConVarBool(g_bOneVotePerPlayer))
	{
		for (int i = 0; i < g_VoteExtends; i++)
		{
			if (StrEqual(g_szUsedVoteExtend[i], g_szSteamID[client], false))
			{
				ReplyToCommand(client, "SurfTimer | You have already used your vote to extend this map.");
				return Plugin_Handled;
			}
		}
	}

	StartVoteExtend(client);
	return Plugin_Handled;
}


public void StartVoteExtend(int client)
{
	char szPlayerName[MAX_NAME_LENGTH];	
	GetClientName(client, szPlayerName, MAX_NAME_LENGTH);
	PrintToChatAll("[SurfTimer] Vote to Extend started by %s", szPlayerName);

	g_szUsedVoteExtend[g_VoteExtends] = g_szSteamID[client];	// Add the user's steam ID to the list
	g_VoteExtends++;	// Increment the total number of vote extends so far

	Menu voteExtend = CreateMenu(H_VoteExtend);
	SetVoteResultCallback(voteExtend, H_VoteExtendCallback);
	char szMenuTitle[128];

	char buffer[8];
	IntToString(RoundToFloor(GetConVarFloat(g_hVoteExtendTime)), buffer, sizeof(buffer));

	Format(szMenuTitle, sizeof(szMenuTitle), "Extend map for %s minutes?", buffer);
	SetMenuTitle(voteExtend, szMenuTitle);
	
	AddMenuItem(voteExtend, "", "Yes");
	AddMenuItem(voteExtend, "", "No");
	SetMenuExitButton(voteExtend, false);
	VoteMenuToAll(voteExtend, 20);
}

public void H_VoteExtendCallback(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	int votesYes = 0;
	int votesNo = 0;

	if (item_info[0][VOTEINFO_ITEM_INDEX] == 0) {	// If the winner is Yes
		votesYes = item_info[0][VOTEINFO_ITEM_VOTES];
		if (num_items > 1) {
			votesNo = item_info[1][VOTEINFO_ITEM_VOTES];
		}
	}
	else {	// If the winner is No
		votesNo = item_info[0][VOTEINFO_ITEM_VOTES];
		if (num_items > 1) {
			votesYes = item_info[1][VOTEINFO_ITEM_VOTES];
		}
	}

	if (votesYes > votesNo) // A tie is a failure
	{
		PrintToChatAll("[SurfTimer] Vote to Extend succeeded - Votes Yes: %i | Votes No: %i", votesYes, votesNo);
		ExtendMapTimeLimit(RoundToFloor(GetConVarFloat(g_hVoteExtendTime)*60));
		g_bVEAllowed = false;
		CreateTimer(g_fInterval.FloatValue, Timer_Delay, _, TIMER_FLAG_NO_MAPCHANGE);
	} 
	else
	{
		PrintToChatAll("[SurfTimer] Vote to Extend failed - Votes Yes: %i | Votes No: %i", votesYes, votesNo);
		g_bVEAllowed = false;
		CreateTimer(g_fInterval.FloatValue, Timer_Delay, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public int H_VoteExtend(Menu tMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		CloseHandle(tMenu);
	}
}

stock bool IsValidClient(int client) 
{ 
    if (client <= 0) 
        return false; 
	
    if (client > MaxClients) 
        return false; 
	
    if ( !IsClientConnected(client) ) 
        return false; 
	
    return IsClientInGame(client); 
}