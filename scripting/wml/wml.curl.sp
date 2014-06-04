// Default CURL options
new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,30},
	{_:CURLOPT_CONNECTTIMEOUT,60},
	{_:CURLOPT_VERBOSE,0}
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

/*
 * Creates a web request with cURL.
 */
stock cURL_GetPage(CURL_OnComplete:OnCurlComplete, const String:URL[], const String:POST[] = "", const String:useragent[] = "", any:data = INVALID_HANDLE)
{
	// Prepare new request
	new Handle:curl = curl_easy_init();
	if(curl != INVALID_HANDLE)
	{
		// Get associated ID
		decl String:id[MAX_ID_LEN];
		ResetPack(data);
		ReadPackString(data, id, sizeof(id));
		
		// Get temp file path
		decl String:path[PLATFORM_MAX_PATH + 1];
		GetTempFilePath(path, sizeof(path), id);
		
		// Create new empty file
		new Handle:file = curl_OpenFile(path, "wt");
		if (file == INVALID_HANDLE)
		{
			LogError("Couldn't create temporary file %s", path);
			CloseHandle(data);
			return;
		}
		
		new Handle:hDLPack = CreateDataPack();
		// Encapsulate ID
		WritePackString(hDLPack, id);
		// Encapsulate temp file handle
		WritePackCell(hDLPack, file);
		
		// Set request options
		CURL_DEFAULT_OPT(curl);
		curl_easy_setopt_string(curl, CURLOPT_URL, URL);
		curl_easy_setopt_string(curl, CURLOPT_POSTFIELDS, POST);
		curl_easy_setopt_string(curl, CURLOPT_USERAGENT, useragent);
		curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, file);
		curl_easy_perform_thread(curl, OnCurlComplete, hDLPack);
	}
}

/*
 * Gets fired after a request has been completed.
 */
public OnCurlComplete(Handle:hndl, CURLcode:code , any:data)
{
	// Get associated ID
	decl String:id[MAX_ID_LEN];
	ResetPack(data);
	// Get ID
	ReadPackString(data, id, sizeof(id));
	// Close file
	CloseHandle(Handle:ReadPackCell(data));
	
	// Check for error condition
	if(hndl != INVALID_HANDLE && code != CURLE_OK)
	{
		new String:error[MAX_ERROR_LEN];
		curl_easy_strerror(code, error, sizeof(error));
		LogError("Steam API error: couldn't fetch data for file ID %s (%s)", id, error);
		CloseHandle(hndl);
		return;
	}
	
	LogMessage("Successfully received file details for ID %s", id);
	
	decl String:path[PLATFORM_MAX_PATH + 1];
	GetTempFilePath(path, sizeof(path), id);
	// Start parsing the file content
	InterpretTempFile(path, id);
}