/*
    ToDo:
        Translations (untested!)
        clean up
*/

#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <csgoitems>
#include <multicolors>
#include <autoexecconfig>

#pragma newdecls required

#define LoopClients(%1) for(int %1 = 1; %1 <= MaxClients; %1++) if(IsClientValid(%1))
#define PTAG "{darkblue}[Outbreak]{default}"

#define CHANGE_INTERVAL 5
#define KNIFE_LENGTH 128

bool g_bDebug = false;

int g_iKnife[MAXPLAYERS + 1] =  { -1, ... };
int g_iSite[MAXPLAYERS + 1] =  { 0, ... };
int g_iLastChange[MAXPLAYERS + 1] =  { -1, ... };

ConVar g_cMessage = null;
ConVar g_cShowDisableKnifes = null;
ConVar g_cFlag = null;

Database g_dDB = null;

public Plugin myinfo = 
{
    name = "Knifes",
    author = "Bara",
    description = "",
    version = "1.0.0",
    url = "github.com/Bara"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("Knifes_GetIndex", Native_GetIndex);

    RegPluginLibrary("knifes");

    return APLRes_Success;
}

public int Native_GetIndex(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    return g_iKnife[client];
}

public void OnPluginStart()
{
    LoadTranslations("knifes.phrases");
    
    RegConsoleCmd("sm_knife", Command_Knife);
    RegConsoleCmd("sm_knifes", Command_Knife);
    RegConsoleCmd("sm_rknife", Command_RKnife);
    
    RegAdminCmd("sm_aknife", Command_AKnife, ADMFLAG_ROOT);
    RegAdminCmd("sm_dknife", Command_DKnife, ADMFLAG_ROOT);
    
    AutoExecConfig_SetCreateDirectory(true);
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("plugin.knifes");
    g_cMessage = AutoExecConfig_CreateConVar("knifes_show_message", "1", "Show message on knife selection", _, true, 0.0, true, 1.0);
    g_cShowDisableKnifes = AutoExecConfig_CreateConVar("knifes_show_disabled_knife", "1", "Show disabled knifes (for user without flag)", _, true, 0.0, true, 1.0);
    g_cFlag = AutoExecConfig_CreateConVar("knifes_flag", "t", "Flag to get access");
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
    
    HookEvent("player_spawn", Event_PlayerSpawn);
    
    LoopClients(i)
    {
        OnClientPutInServer(i);
    }
    
    connectSQL();
}

public void OnMapStart()
{
    connectSQL();
}

