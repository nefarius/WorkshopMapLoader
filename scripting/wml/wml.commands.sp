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

