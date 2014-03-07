// Default CURL options
new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,30},
	{_:CURLOPT_CONNECTTIMEOUT,60},
	{_:CURLOPT_VERBOSE,0}
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

stock cURL_GetPage(CURL_OnComplete:OnCurlComplete, const String:URL[], const String:POST[] = "", const String:useragent[] = "", any:data = INVALID_HANDLE)
{
	new Handle:curl = curl_easy_init();
	if(curl != INVALID_HANDLE)
	{
		// Get associated ID
		decl String:id[MAX_ID_LEN];
		ResetPack(data);
		ReadPackString(data, id, sizeof(id));
		
		decl String:path[PLATFORM_MAX_PATH + 1];
		GetTempFilePath(path, sizeof(path), id);
		
		new Handle:file = curl_OpenFile(path, "wt");
		if (file == INVALID_HANDLE)
		{
			LogError("Couldn't create temporary file %s", path);
			CloseHandle(data);
			return;
		}
		
		new Handle:hDLPack = CreateDataPack();
		WritePackString(hDLPack, id);
		WritePackCell(hDLPack, file);
		
		CURL_DEFAULT_OPT(curl);
		curl_easy_setopt_string(curl, CURLOPT_URL, URL);
		curl_easy_setopt_string(curl, CURLOPT_POSTFIELDS, POST);
		curl_easy_setopt_string(curl, CURLOPT_USERAGENT, useragent);
		curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, file);
		curl_easy_perform_thread(curl, OnCurlComplete, hDLPack);
	}
}

public OnCurlComplete(Handle:hndl, CURLcode:code , any:data)
{
	// Get associated ID
	decl String:id[MAX_ID_LEN];
	ResetPack(data);
	// Get ID
	ReadPackString(data, id, sizeof(id));
	// Close file
	CloseHandle(Handle:ReadPackCell(data));
	
	if(hndl != INVALID_HANDLE && code != CURLE_OK)
	{
		new String:error[MAX_ERROR_LEN];
		curl_easy_strerror(code, error, sizeof(error));
		CloseHandle(hndl);
		return;
	}
	
	LogMessage("Successfully received file details for ID %s", id);
	
	decl String:path[PLATFORM_MAX_PATH + 1];
	GetTempFilePath(path, sizeof(path), id);
	// Start parsing the file content
	InterpretTempFile(path, id);
}