void connectSQL()
{
    if (SQL_CheckConfig("knifes"))
    {
        SQL_TConnect(OnSQLConnect, "knifes");
    }
    else
    {
        SetFailState("Can't find an entry in your databases.cfg with the name \"knifes\"");
        return;
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnClientPostAdminCheck(int client)
{
    if(IsClientValid(client))
    {
        LoadClientKnifes(client);
    }
}

public void OnWeaponEquipPost(int client, int weapon)
{
    if (IsClientValid(client) && IsPlayerAlive(client))
    {
        int iDef = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
        
        if (CSGOItems_IsDefIndexKnife(iDef))
        {
            if (g_bDebug)
            {
                PrintToChat(client, "OnWeaponEquipPost1 - iDef: %d | g_iKnife: %d", iDef, g_iKnife[client]);
            }
            
            if (g_iKnife[client] <= 0 && (iDef == 42 || iDef == 59))
            {
                return;
            }
            
            if (g_bDebug)
            {
                PrintToChat(client, "OnWeaponEquipPost2 - iDef: %d | g_iKnife: %d", iDef, g_iKnife[client]);
            }
            
            char sClassname[KNIFE_LENGTH], sClass[KNIFE_LENGTH];
            CSGOItems_GetWeaponClassNameByDefIndex(g_iKnife[client], sClassname, sizeof(sClassname));
            CSGOItems_GetWeaponClassNameByDefIndex(iDef, sClass, sizeof(sClass));
            
            if(!StrEqual(sClassname, sClass, false))
            {
                if (g_bDebug)
                {
                    PrintToChat(client, "OnWeaponEquipPost3 - iDef: %d (%s) | g_iKnife: %d (%s)", iDef, sClass, g_iKnife[client], sClassname);
                }
                
                ReplaceClientKnife(client);
                return;
            }
        }
    }
}

public Action Command_DKnife(int client, int args)
{
    if (g_bDebug)
    {
        g_bDebug = false;
    }
    else
    {
        g_bDebug = true;
    }
    
    CPrintToChat(client, "%s Debug: {yellow}%d", PTAG, g_bDebug);
    
    CPrintToChat(client, "%s Items Synced: {yellow}%d", PTAG, CSGOItems_AreItemsSynced());
}

public Action Command_AKnife(int client, int args)
{
    if (args != 1)
    {
        ReplyToCommand(client, "sm_aknife <#UserID|Name>");
        return Plugin_Handled;
    }
    
    int targets[129];
    bool ml = false;
    char buffer[MAX_NAME_LENGTH], arg1[MAX_NAME_LENGTH], arg2[5];
    
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int count = ProcessTargetString(arg1, client, targets, sizeof(targets), COMMAND_FILTER_CONNECTED, buffer, sizeof(buffer), ml);
    if (count <= 0)
    {
        ReplyToCommand(client, "Invalid Target");
        return Plugin_Handled;
    }
    else for (int i = 0; i < count; i++)
    {
        int target = targets[i];
        
        if(!IsClientValid(target))
        {
            return Plugin_Handled;
        }
        
        if (!HasClientFlags(target, g_cFlag))
        {
            CPrintToChat(client, "%T", "Target No Permissions", client, PTAG, target);
            return Plugin_Handled;
        }
        
        int iDef = g_iKnife[target];
        char sDisplay[KNIFE_LENGTH];
        
        if (iDef > 0)
        {
            CSGOItems_GetWeaponDisplayNameByDefIndex(iDef, sDisplay, sizeof(sDisplay));
        }
        
        if (iDef == 42 || iDef == 59)
        {
            CPrintToChat(client, "%T", "Target Default Knife", client, PTAG, target);
        }
        else
        {
            if (IsPlayerAlive(target))
            {
                char sWeapon[32];
                
                int iWeapon = -1;
                while((iWeapon = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE)) != -1)
                {
                    if (CSGOItems_IsValidWeapon(iWeapon))
                    {
                        int def = CSGOItems_GetWeaponDefIndexByWeapon(iWeapon);
                        
                        if (CSGOItems_IsDefIndexKnife(def))
                        {
                            CSGOItems_GetWeaponClassNameByDefIndex(def, sWeapon, sizeof(sWeapon));
                            break;
                        }
                    }
                }
                
                CPrintToChat(client, "%T", "Target Knife Active", client, PTAG, target, sDisplay, sWeapon);
            }
            else
            {
                CPrintToChat(client, "%T", "Target Knife", client, PTAG, target, sDisplay);
            }
        }
    }
    
    return Plugin_Continue;
}

public Action Command_Knife(int client, int args)
{
    if(!IsClientValid(client))
    {
        return Plugin_Handled;
    }

    if (!HasClientFlags(client, g_cFlag))
    {
        CPrintToChat(client, "%T", "No Permissions", client, PTAG);
        return Plugin_Handled;
    }
    
    ShowKnifeMenu(client);
    
    return Plugin_Continue;
}

public Action Command_RKnife(int client, int args)
{
    if(!IsClientValid(client))
    {
        return Plugin_Handled;
    }

    if (!HasClientFlags(client, g_cFlag))
    {
        CPrintToChat(client, "%T", "No Permissions", client, PTAG);
        return Plugin_Handled;
    }
    
    char sCommunityID[32];
            
    if (!GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID)))
    {
        LogError("Auth failed for client index %d", client);
        return Plugin_Handled;
    }
    
    char sQuery[2048];
    
    Format(sQuery, sizeof(sQuery), "DELETE FROM `knifes` WHERE communityid = \"%s\";", sCommunityID);
    
    if (g_bDebug)
    {
        LogMessage(sQuery);
    }
    
    g_dDB.Query(Knife_DeletePlayer, sQuery, GetClientUserId(client));
    
    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(IsClientValid(client) && g_iKnife[client] > 0)
    {
        RequestFrame(Frame_PlayerSpawn, event.GetInt("userid"));
    }
}

