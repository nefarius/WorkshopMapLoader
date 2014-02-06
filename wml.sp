#include <sourcemod>
#include <regex>
#include <system2>

#define PLUGIN_VERSION 		"0.2.0"
#define PLUGIN_SHORT_NAME	"sm_wml"
#define WORKSHOP_DIR		"workshop"
#define WORKSHOP_BASE_DIR 	"maps/workshop"
#define WML_TMP_DIR			"data/sm_wml"

// Workshop tag names
#define TAG_Classic			"Classic"
#define TAG_Deathmatch	 	"Deathmatch"
#define TAG_Demolition		"Demolition"
#define TAG_Armsrace		"Armsrace"
#define TAG_Hostage			"Hostage"
#define TAG_Custom			"Custom"

// Plugin Limits
#define MAX_ID_LEN		64
#define MAX_URL_LEN		128
#define MAX_ATTRIBS		8
#define MAX_ATTRIB_LEN	32

// Map attributes
#define MAP_PATH	0
#define MAP_TITLE	1

// Web API
#define MAXPOST MAX_URL_LEN
#define WAPI_USERAGENT		"Valve/Steam HTTP Client 1.0"
#define WAPI_GFDETAILS		"http://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
/*
#define WAPI_KEY_ERROR		"No API key specified or invalid format, major parts of plugin will not work!"
#define MAX_KEY_LENGTH		33
new String:g_SteamAPIKey[MAX_KEY_LENGTH];
new Handle:g_cvarAPIKey = 	INVALID_HANDLE;
*/

// Next Map Mode
// https://forums.alliedmods.net/showthread.php?p=1831213
#define CASUAL				0
#define COMPETITIVE			1
#define ARMSRACE			2
#define DEMOLITION			3
#define DEATHMATCH			4

new g_SelectedMode = 			-1;
new bool:g_IsChangingLevel =	false;
new Handle:g_cvarChangeMode = 	INVALID_HANDLE;
new Handle:h_cvarGameType =		INVALID_HANDLE;
new Handle:h_cvarGameMode =		INVALID_HANDLE;

new Handle:g_WsMapList = 		INVALID_HANDLE;
new Handle:g_WsMapDetails = 	INVALID_HANDLE;
new Handle:g_MapMenu = 			INVALID_HANDLE;

new Handle:g_WsMapsClassic =	INVALID_HANDLE;
new Handle:g_WsMapsDeathmatch =	INVALID_HANDLE;
new Handle:g_WsMapsDemolition =	INVALID_HANDLE;
new Handle:g_WsMapsArmsrace =	INVALID_HANDLE;
new Handle:g_WsMapsHostage =	INVALID_HANDLE;
new Handle:g_WsMapsCustom =		INVALID_HANDLE;

public Plugin:myinfo =
{
	name = "Workshop Map Loader",
	author = "Nefarius",
	description = "Advanced Workshop Map Loader and Game Type Adjuster",
	version = PLUGIN_VERSION,
	url = "http://nefarius.at/"
}

/*
 * Plugin load event.
 */
