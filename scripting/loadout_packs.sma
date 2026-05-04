// Fast spawn loadout packs for public multiplayer.
//
// The pack menu pops up on every respawn and the player must pick a pack
// each time - no auto-reapply of the previous choice. Picking "8. No auto
// pack" is the opt-out: the menu stops appearing for that player. They can
// reopen it any time with /packs.
//
// Commands:
//   /packs, /guns, /loadout  - open the pack menu
//   /rifle, /rush, /shotgun, /heavy, /pistol, /awppack, /random, /nopack
//
// The AWP pack respects wl_awp_per_team when weapon_limits.amxx is enabled.

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>

#define KEYS_ALL 1023
#define TASK_SPAWN_PACK 3000

enum
{
    PACK_NONE = 0,
    PACK_CLASSIC,
    PACK_AWP,
    PACK_RUSH,
    PACK_SHOTGUN,
    PACK_HEAVY,
    PACK_PISTOL,
    PACK_RANDOM
}

new g_pack[33];
new bool:g_menuShown[33];

// Pack choice keyed by SteamID. The engine drops + re-adds every player on
// level change (client_disconnected / client_putinserver fire), which would
// otherwise wipe g_pack and re-show the menu after every map.
new Trie:g_packStore;

new g_cvarEnabled;
new g_cvarShowMenu;
new g_cvarSpawnDelay;

public plugin_init()
{
    register_plugin("Loadout Packs", "1.0", "aiteklabs");

    g_cvarEnabled    = register_cvar("lp_enabled",     "1");
    g_cvarShowMenu   = register_cvar("lp_show_menu",   "1");
    g_cvarSpawnDelay = register_cvar("lp_spawn_delay", "0.6");

    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawnPost", 1);

    register_clcmd("say /packs",        "cmd_pack_menu");
    register_clcmd("say /pack",         "cmd_pack_menu");
    register_clcmd("say /guns",         "cmd_pack_menu");
    register_clcmd("say /gun",          "cmd_pack_menu");
    register_clcmd("say /loadout",      "cmd_pack_menu");
    register_clcmd("say_team /packs",   "cmd_pack_menu");
    register_clcmd("say_team /pack",    "cmd_pack_menu");
    register_clcmd("say_team /guns",    "cmd_pack_menu");
    register_clcmd("say_team /loadout", "cmd_pack_menu");

    register_clcmd("say /1",        "cmd_pack_classic");
    register_clcmd("say /rifle",    "cmd_pack_classic");
    register_clcmd("say /ak",       "cmd_pack_classic");
    register_clcmd("say /m4",       "cmd_pack_classic");
    register_clcmd("say /2",        "cmd_pack_awp");
    register_clcmd("say /awppack",  "cmd_pack_awp");
    register_clcmd("say /sniper",   "cmd_pack_awp");
    register_clcmd("say /3",        "cmd_pack_rush");
    register_clcmd("say /rush",     "cmd_pack_rush");
    register_clcmd("say /p90",      "cmd_pack_rush");
    register_clcmd("say /4",        "cmd_pack_shotgun");
    register_clcmd("say /shotgun",  "cmd_pack_shotgun");
    register_clcmd("say /5",        "cmd_pack_heavy");
    register_clcmd("say /heavy",    "cmd_pack_heavy");
    register_clcmd("say /m249",     "cmd_pack_heavy");
    register_clcmd("say /6",        "cmd_pack_pistol");
    register_clcmd("say /pistol",   "cmd_pack_pistol");
    register_clcmd("say /deagle",   "cmd_pack_pistol");
    register_clcmd("say /7",        "cmd_pack_random");
    register_clcmd("say /random",   "cmd_pack_random");
    register_clcmd("say /8",        "cmd_pack_none");
    register_clcmd("say /nopack",   "cmd_pack_none");
    register_clcmd("say /noauto",   "cmd_pack_none");

    register_clcmd("say_team /1",        "cmd_pack_classic");
    register_clcmd("say_team /rifle",    "cmd_pack_classic");
    register_clcmd("say_team /ak",       "cmd_pack_classic");
    register_clcmd("say_team /m4",       "cmd_pack_classic");
    register_clcmd("say_team /2",        "cmd_pack_awp");
    register_clcmd("say_team /awppack",  "cmd_pack_awp");
    register_clcmd("say_team /sniper",   "cmd_pack_awp");
    register_clcmd("say_team /3",        "cmd_pack_rush");
    register_clcmd("say_team /rush",     "cmd_pack_rush");
    register_clcmd("say_team /p90",      "cmd_pack_rush");
    register_clcmd("say_team /4",        "cmd_pack_shotgun");
    register_clcmd("say_team /shotgun",  "cmd_pack_shotgun");
    register_clcmd("say_team /5",        "cmd_pack_heavy");
    register_clcmd("say_team /heavy",    "cmd_pack_heavy");
    register_clcmd("say_team /m249",     "cmd_pack_heavy");
    register_clcmd("say_team /6",        "cmd_pack_pistol");
    register_clcmd("say_team /pistol",   "cmd_pack_pistol");
    register_clcmd("say_team /deagle",   "cmd_pack_pistol");
    register_clcmd("say_team /7",        "cmd_pack_random");
    register_clcmd("say_team /random",   "cmd_pack_random");
    register_clcmd("say_team /8",        "cmd_pack_none");
    register_clcmd("say_team /nopack",   "cmd_pack_none");
    register_clcmd("say_team /noauto",   "cmd_pack_none");

    register_menucmd(register_menuid("AitekLoadout"), KEYS_ALL, "handle_pack_menu");

    g_packStore = TrieCreate();
}

