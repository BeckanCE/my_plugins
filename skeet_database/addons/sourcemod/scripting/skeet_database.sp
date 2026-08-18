#pragma semicolon 1
#pragma newdecls required //強制1.7以後的新語法

#include <sourcemod>
#include <sdkhooks>
#include <multicolors>
#include <sdktools>

enum struct CPlayerSkeetData
{
	char m_sName[64];
	int m_iSkeets;

	int m_iPosition;
}

#define TOP_NUMBER 5

ConVar hEnablePlugin, OneShotSkeet,hCvarAnnounce, g_hCvarMPGameMode,
	g_hCvarModesTog, g_hCvarSurvivorRequired, g_hCvarAIHunter, g_hCvar1v1Separate;
bool g_bCvarAllow;
ConVar g_hCvarSurvivorLimit, g_hCvarInfectedLimit;
bool g_bRoundEndAnnounce;
bool g_bShotCounted[MAXPLAYERS+1][MAXPLAYERS+1];
bool g_bIsPouncing[MAXPLAYERS+1];
bool g_bHasLandedPounce[MAXPLAYERS+1];
char datafilepath[256];
char datafilepath_1v1[256];
int timerDeath[MAXPLAYERS+1];
int Skeets[MAXPLAYERS+1];
int Kills[MAXPLAYERS+1];
int DeadStoped[MAXPLAYERS+1];
int g_iShotsDealt[MAXPLAYERS+1][MAXPLAYERS+1];
int g_damage[MAXPLAYERS+1][MAXPLAYERS+1];
int g_iDamageDealt[MAXPLAYERS+1][MAXPLAYERS+1];
int g_iLastHealth[MAXPLAYERS+1];
int g_iSurvivorLimit = 4;
bool CvarAnnounce;
bool Is1v1;

KeyValues g_hData;

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

ConVar
	g_hCvarUseSQL,
	g_hCvarSQLConfig;

char
	g_sSQLTable[] = "skeet_stats";

bool
	g_bSQLConnected,
	g_bSQLTableExists,
	g_bSQLConnecting;

enum SQLDriver
{
	SQL_MySQL  = 0,
	SQL_SQLite = 1,
}

Database
	g_db;

SQLDriver
	g_SQLDriver;

/*****************************************************************
			F O R W A R D   P U B L I C S
*****************************************************************/

void OnPluginStart_SQL()
{
	g_hCvarUseSQL = CreateConVar("skeet_database_use_sql", "0",
		"Use SQL storage (MySQL o SQLite) instead of KeyValues files? [1: Yes, 0: No].", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarSQLConfig = CreateConVar("skeet_database_sql_config", "skeet_db",
		"Database config name from databases.cfg for skeet_database", FCVAR_NONE);

	RegAdminCmd("sm_skeet_sql_status", Command_SQLStatus, ADMFLAG_GENERIC, "Show SQL connection status for skeet_database. Requires skeet_database_use_sql 1.");
}

void OnPluginEnd_SQL()
{
	g_bSQLConnecting = false;

	if (g_db == null)
	{
		g_bSQLConnected = false;
		g_bSQLTableExists = false;
		return;
	}

	delete g_db;
	g_db = null;
	g_bSQLConnected = false;
	g_bSQLTableExists = false;
}

void OnConfigsExecuted_SQL()
{
	if (!g_hCvarUseSQL.BoolValue)
		return;

	if (g_db != null || g_bSQLConnecting)
		return;

	char sConfigName[64];
	g_hCvarSQLConfig.GetString(sConfigName, sizeof(sConfigName));
	ConnectDB_SQL(sConfigName);
}

/*****************************************************************
			C O N N E C T I O N
*****************************************************************/

void ConnectDB_SQL(const char[] sConfigName)
{
	if (g_db != null || g_bSQLConnecting)
		return;

	g_bSQLConnected = false;
	g_bSQLTableExists = false;

	if (!SQL_CheckConfig(sConfigName))
	{
		LogError("[\x04Skeets\x01] No se encontro el config \x03'%s' \x01en \x05databases.cfg", sConfigName);
		return;
	}

	g_bSQLConnecting = true;
	Database.Connect(SQL_ConnectCallback, sConfigName);
}

void SQL_ConnectCallback(Database database, const char[] error, any data)
{
	g_bSQLConnecting = false;
	g_bSQLConnected = false;
	g_bSQLTableExists = false;

	if (database == null || error[0] != '\0')
	{
		LogError("[\x04Skeets\x01] Error al conectar a la base de datos: \x03%s", error);
		return;
	}

	g_db = database;
	g_bSQLConnected = true;

	DBDriver driver = database.Driver;
	if (driver == null)
	{
		LogError("[\x04Skeets\x01] No se pudo obtener el driver de la base de datos.");
		g_bSQLConnected = false;
		return;
	}

	char sDriverName[32];
	driver.GetIdentifier(sDriverName, sizeof(sDriverName));

	if (StrEqual(sDriverName, "mysql", false))
	{
		g_SQLDriver = SQL_MySQL;
		if (!database.SetCharset("utf8mb4"))
			LogError("[\x04Skeets\x01] No se pudo establecer charset utf8mb4.");
	}
	else if (StrEqual(sDriverName, "sqlite", false))
	{
		g_SQLDriver = SQL_SQLite;
	}
	else
	{
		LogError("[\x04Skeets\x01] Driver de base de datos desconocido: \x03%s", sDriverName);
		g_bSQLConnected = false;
		return;
	}

	EnsureSchema_SQL();
}

/*****************************************************************
			S C H E M A   ( A U T O - C R E A D O ,   A M B O S   D R I V E R S )
*****************************************************************/

/**
 * Crea la tabla (y su indice de ranking) si no existe, en cualquiera
 * de los dos drivers. Requiere que la cuenta de la base de datos
 * tenga permiso CREATE ademas de los permisos normales de lectura
 * y escritura.
 */
void EnsureSchema_SQL()
{
	if (g_db == null)
		return;

	char sQuery[512];
	int iLen = 0;

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "CREATE TABLE IF NOT EXISTS `%s` ( ", g_sSQLTable);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`steamid` VARCHAR(32) NOT NULL, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`name` VARCHAR(64) NOT NULL DEFAULT 'Unnamed', ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`skeets` INT UNSIGNED NOT NULL DEFAULT 0, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`is_1v1` TINYINT(1) NOT NULL DEFAULT 0, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`last_updated` INT UNSIGNED NOT NULL DEFAULT 0, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "PRIMARY KEY (`steamid`, `is_1v1`), ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "KEY `idx_skeet_stats_rank` (`is_1v1`, `skeets` DESC) ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

			g_db.Query(EnsureSchema_MySQL_Callback, sQuery);
			return; // el callback marca g_bSQLTableExists
		}
		case SQL_SQLite:
		{
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "CREATE TABLE IF NOT EXISTS `%s` ( ", g_sSQLTable);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`steamid` TEXT NOT NULL, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`name` TEXT NOT NULL DEFAULT 'Unnamed', ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`skeets` INTEGER NOT NULL DEFAULT 0, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`is_1v1` INTEGER NOT NULL DEFAULT 0, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "`last_updated` INTEGER NOT NULL DEFAULT 0, ");
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "PRIMARY KEY (`steamid`, `is_1v1`) )");

			if (!SQL_FastQuery(g_db, sQuery))
			{
				char sError[256];
				SQL_GetError(g_db, sError, sizeof(sError));
				LogError("[\x04Skeets\x01] Error creando tabla SQLite \x03'%s': \x05%s", g_sSQLTable, sError);
				return;
			}

			char sIndexQuery[256];
			FormatEx(sIndexQuery, sizeof(sIndexQuery),
				"CREATE INDEX IF NOT EXISTS `idx_skeet_stats_rank` ON `%s` (`is_1v1`, `skeets` DESC)", g_sSQLTable);
			if (!SQL_FastQuery(g_db, sIndexQuery))
			{
				char sError[256];
				SQL_GetError(g_db, sError, sizeof(sError));
				LogError("[\x04Skeets\x01] Error creando indice SQLite: \x05%s", sError);
			}

			g_bSQLTableExists = true;
		}
	}
}

