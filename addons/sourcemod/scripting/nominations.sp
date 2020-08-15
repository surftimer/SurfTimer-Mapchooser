/*
 * =============================================================================
 * SourceMod Rock The Vote Plugin
 * Creates a map vote when the required number of players have requested one.
 *
 * SourceMod (C)2004-2014 AlliedModders LLC.  All rights reserved.
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
#include <autoexecconfig>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "SurfTimer Nominations",
	author = "AlliedModders LLC & SurfTimer Contributors",
	description = "Provides Map Nominations",
	version = "1.3",
	url = "https://github.com/qawery-just-sad/surftimer-mapchooser"
};

ConVar g_Cvar_ExcludeOld;
ConVar g_Cvar_ExcludeCurrent;
ConVar g_Cvar_ServerTier;

Menu g_MapMenu = null;

ArrayList g_MapList = null;
ArrayList g_MapListTier = null;

#define MAPSTATUS_ENABLED (1<<0)
#define MAPSTATUS_DISABLED (1<<1)
#define MAPSTATUS_EXCLUDE_CURRENT (1<<2)
#define MAPSTATUS_EXCLUDE_PREVIOUS (1<<3)
#define MAPSTATUS_EXCLUDE_NOMINATED (1<<4)

StringMap g_mapTrie = null;

// SQL Connection
Handle g_hDb = null;
#define PERCENT 0x25

//SQL Queries
char sql_SelectMapListSpecific[] = "SELECT ck_zones.mapname, tier, count(ck_zones.mapname), bonus FROM `ck_zones` INNER JOIN ck_maptier on ck_zones.mapname = ck_maptier.mapname LEFT JOIN ( SELECT mapname as map_2, MAX(ck_zones.zonegroup) as bonus FROM ck_zones GROUP BY mapname ) as a on ck_zones.mapname = a.map_2 WHERE (zonegroup = 0 AND zonetype = 1 or zonetype = 3) AND tier = %s GROUP BY ck_zones.mapname ORDER BY tier ASC, mapname ASC";
char sql_SelectMapListRange[] = "SELECT ck_zones.mapname, tier, count(ck_zones.mapname), bonus FROM `ck_zones` INNER JOIN ck_maptier on ck_zones.mapname = ck_maptier.mapname LEFT JOIN ( SELECT mapname as map_2, MAX(ck_zones.zonegroup) as bonus FROM ck_zones GROUP BY mapname ) as a on ck_zones.mapname = a.map_2 WHERE (zonegroup = 0 AND zonetype = 1 or zonetype = 3) AND tier >= %s AND tier <= %s GROUP BY ck_zones.mapname ORDER BY tier ASC, mapname ASC";
char sql_SelectMapList[] = "SELECT ck_zones.mapname, tier, count(ck_zones.mapname), bonus FROM `ck_zones` INNER JOIN ck_maptier on ck_zones.mapname = ck_maptier.mapname LEFT JOIN ( SELECT mapname as map_2, MAX(ck_zones.zonegroup) as bonus FROM ck_zones GROUP BY mapname ) as a on ck_zones.mapname = a.map_2 WHERE (zonegroup = 0 AND zonetype = 1 or zonetype = 3) GROUP BY ck_zones.mapname ORDER BY tier ASC, mapname ASC";

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("nominations.phrases");

	db_setupDatabase();
	
	int arraySize = ByteCountToCells(PLATFORM_MAX_PATH);
	g_MapList = new ArrayList(arraySize);
	g_MapListTier = new ArrayList(arraySize);

	AutoExecConfig_SetCreateDirectory(true);
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("nominations");
	
	g_Cvar_ExcludeOld = AutoExecConfig_CreateConVar("sm_nominate_excludeold", "1", "Specifies if the MapChooser excluded maps should also be excluded from Nominations", 0, true, 0.00, true, 1.0);
	g_Cvar_ExcludeCurrent = AutoExecConfig_CreateConVar("sm_nominate_excludecurrent", "1", "Specifies if the current map should be excluded from the Nominations list", 0, true, 0.00, true, 1.0);

	
	RegConsoleCmd("sm_nominate", Command_Nominate);
	
	RegAdminCmd("sm_nominate_addmap", Command_Addmap, ADMFLAG_CHANGEMAP, "sm_nominate_addmap <mapname> - Forces a map to be on the next mapvote.");
	
	g_mapTrie = new StringMap();

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
}

public void OnConfigsExecuted()
{
	SelectMapList();
}

public void OnNominationRemoved(const char[] map, int owner)
{
	int status;
	
	char resolvedMap[PLATFORM_MAX_PATH];
	FindMap(map, resolvedMap, sizeof(resolvedMap));
	
	/* Is the map in our list? */
	if (!g_mapTrie.GetValue(resolvedMap, status))
	{
		return;	
	}
	
	/* Was the map disabled due to being nominated */
	if ((status & MAPSTATUS_EXCLUDE_NOMINATED) != MAPSTATUS_EXCLUDE_NOMINATED)
	{
		return;
	}
	
	g_mapTrie.SetValue(resolvedMap, MAPSTATUS_ENABLED);
}

