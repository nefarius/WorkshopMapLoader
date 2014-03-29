/*
 * Builds map category top-level menu.
 */
stock Handle:BuildCategoryMenu()
{
	// Create main menu handle
	new Handle:menu = CreateMenu(Menu_SelectedCategory);
	SetMenuTitle(menu, "Please select map category:");
	AddMenuItem(menu, g_Tags[MapTag_Classic], g_Tags[MapTag_Classic]);
	AddMenuItem(menu, g_Tags[MapTag_Deathmatch], g_Tags[MapTag_Deathmatch]);
	AddMenuItem(menu, g_Tags[MapTag_Demolition], g_Tags[MapTag_Demolition]);
	AddMenuItem(menu, g_Tags[MapTag_Armsrace], g_Tags[MapTag_Armsrace]);
	AddMenuItem(menu, g_Tags[MapTag_Hostage], g_Tags[MapTag_Hostage]);
	AddMenuItem(menu, g_Tags[MapTag_Custom], g_Tags[MapTag_Custom]);
	
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
		new String:info[MAX_ID_LEN];
		new Handle:h_MapMenu = INVALID_HANDLE;
		
		// Set selected mode and build maps sub-menu
		if (GetMenuItem(menu, param2, info, MAX_ATTRIB_LEN))
		{
			if (StrEqual(info, g_Tags[MapTag_Classic], false))
			{
				g_SelectedMode = NextMapMode_Casual;
			}
			else if (StrEqual(info, g_Tags[MapTag_Deathmatch], false))
			{
				g_SelectedMode = NextMapMode_Deathmatch;
			}
			else if (StrEqual(info, g_Tags[MapTag_Demolition], false))
			{
				g_SelectedMode = NextMapMode_Demolition;
			}
			else if (StrEqual(info, g_Tags[MapTag_Armsrace], false))
			{
				g_SelectedMode = NextMapMode_Armsrace;
			}
			else if (StrEqual(info, g_Tags[MapTag_Hostage], false))
			{
				g_SelectedMode = NextMapMode_Competitive;
			}
			else if (StrEqual(info, g_Tags[MapTag_Custom], false))
			{
				g_SelectedMode = NextMapMode_Custom;
			}
			
			h_MapMenu = BuildMapMenu(info);
			
			DisplayMenu(h_MapMenu, param1, MENU_TIME_FOREVER);
		}
		else
			PrintToChat(param1, "[WML] %t", "Non Existing Category");
	}
	/*
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	*/
}

/*
 * Build simple list-style map chooser menu.
 */
stock Handle:BuildMapMenu(String:category[])
{
	// Create main menu handle
	new Handle:menu = CreateMenu(Menu_SelectedMap);
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
	CloseHandle(h_Query);
 
	// Finally, set the title
	SetMenuTitle(menu, "Please select a map:");
	SetMenuExitBackButton(menu, true);
 
	return menu;
}

/*
 * Gets called if user navigated through maps menu.
 */
public Menu_SelectedMap(Handle:menu, MenuAction:action, param1, param2)
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
							LogMessage("Changing mode to: %s", g_Tags[g_SelectedMode]);
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