public void Frame_PlayerSpawn(any userid)
{
    int client = GetClientOfUserId(userid);
    
    if (IsClientValid(client) && IsPlayerAlive(client) && g_iKnife[client] > 0)
    {
        ReplaceClientKnife(client);
    }
}

public void Frame_OpenMenu(any userid)
{
    int client = GetClientOfUserId(userid);
    
    if (IsClientValid(client))
    {
        ShowKnifeMenu(client);
    }
}

void ShowKnifeMenu(int client)
{
    Menu menu = new Menu(Menu_Knife);
    
    if (g_iKnife[client] > 0)
    {
        char sDisplay[KNIFE_LENGTH];
        CSGOItems_GetWeaponDisplayNameByDefIndex(g_iKnife[client], sDisplay, sizeof(sDisplay));
        
        if(g_iKnife[client] == 59)
        {
            Format(sDisplay, sizeof(sDisplay), "%T", "T Knife", client, sDisplay);
        }
        
        menu.SetTitle("%T", "Choose a Knife Currently", client, sDisplay);
    }
    
    int iDef = CSGOItems_GetActiveWeaponDefIndex(client);
    
    if (g_bDebug)
    {
        PrintToChat(client, "ShowKnifeMenu Def: %d", CSGOItems_GetActiveWeaponDefIndex(client));
    }
    
    if (iDef != 42 && iDef != 59)
    {
        menu.AddItem("0", "Default");
    }
    else if (g_iKnife[client] < 1)
    {
        menu.SetTitle("%T", "Choose a Knife Currently", client, "Default");
        menu.AddItem("0", "Default", ITEMDRAW_DISABLED);
    }
    else
    {
        menu.SetTitle("%T", "Choose a Knife Currently", client, "Default");
        menu.AddItem("0", "Default", ITEMDRAW_DISABLED);
    }
        
    for (int i = 0; i <= CSGOItems_GetWeaponCount(); i++)
    {
        int defIndex = CSGOItems_GetWeaponDefIndexByWeaponNum(i);
        
        if(CSGOItems_IsDefIndexKnife(defIndex))
        {
            char sClassName[KNIFE_LENGTH], sDisplayName[KNIFE_LENGTH];
            CSGOItems_GetWeaponClassNameByDefIndex(defIndex, sClassName, sizeof(sClassName));
            CSGOItems_GetWeaponDisplayNameByDefIndex(defIndex, sDisplayName, sizeof(sDisplayName));
            
            if(defIndex == 59 || defIndex == 42)
            {
                Format(sDisplayName, sizeof(sDisplayName), "%T", "T Knife", client, sDisplayName);
                continue;
            }
            
            if (g_iKnife[client] != defIndex)
            {
                menu.AddItem(sClassName, sDisplayName);
            }
            else if (g_iKnife[client] == defIndex || g_cShowDisableKnifes.BoolValue)
            {
                menu.AddItem(sClassName, sDisplayName, ITEMDRAW_DISABLED);
            }
        }
    }
    
    menu.ExitButton = true;
    menu.DisplayAt(client, g_iSite[client], MENU_TIME_FOREVER);
}

