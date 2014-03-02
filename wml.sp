/*
 * Workshop Map Loader for Counter-Strike: Global Offensive
 *                    made by Benjamin "Nefarius" Höglinger
 *                                      http://nefarius.at/
 * 
 * BINARY, SOURCE & LICENSE
 * ========================
 * https://github.com/nefarius/WorkshopMapLoader
 * 
 */

#pragma semicolon 1
#include <sourcemod>
#include <regex>
#include <system2>
#undef REQUIRE_PLUGIN
#include <mapchooser>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION 		"0.4.28"
#define PLUGIN_SHORT_NAME	"wml"
#define WORKSHOP_BASE_DIR 	"maps/workshop"
#define WML_TMP_DIR			"data/wml"
#define WML_DB_NAME			"nefarius-wml"

// Plugin Limits
#define MAX_ID_LEN			64
#define MAX_ATTRIB_LEN		32
#define MAX_QUERY_LEN		255
#define MAX_ERROR_LEN		255

// Web API
#define MAX_URL_LEN			128
#define MAX_POST_LEN		MAX_URL_LEN
#define WAPI_USERAGENT		"Valve/Steam HTTP Client 1.0"

// Workshop tag names
#define TAG_Classic			"Classic"
#define TAG_Deathmatch		"Deathmatch"
#define TAG_Demolition		"Demolition"
#define TAG_Armsrace		"Armsrace"
#define TAG_Hostage			"Hostage"
#define TAG_Custom			"Custom"

// Map Chooser
#define PLUGIN_MC			"mapchooser"
#define ERROR_NO_MC			"[WML] Command unavailable, MapChooser not loaded!"
new bool:g_IsMapChooserLoaded = false;
new bool:g_IsVoteInTriggered = false;

// Database
new Handle:g_dbiStorage = INVALID_HANDLE;

// System
new g_SelectedMode = -1;
new bool:g_IsChangingLevel = false;
new bool:g_IsChangingMode = false;
new bool:g_IsArmsrace = false;
new Handle:g_cvarChangeMode = INVALID_HANDLE;
new Handle:g_cvarGameType = INVALID_HANDLE;
new Handle:g_cvarGameMode = INVALID_HANDLE;
new Handle:g_cvarAutoLoad = INVALID_HANDLE;
new Handle:g_cvarArmsraceWeapon = INVALID_HANDLE;

// Menu
new Handle:g_MapMenu = INVALID_HANDLE;

// Regex
new Handle:g_RegexId = INVALID_HANDLE;
new Handle:g_RegexMap = INVALID_HANDLE;

#include "wml/wml.database.sp"
#include "wml/wml.gamemode.sp"
#include "wml/wml.steamapi.sp"
#include "wml/wml.adminmenu.sp"
#include "wml/wml.filesystem.sp"


public Plugin:myinfo =
{
	name = "Workshop Map Loader",
	author = "Nefarius",
	description = "Advanced Workshop Map Loader and Game Type Adjuster",
	version = PLUGIN_VERSION,
	url = "https://github.com/nefarius/WorkshopMapLoader"
}

