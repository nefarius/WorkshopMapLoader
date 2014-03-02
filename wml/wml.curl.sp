// Default CURL options
new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,30},
	{_:CURLOPT_CONNECTTIMEOUT,60},
	{_:CURLOPT_VERBOSE,0}
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

stock cURL_GetPage(const String:URL[], const String:POST[] = "", const String:useragent[] = "", any:data = INVALID_HANDLE)
{
	new Handle:curl = curl_easy_init();
	if(curl != INVALID_HANDLE)
	{
		// Get associated ID
		decl String:id[MAX_ID_LEN];
		ResetPack(data);
		ReadPackString(data, id, sizeof(id));
		
		decl String:path[PLATFORM_MAX_PATH + 1];
		BuildPath(Path_SM, path, sizeof(path), "%s/%s.txt", WML_TMP_DIR, id);
		new Handle:file = curl_OpenFile(path, "wt");
		if (file == INVALID_HANDLE)
		{
			LogError("Couldn't create temporary file %s", path);
			CloseHandle(data);
			return;
		}
		
		CURL_DEFAULT_OPT(curl);
		curl_easy_setopt_string(curl, CURLOPT_URL, URL);
		curl_easy_setopt_string(curl, CURLOPT_POSTFIELDS, POST);
		curl_easy_setopt_string(curl, CURLOPT_USERAGENT, useragent);
		curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, file);
		
		new CURLcode:code;
		if((code = curl_easy_perform(curl)) != CURLE_OK)
		{
			new String:error[MAX_ERROR_LEN];
			curl_easy_strerror(code, error, sizeof(error));
			LogError("Getting data for ID %s failed: %s", id, error);
			CloseHandle(curl);
			CloseHandle(file);
			return;
		}
		
		CloseHandle(file);
		LogMessage("Successfully received file details for ID %s", id);
		
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
}