void EnsureSchema_MySQL_Callback(Database database, DBResultSet results, const char[] error, any data)
{
	if (error[0] != '\0')
	{
		LogError("[\x04Skeets\x01] Error creando/verificando tabla MySQL \x04'%s'\x01: \x05%s", g_sSQLTable, error);
		g_bSQLTableExists = false;
		return;
	}

	g_bSQLTableExists = true;
}

/*****************************************************************
			W R I T E S
*****************************************************************/

/**
 * Registra (o incrementa) el contador de skeets de un jugador.
 * Async, no bloquea el hilo del juego.
 */
void RegisterSkeetSQL(int client)
{
	if (!g_bSQLConnected || !g_bSQLTableExists || g_db == null)
		return;

	if (!IsClientInGame(client))
		return;

	char sName[64];
	GetClientName(client, sName, sizeof(sName));

	char sNameEscaped[130];
	g_db.Escape(sName, sNameEscaped, sizeof(sNameEscaped));

	char sSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

	int iIs1v1 = (g_hCvar1v1Separate.BoolValue && Is1v1) ? 1 : 0;
	int iTime = GetTime();

	char sQuery[600];
	int iLen = 0;

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"INSERT INTO `%s` (steamid, name, skeets, is_1v1, last_updated) ", g_sSQLTable);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"VALUES ('%s', '%s', 1, %d, %d) ", sSteamID, sNameEscaped, iIs1v1, iTime);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"ON DUPLICATE KEY UPDATE skeets = skeets + 1, name = VALUES(name), last_updated = VALUES(last_updated)");
		}
		case SQL_SQLite:
		{
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"INSERT INTO `%s` (steamid, name, skeets, is_1v1, last_updated) ", g_sSQLTable);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"VALUES ('%s', '%s', 1, %d, %d) ", sSteamID, sNameEscaped, iIs1v1, iTime);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"ON CONFLICT(steamid, is_1v1) DO UPDATE SET skeets = skeets + 1, name = excluded.name, last_updated = excluded.last_updated");
		}
		default:
		{
			return;
		}
	}

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	g_db.Query(RegisterSkeetSQL_Callback, sQuery, pack);
}

void RegisterSkeetSQL_Callback(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	delete pack;

	if (error[0] != '\0')
	{
		LogError("[\x04Skeets\x01] Error registrando skeet: \x05%s", error);
		return;
	}

	if (!CvarAnnounce || userid == 0)
		return;

	int client = GetClientOfUserId(userid);
	if (client == 0 || !IsClientInGame(client))
		return;

	// El UPSERT no devuelve el valor final, asi que para el mensaje de
	// chat pedimos el contador actualizado con una segunda query liviana.
	FetchSkeetCountForAnnounce_SQL(client);
}

void FetchSkeetCountForAnnounce_SQL(int client)
{
	char sSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

	int iIs1v1 = (g_hCvar1v1Separate.BoolValue && Is1v1) ? 1 : 0;

	char sQuery[256];
	g_db.Format(sQuery, sizeof(sQuery),
		"SELECT skeets FROM `%s` WHERE steamid = '%s' AND is_1v1 = %d LIMIT 1",
		g_sSQLTable, sSteamID, iIs1v1);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	g_db.Query(FetchSkeetCountForAnnounce_Callback, sQuery, pack);
}