public plugin_end()
{
    if (g_packStore != Invalid_Trie)
        TrieDestroy(g_packStore);
}

public client_putinserver(id)
{
    g_pack[id] = PACK_NONE;
    g_menuShown[id] = false;

    if (is_user_bot(id))
        return;

    new authid[40];
    get_user_authid(id, authid, charsmax(authid));
    if (!valid_authid(authid))
        return;

    new stored;
    if (TrieGetCell(g_packStore, authid, stored))
    {
        g_pack[id] = stored;
        g_menuShown[id] = true;
    }
}

public client_disconnected(id)
{
    remove_task(id + TASK_SPAWN_PACK);
    g_pack[id] = PACK_NONE;
    g_menuShown[id] = false;
}

public OnPlayerSpawnPost(id)
{
    if (!is_user_alive(id) || is_user_bot(id))
        return;

    remove_task(id + TASK_SPAWN_PACK);
    set_task(get_pcvar_float(g_cvarSpawnDelay), "task_spawn_pack", id + TASK_SPAWN_PACK);
}

public task_spawn_pack(taskid)
{
    new id = taskid - TASK_SPAWN_PACK;
    if (!is_user_alive(id) || is_user_bot(id))
        return;

    if (get_pcvar_num(g_cvarEnabled) != 1)
        return;

    if (!is_playing_team(id))
        return;

    if (get_pcvar_num(g_cvarShowMenu) != 1)
        return;

    // Opt-out: player picked "8. No auto pack" (PACK_NONE after a menu choice).
    // Everyone else gets the menu fresh on every respawn - no auto-reapply.
    if (g_pack[id] == PACK_NONE && g_menuShown[id])
        return;

    show_pack_menu(id);
}

public cmd_pack_menu(id)
{
    if (get_pcvar_num(g_cvarEnabled) != 1)
        return PLUGIN_HANDLED;

    show_pack_menu(id);
    return PLUGIN_HANDLED;
}

