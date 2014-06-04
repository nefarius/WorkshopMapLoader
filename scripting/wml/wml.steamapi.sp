// Feature checks
#define WEBTERNET_AVAILABLE()		(GetFeatureStatus(FeatureType_Native, "HTTP_CreateSession") == FeatureStatus_Available)

/*
 * API Call to fetch Workshop ID details.
 */
stock GetPublishedFileDetails(const String:id[])
{
	// Build URL
	decl String:url[MAX_URL_LEN];
	Format(url, MAX_URL_LEN, "%s", 
		"http://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/");
		
	// Get temp file path
	decl String:path[PLATFORM_MAX_PATH + 1];
	GetTempFilePath(path, sizeof(path), id);
	
	if (WEBTERNET_AVAILABLE())
	{
		new Handle:session = HTTP_CreateSession();
		new Handle:form = HTTP_CreateWebForm();
		new Handle:downloader = HTTP_CreateFileDownloader(path);
		
		if (session != INVALID_HANDLE)
		{
			HTTP_SetFailOnHTTPError(session, true);
		}
		else
		{
			LogError("Steam API error: Couldn't create session!");
			return;
		}
		
		if (form != INVALID_HANDLE)
		{
			HTTP_AddStringToWebForm(form, "itemcount", "1");
			HTTP_AddStringToWebForm(form, "publishedfileids[0]", id);
			HTTP_AddStringToWebForm(form, "format", "vdf");
		}
		else
		{
			LogError("Steam API error: Couldn't create form!");
			return;
		}
		
		new Handle:hDLPack = CreateDataPack();
		// Encapsulate ID
		WritePackString(hDLPack, id);
		
		if (!HTTP_PostAndDownload(session, downloader, form, url, OnWebternetComplete, hDLPack))
		{
			LogError("Steam API error: Couldn't queue download!");
			CloseHandle(hDLPack);
			return;
		}
	}
	else
	{
		LogError("Couldn't connect to Steam API, do you have Webternet installed?");
	}
}

public OnWebternetComplete(Handle:session, status, Handle:downloader, any:data)
{
	CloseHandle(downloader);
	
	// Get associated ID
	decl String:id[MAX_ID_LEN];
	ResetPack(data);
	// Get ID
	ReadPackString(data, id, sizeof(id));
	CloseHandle(data);

	if (status == HTTP_OK)
	{
		LogMessage("Successfully received file details for ID %s", id);
	
		decl String:path[PLATFORM_MAX_PATH + 1];
		GetTempFilePath(path, sizeof(path), id);
		// Start parsing the file content
		InterpretTempFile(path, id);
	}
	else
	{
		decl String:sError[MAX_ERROR_LEN];
		HTTP_GetLastError(session, sError, sizeof(sError));
		Format(sError, sizeof(sError), "Steam API error: %s", sError);
	}
	
	CloseHandle(session);
}