void FetchSkeetCountForAnnounce_Callback(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	delete pack;

	if (userid == 0 || results == null || !results.FetchRow())
		return;

	int client = GetClientOfUserId(userid);
	if (client == 0)
		return;

	int skeet = results.FetchInt(0);
	CPrintToChat(client, "[{green}Skeets{default}] You have {lightgreen}%d skeets%s",
		skeet, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
}

/*****************************************************************
			R E A D S
*****************************************************************/

void PrintSkeetsToClientSQL(int client)
{
	if (!g_bSQLConnected || !g_bSQLTableExists || g_db == null)
		return;

	char sSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

	int iIs1v1 = (g_hCvar1v1Separate.BoolValue && Is1v1) ? 1 : 0;

	char sQuery[256];
	g_db.Format(sQuery, sizeof(sQuery),
		"SELECT skeets FROM `%s` WHERE steamid = '%s' AND is_1v1 = %d LIMIT 1",
		g_sSQLTable, sSteamID, iIs1v1);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	g_db.Query(PrintSkeetsToClientSQL_Callback, sQuery, pack);
}

void PrintSkeetsToClientSQL_Callback(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	delete pack;

	if (userid == 0)
		return;

	int client = GetClientOfUserId(userid);
	if (client == 0)
		return;

	if (error[0] != '\0')
	{
		LogError("[\x04Skeets\x01] Error obteniendo skeets del cliente: \x05%s", error);
		return;
	}

	int skeet = (results != null && results.FetchRow()) ? results.FetchInt(0) : 0;

	if (skeet == 1)
		CPrintToChat(client, "[{green}Skeets{default}] You have {lightgreen}%d skeet%s", skeet, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
	else if (skeet < 1)
		CPrintToChat(client, "[{green}Skeets{default}] You have {lightgreen}%d skeets%s", skeet, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
	else
		CPrintToChat(client, "[{green}Skeets{default}] You have {lightgreen}%d skeets%s", skeet, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
}

void ShowSkeetRankSQL(int client)
{
	if (!g_bSQLConnected || !g_bSQLTableExists || g_db == null)
		return;

	char sSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

	int iIs1v1 = (g_hCvar1v1Separate.BoolValue && Is1v1) ? 1 : 0;

	char sQuery[512];
	int iLen = 0;

	iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen, "SELECT ");
	iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
		"(SELECT COUNT(*) FROM `%s` WHERE is_1v1 = %d) AS total_count, ", g_sSQLTable, iIs1v1);
	iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
		"(SELECT COUNT(*) FROM `%s` WHERE is_1v1 = %d AND skeets >= COALESCE((SELECT skeets FROM `%s` WHERE steamid = '%s' AND is_1v1 = %d), 0)) AS rank_count",
		g_sSQLTable, iIs1v1, g_sSQLTable, sSteamID, iIs1v1);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	g_db.Query(ShowSkeetRankSQL_Callback, sQuery, pack);
}

void ShowSkeetRankSQL_Callback(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	delete pack;

	if (userid == 0)
		return;

	int client = GetClientOfUserId(userid);
	if (client == 0)
		return;

	if (error[0] != '\0' || results == null || !results.FetchRow())
	{
		LogError("[\x04Skeets\x01] Error obteniendo ranking: \x05%s", error);
		return;
	}

	int total = results.FetchInt(0);
	int rank = results.FetchInt(1);

	CPrintToChat(client, "{green}Skeet Ranking{default}: {lightgreen}%d/%d%s", rank, total, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
}

/**
 * Top 5 - ORDER BY skeets DESC LIMIT 5 indexado, en vez del algoritmo
 * manual O(n x 5) del plugin original.
 *
 * @param client  0 para anunciar a todos los humanos conectados, o un client especifico.
 */
void PrintTopSkeetersSQL(int client)
{
	if (!g_bSQLConnected || !g_bSQLTableExists || g_db == null)
		return;

	int iIs1v1 = (g_hCvar1v1Separate.BoolValue && Is1v1) ? 1 : 0;

	char sTotalQuery[256];
	g_db.Format(sTotalQuery, sizeof(sTotalQuery),
		"SELECT COALESCE(SUM(skeets), 0) FROM `%s` WHERE is_1v1 = %d",
		g_sSQLTable, iIs1v1);

	DataPack pack = new DataPack();
	pack.WriteCell(client == 0 ? 0 : GetClientUserId(client));
	pack.WriteCell(client == 0 ? 1 : 0); // 1 = anunciar a todos los humanos conectados
	g_db.Query(PrintTopSkeetersSQL_TotalCallback, sTotalQuery, pack);
}

void PrintTopSkeetersSQL_TotalCallback(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	int wantsBroadcast = pack.ReadCell();

	if (error[0] != '\0')
	{
		LogError("[\x04Skeets\x01] Error obteniendo total de skeets: \x05%s", error);
		delete pack;
		return;
	}

	int totalskeets = (results != null && results.FetchRow()) ? results.FetchInt(0) : 0;

	int iIs1v1 = (g_hCvar1v1Separate.BoolValue && Is1v1) ? 1 : 0;
	char sQuery[256];
	g_db.Format(sQuery, sizeof(sQuery),
		"SELECT name, skeets FROM `%s` WHERE is_1v1 = %d AND skeets > 0 ORDER BY skeets DESC LIMIT %d",
		g_sSQLTable, iIs1v1, TOP_NUMBER);

	DataPack pack2 = new DataPack();
	pack2.WriteCell(userid);
	pack2.WriteCell(wantsBroadcast);
	pack2.WriteCell(totalskeets);
	delete pack;

	g_db.Query(PrintTopSkeetersSQL_ListCallback, sQuery, pack2);
}

void PrintTopSkeetersSQL_ListCallback(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	int wantsBroadcast = pack.ReadCell();
	int totalskeets = pack.ReadCell();
	delete pack;

	if (error[0] != '\0')
	{
		LogError("[\x04Skeets\x01] Error obteniendo top skeeters: \x05%s", error);
		return;
	}

	Panel panel = new Panel();
	panel.SetTitle((g_hCvar1v1Separate.BoolValue && Is1v1) ? "Mejores Skeeters (1v1)" : "Mejores Skeeters");
	panel.DrawText("\n ");

	if (totalskeets > 0 && results != null)
	{
		char sBuffer[128];
		char sName[64];
		int skeets;

		while (results.FetchRow())
		{
			results.FetchString(0, sName, sizeof(sName));
			skeets = results.FetchInt(1);
			FormatEx(sBuffer, sizeof(sBuffer), "%d skeets - %s", skeets, sName);
			panel.DrawItem(sBuffer);
		}

		panel.DrawText("\n ");
		FormatEx(sBuffer, sizeof(sBuffer), "Hay %d skeets en el servidor%s",
			totalskeets, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " in 1v1." : ".");
		panel.DrawText(sBuffer);
	}
	else
	{
		char sBuffer[128];
		FormatEx(sBuffer, sizeof(sBuffer), "Aun no hay skeets en el servidor%s",
			(g_hCvar1v1Separate.BoolValue && Is1v1) ? " in 1v1." : ".");
		panel.DrawText(sBuffer);
	}

	if (wantsBroadcast == 1)
	{
		for (int player = 1; player <= MaxClients; ++player)
		{
			if (IsClientInGame(player) && !IsFakeClient(player))
				panel.Send(player, TopSkeetPanelHandler, 5);
		}
	}
	else if (userid != 0)
	{
		int client = GetClientOfUserId(userid);
		if (client != 0)
			panel.Send(client, TopSkeetPanelHandler, 5);
	}

	delete panel;
}

/*****************************************************************
			A D M I N   C O M M A N D S
*****************************************************************/

Action Command_SQLStatus(int client, int args)
{
	if (!g_hCvarUseSQL.BoolValue)
	{
		CReplyToCommand(client, "[{green}Skeets{default}] SQL esta desactivado (skeet_database_use_sql 0).");
		return Plugin_Handled;
	}

	CReplyToCommand(client, "[{green}Skeets{default}] Conectado: {lightgreen}%s {green}| {default}Tabla {lightgreen}'%s' {default}existe: {lightgreen}%s {green}| {default}Driver: {lightgreen}%s",
		g_bSQLConnected ? "Si" : "No",
		g_sSQLTable,
		g_bSQLTableExists ? "Si" : "No",
		g_bSQLConnected ? (g_SQLDriver == SQL_MySQL ? "MySQL" : "SQLite") : "N/A");

	return Plugin_Handled;
}

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

int
	g_iMigrationTotal,
	g_iMigrationDone,
	g_iMigrationFailed,
	g_iMigrationClient;

/*****************************************************************
			F O R W A R D   P U B L I C S
*****************************************************************/

void OnPluginStart_Migration()
{
	RegAdminCmd("sm_skeet_migrate_to_sql", Command_MigrateToSQL, ADMFLAG_ROOT,
		"Migra los datos de los .txt de KeyValues a la tabla SQL. Uso: sm_skeet_migrate_to_sql CONFIRM");
}

/*****************************************************************
			C O M M A N D
*****************************************************************/

Action Command_MigrateToSQL(int client, int args)
{
	if (!g_hCvarUseSQL.BoolValue)
	{
		CReplyToCommand(client, "[{green}Skeets{default}] Activa \"{lightgreen}skeet_database_use_sql{default}\" \"{lightgreen}1{default}\" antes de migrar.");
		return Plugin_Handled;
	}

	if (!g_bSQLConnected || !g_bSQLTableExists)
	{
		CReplyToCommand(client, "[{green}Skeets{default}] SQL no esta listo (conectado: {lightgreen}%s {green}| {default}tabla '{lightgreen}%s {default}existe: {lightgreen}%s{default}). Revisa sm_skeet_sql_status.",
			g_bSQLConnected ? "si" : "no", g_sSQLTable, g_bSQLTableExists ? "si" : "no");
		return Plugin_Handled;
	}

	if (g_iMigrationTotal > 0 && g_iMigrationDone < g_iMigrationTotal)
	{
		CReplyToCommand(client, "[{green}Skeets{default}] Ya hay una importación en curso ({lightgreen}%d{default}/{lightgreen}%d{default} filas procesadas). Espera a que termine.",
			g_iMigrationDone, g_iMigrationTotal);
		return Plugin_Handled;
	}

	char sConfirm[16];
	GetCmdArg(1, sConfirm, sizeof(sConfirm));
	if (!StrEqual(sConfirm, "CONFIRM", false))
	{
		CReplyToCommand(client, "[{green}Skeets{default}] Esto va a leer skeet_database.txt / 1v1_skeet_database.txt e insertar/actualizar filas en la tabla '{lightgreen}%s{default}'.", g_sSQLTable);
		CReplyToCommand(client, "[{green}Skeets{default}] Los skeets existentes en SQL NO se pisan hacia abajo (se usa el maximo entre ambos valores).");
		CReplyToCommand(client, "[{green}Skeets{default}] Para confirmar: {lightgreen}sm_skeet_migrate_to_sql CONFIRM{default}");
		return Plugin_Handled;
	}

	g_iMigrationTotal = 0;
	g_iMigrationDone = 0;
	g_iMigrationFailed = 0;
	g_iMigrationClient = (client == 0) ? 0 : GetClientUserId(client);

	int migratedNormal = MigrateFile(datafilepath, false);

	int migrated1v1 = 0;
	if (g_hCvar1v1Separate.BoolValue)
		migrated1v1 = MigrateFile(datafilepath_1v1, true);

	g_iMigrationTotal = migratedNormal + migrated1v1;

	if (g_iMigrationTotal == 0)
	{
		CReplyToCommand(client, "[{green}Skeets{default}] No se encontraron registros validos para migrar (revisa que los .txt existan y tengan datos).");
		return Plugin_Handled;
	}

	CReplyToCommand(client, "[{green}Skeets{default}] Importación iniciada: {lightgreen}%d{default} filas en cola ({lightgreen}%d{default} normal, {lightgreen}%d{default} 1v1).",
		g_iMigrationTotal, migratedNormal, migrated1v1);

	return Plugin_Handled;
}

/*****************************************************************
			L E C T U R A   D E L   K E Y V A L U E S
*****************************************************************/

int MigrateFile(const char[] path, bool is1v1)
{
	if (!FileExists(path))
	{
	LogMessage("[\x04Skeets\x01] Importación: no existe '%s', se salta.", path);
		return 0;
	}

	KeyValues kv = new KeyValues("skeetdata");
	if (!kv.ImportFromFile(path))
	{
		LogError("[\x04Skeets\x01] Importación: no se pudo parsear '%s'.", path);
		delete kv;
		return 0;
	}

	if (!kv.JumpToKey("data"))
	{
		LogMessage("[\x04Skeets\x01] Importación: '%s' no tiene seccion 'data', nada que migrar.", path);
		delete kv;
		return 0;
	}

	int count = 0;

	if (kv.GotoFirstSubKey(true))
	{
		do
		{
			// El nombre de la seccion ES el SteamID2 -- ya es exactamente
			// lo que necesita la columna `steamid`, sin conversion.
			char steamid[32];
			kv.GetSectionName(steamid, sizeof(steamid));

			char name[64];
			kv.GetString("name", name, sizeof(name), "Unnamed");

			int skeets = kv.GetNum("skeet", 0);

			if (skeets <= 0)
				continue;

			QueueMigrationRow(steamid, name, skeets, is1v1);
			count++;

		} while (kv.GotoNextKey(true));
	}

	delete kv;
	return count;
}

/*****************************************************************
			E S C R I T U R A   A S Y N C
*****************************************************************/

/**
 * Encola el upsert de una fila migrada. Usa MAX()/GREATEST() en vez
 * de sobreescribir directo, para que correr el comando dos veces por
 * error no borre progreso que ya se haya acumulado en SQL despues de
 * la primera corrida.
 */
void QueueMigrationRow(const char[] steamid, const char[] name, int skeets, bool is1v1)
{
	char sNameEscaped[130];
	g_db.Escape(name, sNameEscaped, sizeof(sNameEscaped));

	int iIs1v1 = is1v1 ? 1 : 0;
	int iTime = GetTime();

	char sQuery[600];
	int iLen = 0;

	switch (g_SQLDriver)
	{
		case SQL_MySQL:
		{
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"INSERT INTO `%s` (steamid, name, skeets, is_1v1, last_updated) ", g_sSQLTable);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"VALUES ('%s', '%s', %d, %d, %d) ", steamid, sNameEscaped, skeets, iIs1v1, iTime);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"ON DUPLICATE KEY UPDATE skeets = GREATEST(skeets, VALUES(skeets)), name = VALUES(name), last_updated = VALUES(last_updated)");
		}
		case SQL_SQLite:
		{
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"INSERT INTO `%s` (steamid, name, skeets, is_1v1, last_updated) ", g_sSQLTable);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"VALUES ('%s', '%s', %d, %d, %d) ", steamid, sNameEscaped, skeets, iIs1v1, iTime);
			iLen += Format(sQuery[iLen], sizeof(sQuery) - iLen,
				"ON CONFLICT(steamid, is_1v1) DO UPDATE SET skeets = MAX(skeets, excluded.skeets), name = excluded.name, last_updated = excluded.last_updated");
		}
		default:
		{
			g_iMigrationFailed++;
			g_iMigrationDone++;
			return;
		}
	}

	g_db.Query(MigrationRow_Callback, sQuery);
}