public int Menu_Knife(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        if (((g_iLastChange[client] + CHANGE_INTERVAL) <= GetTime()) || g_iLastChange[client] == -1)
        {
            char sClassname[KNIFE_LENGTH];
            menu.GetItem(param, sClassname, sizeof(sClassname));
            int defIndex = CSGOItems_GetWeaponDefIndexByClassName(sClassname);
            
            g_iLastChange[client] = GetTime();
            g_iKnife[client] = defIndex;
            UpdateClientKnife(client);
            
            if (g_cMessage.BoolValue)
            {
                char sDisplay[KNIFE_LENGTH];
                CSGOItems_GetWeaponDisplayNameByDefIndex(g_iKnife[client], sDisplay, sizeof(sDisplay));
                
                if (g_bDebug)
                {
                    PrintToChat(client, "Menu_Knife defIndex: %d - g_iKnife: %d - CSGOItems_GetActiveWeaponDefIndex: %d", defIndex, g_iKnife[client],CSGOItems_GetActiveWeaponDefIndex(client));
                }
                
                if (defIndex != 42 && defIndex != 59 && defIndex > 0)
                {
                    CPrintToChat(client, "%T", "Knife Choosed", client, PTAG, sDisplay);
                }
                else
                {
                    CPrintToChat(client, "%T", "Knife Choosed", client, PTAG, "Standard");
                }
            }
            
            g_iSite[client] = menu.Selection;
            
            if (IsPlayerAlive(client))
            {
                ReplaceClientKnife(client);
            }
        }
        else
        {
            int iLeft = (GetTime() - g_iLastChange[client] - CHANGE_INTERVAL) * -1;
            
            if (iLeft == 1)
            {
                CPrintToChat(client, "%T", "Remaining One", client, PTAG);
            }
            else
            {
                CPrintToChat(client, "%T", "Remaining", client, PTAG, iLeft);
            }
        }
        RequestFrame(Frame_OpenMenu, GetClientUserId(client));
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
}

public void OnSQLConnect(Handle owner, Handle hndl, const char[] error, any data)
{
    if (hndl == null)
    {
        SetFailState("(OnSQLConnect) Can't connect to mysql");
        return;
    }
    
    g_dDB = view_as<Database>(CloneHandle(hndl));
    
    CreateTable();
}

void CreateTable()
{
    char sQuery[1024];
    Format(sQuery, sizeof(sQuery),
    "CREATE TABLE IF NOT EXISTS `knifes` ( \
        `id` INT NOT NULL AUTO_INCREMENT, \
        `communityid` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL, \
        `defindex` int(11) NOT NULL DEFAULT '0', \
        PRIMARY KEY (`id`), \
        UNIQUE KEY (`communityid`) \
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    
    if (g_bDebug)
    {
        LogMessage(sQuery);
    }
    
    g_dDB.Query(SQL_CreateTable, sQuery);
}

public void SQL_CreateTable(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || strlen(error) > 0)
    {
        SetFailState("(SQL_CreateTable) Fail at Query: %s", error);
        return;
    }
    delete results;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientValid(i))
        {
            LoadClientKnifes(i);
        }
    }
}

void LoadClientKnifes(int client)
{
    char sCommunityID[32];
    if (!GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID)))
    {
        LogError("Auth failed for client index %d", client);
        return;
    }
    
    char sQuery[512];
    Format(sQuery, sizeof(sQuery), "SELECT defindex FROM knifes WHERE communityid = \"%s\" LIMIT 1;", sCommunityID);
    
    if (g_bDebug)
    {
        LogMessage(sQuery);
    }
    
    g_dDB.Query(SQL_LoadClientKnife, sQuery, GetClientUserId(client));
}

public void SQL_LoadClientKnife(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || strlen(error) > 0)
    {
        SetFailState("(SQL_LoadClientKnife) Fail at Query: %s", error);
        return;
    }
    else
    {
        if(results.HasResults)
        {
            int client = GetClientOfUserId(data);
                
            if (IsClientValid(client))
            {
                while (results.FetchRow())
                {
                    g_iKnife[client] = results.FetchInt(0);
                }
            }
        }
    }
}

void UpdateClientKnife(int client)
{
    char sCommunityID[32];
            
    if (!GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID)))
    {
        LogError("Auth failed for client index %d", client);
        return;
    }
    
    char sQuery[2048];
    
    Format(sQuery, sizeof(sQuery), "INSERT INTO knifes (communityid, defindex) VALUES (\"%s\", '%d') ON DUPLICATE KEY UPDATE defindex = '%d';", sCommunityID, g_iKnife[client], g_iKnife[client]);
    
    if (g_bDebug)
    {
        LogMessage(sQuery);
    }
    
    g_dDB.Query(Knife_OnUpdateClientArray, sQuery);
}

