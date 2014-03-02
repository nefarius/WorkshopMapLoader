/* ================================================================================
 * DATABASE WRAPPER FUNCTIONS
 * ================================================================================
 */

/*
 * Create database tables if they don't exist.
 */
DB_CreateTables()
{
	if (g_dbiStorage == INVALID_HANDLE)
		return;

	new String:error[MAX_ERROR_LEN];

	if (!SQL_FastQuery(g_dbiStorage, "\
		CREATE TABLE IF NOT EXISTS wml_workshop_maps ( \
			Id INTEGER NOT NULL, \
			Tag TEXT NOT NULL, \
			Map TEXT NOT NULL, \
			Title TEXT NOT NULL, \
			UNIQUE(Id, Tag, Map, Title) ON CONFLICT REPLACE \
	);"))
	{
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		SetFailState("Creating wml_maps_all failed: %s", error);
	}
}

/*
 * Removes an entry identified by Id if tag-less.
 */
DB_RemoveUntagged(id)
{
	if (g_dbiStorage == INVALID_HANDLE)
		return;
	
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		DELETE FROM wml_workshop_maps \
		WHERE Tag = '' AND Id = %d;", id);
	
	SQL_LockDatabase(g_dbiStorage);
	SQL_FastQuery(g_dbiStorage, query);
	SQL_UnlockDatabase(g_dbiStorage);
}

/*
 * Adds skeleton of new map to database.
 */
 DB_AddNewMap(id, String:file[])
 {
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		INSERT OR REPLACE INTO wml_workshop_maps VALUES \
			(%d, \"\", \"%s\", \"\");", id, file);

	SQL_LockDatabase(g_dbiStorage);
	if (!SQL_FastQuery(g_dbiStorage, query))
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
 }
 
 /*
 * Adds title to map with specified id.
 */
 DB_SetMapTitle(id, String:title[])
 {
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		UPDATE OR REPLACE wml_workshop_maps \
		SET Title = \"%s\" WHERE Id = %d;", title, id);

	SQL_LockDatabase(g_dbiStorage);
	if (!SQL_FastQuery(g_dbiStorage, query))
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed setting map title (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
 }
 
 /*
 * Adds tag to map with specified id.
 */
 DB_SetMapTag(id, String:tag[])
 {
	new String:query[MAX_QUERY_LEN];
	Format(query, sizeof(query), " \
		INSERT INTO wml_workshop_maps (Id, Tag, Map, Title) \
		SELECT Id, \"%s\", Map, Title \
		FROM wml_workshop_maps \
		WHERE Id = %d;", tag, id);

	SQL_LockDatabase(g_dbiStorage);
	if (!SQL_FastQuery(g_dbiStorage, query))
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed setting map tag (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
 }
 
/*
 * Helper to get local map path from ID.
 */
bool:DB_GetMapPath(id, String:path[])
{
	new Handle:h_Query = INVALID_HANDLE;
	new String:query[MAX_QUERY_LEN];
	
	Format(query, sizeof(query), " \
		SELECT 'workshop/' || Id || '/' || Map \
		FROM wml_workshop_maps WHERE Id = %d;", id);
		
	SQL_LockDatabase(g_dbiStorage);
	h_Query = SQL_Query(g_dbiStorage, query);
	if (h_Query == INVALID_HANDLE)
	{
		new String:error[MAX_ERROR_LEN];
		SQL_GetError(g_dbiStorage, error, sizeof(error));
		PrintToServer("Failed setting map tag (error: %s)", error);
	}
	SQL_UnlockDatabase(g_dbiStorage);
			
	if (!SQL_FetchRow(h_Query))
	{
		CloneHandle(h_Query);
		return false;
	}
	
	SQL_FetchString(h_Query, 0, path, PLATFORM_MAX_PATH + 1);
	CloseHandle(h_Query);
	
	return true;
}