public Action Command_Addmap(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_nominate_addmap <mapname>");
		return Plugin_Handled;
	}
	
	char mapname[PLATFORM_MAX_PATH];
	char resolvedMap[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));

	if (FindMap(mapname, resolvedMap, sizeof(resolvedMap)) == FindMap_NotFound)
	{
		// We couldn't resolve the map entry to a filename, so...
		ReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;		
	}
	
	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(resolvedMap, displayName, sizeof(displayName));
	
	int status;
	if (!g_mapTrie.GetValue(resolvedMap, status))
	{
		ReplyToCommand(client, "%t", "Map was not found", displayName);
		return Plugin_Handled;		
	}

	RemoveMapPath(resolvedMap, resolvedMap, sizeof(resolvedMap));

	NominateResult result = NominateMap(resolvedMap, false, client);
	
	if (result > Nominate_Replaced)
	{
		/* We assume already in vote is the casue because the maplist does a Map Validity check and we forced, so it can't be full */
		ReplyToCommand(client, "%t", "Map Already In Vote", displayName);
		
		return Plugin_Handled;	
	}
	
	
	g_mapTrie.SetValue(resolvedMap, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

	
	ReplyToCommand(client, "%t", "Map Inserted", displayName);
	LogAction(client, -1, "\"%L\" inserted map \"%s\".", client, mapname);

	return Plugin_Handled;		
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!client || IsChatTrigger())
	{
		return;
	}
	
	if (strcmp(sArgs, "nominate", false) == 0)
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		AttemptNominate(client);
		
		SetCmdReplySource(old);
	}
}