public OnPluginStart()
{
	// All map IDs
	g_WsMapList = 			CreateArray(MAX_ID_LEN, 0);
	// Map attributes
	g_WsMapDetails = 		CreateTrie();
	// Classic maps
	g_WsMapsClassic =		CreateArray(MAX_ID_LEN, 0);
	// Deathmatch maps
	g_WsMapsDeathmatch =	CreateArray(MAX_ID_LEN, 0);
	// Demolition maps
	g_WsMapsDemolition =	CreateArray(MAX_ID_LEN, 0);
	// Armsrace maps
	g_WsMapsArmsrace =		CreateArray(MAX_ID_LEN, 0);
	// Hostage maps
	g_WsMapsHostage =		CreateArray(MAX_ID_LEN, 0);
	// Custom maps
	g_WsMapsCustom =		CreateArray(MAX_ID_LEN, 0);
	
	// *** Cvars ***
	// Plugin version
	// NOTE: FCVAR_DONTRECORD doesn't work?!
	CreateConVar("sm_wml_version", PLUGIN_VERSION, 
		"Version of Workshop Map Loader", 
		FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_UNLOGGED|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	// Allow user to control changemode behaviour
	g_cvarChangeMode = CreateConVar("sm_wml_changemode", "1", 
		"Automatically adjust game mode/type to map category <1 = Enabled/Default, 0 = Disabled>", 
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	if (g_cvarChangeMode == INVALID_HANDLE)
		LogError("[WML] Couldn't register 'sm_wml_changemode'!");
	
	/* THIS IS NOT NEEDED RIGHT NOW!
	// Fetch Web API key
	g_cvarAPIKey = CreateConVar("sm_wml_api_key", "", 
		"The Servers' Steam Web API key. Visit 'https://steamcommunity.com/dev/apikey' if you don't have one.", 
		FCVAR_PROTECTED|FCVAR_SPONLY);
	if (g_cvarAPIKey == INVALID_HANDLE)
		SetFailState("[WML] Couldn't register 'sm_wml_api_key'!");
	*/
	
	// *** Cmds ***
	RegAdminCmd("sm_wml", DisplayMapList, ADMFLAG_CHANGEMAP, "Display map list of workshop maps");
	RegAdminCmd("sm_wml_reload", ReloadMapList, ADMFLAG_CHANGEMAP, "Re-create list of workshop maps");
	
#if defined WML_DEBUG
	RegAdminCmd("sm_wml_debug", PrintDebugOutput, ADMFLAG_CHANGEMAP, "Debug output");
#endif

	// *** Hooks ***
	h_cvarGameType = FindConVar("game_type");
	h_cvarGameMode = FindConVar("game_mode");
	// Intercept game mode/type changes
	HookConVarChange(h_cvarGameType, OnConvarChanged);
	HookConVarChange(h_cvarGameMode, OnConvarChanged);
	
	// Load/Store Cvars
	AutoExecConfig(true, PLUGIN_SHORT_NAME);
}

/*
 * Gets fired after Plugin has loaded all configs.
 */
public OnConfigsExecuted()
{
	/* NOT NEEDED RIGHT NOW!
	// Fetch Web API key
	GetConVarString(g_cvarAPIKey, g_SteamAPIKey, MAX_KEY_LENGTH);
	if (IsValidAPIKey(g_SteamAPIKey))
		GenerateMapList();
	else
		LogError(WAPI_KEY_ERROR);
	*/
	GenerateMapList();
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
			if (cvar == h_cvarGameMode || cvar == h_cvarGameType)
			{
				PrintToServer("[WML] Game Mode/Type changed outside of WML, correcting...");
				// Override settings
				ChangeMode(g_SelectedMode);
			}
		}
	}
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
	SetConVarInt(h_cvarGameType, 0);
	SetConVarInt(h_cvarGameMode, 0);
}

ChangeModeCompetitive()
{
	SetConVarInt(h_cvarGameType, 0);
	SetConVarInt(h_cvarGameMode, 1);
}

ChangeModeArmsrace()
{
	SetConVarInt(h_cvarGameType, 1);
	SetConVarInt(h_cvarGameMode, 0);
}

ChangeModeDemolition()
{
	SetConVarInt(h_cvarGameType, 1);
	SetConVarInt(h_cvarGameMode, 1);
}

ChangeModeDeathmatch()
{
	SetConVarInt(h_cvarGameType, 1);
	SetConVarInt(h_cvarGameMode, 2);
}

#if defined WML_DEBUG
/*
 * Just ignore this :)
 */
public Action:PrintDebugOutput(client, args)
{
	new String:buffer[64];
	GetCmdArg(1, buffer, 64);
	new i = StringToInt(buffer);
	new Handle:h_MapDetails = INVALID_HANDLE;
	
	GetTrieValue(g_WsMapDetails, "204063065", h_MapDetails);
	GetArrayString(h_MapDetails, i, buffer, sizeof(buffer));
	PrintToServer("Array value: %s", buffer);
	
	for (new j = 0; j < GetArraySize(g_WsMapsClassic); j++)
	{
		GetArrayString(g_WsMapsClassic, j, buffer, 64);
		PrintToServer("Classic map: %s", buffer);
	}
	
	return Plugin_Handled;
}
#endif