public cmd_pack_classic(id) { select_pack(id, PACK_CLASSIC); return PLUGIN_HANDLED; }
public cmd_pack_awp(id)     { select_pack(id, PACK_AWP);     return PLUGIN_HANDLED; }
public cmd_pack_rush(id)    { select_pack(id, PACK_RUSH);    return PLUGIN_HANDLED; }
public cmd_pack_shotgun(id) { select_pack(id, PACK_SHOTGUN); return PLUGIN_HANDLED; }
public cmd_pack_heavy(id)   { select_pack(id, PACK_HEAVY);   return PLUGIN_HANDLED; }
public cmd_pack_pistol(id)  { select_pack(id, PACK_PISTOL);  return PLUGIN_HANDLED; }
public cmd_pack_random(id)  { select_pack(id, PACK_RANDOM);  return PLUGIN_HANDLED; }
public cmd_pack_none(id)    { select_pack(id, PACK_NONE);    return PLUGIN_HANDLED; }

show_pack_menu(id)
{
    new menu[768];
    formatex(menu, charsmax(menu), "\y[AITEKLABS] Spawn Packs\w^n^n\
\y1. \wRifle: AK/M4 + Deagle + grenades^n\
\y2. \wSniper: AWP + Deagle + grenades^n\
\y3. \wRush: P90 + Deagle + grenades^n\
\y4. \wShotgun: XM1014 + Deagle + grenades^n\
\y5. \wHeavy: M249 + Deagle + grenades^n\
\y6. \wPistol: Deagle + grenades^n\
\y7. \wRandom fun pack every spawn^n\
\y8. \wNo auto pack^n^n\
\y0. \wClose");

    show_menu(id, KEYS_ALL, menu, -1, "AitekLoadout");
}

public handle_pack_menu(id, key)
{
    switch (key)
    {
        case 0: select_pack(id, PACK_CLASSIC);
        case 1: select_pack(id, PACK_AWP);
        case 2: select_pack(id, PACK_RUSH);
        case 3: select_pack(id, PACK_SHOTGUN);
        case 4: select_pack(id, PACK_HEAVY);
        case 5: select_pack(id, PACK_PISTOL);
        case 6: select_pack(id, PACK_RANDOM);
        case 7: select_pack(id, PACK_NONE);
    }
    return PLUGIN_HANDLED;
}

select_pack(id, pack)
{
    if (!is_user_connected(id))
        return;

    g_pack[id] = pack;
    g_menuShown[id] = true;

    persist_pack(id, pack);

    if (pack == PACK_NONE)
    {
        client_print(id, print_chat, "[PACKS] Auto pack disabled. Type /packs to choose again.");
        return;
    }

    new label[32];
    pack_label(pack, label, charsmax(label));
    client_print(id, print_chat, "[PACKS] Selected: %s. Type /packs to change.", label);

    if (is_user_alive(id) && is_playing_team(id))
        apply_pack(id, pack, true);
}

apply_pack(id, pack, bool:manual)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return 0;

    new actual = pack;
    if (actual == PACK_RANDOM)
        actual = random_num(PACK_CLASSIC, PACK_PISTOL);

    if (actual == PACK_AWP && !can_take_awp(id))
    {
        client_print(id, print_center, "AWP limit reached - rifle pack given");
        actual = PACK_CLASSIC;
    }

    reset_player_weapons(id, team);

    switch (actual)
    {
        case PACK_CLASSIC:
        {
            if (team == CS_TEAM_T)
                give_weapon_ammo(id, "weapon_ak47", CSW_AK47, 90);
            else
                give_weapon_ammo(id, "weapon_m4a1", CSW_M4A1, 90);
            give_deagle(id);
            give_grenades(id);
        }
        case PACK_AWP:
        {
            give_weapon_ammo(id, "weapon_awp", CSW_AWP, 30);
            give_deagle(id);
            give_grenades(id);
        }
        case PACK_RUSH:
        {
            give_weapon_ammo(id, "weapon_p90", CSW_P90, 100);
            give_deagle(id);
            give_grenades(id);
        }
        case PACK_SHOTGUN:
        {
            give_weapon_ammo(id, "weapon_xm1014", CSW_XM1014, 32);
            give_deagle(id);
            give_grenades(id);
        }
        case PACK_HEAVY:
        {
            give_weapon_ammo(id, "weapon_m249", CSW_M249, 200);
            give_deagle(id);
            give_grenades(id);
        }
        case PACK_PISTOL:
        {
            give_deagle(id);
            give_grenades(id);
        }
    }

    new label[32];
    pack_label(actual, label, charsmax(label));

    if (manual)
        client_print(id, print_chat, "[PACKS] %s applied now.", label);
    else
        client_print(id, print_center, "Pack: %s", label);

    return 1;
}

