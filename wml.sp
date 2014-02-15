#pragma semicolon 1
#include <sourcemod>
#include <regex>
#include <system2>
#undef REQUIRE_PLUGIN
#include <mapchooser_extended>

#define PLUGIN_VERSION 		"0.4.6"
#define PLUGIN_SHORT_NAME	"wml"
#define WORKSHOP_DIR		"workshop"
#define WORKSHOP_BASE_DIR 	"maps/workshop"
#define WML_TMP_DIR			"data/wml"
#define WML_DB_NAME			"nefarius-wml"

// Plugin Limits
#define MAX_ID_LEN			64
#define MAX_URL_LEN			128
#define MAX_ATTRIB_LEN		32
#define MAX_QUERY_LEN		255
#define MAX_ERROR_LEN		255

// Workshop tag names
#define TAG_Classic			"Classic"
#define TAG_Deathmatch		"Deathmatch"
#define TAG_Demolition		"Demolition"
#define TAG_Armsrace		"Armsrace"
#define TAG_Hostage			"Hostage"
#define TAG_Custom			"Custom"

// Web API
#define MAX_POST_LEN		MAX_URL_LEN
#define WAPI_USERAGENT		"Valve/Steam HTTP Client 1.0"
#define WAPI_GFDETAILS		"http://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"

// Next Map Mode
// https://forums.alliedmods.net/showthread.php?p=1831213
#define CASUAL				0
#define COMPETITIVE			1
#define ARMSRACE			2
#define DEMOLITION			3
#define DEATHMATCH			4

// Extended Map Chooser
#define PLUGIN_EMC			"mapchooser"
#define ERROR_NO_EMC		"[WML] Command unavailable, Extended MapChooser not found!"
new bool:g_IsMapChooserLoaded = false;
new bool:g_HasVoteOccured = false;

// Database
new Handle:g_dbiStorage = INVALID_HANDLE;

// System
new g_SelectedMode = -1;
new bool:g_IsChangingLevel = false;
new Handle:g_cvarChangeMode = INVALID_HANDLE;
new Handle:g_cvarGameType = INVALID_HANDLE;
new Handle:g_cvarGameMode = INVALID_HANDLE;
new Handle:g_cvarAutoLoad = INVALID_HANDLE;

// Menu
new Handle:g_MapMenu = INVALID_HANDLE;

// Regex
new Handle:g_RegexId = INVALID_HANDLE;
new Handle:g_RegexMap = INVALID_HANDLE;


public Plugin:myinfo =
{
	name = "Workshop Map Loader",
	author = "Nefarius",
	description = "Advanced Workshop Map Loader and Game Type Adjuster",
	version = PLUGIN_VERSION,
	url = "https://github.com/nefarius/WorkshopMapLoader"
}

/*
 * Plugin load event.
 */