void MigrationRow_Callback(Database database, DBResultSet results, const char[] error, any data)
{
	if (error[0] != '\0')
	{
		g_iMigrationFailed++;
		LogError("[\x04Skeets\x01] Importación: error insertando fila: %s", error);
	}

	g_iMigrationDone++;

	if (g_iMigrationDone >= g_iMigrationTotal)
		AnnounceMigrationComplete();
}

void AnnounceMigrationComplete()
{
	int ok = g_iMigrationTotal - g_iMigrationFailed;

	char msg[256];
	FormatEx(msg, sizeof(msg), "[\x04Skeets\x01] Importación completa: %d/%d filas OK, %d fallidas.",
		ok, g_iMigrationTotal, g_iMigrationFailed);

	LogMessage(msg);

	if (g_iMigrationClient != 0)
	{
		int client = GetClientOfUserId(g_iMigrationClient);
		if (client != 0)
			PrintToConsole(client, msg);
	}
}


public void OnPluginStart()
{
	hEnablePlugin 			= CreateConVar("skeet_database_enable", 			"1", "Enable this plugin?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	OneShotSkeet 			= CreateConVar("skeet_database_announce_oneshot", 	"1", "Only count 'One Shot' skeet? [1: Yes, 0: No]", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hCvarAnnounce 			= CreateConVar("skeet_database_announce", 			"0", "Announce skeet/shots in chatbox when someone skeets.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarModesTog 		= CreateConVar("skeet_database_modes_tog",			"4", "Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus. Add numbers together.", FCVAR_NOTIFY, true, 0.0, true, 7.0);
	g_hCvarSurvivorRequired = CreateConVar("top_skeet_survivors_required",		"1", "Numbers of Survivors required at least to enable this plugin", FCVAR_NOTIFY , true, 1.0, true, 32.0);
	g_hCvarAIHunter 		= CreateConVar("skeet_database_ai_hunter_enable",	"1", "Count AI Hunter also? [1: Yes, 0: No]", FCVAR_NOTIFY , true, 0.0, true, 1.0);
	g_hCvar1v1Separate 		= CreateConVar("skeet_database_1v1_seprate",		"1", "Record 1v1 skeet database in 1v1 mode.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	GetCvars();
	hCvarAnnounce.AddChangeHook(ConVarChange_hCvarAnnounce);
	
	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarSurvivorLimit = FindConVar("survivor_limit");
	g_hCvarInfectedLimit = FindConVar("z_max_player_zombies");
	hEnablePlugin.AddChangeHook(ConVarChanged_Allow);
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarSurvivorRequired.AddChangeHook(ConVarChanged_Allow);
	g_hCvarSurvivorLimit.AddChangeHook(ConVarChanged_Allow);

	BuildPath(Path_SM, datafilepath, 256, "data/%s", "skeet_database.txt");
	BuildPath(Path_SM, datafilepath_1v1, 256, "data/%s", "1v1_skeet_database.txt");
	RegConsoleCmd("sm_skeets", Command_Stats, "Show your current skeet statistics and rank.", 0);
	RegConsoleCmd("sm_top5", Command_Top, "Show TOP 5 players in statistics.", 0);

	OnPluginStart_SQL();
	OnPluginStart_Migration();

	AutoExecConfig(true,"skeet_database");
}

public void OnPluginEnd()
{
	delete g_hData;
	OnPluginEnd_SQL();
}

public void OnConfigsExecuted()
{
	IsAllowed();

	int SurvivorsLimit = g_hCvarSurvivorLimit.IntValue;
	int InfectedLimit = g_hCvarInfectedLimit.IntValue;
	if(SurvivorsLimit == 1 && InfectedLimit == 1)
	{
		Is1v1 = true;
	}
	else
	{
		Is1v1 = false;
	}

	if (g_hCvarUseSQL.BoolValue)
	{
		// Modo SQL: no se usa KeyValues, delegamos la conexión al módulo.
		delete g_hData;
		OnConfigsExecuted_SQL();
		return;
	}

	delete g_hData;
	g_hData = new KeyValues("skeetdata");
	if(g_hCvar1v1Separate.BoolValue && Is1v1)
	{
		if (!g_hData.ImportFromFile(datafilepath_1v1))
		{
			g_hData.JumpToKey("data", true);
			g_hData.GoBack();
			g_hData.JumpToKey("info", true);
			g_hData.SetNum("count", 0);
			g_hData.Rewind();
			g_hData.ExportToFile(datafilepath_1v1);
		}
	}
	else
	{	
		if (!g_hData.ImportFromFile(datafilepath))
		{
			g_hData.JumpToKey("data", true);
			g_hData.GoBack();
			g_hData.JumpToKey("info", true);
			g_hData.SetNum("count", 0);
			g_hData.Rewind();
			g_hData.ExportToFile(datafilepath);
		}
	}
}

void IsAllowed()
{
	bool bCvarAllow = hEnablePlugin.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	int SurvivorsLimit = g_hCvarSurvivorLimit.IntValue;
	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true && SurvivorsLimit>= g_hCvarSurvivorRequired.IntValue)
	{
		g_bCvarAllow = true;
		GetCvars();
		HookEvent("player_hurt", Event_PlayerHurt);
		HookEvent("ability_use", Event_AbilityUse);
		HookEvent("player_death", Event_PlayerDeath);
		HookEvent("round_start", Event_RoundStart);
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("weapon_fire", weapon_fire);
		HookEvent("player_bot_replace", Event_Replace);
		HookEvent("bot_player_replace", Event_Replace);
		HookEvent("player_shoved", Event_PlayerShoved);
		HookEvent("lunge_pounce", Event_LungePounce);
	}
	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false || SurvivorsLimit < g_hCvarSurvivorRequired.IntValue) )
	{
		g_bCvarAllow = false;
		UnhookEvent("player_hurt", Event_PlayerHurt);
		UnhookEvent("ability_use", Event_AbilityUse);
		UnhookEvent("player_death", Event_PlayerDeath);
		UnhookEvent("round_start", Event_RoundStart);
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("weapon_fire", weapon_fire);
		UnhookEvent("player_bot_replace", Event_Replace);
		UnhookEvent("bot_player_replace", Event_Replace);
		UnhookEvent("player_shoved", Event_PlayerShoved);
		UnhookEvent("lunge_pounce", Event_LungePounce);
	}
}