reset_player_weapons(id, CsTeams:team)
{
    new hadC4 = user_has_weapon(id, CSW_C4);

    strip_user_weapons(id);
    give_item(id, "weapon_knife");

    if (team == CS_TEAM_CT)
        cs_set_user_defuse(id, 1);

    new money = get_cvar_num("fe_money");
    if (money > 0)
        cs_set_user_money(id, money, 1);

    if (get_cvar_num("fe_armor") == 1)
        cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);

    if (hadC4 && team == CS_TEAM_T)
    {
        give_item(id, "weapon_c4");
        cs_set_user_plant(id, 1, 1);
    }
}

give_deagle(id)
{
    give_weapon_ammo(id, "weapon_deagle", CSW_DEAGLE, 35);
}

give_grenades(id)
{
    give_item(id, "weapon_hegrenade");
    cs_set_user_bpammo(id, CSW_HEGRENADE, 1);

    give_item(id, "weapon_flashbang");
    cs_set_user_bpammo(id, CSW_FLASHBANG, 2);

    give_item(id, "weapon_smokegrenade");
    cs_set_user_bpammo(id, CSW_SMOKEGRENADE, 1);
}

give_weapon_ammo(id, const weapon[], csw, ammo)
{
    give_item(id, weapon);
    if (ammo > 0)
        cs_set_user_bpammo(id, csw, ammo);
}

bool:is_playing_team(id)
{
    new CsTeams:team = cs_get_user_team(id);
    return (team == CS_TEAM_T || team == CS_TEAM_CT);
}

bool:can_take_awp(id)
{
    new limit = get_cvar_num("wl_awp_per_team");
    if (limit <= 0)
        return true;

    return team_awp_count(id) < limit;
}

team_awp_count(exclude_id)
{
    new CsTeams:team = cs_get_user_team(exclude_id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return 0;

    new players[32], num;
    get_players(players, num, "a");

    new count = 0;
    for (new i = 0; i < num; i++)
    {
        if (players[i] == exclude_id)
            continue;
        if (cs_get_user_team(players[i]) != team)
            continue;
        if (user_has_weapon(players[i], CSW_AWP))
            count++;
    }
    return count;
}

pack_label(pack, label[], len)
{
    switch (pack)
    {
        case PACK_CLASSIC: copy(label, len, "Rifle AK/M4");
        case PACK_AWP:     copy(label, len, "AWP Sniper");
        case PACK_RUSH:    copy(label, len, "Rush P90");
        case PACK_SHOTGUN: copy(label, len, "Shotgun");
        case PACK_HEAVY:   copy(label, len, "Heavy M249");
        case PACK_PISTOL:  copy(label, len, "Pistol Deagle");
        case PACK_RANDOM:  copy(label, len, "Random");
        default:           copy(label, len, "None");
    }
}

persist_pack(id, pack)
{
    if (is_user_bot(id))
        return;

    new authid[40];
    get_user_authid(id, authid, charsmax(authid));
    if (!valid_authid(authid))
        return;

    TrieSetCell(g_packStore, authid, pack);
}

bool:valid_authid(const authid[])
{
    if (authid[0] == 0)
        return false;
    if (equal(authid, "BOT"))
        return false;
    if (equal(authid, "HLTV"))
        return false;
    if (equal(authid, "STEAM_ID_PENDING"))
        return false;
    if (equal(authid, "STEAM_ID_LAN"))
        return false;
    if (equal(authid, "VALVE_ID_LOH"))
        return false;
    return true;
}