public OnPluginStart()
{
	// *** Internals ***
	// Pre-compile regex to improve performance
	g_RegexId = CompileRegex("\\/(\\d*)\\/");
	g_RegexMap = CompileRegex("[^/]+$");
	
	// *** Cvars ***
	// Plugin version
	CreateConVar("sm_wml_version", PLUGIN_VERSION, 
		"Version of Workshop Map Loader", 
		FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_UNLOGGED|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	// Allow user to control changemode behaviour
	g_cvarChangeMode = CreateConVar("sm_wml_changemode", "1", 
		"Automatically adjust game mode/type to map category <1 = Enabled/Default, 0 = Disabled>", 
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	if (g_cvarChangeMode == INVALID_HANDLE)
		LogError("[WML] Couldn't register 'sm_wml_changemode'!");
	// Refresh map details on plugin load
	g_cvarAutoLoad = CreateConVar("sm_wml_autoreload", "1",
		"Automatically refresh map info on plugin (re)load <1 = Enabled/Default, 0 = Disabled>",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	if (g_cvarAutoLoad == INVALID_HANDLE)
		LogError("[WML] Couldn't register 'sm_wml_autoreload'!");
	
	// *** Cmds ***
	RegAdminCmd("sm_wml", Cmd_DisplayMapList, ADMFLAG_CHANGEMAP, 
		"Display map list of workshop maps");
	RegAdminCmd("sm_wml_reload", Cmd_ReloadMapList, ADMFLAG_CHANGEMAP, 
		"(Re)download map details from Steam");
	RegAdminCmd("sm_wml_vote_now", Cmd_VoteNow, ADMFLAG_CHANGEMAP, 
		"Bring up map vote menu");
	RegAdminCmd("sm_wml_nominate_random_maps", Cmd_NominateRandom, ADMFLAG_CHANGEMAP, 
		"Bring up map vote menu");

	// *** Hooks ***
	g_cvarGameType = FindConVar("game_type");
	g_cvarGameMode = FindConVar("game_mode");
	// Intercept game mode/type changes
	HookConVarChange(g_cvarGameType, OnConvarChanged);
	HookConVarChange(g_cvarGameMode, OnConvarChanged);
	// Intercept round end for mapchooser
	HookEvent("cs_win_panel_match", Event_GameEnd, EventHookMode_PostNoCopy);
	
	// Load/Store Cvars
	AutoExecConfig(true, PLUGIN_SHORT_NAME);
}

/*
 * Gets fired after Plugin has loaded all configs.
 */
public OnConfigsExecuted()
{
	new String:error[MAX_ERROR_LEN];
	
	// Open database connection
	g_dbiStorage = SQLite_UseDatabase(WML_DB_NAME, error, sizeof(error));
	if (g_dbiStorage == INVALID_HANDLE)
	{
		SetFailState("Could not open database: %s", error);
	}
	
	// Perform initial database tasks
	DB_CreateTables();
	// Start fetching content if wished by user
	if (GetConVarBool(g_cvarAutoLoad))
		GenerateMapList();
}

/*
 * Gets fired on end of match.
 */
public Action:Event_GameEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	LogMessage("Detected end of game");
	
	if (g_HasVoteOccured)
	{
		g_HasVoteOccured = false;
		// Delay actual changelevel so players can see the leader board
		new Float:delay = GetConVarFloat(FindConVar("mp_endmatch_votenextleveltime"));
		new String:map[PLATFORM_MAX_PATH + 1];
		GetNextMap(map, sizeof(map));
		LogMessage("Changing map to %s", map);
		// Trigger delayed changelevel2
		ChangeLevel2(map, delay);
	}
	
	return Plugin_Continue;
}

/*
 * Gets fired after vote has ended.
 */
public OnMapVoteEnd(const String:map[])
{
	LogMessage("%s has been chosen to be the next map", map);
	g_HasVoteOccured = true;
}

public Action:Cmd_NominateRandom(client, args)
{
	// Is Extended MapChooser available
	if (!g_IsMapChooserLoaded)
	{
		PrintToChat(client, ERROR_NO_EMC);
		return Plugin_Handled;
	}
	
	// Is argument supplied
	if (args < 1)
	{
		PrintToConsole(client, "No argument specified.");
		return Plugin_Handled;
	}
	
	decl String:buffer[3];
	new count = 0;
	
	GetCmdArgString(buffer, sizeof(buffer));
	// Is argument valid/within range
	if (0 >= (count = StringToInt(buffer)))
	{
		PrintToConsole(client, "Invalid argument specified.");
		return Plugin_Handled;
	}
	
	decl String:mode[MAX_ATTRIB_LEN];
	// Detect current mode to query only matching maps
	switch (GetMode())
	{
		case CASUAL:
			mode = TAG_Classic;
		case COMPETITIVE:
			mode = TAG_Hostage;
		case ARMSRACE:
			mode = TAG_Armsrace;
		case DEMOLITION:
			mode = TAG_Demolition;
		case DEATHMATCH:
			mode = TAG_Deathmatch;
		default:
		{
			PrintToConsole(client, "Couldn't detect valid game mode!");
			return Plugin_Handled;
		}
	}
	
	decl String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		SELECT 'workshop/' || Id || '/' || Map FROM wml_workshop_maps \
		WHERE Tag = \"%s\" \
		ORDER BY RANDOM() LIMIT %d;", mode, count);
	
	SQL_LockDatabase(g_dbiStorage);	
	new Handle:h_Query = SQL_Query(g_dbiStorage, query);
	
	decl String:map[MAX_ID_LEN];
	// Enumerate through all the results
	while (SQL_FetchRow(h_Query))
	{
		SQL_FetchString(h_Query, 0, map, sizeof(map));
		switch (NominateMap(map, true, client))
		{
			case Nominate_Added:
				PrintToConsole(client, "Nominated map: %s", map);
			case Nominate_InvalidMap:
				PrintToConsole(client, "Couldn't nominate %s", map);
			case Nominate_Replaced:
				PrintToConsole(client, "%s replaced an existing nomination", map);
			case Nominate_AlreadyInVote:
				PrintToConsole(client, "%s is already nominated", map);
		}
	}
	
	SQL_UnlockDatabase(g_dbiStorage);
	
	return Plugin_Handled;
}

public Action:Cmd_VoteNow(client, args)
{
	if (!g_IsMapChooserLoaded)
	{
		PrintToChat(client, ERROR_NO_EMC);
		return Plugin_Handled;
	}

	InitiateMapChooserVote(MapChange_MapEnd);
	
	return Plugin_Handled;
}

/*
 * Plugin unload event.
 */
public OnPluginEnd()
{
	if (g_RegexId != INVALID_HANDLE)
		CloseHandle(g_RegexId);
		
	if (g_RegexMap != INVALID_HANDLE)
		CloneHandle(g_RegexMap);
	
	if (g_MapMenu != INVALID_HANDLE)
		CloseHandle(g_MapMenu);
	
	// Close database connection
	if (g_dbiStorage != INVALID_HANDLE)
		CloseHandle(g_dbiStorage);
}

/*
 * Gets fired after all plugins where loaded.
 */
public OnAllPluginsLoaded()
{
	if (LibraryExists(PLUGIN_EMC))
		g_IsMapChooserLoaded = EMC_IsOnMapVoteEndPresent();
}

/*
 * Checks if extended API is present.
 */
bool:EMC_IsOnMapVoteEndPresent()
{
	return (GetFeatureStatus(FeatureType_Native, "IsMapOfficial") == FeatureStatus_Available);
}

/*
 * Gets fired after a plugin was loaded.
 */
public OnLibraryAdded(const String:name[])
{
	// Check for presence of Extended MapChooser
	if (StrEqual(name, PLUGIN_EMC))
		g_IsMapChooserLoaded = EMC_IsOnMapVoteEndPresent();
}

/*
 * Gets fired after a plugin was unloaded.
 */
public OnLibraryRemoved(const String:name[])
{
	// Check for presence of Extended MapChooser
	if (StrEqual(name, PLUGIN_EMC))
		g_IsMapChooserLoaded = EMC_IsOnMapVoteEndPresent();
}

/*
 * Gets fired after map has finished loading.
 */
public OnMapStart()
{
	// This will activate Cvar Hook only on map change
	// Important to not bust other plugins
	g_IsChangingLevel = false;
	
	// no return required
}

/*
 * Intercepts changing the game mode/type variables from outside the plugin.
 */
public OnConvarChanged(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	// Validate handle
	if (g_cvarChangeMode != INVALID_HANDLE)
	{
		// Only execute if user allowed it and on right time
		if (GetConVarBool(g_cvarChangeMode) && g_IsChangingLevel)
		{
			// Let everything pass 
			if (cvar == g_cvarGameMode || cvar == g_cvarGameType)
			{
				PrintToServer("[WML] Game Mode/Type changed outside of WML, correcting...");
				// Override settings
				ChangeMode(g_SelectedMode);
			}
		}
	}
}

/*
 * Gets called when response is received.
 * TODO: proper handling if response is over 4KBytes.
 */
public OnGetPage(const String:output[], const size, CMDReturn:status, any:data)
{
	// Response is complete
	if(status == CMD_SUCCESS)
	{
		// Get associated ID
		decl String:id[MAX_ID_LEN];
		ResetPack(data);
		ReadPackString(data, id, sizeof(id));
		CloseHandle(data);
		
		// Create temporary directory
		decl String:path[PLATFORM_MAX_PATH + 1];
		BuildPath(Path_SM, path, sizeof(path), "%s", WML_TMP_DIR);
		if (!DirExists(path))
			CreateDirectory(path, 511);
		// Create Kv file
		BuildPath(Path_SM, path, sizeof(path), "%s/%s.txt", WML_TMP_DIR, id);
		new Handle:file = OpenFile(path, "wt");
		if (file == INVALID_HANDLE)
			LogError("Couldn't create tmp file!");
		WriteFileString(file, output, false);
		CloseHandle(file);
		
		// Begin parse response
		new Handle:kv = CreateKeyValues("response");
		if(kv != INVALID_HANDLE)
		{
			if (FileToKeyValues(kv, path))
			{
				BrowseKeyValues(kv, id);
				CloseHandle(kv);
				// Once the map has been tagged, it's origin may be purged
				DB_RemoveUntagged(StringToInt(id));
			}
			else
				LogError("Couldn't open KeyValues!");
		}
		
		// Delete (temporary) Kv file
		DeleteFile(path);
	}
}

/*
 * Get current game mode/type.
 */
GetMode()
{
	new type = GetConVarInt(g_cvarGameType);
	new mode = GetConVarInt(g_cvarGameMode);
	
	if (type == 0 && mode == 0)
		return CASUAL;
	if (type == 0 && mode == 1)
		return COMPETITIVE;
	if (type == 1 && mode == 0)
		return ARMSRACE;
	if (type == 1 && mode == 1)
		return DEMOLITION;
	if (type == 1 && mode == 2)
		return DEATHMATCH;
		
	return -1;
}

/*
 * Changes game type and game mode to set value
 */
ChangeMode(mode)
{
	switch (mode)
	{
		case CASUAL:
			ChangeModeCasual();
		case COMPETITIVE:
			ChangeModeCompetitive();
		case ARMSRACE:
			ChangeModeArmsrace();
		case DEMOLITION:
			ChangeModeDemolition();
		case DEATHMATCH:
			ChangeModeDeathmatch();
	}
}

// https://forums.alliedmods.net/showthread.php?p=1891305
ChangeModeCasual()
{
	SetConVarInt(g_cvarGameType, 0);
	SetConVarInt(g_cvarGameMode, 0);
}

ChangeModeCompetitive()
{
	SetConVarInt(g_cvarGameType, 0);
	SetConVarInt(g_cvarGameMode, 1);
}

ChangeModeArmsrace()
{
	SetConVarInt(g_cvarGameType, 1);
	SetConVarInt(g_cvarGameMode, 0);
}

ChangeModeDemolition()
{
	SetConVarInt(g_cvarGameType, 1);
	SetConVarInt(g_cvarGameMode, 1);
}

ChangeModeDeathmatch()
{
	SetConVarInt(g_cvarGameType, 1);
	SetConVarInt(g_cvarGameMode, 2);
}

/*
 * API Call to fetch Workshop ID details.
 */
GetPublishedFileDetails(const String:id[])
{
	// Build URL
	decl String:request[MAX_URL_LEN];
	//Format(request, MAX_URL_LEN, "%s?key=%s", WAPI_GFDETAILS, g_SteamAPIKey);
	Format(request, MAX_URL_LEN, "%s", WAPI_GFDETAILS);
	// Build POST
	decl String:data[MAX_POST_LEN];
	Format(data, MAX_POST_LEN, "itemcount=1&publishedfileids%%5B0%%5D=%s&format=vdf", id);
	
#if defined WML_DEBUG
	PrintToServer("Requested: %s, length: %d", request, strlen(request));
	PrintToServer("POST String: %s", data);
	PrintToServer("User Agent: %s", WAPI_USERAGENT);
#endif
	
	// Attach ID to keep track of response
	new Handle:pack = CreateDataPack();
	WritePackString(pack, id);
	System2_GetPage(OnGetPage, request, data, WAPI_USERAGENT, pack);
}

/*
 * Dives through local stored map info file.
 */
BrowseKeyValues(Handle:kv, const String:id[])
{
	decl String:buffer[MAX_ATTRIB_LEN];

	do
	{
		// You can read the section/key name by using KvGetSectionName here.
 
		if (KvGotoFirstSubKey(kv, false))
		{
			// Current key is a section. Browse it recursively.
			BrowseKeyValues(kv, id);
			KvGoBack(kv);
		}
		else
		{
			// Current key is a regular key, or an empty section.
			if (KvGetDataType(kv, NULL_STRING) != KvData_None)
			{
				// Read value of key here (use NULL_STRING as key name). You can
				// also get the key name by using KvGetSectionName here.
				KvGetSectionName(kv, buffer, sizeof(buffer));
				if (StrEqual("publishedfileid", buffer, false))
				{
					// TODO: We already have this value, maybe compare for check?
					//KvGetString(kv, NULL_STRING, buffer, sizeof(buffer));
#if defined WML_DEBUG
					PrintToServer("ID: %s", buffer);
#endif
				}
				else if (StrEqual("title", buffer, false))
				{
					// Retrieve and store official map title
					KvGetString(kv, NULL_STRING, buffer, sizeof(buffer));
#if defined WML_DEBUG
					PrintToServer("Title: %s", buffer);
#endif
					DB_SetMapTitle(StringToInt(id), buffer);
				}
				else if (StrEqual("tag", buffer, false))
				{
					// Retrieve tag and associate map with it
					KvGetString(kv, NULL_STRING, buffer, sizeof(buffer));
#if defined WML_DEBUG
					PrintToServer("Tag: %s", buffer);
#endif
					DB_SetMapTag(StringToInt(id), buffer);
				}
			}
			else
			{
				// Found an empty sub section. It can be handled here if necessary.
			}
		}
	} while (KvGotoNextKey(kv, false));
}

/*
 * Refreshing the map list requested.
 */
public Action:Cmd_ReloadMapList(client, args)
{
	PrintToConsole(client, "[SM] Refreshing map list...");
	GenerateMapList();
	
	return Plugin_Handled;
}

/*
 * Displaying in-game menu to user.
 */
public Action:Cmd_DisplayMapList(client, args)
{
	// NOTE: stored to g_MapMenu to make Back button work
	if ((g_MapMenu = BuildCategoryMenu()) == INVALID_HANDLE)
	{
		PrintToConsole(client, "[WML] The map list and/or menu could not be generated!");
		return Plugin_Handled;
	}	
 
	DisplayMenu(g_MapMenu, client, MENU_TIME_FOREVER);
 
	return Plugin_Handled;
}

/*
 * Builds map category top-level menu.
 */
Handle:BuildCategoryMenu()
{
	// Create main menu handle
	new Handle:menu = CreateMenu(Menu_SelectedCategory);
	SetMenuTitle(menu, "Please select map category:");
	AddMenuItem(menu, TAG_Classic, TAG_Classic);
	AddMenuItem(menu, TAG_Deathmatch, TAG_Deathmatch);
	AddMenuItem(menu, TAG_Demolition, TAG_Demolition);
	AddMenuItem(menu, TAG_Armsrace, TAG_Armsrace);
	AddMenuItem(menu, TAG_Hostage, TAG_Hostage);
	AddMenuItem(menu, TAG_Custom, TAG_Custom);
	
	return menu;
}

/*
 * Gets called if user navigated through category menu.
 */
public Menu_SelectedCategory(Handle:menu, MenuAction:action, param1, param2)
{
	// An item was selected
	if (action == MenuAction_Select)
	{
		// Stores map id
		new String:info[MAX_ATTRIB_LEN];
		new Handle:h_MapMenu = INVALID_HANDLE;
 
		// Validate passed item
		new bool:found = GetMenuItem(menu, param2, info, MAX_ATTRIB_LEN);
		
		// Set selected mode and build maps sub-menu
		if (found)
		{
			if (StrEqual(info, TAG_Classic, false))
			{
				g_SelectedMode = CASUAL;
			}
			else if (StrEqual(info, TAG_Deathmatch, false))
			{
				g_SelectedMode = DEATHMATCH;
			}
			else if (StrEqual(info, TAG_Demolition, false))
			{
				g_SelectedMode = DEMOLITION;
			}
			else if (StrEqual(info, TAG_Armsrace, false))
			{
				g_SelectedMode = ARMSRACE;
			}
			else if (StrEqual(info, TAG_Hostage, false))
			{
				g_SelectedMode = COMPETITIVE;
			}
			else if (StrEqual(info, TAG_Custom, false))
			{
				g_SelectedMode = CASUAL;
			}
			
			h_MapMenu = BuildMapMenu(info);
			
			DisplayMenu(h_MapMenu, param1, MENU_TIME_FOREVER);
		}
	}
	/*
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	*/
}

/*
 * Create database tables if they don't exist.
 */
DB_CreateTables()
{
	if (g_dbiStorage == INVALID_HANDLE)
		return;

	new String:error[MAX_ERROR_LEN];

	if (!SQL_FastQuery(g_dbiStorage, "\
		CREATE TABLE IF NOT EXISTS wml_workshop_maps ( \
			Id INTEGER NOT NULL, \
			Tag TEXT NOT NULL, \
			Map TEXT NOT NULL, \
			Title TEXT NOT NULL, \
			UNIQUE(Id, Tag, Map, Title) ON CONFLICT REPLACE \
	);"))
	{
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		SetFailState("Creating wml_maps_all failed: %s", error);
	}
}

/*
 * Removes an entry identified by Id if tag-less.
 */
DB_RemoveUntagged(id)
{
	if (g_dbiStorage == INVALID_HANDLE)
		return;
	
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		DELETE FROM wml_workshop_maps \
		WHERE Tag = '' AND Id = %d;", id);
	
	SQL_LockDatabase(g_dbiStorage);
	SQL_FastQuery(g_dbiStorage, query);
	SQL_UnlockDatabase(g_dbiStorage);
}

/*
 * Adds skeleton of new map to database.
 */
 DB_AddNewMap(id, String:file[])
 {
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		INSERT OR REPLACE INTO wml_workshop_maps VALUES \
			(%d, \"\", \"%s\", \"\");", id, file);

	SQL_LockDatabase(g_dbiStorage);
	if (!SQL_FastQuery(g_dbiStorage, query))
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
 }
 
 /*
 * Adds title to map with specified id.
 */
 DB_SetMapTitle(id, String:title[])
 {
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		UPDATE OR REPLACE wml_workshop_maps \
		SET Title = \"%s\" WHERE Id = %d;", title, id);

	SQL_LockDatabase(g_dbiStorage);
	if (!SQL_FastQuery(g_dbiStorage, query))
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed setting map title (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
 }
 
 /*
 * Adds tag to map with specified id.
 */
 DB_SetMapTag(id, String:tag[])
 {
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		INSERT INTO wml_workshop_maps (Id, Tag, Map, Title) \
		SELECT Id, \"%s\", Map, Title \
		FROM wml_workshop_maps \
		WHERE Id = %d;", tag, id);

	SQL_LockDatabase(g_dbiStorage);
	if (!SQL_FastQuery(g_dbiStorage, query))
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed setting map tag (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
 }
 
/*
 * Helper to get local map path from ID.
 */
bool:DB_GetMapPath(id, String:path[])
{
	new Handle:h_Query = INVALID_HANDLE;
	new String:query[MAX_QUERY_LEN];
	
	Format(query, sizeof(query), " \
		SELECT 'workshop/' || Id || '/' || Map \
		FROM wml_workshop_maps WHERE Id = %d;", id);
		
	SQL_LockDatabase(g_dbiStorage);
	h_Query = SQL_Query(g_dbiStorage, query);
	if (h_Query == INVALID_HANDLE)
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed setting map tag (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
			
	if (!SQL_FetchRow(h_Query))
		return false;
	
	SQL_FetchString(h_Query, 0, path, PLATFORM_MAX_PATH + 1);
	
	return true;
}

/*
 * Build simple list-style map chooser menu.
 */
Handle:BuildMapMenu(String:category[])
{
	// Create main menu handle
	new Handle:menu = CreateMenu(Menu_ChangeMap);
	new String:id[MAX_ID_LEN];
	new String:tag[MAX_ATTRIB_LEN];
	new Handle:h_Query = INVALID_HANDLE;
	new String:query[MAX_QUERY_LEN];

	Format(query, sizeof(query), " \
		SELECT Id, Title FROM wml_workshop_maps \
		WHERE Tag = \"%s\" \
		ORDER BY Title COLLATE NOCASE ASC;",
		category);
		
	SQL_LockDatabase(g_dbiStorage);
	h_Query = SQL_Query(g_dbiStorage, query);
	if (h_Query != INVALID_HANDLE)
	{
		while (SQL_FetchRow(h_Query))
		{
			SQL_FetchString(h_Query, 0, id, sizeof(id));
			SQL_FetchString(h_Query, 1, tag, sizeof(tag));
			AddMenuItem(menu, id, tag);
		}
	}
	SQL_UnlockDatabase(g_dbiStorage);
 
	// Finally, set the title
	SetMenuTitle(menu, "Please select a map:");
	SetMenuExitBackButton(menu, true);
 
	return menu;
}

/*
 * Gets called if user navigated through maps menu.
 */
public Menu_ChangeMap(Handle:menu, MenuAction:action, param1, param2)
{
	// User selected item
	if (action == MenuAction_Select)
	{
		// Stores map id
		new String:id[MAX_ID_LEN];
 
		// Validate passed item
		if (GetMenuItem(menu, param2, id, MAX_ID_LEN))
		{
			new String:map[PLATFORM_MAX_PATH + 1];
			if (DB_GetMapPath(StringToInt(id), map))
			{
				// Send info to client
				PrintToChatAll("[WML] Changing map to %s", map);
		 
				// Change the map
				if (IsMapValid(map))
				{
					if (g_cvarChangeMode != INVALID_HANDLE)
						if (GetConVarBool(g_cvarChangeMode))
						{
							PrintToServer("[WML] Changing mode to: %d", g_SelectedMode);
							ChangeMode(g_SelectedMode);
						}
					
					ChangeLevel2(map);
				}
				else
					LogError("Map '%s' unexpectedly couldn't be validated!", map);
			}
			else
				LogError("Map '%s' wasn't found in the database!", id);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		// On menu exit back, revert to category menu
		if (param2 == MenuCancel_ExitBack)
		{
			DisplayMenu(g_MapMenu, param1, MENU_TIME_FOREVER);
		}
		else if (param2 == MenuCancel_Exit)
		{
			// In this case the user aborted map selection, we may free
			CloseHandle(g_MapMenu);
		}
	}
	else if (action == MenuAction_End)
	{
		// This sub-menu is regenerated every time so free up memory
		CloseHandle(menu);
	}
}

/*
 * Perform map change.
 */
ChangeLevel2(const String:map[], const Float:delay=2.0)
{
	// Submit map name to timer callback
	new Handle:h_MapName = CreateDataPack();
	WritePackString(h_MapName, map);
	// Delay for chat messages
	CreateTimer(delay, PerformMapChange, h_MapName);
}

/*
 * Commands the server to change level.
 */
public Action:PerformMapChange(Handle:timer, Handle:pack)
{
	// Unpack map name
	new String:map[PLATFORM_MAX_PATH + 1];
	ResetPack(pack);
	ReadPackString(pack, map, sizeof(map));
	CloseHandle(pack);
	
	// We enter protected state
	g_IsChangingLevel = true;
	// Fire!
	ServerCommand("changelevel2 %s", map);
}

/*
 * Trims away file extension and adds element to global map list.
 */
AddMapToList(String:map[])
{
	if (StrEqual(map[strlen(map) - 3], "bsp", false))
	{
		// Cuts off file extension
		map[strlen(map) - 4] = '\0';
		
		// Extract workshop ID
		decl String:id[MAX_ID_LEN];
		MatchRegex(g_RegexId, map);
		GetRegexSubString(g_RegexId, 1, id, MAX_ID_LEN);
		
		decl String:file[MAX_ATTRIB_LEN];
		MatchRegex(g_RegexMap, map);
		GetRegexSubString(g_RegexMap, 0, file, MAX_ID_LEN);
		
		// Add map skeleton to database
		DB_AddNewMap(StringToInt(id), file);

		// Fetch workshop item info
		GetPublishedFileDetails(id);
	}
}

/*
 * Builds in-memory map list and user menu.
 * */
GenerateMapList()
{
	// Dive through file system
	ReadFolder(WORKSHOP_BASE_DIR);
}

/*
 * Recursively fetch content of given folder.
 */
ReadFolder(String:path[])
{
	new Handle:dirh = INVALID_HANDLE;
	new String:buffer[PLATFORM_MAX_PATH + 1];
	new String:tmp_path[PLATFORM_MAX_PATH + 1];

	dirh = OpenDirectory(path);
	if (dirh == INVALID_HANDLE)
	{
		LogError("[WML] Couldn't find the workshop folder, maybe you don't have downloaded maps yet?");
		return;
	}
	
	new FileType:type;
	
	// Enumerate directory elements
	while(ReadDirEntry(dirh, buffer, sizeof(buffer), type))
	{
		new len = strlen(buffer);
		
		// Null-terminate if last char is newline
		if (buffer[len-1] == '\n')
			buffer[--len] = '\0';

		// Remove spaces
		TrimString(buffer);

		// Skip empty, current and parent directory names
		if (!StrEqual(buffer, "", false) && !StrEqual(buffer, ".", false) && !StrEqual(buffer, "..", false))
		{
			// Match files
			if(type == FileType_File)
			{
				strcopy(tmp_path, PLATFORM_MAX_PATH, path[5]);
				StrCat(tmp_path, PLATFORM_MAX_PATH, "/");
				StrCat(tmp_path, PLATFORM_MAX_PATH, buffer);
				// Adds map path to the end of map list
				AddMapToList(tmp_path);
			}
			else // Dive deeper if it's a directory
			{
				strcopy(tmp_path, PLATFORM_MAX_PATH, path);
				StrCat(tmp_path, PLATFORM_MAX_PATH, "/");
				StrCat(tmp_path, PLATFORM_MAX_PATH, buffer);
				ReadFolder(tmp_path);
			}
		}
	}

	// Clean-up
	CloseHandle(dirh);
}