public Action Command_Nominate(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (args == 0)
	{
		AttemptNominate(client);
		return Plugin_Handled;
	}
	
	char mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));
	
	if (FindMap(mapname, mapname, sizeof(mapname)) == FindMap_NotFound)
	{
		// We couldn't resolve the map entry to a filename, so...
		ReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;		
	}
	
	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(mapname, displayName, sizeof(displayName));
	
	int status;
	if (!g_mapTrie.GetValue(mapname, status))
	{
		ReplyToCommand(client, "%t", "Map was not found", displayName);
		return Plugin_Handled;		
	}
	
	if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
	{
		if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
		{
			ReplyToCommand(client, "[SM] %t", "Can't Nominate Current Map");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
		{
			ReplyToCommand(client, "[SM] %t", "Map in Exclude List");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
		{
			ReplyToCommand(client, "[SM] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;
	}

	RemoveMapPath(mapname, mapname, sizeof(mapname));

	NominateResult result = NominateMap(mapname, false, client);
	
	if (result > Nominate_Replaced)
	{
		if (result == Nominate_AlreadyInVote)
		{
			ReplyToCommand(client, "%t", "Map Already In Vote", displayName);
		}
		else
		{
			ReplyToCommand(client, "[SM] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;	
	}
	
	/* Map was nominated! - Disable the menu item and update the trie */
	
	g_mapTrie.SetValue(mapname, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);
	
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	PrintToChatAll("[SM] %t", "Map Nominated", name, displayName);
	
	return Plugin_Handled;
}

void AttemptNominate(int client)
{
	g_MapMenu.SetTitle("%T", "Nominate Title", client);
	g_MapMenu.Display(client, MENU_TIME_FOREVER);
	
	return;
}

void BuildMapMenu()
{
	delete g_MapMenu;

	g_mapTrie.Clear();

	g_MapMenu = new Menu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);

	char map[PLATFORM_MAX_PATH];
	
	ArrayList excludeMaps;
	char currentMap[PLATFORM_MAX_PATH];
	
	if (g_Cvar_ExcludeOld.BoolValue)
	{	
		excludeMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		GetExcludeMapList(excludeMaps);
	}
	
	if (g_Cvar_ExcludeCurrent.BoolValue)
	{
		GetCurrentMap(currentMap, sizeof(currentMap));
	}


	for (int i = 0; i < g_MapList.Length; i++)
	{
		int status = MAPSTATUS_ENABLED;
		
		g_MapList.GetString(i, map, sizeof(map));

		Format(map, sizeof(map), "%s.", map);
		
		FindMap(map, map, sizeof(map));
		
		char displayName[PLATFORM_MAX_PATH];
		GetArrayString(g_MapListTier, i, displayName, sizeof(displayName));
		// GetMapDisplayName(map, displayName, sizeof(displayName));

		if (g_Cvar_ExcludeCurrent.BoolValue)
		{
			if (StrEqual(map, currentMap))
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_CURRENT;
			}
		}
		
		/* Dont bother with this check if the current map check passed */
		if (g_Cvar_ExcludeOld.BoolValue && status == MAPSTATUS_ENABLED)
		{
			if (excludeMaps.FindString(map) != -1)
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_PREVIOUS;
			}
		}
		
		g_MapMenu.AddItem(map, displayName);
		g_mapTrie.SetValue(map, status);
	}

	g_MapMenu.ExitButton = true;

	delete excludeMaps;
}

public int Handler_MapSelectMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char map[PLATFORM_MAX_PATH], name[MAX_NAME_LENGTH], displayName[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map), _, displayName, sizeof(displayName));
			
			GetClientName(param1, name, sizeof(name));

			RemoveMapPath(map, map, sizeof(map));

			NominateResult result = NominateMap(map, false, param1);
			
			/* Don't need to check for InvalidMap because the menu did that already */
			if (result == Nominate_AlreadyInVote)
			{
				PrintToChat(param1, "[SM] %t", "Map Already Nominated");
				return 0;
			}
			else if (result == Nominate_VoteFull)
			{
				PrintToChat(param1, "[SM] %t", "Max Nominations");
				return 0;
			}
			
			g_mapTrie.SetValue(map, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

			if (result == Nominate_Replaced)
			{
				PrintToChatAll("[SM] %t", "Map Nomination Changed", name, displayName);
				return 0;	
			}
			
			PrintToChatAll("[SM] %t", "Map Nominated", name, displayName);
		}
		
		case MenuAction_DrawItem:
		{
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));
			
			int status;
			
			if (!g_mapTrie.GetValue(map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return ITEMDRAW_DEFAULT;
			}
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				return ITEMDRAW_DISABLED;	
			}
			
			return ITEMDRAW_DEFAULT;
						
		}
		
		case MenuAction_DisplayItem:
		{
			char map[PLATFORM_MAX_PATH], displayName[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map), _, displayName, sizeof(displayName));
			
			int status;
			
			if (!g_mapTrie.GetValue(map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return 0;
			}
			
			char display[PLATFORM_MAX_PATH + 64];
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
				{
					Format(display, sizeof(display), "%s (%T)", displayName, "Current Map", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
				{
					Format(display, sizeof(display), "%s (%T)", displayName, "Recently Played", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
				{
					Format(display, sizeof(display), "%s (%T)", displayName, "Nominated", param1);
					return RedrawMenuItem(display);
				}
			}
			
			return 0;
		}
	}
	
	return 0;
}

public void db_setupDatabase()
{
	char szError[255];
	g_hDb = SQL_Connect("surftimer", false, szError, 255);

	if (g_hDb == null)
		SetFailState("[Nominations] Unable to connect to database (%s)", szError);

	char szIdent[8];
	SQL_ReadDriver(g_hDb, szIdent, 8);

	if (strcmp(szIdent, "mysql", false) == 0)
	{
		// https://github.com/nikooo777/ckSurf/pull/58 - eeeee that is an issue in a half || Also https://discordapp.com/channels/366959507764674560/379572504542445568/729723679541559336
		SQL_FastQuery(g_hDb, "SET sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));");
	}
	else
	{
		SetFailState("[Nominations] Invalid database type");
		return;
	}
	return;
}

public void SelectMapList()
{
	char szQuery[512], szTier[16], szBuffer[2][32];
	
	g_Cvar_ServerTier = FindConVar("sm_server_tier");
	GetConVarString(g_Cvar_ServerTier, szTier, sizeof(szTier));
	ExplodeString(szTier, ".", szBuffer, 2, 32);

	if (StrEqual(szBuffer[1], "0"))
		// OLD QUERY Format(szQuery, sizeof(szQuery), "SELECT mapname, tier FROM ck_maptier WHERE tier = %s ORDER BY tier asc, mapname asc;", szBuffer[0]);
		Format(szQuery, sizeof(szQuery), sql_SelectMapListSpecific, szBuffer[0]);
	else if (strlen(szBuffer[1]) > 0)
		// OLD QUERY Format(szQuery, sizeof(szQuery), "SELECT mapname, tier FROM ck_maptier WHERE tier >= %s AND tier <= %s ORDER BY tier asc, mapname asc;", szBuffer[0], szBuffer[1]);
		Format(szQuery, sizeof(szQuery), sql_SelectMapListRange, szBuffer[0], szBuffer[1]);
	else
		// OLD QUERY Format(szQuery, sizeof(szQuery), "SELECT mapname, tier FROM ck_maptier ORDER BY tier asc, mapname asc;");
		Format(szQuery, sizeof(szQuery), sql_SelectMapList);

	SQL_TQuery(g_hDb, SelectMapListCallback, szQuery, DBPrio_Low);
}

public void SelectMapListCallback(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("[Nominations] SQL Error (SelectMapListCallback): %s", error);
		return;
	}

	if (SQL_HasResultSet(hndl))
	{
		g_MapList.Clear();
		g_MapListTier.Clear();

		int tier, zones, bonus;
		char szValue[256], szMapName[128], stages[128], bonuses[128];
		while (SQL_FetchRow(hndl))
		{
			SQL_FetchString(hndl, 0, szMapName, sizeof(szMapName));
			tier = SQL_FetchInt(hndl, 1);
			zones = SQL_FetchInt(hndl, 2);
			bonus = SQL_FetchInt(hndl, 3);

			if (zones == 1)
			{
				Format(stages, sizeof(stages), "- Linear");
			}
			else
				Format(stages, sizeof(stages), "- Stages %d", zones);

			if (bonus == 0)
			{
				Format(bonuses, sizeof(bonuses), "");
			}
			else
				Format(bonuses, sizeof(bonuses), "- Bonuses %d", bonus);
			
			Format(szValue, sizeof(szValue), "%s - Tier %d %s %s", szMapName, tier, stages, bonuses);

			if (IsMapValid(szMapName))
			{
				g_MapList.PushString(szMapName);
				g_MapListTier.PushString(szValue);
			}
			else
				LogError("Error 404: Map %s was found in database but not on server! Please delete entry in database or add the map to server!", szMapName);
		}

		BuildMapMenu();
	}
}

