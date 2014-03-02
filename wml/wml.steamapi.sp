/*
 * API Call to fetch Workshop ID details.
 */
GetPublishedFileDetails(const String:id[])
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
	System2_GetPage(OnGetPage, request, data, WAPI_USERAGENT, pack);
}