/*
 * API Call to fetch Workshop ID details.
 */
GetPublishedFileDetails(const String:id[])
{
	/* NOT NEEDED RIGHT NOW NOT NEEDED RIGHT NOW!!
	// Valid key needed to contact APi server
	if (!IsValidAPIKey(g_SteamAPIKey))
	{
		LogError(WAPI_KEY_ERROR);
		return;
	}
	*/

	// Build URL
	decl String:request[MAX_URL_LEN];
	//Format(request, MAX_URL_LEN, "%s?key=%s", WAPI_GFDETAILS, g_SteamAPIKey);
	Format(request, MAX_URL_LEN, "%s", WAPI_GFDETAILS);
	// Build POST
	decl String:data[MAXPOST];
	Format(data, MAXPOST, "itemcount=1&publishedfileids%%5B0%%5D=%s&format=vdf", id);
	
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
 * Gets called when response is received.
 * TODO: proper handling if response is over 4KBytes.
 */
public OnGetPage(const String:output[], const size, CMDReturn:status, any:data)
{
#if defined WML_DEBUG
	PrintToServer("Response received.");
#endif
	// Response is complete
	if(status == CMD_SUCCESS)
	{
		// Get associated ID
		decl String:id[MAX_ID_LEN];
		ResetPack(data);
		ReadPackString(data, id, sizeof(id));
		CloseHandle(data);
		
#if defined WML_DEBUG
		PrintToServer("Provided ID: %s", id);
		PrintToServer("OnGetPage() finished.");
		PrintToServer("Status: %d", status);
		PrintToServer("Size: %d", size);
#endif
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
			}
			else
				LogError("Couldn't open KeyValues!");
		}		
		
#if defined WML_DEBUG
		PrintToServer("Done");
#endif
	}
}

/*
 * Dives through local stored map info file.
 */
BrowseKeyValues(Handle:kv, const String:id[])
{
	decl String:buffer[MAX_ATTRIB_LEN];
	new Handle:h_MapDetails = INVALID_HANDLE;

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
					GetTrieValue(g_WsMapDetails, id, h_MapDetails);
					SetArrayString(h_MapDetails, MAP_TITLE, buffer);
				}
				else if (StrEqual("tag", buffer, false))
				{
					// Retrieve tag and associate map with it
					KvGetString(kv, NULL_STRING, buffer, sizeof(buffer));
#if defined WML_DEBUG
					PrintToServer("Tag: %s", buffer);
#endif
					if (StrEqual(buffer, TAG_Classic, false))
					{
						PushArrayString(g_WsMapsClassic, id);
						// Sort maps alphabetical ascending
						SortADTArrayCustom(g_WsMapsClassic, SortMapArray);
					}
					if (StrEqual(buffer, TAG_Deathmatch, false))
					{
						PushArrayString(g_WsMapsDeathmatch, id);
						// Sort maps alphabetical ascending
						SortADTArrayCustom(g_WsMapsDeathmatch, SortMapArray);
					}
					if (StrEqual(buffer, TAG_Demolition, false))
					{
						PushArrayString(g_WsMapsDemolition, id);
						// Sort maps alphabetical ascending
						SortADTArrayCustom(g_WsMapsDemolition, SortMapArray);
					}
					if (StrEqual(buffer, TAG_Armsrace, false))
					{
						PushArrayString(g_WsMapsArmsrace, id);
						// Sort maps alphabetical ascending
						SortADTArrayCustom(g_WsMapsArmsrace, SortMapArray);
					}
					if (StrEqual(buffer, TAG_Hostage, false))
					{
						PushArrayString(g_WsMapsHostage, id);
						// Sort maps alphabetical ascending
						SortADTArrayCustom(g_WsMapsHostage, SortMapArray);
					}
					if (StrEqual(buffer, TAG_Custom, false))
					{
						PushArrayString(g_WsMapsCustom, id);
						// Sort maps alphabetical ascending
						SortADTArrayCustom(g_WsMapsCustom, SortMapArray);
					}
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
public Action:ReloadMapList(client, args)
{
	PrintToConsole(client, "[SM] Refreshing map list...");
	GenerateMapList();
	
	return Plugin_Handled;
}

/*
 * Displaying in-game menu to user.
 */
public Action:DisplayMapList(client, args)
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
	// No work if no content
	if (GetArraySize(g_WsMapList) <= 0)
	{
		return INVALID_HANDLE;
	}
 
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
		// Stores array index
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
				h_MapMenu = BuildMapMenu(g_WsMapsClassic);
			}
			else if (StrEqual(info, TAG_Deathmatch, false))
			{
				g_SelectedMode = DEATHMATCH;
				h_MapMenu = BuildMapMenu(g_WsMapsDeathmatch);
			}
			else if (StrEqual(info, TAG_Demolition, false))
			{
				g_SelectedMode = DEMOLITION;
				h_MapMenu = BuildMapMenu(g_WsMapsDemolition);
			}
			else if (StrEqual(info, TAG_Armsrace, false))
			{
				g_SelectedMode = ARMSRACE;
				h_MapMenu = BuildMapMenu(g_WsMapsArmsrace);
			}
			else if (StrEqual(info, TAG_Hostage, false))
			{
				g_SelectedMode = COMPETITIVE;
				h_MapMenu = BuildMapMenu(g_WsMapsHostage);
			}
			else if (StrEqual(info, TAG_Custom, false))
			{
				g_SelectedMode = CASUAL;
				h_MapMenu = BuildMapMenu(g_WsMapsCustom);
			}
			
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
 * Helper to get map ID and Title from array index.
 */
