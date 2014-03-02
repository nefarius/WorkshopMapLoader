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
		CURL_DEFAULT_OPT(curl);
		curl_easy_setopt_string(curl, CURLOPT_URL, URL);
		curl_easy_setopt_string(curl, CURLOPT_POSTFIELDS, POST);
		curl_easy_setopt_string(curl, CURLOPT_USERAGENT, useragent);
		curl_easy_perform_thread(curl, OnCurlComplete, data);
	}
}

public OnCurlComplete(Handle:hndl, CURLcode:code , any:data)
{
	if(hndl != INVALID_HANDLE && code != CURLE_OK)
	{
		new String:error[MAX_ERROR_LEN];
		curl_easy_strerror(code, error, sizeof(error));
		CloseHandle(hndl);
		return;
	}
}