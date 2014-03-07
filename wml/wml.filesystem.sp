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

stock GetTempFilePath(String:path[], maxsize, const String:id[])
{
	BuildPath(Path_SM, path, maxsize, "%s/%s.txt", WML_TMP_DIR, id);
}
