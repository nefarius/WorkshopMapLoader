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
#undef REQUIRE_PLUGIN
#include <mapchooser>
#include <updater>
#define REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#include <system2>
#include <cURL>

#define PLUGIN_VERSION 		"0.13.0"
#define PLUGIN_SHORT_NAME	"wml"
#define WORKSHOP_BASE_DIR 	"maps/workshop"
#define WML_TMP_DIR			"data/wml"
#define WML_DB_NAME			"nefarius-wml"

// Plugin Limits
#define MAX_ID_LEN			64
#define MAX_ATTRIB_LEN		32
#define MAX_QUERY_LEN		255
#define MAX_ERROR_LEN		255
#define MAX_TAGS			6

// Web API
#define MAX_URL_LEN			128
#define MAX_POST_LEN		MAX_URL_LEN
#define WAPI_USERAGENT		"Valve/Steam HTTP Client 1.0"

// Workshop tag names
enum
{
	MapTag_Classic = 0,
	MapTag_Deathmatch = 1,
	MapTag_Demolition = 2,
	MapTag_Armsrace = 3,
	MapTag_Hostage = 4,
	MapTag_Custom = 5
}

new const String:g_Tags[MAX_TAGS][MAX_ATTRIB_LEN] =
{
	"Classic",
	"Deathmatch",
	"Demolition",
	"Armsrace",
	"Hostage",
	"Custom"
};

// Map Chooser
#define PLUGIN_MC			"mapchooser"
new bool:g_IsMapChooserLoaded = false;
new bool:g_IsVoteInTriggered = false;

// Updater
#define PLUGIN_UPDATER		"updater"
#define UPDATE_URL			"https://git.nefarius.at/WorkshopMapLoader/master/updatefile.txt"

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
new Handle:g_cvarNominateAll = INVALID_HANDLE;
new Handle:g_cvarMapcyclefile = INVALID_HANDLE;
new Handle:g_cvarUseMapcyclefile = INVALID_HANDLE;

// Menu
new Handle:g_MapMenu = INVALID_HANDLE;

// Regex
new Handle:g_RegexId = INVALID_HANDLE;
new Handle:g_RegexMap = INVALID_HANDLE;

// Supported operating system types
enum
{
	OSType_Unknown = 0,
	OSType_Windows = 1,
	OSType_Linux = 2,
}

#include "wml/wml.database.sp"
#include "wml/wml.gamemode.sp"
#include "wml/wml.steamapi.sp"
#include "wml/wml.commands.sp"
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
 * Pre-plugin load event.
 */
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// cURL
	MarkNativeAsOptional("curl_OpenFile");
	MarkNativeAsOptional("curl_easy_init");
	MarkNativeAsOptional("curl_easy_setopt_handle");
	MarkNativeAsOptional("curl_easy_setopt_string");
	MarkNativeAsOptional("curl_easy_perform_thread");
	MarkNativeAsOptional("curl_easy_strerror");
	MarkNativeAsOptional("curl_easy_setopt_int_array");
	
	// System2
	MarkNativeAsOptional("System2_GetPage");
	
	// Updater
	MarkNativeAsOptional("Updater_AddPlugin");
	MarkNativeAsOptional("ReloadPlugin");
	
	// Mapchooser
	MarkNativeAsOptional("NominateMap");
	MarkNativeAsOptional("InitiateMapChooserVote");
	
	return APLRes_Success;
}
 
/*
 * Plugin load event.
 */
