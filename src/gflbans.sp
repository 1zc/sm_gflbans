// Copyright (c) 2021 Dreae
// 
// This software is released under the MIT License.
// https://opensource.org/licenses/MIT

#pragma semicolon 1

#include <sourcemod>
#include <adminmenu>
#include <clientprefs>
#include "includes/commands"
#include "includes/globals"
#include "includes/api"
#include "includes/log"

public Plugin myinfo = {
    name = "GFLBans",
    author = "Dreae",
    description = "SourceMod integration with GFL Bans",
    version = "0.0.1", 
    url = "https://gitlab.gflclan.com/Dreae/sm_gflbans"
}

public void OnPluginStart() {
    GFLBans_RegisterCommands();
    GFLBans_InitLogging();
    g_cvar_gflbans_website = CreateConVar("gflbans_website", "", "Base URL for GFL Bans instance");
    g_cvar_gflbans_global_bans = CreateConVar("gflbans_global_bans", "1", "Should this server accept global bans");
    g_cvar_gflbans_server_id = CreateConVar("gflbans_server_id", "", "ID for this server in GFL Bans", FCVAR_PROTECTED);
    g_cvar_gflbans_server_key = CreateConVar("gflbans_server_key", "", "Key for this server in GFL Bans", FCVAR_PROTECTED);

    g_cvar_gflbans_vpn_mode = CreateConVar("gflbans_vpn_mode", "kick", "kick|notify - Action to take when a VPN is detected");
    g_cvar_gflbans_vpn_mode.AddChangeHook(Cvar_VPNModeChanged);
    g_cvar_gflbans_allow_cloud_gaming = CreateConVar("gflbans_allow_cloud_gaming", "1", "Should cloud gaming IPs be allowed");

    ConVar cvar_hostname = FindConVar("hostname");
    ConVar cvar_password = FindConVar("sv_password");
    cvar_hostname.AddChangeHook(Cvar_HostnameChanged);
    cvar_password.AddChangeHook(Cvar_PasswordChanged);

    CheckServerMod();
    CheckServerOS();
    GFLBansAPI_StartHeartbeatTimer();

    LoadTranslations("common.phrases");
    LoadTranslations("gflbans.phrases");
    AutoExecConfig(true, "gflbans");
    
    TopMenu topmenu;
    if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null)) {
        OnAdminMenuReady(topmenu);
    }

    for (int c = 1; c <= MaxClients; c++) {
        if (IsClientAuthorized(c)) {
            OnClientAuthorized(c, "");
        }
        if (AreClientCookiesCached(c)) {
            OnClientCookiesCached(c);
        }
    }
}

public void OnMapStart() {
    GetCurrentMap(g_s_current_map, sizeof(g_s_current_map));
}

public void OnConfigsExecuted() {
    ConVar cvar_hostname = FindConVar("hostname");
    ConVar cvar_password = FindConVar("sv_password");
    
    cvar_hostname.GetString(g_s_server_hostname, sizeof(g_s_server_hostname));

    char buffer[32];
    cvar_password.GetString(buffer, sizeof(buffer));
    Cvar_PasswordChanged(cvar_password, "", buffer);
    
    g_cvar_gflbans_vpn_mode.GetString(buffer, sizeof(buffer));
    Cvar_VPNModeChanged(g_cvar_gflbans_vpn_mode, "", buffer);

    GFLBansLogs_OnConfigsLoaded();
    GFLBansAPI_DoHeartbeat();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args) {
    return GFLBansAM_OnClientSayCommand(client, args);
}

public void OnClientAuthorized(int client, const char[] auth) {
    if (!IsFakeClient(client)) {
        GFLBansAPI_CheckClient(client);
        GFLBansAPI_VPNCheckClient(client);
    }
}

public void OnClientPostAdminCheck(int client) {
    if (AreClientCookiesCached(client)) {
        OnClientCookiesCached(client);
    }
}

public void OnClientDisconnect(int client) {
    if (!IsFakeClient(client)) {
        GFLBansAM_Abort(client);
        GFLBansLogs_OnClientDisconnected(client);
    }
    GFLBans_KillPunishmentTimers(client);
}

public void OnClientCookiesCached(int client) {
    GFLBansLogs_OnClientCookiesCached(client);
}

public void Cvar_HostnameChanged(ConVar cvar, const char[] old_value, const char[] new_value) {
    Format(g_s_server_hostname, sizeof(g_s_server_hostname), new_value);
}

public void Cvar_PasswordChanged(ConVar cvar, const char[] old_value, const char[] new_value) {
    if (strlen(new_value) == 0) {
        g_b_server_locked = false;
    } else {
        g_b_server_locked = true;
    }
}

public void Cvar_VPNModeChanged(ConVar cvar, const char[] old_value, const char[] new_value) {
    if (StrEqual(new_value, "kick", false)) {
        g_vpn_action = VPNAction_Kick;
    } else if (StrEqual(new_value, "notify", false)) {
        g_vpn_action = VPNAction_Notify;
    } else {
        GFLBans_LogWarn("gfl_vpn_mode %s is invalid, defaulting to notify", new_value);
        g_vpn_action = VPNAction_Notify;
    }
}

void CheckServerMod() {
    if (GetEngineVersion() == Engine_CSGO) {
        Format(g_s_server_mod, sizeof(g_s_server_mod), "csgo");
    } else if (GetEngineVersion() == Engine_CSS) { 
        Format(g_s_server_mod, sizeof(g_s_server_mod), "css"); // The best game
    } else if (GetEngineVersion() == Engine_TF2) { 
        Format(g_s_server_mod, sizeof(g_s_server_mod), "tf");
    } else {
        SetFailState("Incompatible mod");
    }
}

void CheckServerOS() {
    Handle game_data = LoadGameConfigFile("gflbans.games");
    if (game_data == INVALID_HANDLE) {
        GFLBans_LogError("Error getting server OS, unable to load gamedata");
        Format(g_s_server_os, sizeof(g_s_server_os), "unknown");
    } else {
        if (GameConfGetOffset(game_data, "CheckOS") == 1) {
            Format(g_s_server_os, sizeof(g_s_server_os), "windows");
        } else {
            Format(g_s_server_os, sizeof(g_s_server_os), "linux");
        }
        delete game_data;
    }
}
