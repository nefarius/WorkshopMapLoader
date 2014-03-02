/*
 * API Call to fetch Workshop ID details.
 */
stock GetPublishedFileDetails(const String:id[])
{
	// Build URL
	decl String:request[MAX_URL_LEN];
	Format(request, MAX_URL_LEN, "%s", 
		"http://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/");
	// Build POST
	decl String:data[MAX_POST_LEN];
	Format(data, MAX_POST_LEN, "itemcount=1&publishedfileids%%5B0%%5D=%s&format=vdf", id);
	
	// Attach ID to keep track of response
	new Handle:pack = CreateDataPack();
	WritePackString(pack, id);
	
	if (SYSTEM2_AVAILABLE())
	{
		System2_GetPage(OnGetPageComplete, request, data, WAPI_USERAGENT, pack);
	}
	else if (CURL_AVAILABLE())
	{
		cURL_GetPage(OnCurlComplete, request, data, WAPI_USERAGENT, pack);
	}
}