bool IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == INVALID_HANDLE )
		return false;

	int iCvarModesTog = g_hCvarModesTog.IntValue;
	if( iCvarModesTog == 0) return true;

	char CurrentGameMode[32];
	g_hCvarMPGameMode.GetString(CurrentGameMode, sizeof(CurrentGameMode));
	int g_iCurrentMode = 0;
	if(StrEqual(CurrentGameMode,"coop", false))
	{
		g_iCurrentMode = 1;
	}
	else if (StrEqual(CurrentGameMode,"versus", false))
	{
		g_iCurrentMode = 4;
	}
	else if (StrEqual(CurrentGameMode,"survival", false))
	{
		g_iCurrentMode = 2;
	}

	if( g_iCurrentMode == 0 )
		return false;
		
	if(!(iCvarModesTog & g_iCurrentMode))
		return false;

	return true;
}

void ConVarChanged_Allow(ConVar convar, const char[] oldValue, const char[] newValue)
{	
	IsAllowed();
}

void ConVarChange_hCvarAnnounce(ConVar convar, const char[] oldValue, const char[] newValue)
{	
	GetCvars();
}

void GetCvars()
{
	CvarAnnounce = hCvarAnnounce.BoolValue;
}

public void OnMapStart()
{
	PrecacheSound("player/orch_hit_Csharp_short.wav", true);
	ClearSkeetCounter();
}