public OnPluginStart()
{
	// *** Internals ***
	// Pre-compile regex to improve performance
	// Extracts ID from workshop path
	g_RegexId = CompileRegex("\\/(\\d*)\\/");
	// Matches workshop map path
	g_RegexMap = CompileRegex("[^/]+$");
	
	// Load translations
	LoadTranslations("common.phrases");
	LoadTranslations("wml.phrases");
	
	// Open database connection
	decl String:error[MAX_ERROR_LEN];
	g_dbiStorage = SQLite_UseDatabase(WML_DB_NAME, error, sizeof(error));
	if (g_dbiStorage == INVALID_HANDLE)
		SetFailState("Could not open database: %s", error);
	// Perform initial database tasks
	DB_CreateTables();
	
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
	// Allow all map types for nomination
	g_cvarNominateAll = CreateConVar("sm_wml_nominate_all_maps", "0",
		"Allow all maps to get nominated <1 = Enabled, 0 = Disabled/Default>",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	if (g_cvarNominateAll == INVALID_HANDLE)
		LogError("Couldn't register 'sm_wml_nominate_all_maps'!");
	// Write custom mapcycle file to use for 3rd party plugins
	g_cvarUseMapcyclefile = CreateConVar("sm_wml_override_mapcycle", "1",
		"Set mapcyclefile to workshop customized version <1 = Enabled/Default, 0 = Disabled>",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	if (g_cvarUseMapcyclefile == INVALID_HANDLE)
		LogError("Couldn't register 'sm_wml_override_mapcycle'!");
	
	// *** Cmds ***
	RegAdminCmd("sm_wml", Cmd_DisplayMapList, ADMFLAG_CHANGEMAP, 
		"Display map list of workshop maps");
	RegAdminCmd("sm_wml_reload", Cmd_ReloadMapList, ADMFLAG_CHANGEMAP, 
		"(Re)download map details from Steam");
	RegAdminCmd("sm_wml_rebuild", Cmd_RebuildMapList, ADMFLAG_CHANGEMAP,
		"Purges database content and downloads it freshly from Steam");
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
	// Get mapcyclefile to nominate workshop maps
	g_cvarMapcyclefile = FindConVar("mapcyclefile");
	if (g_cvarMapcyclefile == INVALID_HANDLE)
		LogError("Convar 'mapcyclefile' not found, can't nominate maps!");
		
	// Intercept round end for mapchooser
	HookEvent("cs_win_panel_match", Event_GameEnd, EventHookMode_PostNoCopy);
	// Intercept item equipment for mapchooser
	HookEvent("item_equip", Event_ItemEquip, EventHookMode_Post);
	
	// Create temporary directory
	decl String:path[PLATFORM_MAX_PATH + 1];
	BuildPath(Path_SM, path, sizeof(path), "%s", WML_TMP_DIR);
	if (!DirExists(path))
		CreateDirectory(path, 511);
	
	// Load/Store Cvars
	AutoExecConfig(true, PLUGIN_SHORT_NAME);
}

/*
 * Gets fired after Plugin has loaded all configs.
 */
public OnConfigsExecuted()
{
	// Refresh map metadata if wished by user
	if (GetConVarBool(g_cvarAutoLoad))
		GenerateMapList();
	
	// Generate mapcyclefile for 3rd party plugins
	if (GetConVarBool(g_cvarUseMapcyclefile))
		SetMapcycleFile();
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
		
	if (LibraryExists(PLUGIN_UPDATER))
		Updater_AddPlugin(UPDATE_URL);
}

/*
 * Gets fired after a plugin was loaded.
 */
public OnLibraryAdded(const String:name[])
{
	// Check for presence of Extended MapChooser
	if (StrEqual(name, PLUGIN_MC))
		g_IsMapChooserLoaded = true;
	
	if (StrEqual(name, PLUGIN_UPDATER))
		Updater_AddPlugin(UPDATE_URL);
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
	
	// Use different methods for each OS due to SRCDS bugs
	switch (GetOSType())
	{
		case OSType_Windows:
			ForceChangeLevel(map, "Workshop Map Loader");
		case OSType_Linux:
			ServerCommand("changelevel2 %s", map);
		case OSType_Unknown:
			LogError("Couldn't detect operating system! Maybe missing wml.os.gamedata.txt?");
	}
}

/*
 * Dives through local stored map info file.
 */
stock BrowseKeyValues(Handle:kv, const String:id[])
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
#if defined DEBUG
					PrintToServer("ID: %s", buffer);
#endif
				}
				else if (StrEqual("title", buffer, false))
				{
					// Retrieve and store official map title
					KvGetString(kv, NULL_STRING, buffer, sizeof(buffer));
#if defined DEBUG
					PrintToServer("Title: %s", buffer);
#endif
					DB_SetMapTitle(StringToInt(id), buffer);
				}
				else if (StrEqual("tag", buffer, false))
				{
					// Retrieve tag and associate map with it
					KvGetString(kv, NULL_STRING, buffer, sizeof(buffer));
#if defined DEBUG
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
stock ChangeLevel2(const String:map[], const Float:delay=2.0)
{
	// Submit map name to timer callback
	new Handle:h_MapName = CreateDataPack();
	WritePackString(h_MapName, map);
	// Delay for chat messages
	CreateTimer(delay, PerformMapChange, h_MapName);
}

/*
 * Detects underlying operating system.
 */
stock GetOSType()
{
	new Handle:conf = LoadGameConfigFile("wml.os.gamedata");
	
	if (conf == INVALID_HANDLE)
		return 0; // Error
	
	new WindowsOrLinux = GameConfGetOffset(conf, "WindowsOrLinux");
	CloseHandle(conf);
	
	return WindowsOrLinux; //1 for windows; 2 for linux
}

/*
 * Trims away file extension and adds element to global map list.
 */
stock AddMapToList(String:map[])
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
stock GenerateMapList()
{
	// Dive through file system
	ReadFolder(WORKSHOP_BASE_DIR);
}

stock SetMapcycleFile()
{
	if (g_cvarMapcyclefile == INVALID_HANDLE)
		return;
		
	new String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s", WML_TMP_DIR, "wml.mapcycle.txt");
	
	// Detect current mode to query only matching maps
	switch (GetMode())
	{
		case NextMapMode_Casual:
			CreateMapcycleFile(g_Tags[MapTag_Classic], path);
		case NextMapMode_Competitive:
			CreateMapcycleFile(g_Tags[MapTag_Hostage], path);
		case NextMapMode_Armsrace:
			CreateMapcycleFile(g_Tags[MapTag_Armsrace], path);
		case NextMapMode_Demolition:
			CreateMapcycleFile(g_Tags[MapTag_Demolition], path);
		case NextMapMode_Deathmatch:
			CreateMapcycleFile(g_Tags[MapTag_Deathmatch], path);
		case NextMapMode_Custom:
			CreateMapcycleFile(g_Tags[MapTag_Custom], path);
		default:
		{
			LogError("%T", "Unknown Game Mode Error", LANG_SERVER);
			return;
		}
	}
	
	// Set new mapcycle file
	SetConVarString(g_cvarMapcyclefile, path);
}