#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>

/*****************************************************************
            G L O B A L   V A R S
*****************************************************************/

ConVar
    g_cvarEnable; // Para habilitar o deshabilitar el plugin.

bool g_bReadyUpAvailable;

/*****************************************************************
            P L U G I N   I N F O
*****************************************************************/

public Plugin myinfo = 
{
    name        = "[L4D2] Map on ReadyUp",
    author      = "Beckan",
    description = "Displays the map name in the ReadyUp panel footer (Optional Dep).",
    version     = "1.0.2",
    url         = ""
};

/*****************************************************************
            F O R W A R D   P U B L I C S
*****************************************************************/

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    g_bReadyUpAvailable = LibraryExists("readyup");
}

public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, "readyup"))
        g_bReadyUpAvailable = true;
}

public void OnLibraryRemoved(const char[] sName)
{
    if (StrEqual(sName, "readyup"))
        g_bReadyUpAvailable = false;
}

/*****************************************************************
            P L U G I N   I N I T I A L I Z A T I O N
*****************************************************************/

public void OnPluginStart()
{
    g_cvarEnable = CreateConVar(
        "sm_mapname_readyup_enable",
        "1",
        "Enable or disable the Map Name on ReadyUp plugin.",
        FCVAR_NOTIFY,
        true, 0.0, true, 1.0
    );

    LoadTranslations("MapNameReadyUp.phrases");

    AutoExecConfig(false, "MapNameReadyUp");
}

/*****************************************************************
        R E A D Y U P   F O R W A R D S
*****************************************************************/

public void OnReadyUpInitiate()
{
    if (!g_cvarEnable.BoolValue || !g_bReadyUpAvailable)
        return;

    char sMapName[64];
    GetCurrentMap(sMapName, sizeof(sMapName));

    char sFooter[128];
    Format(sFooter, sizeof(sFooter), "%T: %s", "Current Map", LANG_SERVER, sMapName);

    AddStringToReadyFooter("");
    AddStringToReadyFooter(sFooter);
}