GetMapIdTitle(Handle:mapList, index, String:id[], String:output[])
{
	new Handle:h_MapDetails = INVALID_HANDLE;
	GetArrayString(mapList, index, id, MAX_ID_LEN);
	GetTrieValue(g_WsMapDetails, id, h_MapDetails);
	GetArrayString(h_MapDetails, MAP_TITLE, output, MAX_ATTRIB_LEN);
}

/*
 * Helper to get local map path from ID.
 */
GetMapPath(String:id[], String:output[])
{
	new Handle:h_MapDetails = INVALID_HANDLE;
	GetTrieValue(g_WsMapDetails, id, h_MapDetails);
	GetArrayString(h_MapDetails, MAP_PATH, output, PLATFORM_MAX_PATH + 1);
}

/*
 * Helper to validate Steam API Key.
 * NOT NEEDED RIGHT NOW!
bool:IsValidAPIKey(const String:key[])
{
	return (SimpleRegexMatch(key, "^[0-9a-f]{32}$", PCRE_CASELESS) > 0);
}
*/

/*
 * Build simple list-style map chooser menu.
 */
Handle:BuildMapMenu(Handle:category)
{
	// No work if no content
	if (GetArraySize(g_WsMapList) <= 0)
	{
		return INVALID_HANDLE;
	}
 
	// Create main menu handle
	new Handle:menu = CreateMenu(Menu_ChangeMap);
	new String:id[MAX_ID_LEN];
	new String:buffer[MAX_ATTRIB_LEN];

	// Add maps as menu items
	for (new i = 0; i < GetArraySize(category); i++)
	{
		GetMapIdTitle(category, i, id, buffer);
		AddMenuItem(menu, id, buffer);
	}
 
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
		new bool:found = GetMenuItem(menu, param2, id, MAX_ID_LEN);
		
		if (found)
		{
			new String:map[PLATFORM_MAX_PATH + 1];
			GetMapPath(id, map);
 
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
				
				// Submit map name to timer callback
				new Handle:h_MapName = CreateDataPack();
				WritePackString(h_MapName, map);
				// Delay for chat messages
				CreateTimer(2.0, PerformMapChange, h_MapName);
			}
			else
				LogError("Map '%s' unexpectedly couldn't be validated!", map);
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
 * Plugin unload event.
 */
public OnPluginEnd()
{
	// Do all the clean-up
	decl String:key[MAX_ID_LEN];
	new Handle:value = INVALID_HANDLE;
	for (new i = 0; i < GetTrieSize(g_WsMapDetails); i++)
	{
		GetArrayString(g_WsMapList, i, key, MAX_ID_LEN);
		GetTrieValue(g_WsMapDetails, key, value);
		CloneHandle(value);
		RemoveFromTrie(g_WsMapDetails, key);
	}
	CloseHandle(g_WsMapDetails);
	ClearArray(g_WsMapList);
	CloseHandle(g_WsMapList);
	if (g_MapMenu != INVALID_HANDLE)
		CloseHandle(g_MapMenu);
	
	CloseHandle(g_WsMapsClassic);
	CloseHandle(g_WsMapsDeathmatch);
	CloseHandle(g_WsMapsDemolition);
	CloseHandle(g_WsMapsArmsrace);
	CloseHandle(g_WsMapsHostage);
	CloseHandle(g_WsMapsCustom);
}

/*
 * Trims away file extension and adds element to global map list.
 */
public AddMapToList(String:map[])
{
	if (StrEqual(map[strlen(map) - 3], "bsp", false))
	{
		// Cuts off file extension
		map[strlen(map) - 4] = '\0';
		
		// Extract workshop ID
		decl String:id[MAX_ID_LEN];
		new Handle:regex_id = CompileRegex("\\/(\\d*)\\/");
		MatchRegex(regex_id, map);
		GetRegexSubString(regex_id, 1, id, MAX_ID_LEN);
		CloseHandle(regex_id);
		PushArrayString(g_WsMapList, id);
		
		// Create new storage for map details
		new Handle:h_MapDetails = CreateArray(MAX_ATTRIB_LEN, MAX_ATTRIBS);
		// create/set attributes
		SetArrayString(h_MapDetails, MAP_PATH, map);
		SetArrayString(h_MapDetails, MAP_TITLE, "");
		// Store details in tree value
		SetTrieValue(g_WsMapDetails, id, h_MapDetails);

#if defined WML_DEBUG
		PrintToServer("ID: %s", id);
#endif
		// Fetch workshop item info
		GetPublishedFileDetails(id);
	}
}

/*
 * Builds in-memory map list and user menu.
 * */
public GenerateMapList()
{
	// Empty and shrink array
	ClearArray(g_WsMapList);
	ResizeArray(g_WsMapList, 0);
	ClearTrie(g_WsMapDetails);
	// Empty categories
	ClearArray(g_WsMapsClassic);
	ResizeArray(g_WsMapsClassic, 0);
	ClearArray(g_WsMapsDeathmatch);
	ResizeArray(g_WsMapsDeathmatch, 0);
	ClearArray(g_WsMapsDemolition);
	ResizeArray(g_WsMapsDemolition, 0);
	ClearArray(g_WsMapsArmsrace);
	ResizeArray(g_WsMapsArmsrace, 0);
	ClearArray(g_WsMapsHostage);
	ResizeArray(g_WsMapsHostage, 0);
	ClearArray(g_WsMapsCustom);
	ResizeArray(g_WsMapsCustom, 0);
	
	// Dive through file system
	ReadFolder(WORKSHOP_BASE_DIR);
}

/*
 * Custom sorting algorithm to alphabetically sort short map names.
 * TODO: re-implement
 */
public SortMapArray(index1, index2, Handle:array, Handle:hndl)
{
	decl String:id[MAX_ID_LEN]; // Dummy
	decl String:title1[MAX_ATTRIB_LEN];
	decl String:title2[MAX_ATTRIB_LEN];

	GetMapIdTitle(array, index1, id, title1);
	GetMapIdTitle(array, index2, id, title2);

	return strcmp(title1, title2, false);
}

/*
 * Recursively fetch content of given folder.
 */
public ReadFolder(String:path[])
{
	new Handle:dirh = INVALID_HANDLE;
	new String:buffer[PLATFORM_MAX_PATH + 1];
	new String:tmp_path[PLATFORM_MAX_PATH + 1];

	dirh = OpenDirectory(path);
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
