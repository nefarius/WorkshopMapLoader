/*
 * Recursively fetch content of given folder.
 */
stock ReadFolder(String:path[])
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

/*
 * Returns file system path to temporary Kv file.
 */
stock GetTempFilePath(String:path[], maxsize, const String:id[])
{
	BuildPath(Path_SM, path, maxsize, "%s/%s.txt", WML_TMP_DIR, id);
}

/*
 * Browses through metadata Kv file and adds to database.
 */
stock InterpretTempFile(const String:path[], const String:id[])
{
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

/*
 * Creates a custom mapcycle file filtered by game mode (tag).
 */
stock CreateMapcycleFile(const String:tag[], const String:path[])
{
	if (g_dbiStorage == INVALID_HANDLE)
		return;
		
	if (g_cvarMapcyclefile == INVALID_HANDLE)
		return;
	
	new Handle:file = OpenFile(path, "wt");
	if (file == INVALID_HANDLE)
	{
		LogError("Couldn't create '%s', mapcyclefile unchanged");
		return;
	}
		
	new Handle:h_Query = INVALID_HANDLE;
	decl String:query[MAX_QUERY_LEN];
	decl String:map[PLATFORM_MAX_PATH];
	
	if (GetConVarBool(g_cvarNominateAll))
	{
		// Nominate all maps
		Format(query, sizeof(query), " \
			SELECT 'workshop/' || Id || '/' || Map \
			FROM wml_workshop_maps;");
	}
	else
	{
		// Nominate only maps matching the supplied tag
		Format(query, sizeof(query), " \
			SELECT 'workshop/' || Id || '/' || Map \
			FROM wml_workshop_maps WHERE Tag LIKE '%s';", tag);
	}
	
	// Enumerate through results and write to file
	SQL_LockDatabase(g_dbiStorage);
	h_Query = SQL_Query(g_dbiStorage, query);
	if (h_Query != INVALID_HANDLE)
	{
		while (SQL_FetchRow(h_Query))
		{
			SQL_FetchString(h_Query, 0, map, sizeof(map));
			WriteFileLine(file, map);
		}
	}
	SQL_UnlockDatabase(g_dbiStorage);
	CloseHandle(h_Query);
	CloseHandle(file);
}