public void Knife_OnUpdateClientArray(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || strlen(error) > 0)
    {
        SetFailState("(Knife_OnUpdateClientArray) Fail at Query: %s", error);
        return;
    }
}

public void Knife_DeletePlayer(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || strlen(error) > 0)
    {
        SetFailState("(Knife_DeletePlayer) Fail at Query: %s", error);
        return;
    }
    
    int client = GetClientOfUserId(data);
    
    if (IsClientValid(client))
    {
        g_iKnife[client] = -1;
        ReplaceClientKnife(client);
    }
}

void ReplaceClientKnife(int client)
{
    if (HasClientFlags(client, g_cFlag))
    {
        if(g_iKnife[client] > 0)
        {
            char sClassname[KNIFE_LENGTH];
            CSGOItems_GetWeaponClassNameByDefIndex(g_iKnife[client], sClassname, sizeof(sClassname));
            bool success = CSGOItems_RemoveKnife(client);
            
            if (success)
            {
                DataPack pack = new DataPack();
                RequestFrame(Frame_GivePlayerItem, pack);
                pack.WriteCell(GetClientUserId(client));
                pack.WriteString(sClassname);
            }
        }
        else
        {
            bool success = CSGOItems_RemoveKnife(client);
            
            if (success)
            {
                DataPack pack = new DataPack();
                RequestFrame(Frame_GivePlayerItem, pack);
                pack.WriteCell(GetClientUserId(client));
                pack.WriteString("weapon_knife");
            }
        }		
    }
}

public void Frame_GivePlayerItem(any pack)
{
    ResetPack(pack);
    int client = GetClientOfUserId(ReadPackCell(pack));
    char sClass[KNIFE_LENGTH];
    ReadPackString(pack, sClass, sizeof(sClass));
    delete view_as<DataPack>(pack);
    
    if(IsClientValid(client) && strlen(sClass) > 2)
    {
        int iWeapon = CSGOItems_GiveWeapon(client, sClass);
        
        if (iWeapon > 0)
        {
            EquipPlayerWeapon(client, iWeapon);
            
            if (g_bDebug)
            {
                PrintToChat(client, "CSGOItems_GiveWeapon");
            }
        
            DataPack pack2 = new DataPack();
            RequestFrame(Frame_SetActionWeapon, pack2);
            pack2.WriteCell(GetClientUserId(client));
            pack2.WriteCell(iWeapon);
        }
    }
}

public void Frame_SetActionWeapon(any pack)
{
    ResetPack(pack);
    int client = GetClientOfUserId(ReadPackCell(pack));
    int weapon = ReadPackCell(pack);
    delete view_as<DataPack>(pack);
    
    if (IsClientValid(client) && CSGOItems_IsValidWeapon(weapon))
    {
        CSGOItems_SetActiveWeapon(client, weapon);
    }
}

stock bool IsClientValid(int client, bool bots = false)
{
    if (client > 0 && client <= MaxClients)
    {
        if(IsClientInGame(client) && (bots || !IsFakeClient(client)) && !IsClientSourceTV(client))
        {
            return true;
        }
    }
    
    return false;
}

stock bool HasClientFlags(int client, ConVar convar)
{
    char sConvar[18];
    convar.GetString(sConvar, sizeof(sConvar));

    AdminFlag aFlags[16];
    FlagBitsToArray(ReadFlagString(sConvar), aFlags, sizeof(aFlags));
    
    return HasFlags(client, aFlags);
}

stock bool HasFlags(int client, AdminFlag flags[16])
{
    int iFlags = GetUserFlagBits(client);
    
    if (iFlags & ADMFLAG_ROOT)
    {
        return true;
    }
    
    for (int i = 0; i < sizeof(flags); i++)
    {
        if (iFlags & FlagToBit(flags[i]))
        {
            return true;
        }
    }
    
    return false;
}
