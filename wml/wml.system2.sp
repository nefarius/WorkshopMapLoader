/*
 * Gets called when response is received.
 */
public OnGetPageComplete(const String:output[], const size, CMDReturn:status, any:data)
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
	
	// Create Kv file
	decl String:path[PLATFORM_MAX_PATH + 1];
	GetTempFilePath(path, sizeof(path), id);
	
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
			// Start parsing the file content
			InterpretTempFile(path, id);
		}
		default:
			CloseHandle(file);
	}
}