/* ================================================================================
 * BUILT-IN FORWARDS
 * ================================================================================
 */

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
		LogError("Couldn't register 'sm_wml_changemode'!");
	// Refresh map details on plugin load
	g_cvarAutoLoad = CreateConVar("sm_wml_autoreload", "1",
		"Automatically refresh map info on plugin (re)load <1 = Enabled/Default, 0 = Disabled>",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	if (g_cvarAutoLoad == INVALID_HANDLE)
		LogError("Couldn't register 'sm_wml_autoreload'!");
	// Enable special handling of Armsrace sessions
	g_cvarArmsraceWeapon = CreateConVar("sm_wml_armsrace_weapon", "awp",
		"Sets weapon on which the vote will be started on Armsrace <awp = Default>");
	if (g_cvarArmsraceWeapon == INVALID_HANDLE)
		LogError("Couldn't register 'sm_wml_armsrace_weapon'!");
	
	// *** Cmds ***
	RegAdminCmd("sm_wml", Cmd_DisplayMapList, ADMFLAG_CHANGEMAP, 
		"Display map list of workshop maps");
	RegAdminCmd("sm_wml_reload", Cmd_ReloadMapList, ADMFLAG_CHANGEMAP, 
		"(Re)download map details from Steam");
	RegAdminCmd("sm_wml_vote_now", Cmd_VoteNow, ADMFLAG_CHANGEMAP, 
		"Bring up map vote menu");
	RegAdminCmd("sm_wml_nominate_random_maps", Cmd_NominateRandom, ADMFLAG_CHANGEMAP, 
		"Nominate a specified amount of random maps from the database");

	// *** Hooks ***
	g_cvarGameType = FindConVar("game_type");
	// Intercept game mode/type changes
	if (g_cvarGameType != INVALID_HANDLE)
		HookConVarChange(g_cvarGameType, OnConvarChanged);
	else
		LogError("Convar 'game_type' not found! Are you running CS:GO?");
	// Intercept game mode/type changes	
	g_cvarGameMode = FindConVar("game_mode");
	if (g_cvarGameMode != INVALID_HANDLE)
		HookConVarChange(g_cvarGameMode, OnConvarChanged);
	else
		LogError("Convar 'game_mode' not found! Are you running CS:GO?");
		
	// Intercept round end for mapchooser
	HookEvent("cs_win_panel_match", Event_GameEnd, EventHookMode_PostNoCopy);
	// Intercept item equipment for mapchooser
	HookEvent("item_equip", Event_ItemEquip, EventHookMode_Post);
	
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
	else
		LogMessage("Database won't be refreshed because 'sm_wml_autoreload' is 0");
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
	if (LibraryExists(PLUGIN_MC))
		g_IsMapChooserLoaded = true;
}

/*
 * Gets fired after a plugin was loaded.
 */
public OnLibraryAdded(const String:name[])
{
	// Check for presence of Extended MapChooser
	if (StrEqual(name, PLUGIN_MC))
		g_IsMapChooserLoaded = true;
}

/*
 * Gets fired after a plugin was unloaded.
 */
public OnLibraryRemoved(const String:name[])
{
	// Check for presence of Extended MapChooser
	if (StrEqual(name, PLUGIN_MC))
		g_IsMapChooserLoaded = false;
}

/*
 * Gets fired after map has finished loading.
 */
public OnMapStart()
{
	// This will activate Cvar Hook only on map change
	// Important to not bust other plugins
	g_IsChangingLevel = false;
	
	// Check game mode only on start to improve performance
	if (GetMode() == NextMapMode_Armsrace)
		g_IsArmsrace = true;
	else
		g_IsArmsrace = false;
	
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
				// Prevent endless loop
				if (!g_IsChangingMode)
				{
					LogMessage("Game Mode/Type changed unexpectedly, correcting...");
					// Override settings
					ChangeMode(g_SelectedMode);
				}
			}
		}
	}
}

/*
 * Gets called when response is received.
 */
public OnGetPage(const String:output[], const size, CMDReturn:status, any:data)
{
	// Get associated ID
	decl String:id[MAX_ID_LEN];
	ResetPack(data);
	ReadPackString(data, id, sizeof(id));
	
	if (status == CMD_ERROR)
	{
		LogError("Steam API error: couldn't fetch data for file ID %s", id);
		CloseHandle(data);
		return;
	}
	
	// Create temporary directory
	decl String:path[PLATFORM_MAX_PATH + 1];
	BuildPath(Path_SM, path, sizeof(path), "%s", WML_TMP_DIR);
	if (!DirExists(path))
		CreateDirectory(path, 511);
	
	// Create Kv file
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.txt", WML_TMP_DIR, id);
	new Handle:file = OpenFile(path, "a+t");
	if (file == INVALID_HANDLE)
	{
		LogError("Couldn't create temporary file %s", path);
		CloseHandle(data);
		return;
	}
	
	// Interpret response status
	switch (status)
	{
		case CMD_PROGRESS:
		{
			LogMessage("Successfully received a part for file ID %s", id);
			WriteFileString(file, output, false);
			CloseHandle(file);
		}
		case CMD_SUCCESS:
		{
			CloseHandle(data);
			LogMessage("Successfully received file details for ID %s", id);
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
					LogError("Couldn't open KeyValues for file ID %s", id);
			}
			
			// Delete (temporary) Kv file
			DeleteFile(path);
		}
		default:
			CloseHandle(file);
	}
}

/* ================================================================================
 * CUSTOM CALLBACKS
 * ================================================================================
 */

/*
 * Gets fired if any player equips an item (used for Armsrace progression detection).
 */