public void OnMapEnd()
{
    delete g_hData;
}

Action Command_Stats(int client, int args)
{
	if(client == 0) return Plugin_Handled;

	if(!g_bCvarAllow) return Plugin_Handled;

	if (g_hCvarUseSQL.BoolValue)
	{
		ShowSkeetRankSQL(client);
		PrintSkeetsToClientSQL(client);
	}
	else
	{
		ShowSkeetRank(client);
		PrintSkeetsToClient(client);
	}

	return Plugin_Handled;
}

Action Command_Top(int client, int args)
{
	if(client == 0) return Plugin_Handled;

	if(!g_bCvarAllow) return Plugin_Handled;

	if (g_hCvarUseSQL.BoolValue)
		PrintTopSkeetersSQL(client);
	else
		PrintTopSkeeters(client);

	return Plugin_Handled;
}

void Event_LungePounce(Event event, const char[] name, bool dontBroadcast) 
{
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	g_bIsPouncing[attacker] = false;
	g_bHasLandedPounce[attacker] = true;
}

void weapon_fire(Event event, const char[] name, bool dontBroadcast) 
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	for (int i=1;i <= MaxClients;++i)
	{
		g_bShotCounted[i][client] = false;
	}
}

void Event_Replace(Event event, const char[] name, bool dontBroadcast) 
{
	int player = GetClientOfUserId(event.GetInt("player"));
	int bot = GetClientOfUserId(event.GetInt("bot"));
	Skeets[player] = 0;
	Skeets[bot] = 0;
	Kills[player] = 0;
	Kills[bot] = 0;
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) 
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim))
	{
		return;
	}
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int damage = event.GetInt("dmg_health");
	if (IsValidClient(attacker) && GetClientTeam(attacker) == 2)
	{
		if (IsPlayerHunter(victim))
		{
			if (!g_bShotCounted[victim][attacker])
			{
				g_iShotsDealt[victim][attacker]++;
				g_bShotCounted[victim][attacker] = true;
			}
			int remaining_health = event.GetInt("health");
			if (0 >= remaining_health)
			{
				return;
			}
			g_iLastHealth[victim] = remaining_health;
			g_iDamageDealt[victim][attacker] += damage;
		}
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) 
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim))
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (attacker == 0 || !IsClientInGame(attacker))
	{
		if (GetClientTeam(victim) == 3)
		{
			ClearDamage(victim);
		}

		return;
	}
	if (GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 3)
	{
		int zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
		if (zombieclass == 5)
		{
			return;
		}

		int lasthealth = g_iLastHealth[victim];
		g_iDamageDealt[victim][attacker] += lasthealth ;
		if (zombieclass == 3 && g_bIsPouncing[victim] == true)
		{
			int[][] assisters = new int[g_iSurvivorLimit][2];
			int assister_count;
			int shots = g_iShotsDealt[victim][attacker];
			for (int i=1;i <= MaxClients;++i)
			{
				if (!(attacker == i))
				{
					if (g_iDamageDealt[victim][i] > 0 && IsClientInGame(i))
					{
						assisters[assister_count][0] = i;
						assisters[assister_count][1] = g_iDamageDealt[victim][i];
						assister_count++;
					}
				}
			}
			if (assister_count)
			{
			}
			else
			{
				if (!IsFakeClient(victim) || (IsFakeClient(victim) && GetConVarBool(g_hCvarAIHunter)) )
				{
					if (!IsFakeClient(attacker))
					{
						int mode = OneShotSkeet.IntValue;
						if (mode == 1)
						{
							if (shots == 1)
							{
								RegisterSkeetStat(attacker);
								Skeeted(attacker);
								Skeets[attacker]++;
								Kills[attacker]++;
							}
						}
						else
						{
							RegisterSkeetStat(attacker);
							Skeeted(attacker);
							Skeets[attacker]++;
							Kills[attacker]++;
						}
						if (shots == 1)
						{
							if(CvarAnnounce)
							{
								CPrintToChatAll("[{green}Skeets{default}] {olive}%N skeeted {olive}%N in 1 shot%s", attacker, victim, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " in 1v1." : ".");
							}
						}
						else
						{
							if(CvarAnnounce)
							{
								CPrintToChatAll("[{green}Skeets{default}] {olive}%N skeeted {olive}%N in {green}%i{default} shots%s", attacker, victim, shots, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " in 1v1." : ".");
							}
						}
					}
				}
			}
		}
		else
		{
			Kills[attacker]++;
		}
	}
	if (GetClientTeam(victim) == 3)
	{
		ClearDamage(victim);
	}
}

void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast) 
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsClientInGame(client) && IsPlayerHunter(client))
	{
		g_bIsPouncing[client] = true;
		CreateTimer(0.1, Timer_GroundedCheck, client, TIMER_REPEAT);
	}
}

Action Timer_GroundedCheck(Handle timer, int client)
{
	if ( !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 3 || !IsPlayerHunter(client) || IsGrounded(client) || IsOnLadder(client) )
	{
		g_bIsPouncing[client] = false;
		remove_damage(client);

		return Plugin_Stop;
	}
	return Plugin_Continue;
}

void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast) 
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim))
	{
		return;
	}
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (attacker == 0 || !IsClientInGame(attacker) || GetClientTeam(attacker) != 2)
	{
		return;
	}
	int zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
	if (zombieclass == 3 && g_bIsPouncing[victim])
	{
		if (IsFakeClient(victim) && !g_hCvarAIHunter.BoolValue )
		{
			return;
		}
		g_bIsPouncing[victim] = false;
		g_bHasLandedPounce[attacker] = false;
		Handle pack;
		CreateDataTimer(0.2, Timer_DeadstopCheck, pack, TIMER_FLAG_NO_MAPCHANGE);
		WritePackCell(pack, attacker);
		WritePackCell(pack, victim);
	}
}

