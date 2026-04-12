// Map voting grouped by category.
// /maps lists groups. /de /cs /fy /aim /awp /rats /ka /dr start a vote
// between three random maps from the matching group.
// Maps not installed are filtered out by is_map_valid().

#include <amxmodx>

new const g_group_de[][32] = {
    "de_dust2", "de_dust", "de_inferno", "de_nuke", "de_train",
    "de_aztec", "de_cbble", "de_chateau", "de_vertigo", "de_prodigy",
    "de_storm", "de_piranesi", "de_torn", "de_airstrip", "de_survivor",
    "de_dust2_kosovo", "de_kosovo", "de_dolc", "de_gash", "de_kps", "de_pub2_r3"
};

new const g_group_cs[][32] = {
    "cs_assault", "cs_italy", "cs_office", "cs_militia",
    "cs_747", "cs_backalley", "cs_havana", "cs_siege", "cs_estate"
};

new const g_group_fy[][32] = {
    "fy_pool_day", "fy_snow", "fy_iceworld", "fy_buzzkill",
    "fy_osama_house", "35hp_2"
};

new const g_group_aim[][32] = {
    "aim_map", "aim_ak-colt", "aim_deagle_fiesta", "aim_headshot",
    "aim_sillos", "aim_dgl_old", "aim_esk_ak47",
    "aim_kosova_ak47", "aim_kosova_battle", "aim_kosova_famas"
};

new const g_group_awp[][32] = {
    "awp_map", "awp_india", "awp_snow_india",
    "awp_india_ks", "awp_kosova", "awp_kosova_battle", "awp_kosovo_trainstation"
};

new const g_group_rats[][32] = {
    "de_rats", "de_rats_2001", "de_rats4_final", "de_rats_1337"
};

new const g_group_ka[][32] = {
    "35hp", "35hp_2"
};

new const g_group_dr[][32] = {
    "deathrun_kosova"
};

public plugin_init()
{
    register_plugin("Map Groups", "1.0", "aiteklabs");

    register_clcmd("say /maps",      "cmd_menu_main");
    register_clcmd("say /mapmenu",   "cmd_menu_main");
    register_clcmd("say_team /maps", "cmd_menu_main");

    register_clcmd("say /de",        "cmd_vote_de");
    register_clcmd("say /cs",        "cmd_vote_cs");
    register_clcmd("say /fy",        "cmd_vote_fy");
    register_clcmd("say /aim",       "cmd_vote_aim");
    register_clcmd("say /awp",       "cmd_vote_awp");
    register_clcmd("say /rats",      "cmd_vote_rats");
    register_clcmd("say /ka",        "cmd_vote_ka");
    register_clcmd("say /knife",     "cmd_vote_ka");
    register_clcmd("say /dr",        "cmd_vote_dr");
    register_clcmd("say /deathrun",  "cmd_vote_dr");
}

public cmd_menu_main(id)
{
    client_print(id, print_chat, "[MAPS] Classic: /de /cs  |  Fun: /fy /aim /awp /rats /ka /dr");
    client_print(id, print_chat, "[MAPS] Each command starts a random 3-map vote in that group.");
    return PLUGIN_HANDLED;
}

public cmd_vote_de(id)  { start_group_vote(g_group_de,   sizeof(g_group_de),   "Defuse (de)");      return PLUGIN_HANDLED; }
public cmd_vote_cs(id)  { start_group_vote(g_group_cs,   sizeof(g_group_cs),   "Hostage (cs)");     return PLUGIN_HANDLED; }
public cmd_vote_fy(id)  { start_group_vote(g_group_fy,   sizeof(g_group_fy),   "Fight Yard (fy)");  return PLUGIN_HANDLED; }
public cmd_vote_aim(id) { start_group_vote(g_group_aim,  sizeof(g_group_aim),  "Aim training");     return PLUGIN_HANDLED; }
public cmd_vote_awp(id) { start_group_vote(g_group_awp,  sizeof(g_group_awp),  "AWP arena");        return PLUGIN_HANDLED; }
public cmd_vote_rats(id){ start_group_vote(g_group_rats, sizeof(g_group_rats), "Rats");             return PLUGIN_HANDLED; }
public cmd_vote_ka(id)  { start_group_vote(g_group_ka,   sizeof(g_group_ka),   "Knife arena");      return PLUGIN_HANDLED; }
public cmd_vote_dr(id)  { start_group_vote(g_group_dr,   sizeof(g_group_dr),   "Deathrun");         return PLUGIN_HANDLED; }

start_group_vote(const list[][32], count, const label[])
{
    new valid[16], vcount = 0;
    for (new i = 0; i < count && vcount < sizeof(valid); i++)
    {
        if (is_map_valid(list[i]))
            valid[vcount++] = i;
    }

    if (vcount == 0)
    {
        client_print(0, print_chat, "[MAPS] No %s maps installed on this server yet.", label);
        return;
    }

    new m1 = valid[random(vcount)];
    new m2 = -1;
    new m3 = -1;

    if (vcount >= 2)
    {
        m2 = valid[random(vcount)];
        while (m2 == m1)
            m2 = valid[random(vcount)];
    }
    if (vcount >= 3)
    {
        m3 = valid[random(vcount)];
        while (m3 == m1 || m3 == m2)
            m3 = valid[random(vcount)];
    }

    new cmd[128];
    if (m3 != -1)
        formatex(cmd, charsmax(cmd), "amx_votemap %s %s %s", list[m1], list[m2], list[m3]);
    else if (m2 != -1)
        formatex(cmd, charsmax(cmd), "amx_votemap %s %s", list[m1], list[m2]);
    else
        formatex(cmd, charsmax(cmd), "amx_map %s", list[m1]);

    client_print(0, print_chat, "[MAPS] %s vote started!", label);
    server_cmd(cmd);
}