public Action:Event_ItemEquip(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Only intercept if Armsrace mode detected
	if (g_IsArmsrace)
	{
		decl String:weapon[MAX_ATTRIB_LEN];
		GetEventString(event, "item", weapon, sizeof(weapon));
		
		decl String:setting[MAX_ATTRIB_LEN];
		GetConVarString(g_cvarArmsraceWeapon, setting, sizeof(setting));
		
		if (StrEqual(weapon, setting, false) && !g_IsVoteInTriggered)
		{
			if (!g_IsMapChooserLoaded)
				return Plugin_Continue;
			
			g_IsVoteInTriggered = true;
			
			// Get name of player who gained weapon
			new userid = GetEventInt(event, "userid");
			new user_index = 0;
			if ((user_index = GetClientOfUserId(userid)) > 0)
			{
				decl String:player[MAX_NAME_LENGTH];
				GetClientName(user_index, player, sizeof(player));
				// Log info
				LogMessage("Requesting vote because '%s' acquired weapon '%s'",
					player, weapon);
			}
			
			// Request vote
			InitiateMapChooserVote(MapChange_MapEnd);
		}
	}
	
	return Plugin_Continue;
}

/*
 * Gets fired on end of match.
 */
public Action:Event_GameEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	LogMessage("Detected end of game, initializing map change...");

	g_IsVoteInTriggered = false;
	// Delay actual changelevel so players can see the leader board
	new Float:delay = GetConVarFloat(FindConVar("mp_endmatch_votenextleveltime"));
	new String:map[PLATFORM_MAX_PATH + 1];
	GetNextMap(map, sizeof(map));
	LogMessage("Changing map to %s", map);
	// Trigger delayed changelevel2
	ChangeLevel2(map, delay);
	
	return Plugin_Continue;
}

/*
 * Command to add given amount of random maps to map nominations.
 * Needs mapchooser to be available.
 */
public Action:Cmd_NominateRandom(client, args)
{
	// Is Extended MapChooser available
	if (!g_IsMapChooserLoaded)
	{
		PrintToChat(client, ERROR_NO_MC);
		return Plugin_Handled;
	}
	
	// Is argument supplied
	if (args < 1)
	{
		PrintToConsole(client, "No argument specified");
		return Plugin_Handled;
	}
	
	decl String:buffer[3];
	new count = 0;
	
	GetCmdArgString(buffer, sizeof(buffer));
	// Is argument valid/within range
	if (0 >= (count = StringToInt(buffer)))
	{
		PrintToConsole(client, "Invalid argument specified");
		return Plugin_Handled;
	}
	
	decl String:mode[MAX_ATTRIB_LEN];
	// Detect current mode to query only matching maps
	switch (GetMode())
	{
		case NextMapMode_Casual:
			mode = TAG_Classic;
		case NextMapMode_Competitive:
			mode = TAG_Hostage;
		case NextMapMode_Armsrace:
			mode = TAG_Armsrace;
		case NextMapMode_Demolition:
			mode = TAG_Demolition;
		case NextMapMode_Deathmatch:
			mode = TAG_Deathmatch;
		case NextMapMode_Custom:
			mode = TAG_Custom;
		default:
		{
			PrintToConsole(client, "Couldn't detect valid game mode");
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
	CloseHandle(h_Query);
	
	return Plugin_Handled;
}

/*
 * Command to trigger next map vote.
 * Needs mapchooser to be available.
 */
public Action:Cmd_VoteNow(client, args)
{
	if (!g_IsMapChooserLoaded)
	{
		LogError("Vote was requested but MapChooser is not loaded");
		PrintToChat(client, ERROR_NO_MC);
		return Plugin_Handled;
	}

	LogMessage("Requested voting for next map");
	InitiateMapChooserVote(MapChange_MapEnd);
	
	return Plugin_Handled;
}

/*
 * Refreshing the map list requested.
 */
public Action:Cmd_ReloadMapList(client, args)
{
	PrintToConsole(client, "[WML] Refreshing map details...");
	GenerateMapList();
	PrintToConsole(client, "[WML] Done refreshing map details");
	
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
	LogMessage("Changing map to %s", map);
	// Fire!
	ServerCommand("changelevel2 %s", map);
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
				LogError("Unexpected section found in file with ID %s", id);
			}
		}
	} while (KvGotoNextKey(kv, false));
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