Action Timer_DeadstopCheck(Handle timer, Handle pack)
{
	ResetPack(pack, false);
	int attacker = ReadPackCell(pack);
	if (!g_bHasLandedPounce[attacker])
	{
		int victim = ReadPackCell(pack);
		if (!IsFakeClient(victim) || (IsFakeClient(victim) && g_hCvarAIHunter.BoolValue) )
		{
			if (IsClientInGame(victim) && IsClientInGame(attacker))
			{
				DeadStoped[attacker]++;
				if (!IsFakeClient(attacker))
				{
					if(CvarAnnounce)
					{
						CPrintToChat(attacker, "[{green}Skeets{default}] You {green}DeadStoped {olive}%N%s", victim, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
					}
				}
				if (!IsFakeClient(victim))
				{
					if(CvarAnnounce)
					{
						CPrintToChat(victim, "[{green}Skeets{default}] {olive}You {default}were deadstopped by {green}%N%s", attacker, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

void remove_damage(int client)
{
	for (int i=1;MaxClients >= i;++i)
	{
		g_damage[client][i] = 0;
	}
}

bool IsGrounded(int client)
{
	return (GetEntProp(client, Prop_Data, "m_fFlags") & FL_ONGROUND) > 0;
}

void ClearDamage(int client)
{
	for (int i=1;i <= MaxClients;++i)
	{
		g_iDamageDealt[client][i] = 0;
		g_iShotsDealt[client][i] = 0;
	}
}

bool IsValidClient(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return false;
	}
	if (!IsValidEntity(client))
	{
		return false;
	}
	return true;
}

void ClearSkeetCounter()
{
	for (int i=1;i <= MaxClients;++i)
	{
		Skeets[i] = 0;
		Kills[i] = 0;
		DeadStoped[i] = 0;
	}
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) 
{
	for (int i=1;i <= MaxClients;++i)
	{
		ClearDamage(i);
	}
	if (!g_bRoundEndAnnounce)
	{
		if(CvarAnnounce)
			PrintStats();
		g_bRoundEndAnnounce = true;
	}
}

void PrintStats()
{
	int survivor_index = 0;
	int[] survivor_clients = new int[MaxClients+1];
	int client;
	for (client=1;client <= MaxClients;++client)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != 2) continue;

		survivor_clients[survivor_index] = client;
		survivor_index++;
	}

	SortCustom1D(survivor_clients, survivor_index, SortByDamageDesc);

	PrintToChatAll("{default}------------------------------");
	int frags;
	int skeetscount;
	int shoved;
	for (int i=0;i < survivor_index;++i)
	{
		client = survivor_clients[i];
		frags = Kills[client];
		skeetscount = Skeets[client];
		shoved = DeadStoped[client];
		PrintToChatAll("\x04%N \x03(Kills: \x01%i \x03| Skeets: \x01%i \x03| Deadstops: \x01%i\x03)", client, frags, skeetscount, shoved);
	}
	PrintToChatAll("{default}------------------------------");
}

int SortByDamageDesc(int elem1, int elem2, const int[] array, Handle hndl)
{
	if (Kills[elem1] > Kills[elem2])
	{
		return -1;
	}
	if (Kills[elem2] > Kills[elem1])
	{
		return 1;
	}
	if (elem1 > elem2)
	{
		return -1;
	}
	if (elem2 > elem1)
	{
		return 1;
	}
	return 0;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	ClearSkeetCounter();
	g_bRoundEndAnnounce = false;
}

/**
 * Punto unico de registro de un skeet. Bifurca entre el modulo SQL
 * y el flujo original de KeyValues segun skeet_database_use_sql.
 *
 * Reemplaza los dos CreateTimer(0.0, Timer_Statistic, ...) duplicados
 * que existian en Event_PlayerDeath.
 *
 * @param attacker  Cliente que hizo el skeet.
 * @noreturn
 */
void RegisterSkeetStat(int attacker)
{
	if (g_hCvarUseSQL.BoolValue)
	{
		RegisterSkeetSQL(attacker);
		CreateTimer(0.1, Timer_PrintTopSkeetersSQL, 0, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		CreateTimer(0.0, Timer_Statistic, GetClientUserId(attacker), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(0.1, Timer_PrintTopSkeeters, 0, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_PrintTopSkeetersSQL(Handle timer, int data)
{
	PrintTopSkeetersSQL(0);
	return Plugin_Continue;
}

void Skeeted(int client)
{
	CreateTimer(0.1, Award, client, TIMER_FLAG_NO_MAPCHANGE);
	timerDeath[client] = 200;
}

Action Award(Handle timer, int client)
{
	if (!IsClientInGame(client)) return Plugin_Continue;

	timerDeath[client] -= 20;
	if (timerDeath[client] > 101)
	{
		EmitSoundToAll("player/orch_hit_Csharp_short.wav", client, 3, 140, 0, 1.0, timerDeath[client], -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		switch (timerDeath[client])
		{
			case 120:
			{
				CreateTimer(1.1, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			case 140:
			{
				CreateTimer(0.8, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			case 160:
			{
				CreateTimer(0.5, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			case 180:
			{
				CreateTimer(0.3, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			default:
			{
				CreateTimer(1.3, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}

	return Plugin_Continue;
}

bool IsPlayerHunter(int client)
{
	if (GetEntProp(client, Prop_Send, "m_zombieClass") == 3)
	{
		return true;
	}
	return false;
}

Action Timer_PrintTopSkeeters(Handle timer, int attacker)
{
	PrintTopSkeeters(0);
	return Plugin_Continue;
}

void PrintTopSkeeters(int client)
{
	if(g_hData == null) return;
	g_hData.Rewind();

	g_hData.JumpToKey("info", false);
	int count = g_hData.GetNum("count", 0);

	CPlayerSkeetData CTopPlayer[TOP_NUMBER];
	int totalskeets=0, Max_skeets, iSkeets, Max_index;
	bool bIgnore;
	g_hData.GoBack();
	g_hData.JumpToKey("data", false);
	
	for(int current = 0; current < TOP_NUMBER; current++)
	{
		g_hData.GotoFirstSubKey(true);

		Max_skeets = 0;
		Max_index = 0;
		for (int index=1; index <= count ;++index, g_hData.GotoNextKey(true))
		{
			iSkeets = g_hData.GetNum("skeet", 0);
			if(iSkeets <= 0) continue;

			if(current == 0)
			{
				totalskeets += iSkeets;
			}
			else
			{
				bIgnore = false;
				for(int previous = 0; previous < current; previous++)
				{
					//PrintToChatAll("%d - CTopPlayer[previous].m_iPosition: %d", previous, CTopPlayer[previous].m_iPosition);
					if(index == CTopPlayer[previous].m_iPosition)
					{
						//PrintToChatAll("index(%d) == CTopPlayer[previous].m_iPosition", index);
						if(current-1==previous) g_hData.GetString("name", CTopPlayer[previous].m_sName, sizeof(CPlayerSkeetData::m_sName), "Unnamed");
						bIgnore = true;
						break;
					}
				}
				if(bIgnore) continue;
			}
			
			if(iSkeets > Max_skeets)
			{
				//PrintToChatAll("iSkeets: %d, Max_skeets: %d, index: %d", iSkeets, Max_skeets, index);
				Max_skeets 	= iSkeets;
				Max_index 	= index;
			}
		}
		//PrintToChatAll("Max_skeets: %d, Max_index: %d", Max_skeets, Max_index);
		CTopPlayer[current].m_iSkeets 		= Max_skeets;
		CTopPlayer[current].m_iPosition 	= Max_index;
		g_hData.GoBack();
	}
	g_hData.GotoFirstSubKey(true);
	for (int index=1; index <= count ;++index, g_hData.GotoNextKey(true))
	{
		if(index == CTopPlayer[TOP_NUMBER-1].m_iPosition)
		{
			g_hData.GetString("name", CTopPlayer[TOP_NUMBER-1].m_sName, sizeof(CPlayerSkeetData::m_sName), "Unnamed");
			break;
		}
	}

	Panel panel = new Panel();
	int oneshot = OneShotSkeet.IntValue;
	static char sBuffer[128];
	if (oneshot == 1)
	{
		if(g_hCvar1v1Separate.BoolValue && Is1v1)
			FormatEx(sBuffer, sizeof(sBuffer), "Mejores skeeters de One Shot");
		else
			FormatEx(sBuffer, sizeof(sBuffer), "Mejores skeeters de One Shot");
	}
	else
	{
		if(g_hCvar1v1Separate.BoolValue && Is1v1)
			FormatEx(sBuffer, sizeof(sBuffer), "Mejores %d Skeeters", TOP_NUMBER);
		else 
			FormatEx(sBuffer, sizeof(sBuffer), "Mejores %d Skeeters", TOP_NUMBER);
	}
	panel.SetTitle(sBuffer);
	panel.DrawText("\n ");
	if (totalskeets)
	{
		for (int i=0 ; i<TOP_NUMBER && i < count;++i)
		{
			FormatEx(sBuffer, sizeof(sBuffer), "%d skeets - %s", CTopPlayer[i].m_iSkeets, CTopPlayer[i].m_sName);
			panel.DrawItem(sBuffer);
		}
		panel.DrawText("\n ");
		FormatEx(sBuffer, sizeof(sBuffer), "Hay %d skeets en el servidor%s", totalskeets, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " in 1v1." : ".");
		panel.DrawText(sBuffer);
	}
	else
	{
		Format(sBuffer, sizeof(sBuffer), "Aún no hay skeets en el servidor%s", (g_hCvar1v1Separate.BoolValue && Is1v1) ? " in 1v1." : ".");
	}

	if(client == 0)
	{
		for (int player = 1; player<=MaxClients; ++player)
		{	
			if (IsClientInGame(player) && !IsFakeClient(player))
			{
				panel.Send(player, TopSkeetPanelHandler, 5);
			}
		}
	}
	else 
	{
		panel.Send(client, TopSkeetPanelHandler, 5);
	}

	delete panel;
}

Action Timer_Statistic(Handle timer, int attacker)
{
	if(g_hData == null) return Plugin_Continue;
	g_hData.Rewind();
	g_hData.JumpToKey("data", true);

	attacker = GetClientOfUserId(attacker);
	if(attacker > 0 && IsClientInGame(attacker))
	{
		static char clientname[32];
		GetClientName(attacker, clientname, 32);
		ReplaceString(clientname, 32, "'", "", true);
		ReplaceString(clientname, 32, "<", "", true);
		ReplaceString(clientname, 32, "{", "", true);
		ReplaceString(clientname, 32, "}", "", true);
		ReplaceString(clientname, 32, "\n", "", true);
		ReplaceString(clientname, 32, "\"", "", true);
		static char clientauth[32];
		GetClientAuthId(attacker, AuthId_Steam2, clientauth, 32);
		if (!g_hData.JumpToKey(clientauth, false))
		{
			g_hData.GoBack();
			g_hData.JumpToKey("info", true);
			int count = g_hData.GetNum("count", 0);
			count++;
			g_hData.SetNum("count", count);
			g_hData.GoBack();
			g_hData.JumpToKey("data", true);
			g_hData.JumpToKey(clientauth, true);
		}
		int skeet = g_hData.GetNum("skeet", 0);
		skeet++;
		g_hData.SetNum("skeet", skeet);
		g_hData.SetString("name", clientname);
		g_hData.Rewind();

		if(g_hCvar1v1Separate.BoolValue && Is1v1)
			g_hData.ExportToFile(datafilepath_1v1);
		else
			g_hData.ExportToFile(datafilepath);
		if(CvarAnnounce)
		{
			CPrintToChat(attacker, "[{green}Skeets{default}] You have {green}%d skeets%s", skeet, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
		}
	}

	return Plugin_Continue;
}

void PrintSkeetsToClient(int client)
{
	if(g_hData == null) return;
	g_hData.Rewind();

	char auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, 32);
	g_hData.JumpToKey("data", false);
	g_hData.JumpToKey(auth, false);
	int skeet = g_hData.GetNum("skeet", 0);
	if (skeet == 1)
	{
		CPrintToChat(client, "[{green}Skeets{default}] You only have {green}1 skeet%s", (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
	}
	else if (skeet < 1)
	{
		CPrintToChat(client, "[{green}Skeets{default}] You don't have skeets%s", (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
	}
	else
	{
		CPrintToChat(client, "[{green}Skeets{default}] You have {green}%d skeets%s", skeet, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in 1v1." : ".");
	}
	return;
}

void ShowSkeetRank(int client)
{
	if(g_hData == null) return;
	g_hData.Rewind();

	g_hData.JumpToKey("info", false);
	int count = g_hData.GetNum("count", 0);
	g_hData.GoBack();
	g_hData.JumpToKey("data", false);
	int skeet;
	char auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, 32);
	if (g_hData.JumpToKey(auth, false))
	{
		skeet = g_hData.GetNum("skeet", 0);
	}
	else
	{
		skeet = 0;
	}
	int rank = TopTo(skeet);
	CPrintToChat(client, "{green}Skeet Ranking{default}: {lightgreen}%d/%d%s", rank, count, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " {default}in {lightgreen}1v1{default}." : ".");
}

int TopTo(int skeeti)
{
	if(g_hData == null) return 0;
	g_hData.Rewind();
	
	g_hData.JumpToKey("info", false);
	int count = g_hData.GetNum("count", 0);
	int skeet;
	g_hData.GoBack();
	g_hData.JumpToKey("data", false);
	g_hData.GotoFirstSubKey(true);
	int total;
	for (int i=0;i < count;++i)
	{
		skeet = g_hData.GetNum("skeet", 0);
		if (skeet >= skeeti)
		{
			total++;
		}
		g_hData.GotoNextKey(true);
	}
	return total;
}

int TopSkeetPanelHandler(Handle menu, MenuAction action, int param1, int param2)
{
	return 0;
}

bool IsOnLadder(int entity)
{
    return GetEntityMoveType(entity) == MOVETYPE_LADDER;
}