public void RemoveMapPath(const char[] map, char[] destination, any maxlen)
{
	if (strlen(map) < 1)
	{
		ThrowError("Bad map name: %s", map);
	}
	
	// UNIX paths
	char pos = FindCharInString(map, '/', true);
	if (pos == -1)
	{
		// Windows paths
		pos = FindCharInString(map, '\\', true);
		if (pos == -1)
		{
			//destination[0] = '\0';
			strcopy(destination, maxlen, map);
		}
	}

	// strlen is last + 1
	int len = strlen(map) - 1 - pos;
	
	// pos + 1 is because pos is the last / or \ location and we want to start one char further
	SubString(map, pos + 1, len, destination, maxlen);
}

public void SubString(const char[] source, any start, any len, char[] destination, any maxlen)
{
	if (maxlen < 1)
	{
		ThrowError("Destination size must be 1 or greater, but was %d", maxlen);
	}
	
	// optimization
	if (len == 0)
	{
		destination[0] = '\0';
	}
	
	if (start < 0)
	{
		// strlen doesn't count the null terminator, so don't -1 on it.
		start = strlen(source) + start;
		if (start < 0)
			start = 0;
	}
	
	if (len < 0)
	{
		len = strlen(source) + len - start;
		// If length is still less than 0, that'd be an error.
	}
	
	// Check to make sure destination is large enough to hold the len, or truncate it.
	// len + 1 because second arg to strcopy counts 1 for the null terminator
	int realLength = len + 1 < maxlen ? len + 1 : maxlen;
	
	strcopy(destination, realLength, source[start]);
}