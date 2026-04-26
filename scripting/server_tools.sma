// Lightweight admin tools that should stay cheap at runtime.
//
// Commands:
//   /revive, /respawn  - menu of dead players to respawn
//   amx_revive <name>  - console command for admins/RCON
//
// Access:
//   Uses ADMIN_CFG by default. This avoids exposing revive to every player,
//   because server.cfg intentionally grants some lower admin flags globally.

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <hamsandwich>

#define REVIVE_ACCESS ADMIN_CFG

new g_cvarReviveHealth;

public plugin_init()
{
    register_plugin("Server Tools", "1.0", "aiteklabs");

    register_clcmd("say /revive",       "cmd_revive_menu");
    register_clcmd("say_team /revive",  "cmd_revive_menu");
    register_clcmd("say /respawn",      "cmd_revive_menu");
    register_clcmd("say_team /respawn", "cmd_revive_menu");

    register_concmd("amx_revive", "cmd_amx_revive", REVIVE_ACCESS, "<name|#userid> - respawn a dead player");

    // 0 = reuse fe_health from full_equip.amxx. Set a value to override.
    g_cvarReviveHealth = register_cvar("st_revive_health", "0");
}

public cmd_revive_menu(id)
{
    if (!has_revive_access(id))
        return PLUGIN_HANDLED;

    new menu = menu_create("\y[AITEKLABS] Revive Player", "handle_revive_menu");
    new players[32], num, count;
    get_players(players, num, "bch");

    for (new i = 0; i < num; i++)
    {
        new target = players[i];
        if (!is_playing_team(target))
            continue;

        new name[32], info[4];
        get_user_name(target, name, charsmax(name));
        num_to_str(target, info, charsmax(info));
        menu_additem(menu, name, info);
        count++;
    }

    if (count == 0)
    {
        menu_destroy(menu);
        client_print(id, print_chat, "[REVIVE] No dead player available.");
        return PLUGIN_HANDLED;
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public handle_revive_menu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new info[8], name[64], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), name, charsmax(name), callback);

    new target = str_to_num(info);
    revive_player(id, target);

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_amx_revive(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED;

    new arg[32];
    read_argv(1, arg, charsmax(arg));

    new target = cmd_target(id, arg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
    if (!target)
        return PLUGIN_HANDLED;

    revive_player(id, target);
    return PLUGIN_HANDLED;
}

bool:has_revive_access(id)
{
    if (id == 0)
        return true;

    if (get_user_flags(id) & REVIVE_ACCESS)
        return true;

    client_print(id, print_chat, "[REVIVE] No access.");
    return false;
}

bool:is_playing_team(id)
{
    new CsTeams:team = cs_get_user_team(id);
    return (team == CS_TEAM_T || team == CS_TEAM_CT);
}

revive_player(admin, target)
{
    if (!is_user_connected(target))
        return 0;

    if (!is_playing_team(target))
    {
        print_admin(admin, "[REVIVE] Target must be on T or CT.");
        return 0;
    }

    if (is_user_alive(target))
    {
        print_admin(admin, "[REVIVE] Target is already alive.");
        return 0;
    }

    ExecuteHamB(Ham_CS_RoundRespawn, target);
    set_task(0.2, "task_post_revive_equip", target);

    new target_name[32], admin_name[32];
    get_user_name(target, target_name, charsmax(target_name));
    get_admin_name(admin, admin_name, charsmax(admin_name));

    client_print(0, print_chat, "[REVIVE] %s revived %s.", admin_name, target_name);
    log_amx("[REVIVE] %s revived %s", admin_name, target_name);
    return 1;
}

public task_post_revive_equip(id)
{
    if (!is_user_alive(id))
        return;

    new hp = get_pcvar_num(g_cvarReviveHealth);
    if (hp <= 0)
        hp = get_cvar_num("fe_health");
    if (hp > 0)
        set_user_health(id, hp);

    if (get_cvar_num("fe_armor") == 1)
        cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);

    new money = get_cvar_num("fe_money");
    if (money > 0)
        cs_set_user_money(id, money, 1);
}

get_admin_name(admin, output[], len)
{
    if (admin > 0 && is_user_connected(admin))
        get_user_name(admin, output, len);
    else
        copy(output, len, "Console");
}

print_admin(admin, const message[])
{
    if (admin > 0 && is_user_connected(admin))
        client_print(admin, print_chat, "%s", message);
    else
        server_print("%s", message);
}
