// Rock-the-vote, welcome message, /help.
// /rtv triggers a map vote when 60% of players agree.
// /nextmap and /timeleft come from nextmap.amxx and timeleft.amxx.

#include <amxmodx>

#define RTV_PERCENT 60

new bool:g_hasRTVd[33];
new g_rtvCount = 0;

new const g_maps[][] = {
    "de_dust2", "de_inferno", "de_nuke", "de_train",
    "de_aztec", "cs_italy", "de_cbble", "cs_assault"
};

public plugin_init()
{
    register_plugin("Fun Extras", "1.0", "aiteklabs");

    register_clcmd("say /rtv",        "cmd_rtv");
    register_clcmd("say rtv",         "cmd_rtv");
    register_clcmd("say_team /rtv",   "cmd_rtv");

    register_clcmd("say /help",       "cmd_help");
    register_clcmd("say /commands",   "cmd_help");
    register_clcmd("say /cmds",       "cmd_help");
}

public client_putinserver(id)
{
    g_hasRTVd[id] = false;
    set_task(8.0, "welcome_msg", id);
}

public client_disconnected(id)
{
    if (g_hasRTVd[id])
    {
        g_hasRTVd[id] = false;
        if (g_rtvCount > 0)
            g_rtvCount--;
    }
}

public welcome_msg(id)
{
    if (!is_user_connected(id))
        return;
    client_print(id, print_chat, "[AITEKLABS] Welcome! Type /help to see available commands.");
}

public cmd_help(id)
{
    client_print(id, print_chat, "[AITEKLABS] Player: /rtv /maps /nextmap /timeleft /help");
    client_print(id, print_chat, "[AITEKLABS] Maps: /de /cs /fy /aim /awp /rats /ka /dr");
    client_print(id, print_chat, "[AITEKLABS] Admin: /admin /kick /ban /slap /map /bot /restart /revive");
    return PLUGIN_HANDLED;
}

public cmd_rtv(id)
{
    if (g_hasRTVd[id])
    {
        client_print(id, print_chat, "[RTV] You already voted.");
        return PLUGIN_HANDLED;
    }

    g_hasRTVd[id] = true;
    g_rtvCount++;

    new name[32];
    get_user_name(id, name, charsmax(name));

    new players[32], num;
    get_players(players, num, "ch");

    new need = (num * RTV_PERCENT) / 100;
    if (need < 2)
        need = 2;

    client_print(0, print_chat, "[RTV] %s wants to change map (%d/%d votes)", name, g_rtvCount, need);

    if (g_rtvCount >= need)
    {
        start_map_vote();
    }

    return PLUGIN_HANDLED;
}

start_map_vote()
{
    new total = sizeof(g_maps);
    new m1 = random(total);
    new m2 = random(total);
    while (m2 == m1)
        m2 = random(total);
    new m3 = random(total);
    while (m3 == m1 || m3 == m2)
        m3 = random(total);

    new cmd[128];
    formatex(cmd, charsmax(cmd), "amx_votemap %s %s %s", g_maps[m1], g_maps[m2], g_maps[m3]);

    client_print(0, print_chat, "[RTV] Enough votes -- starting map vote!");
    server_cmd(cmd);

    g_rtvCount = 0;
    for (new i = 1; i <= 32; i++)
        g_hasRTVd[i] = false;
}
