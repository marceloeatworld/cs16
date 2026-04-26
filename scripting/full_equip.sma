// Spawn loadout (money/armor/HP) + ammo refill on every weapon event.
// Money can also be topped back up after purchases so players can always buy.
//
// Cvars:
//   fe_money   int    money on spawn             (default 16000)
//   fe_armor   0|1    kevlar+helmet on spawn     (default 1)
//   fe_health  int    HP on spawn, 0 = default 100 (default 125)
//   fe_refill_money 0|1 top money back up after buys (default 1)
//
// Pistols and shotguns never reload (clip refilled on every shot).
// Rifles/SMGs/snipers reload normally but their backpack ammo is kept
// topped up — mp_infinite_ammo stays at 0 because ReGameDLL's value 1
// makes rifles skip reload, which we don't want.
//
// CZ bots run their own auto-buy after Ham_Spawn and overwrite the
// armor/HP we set, so we re-apply via set_task(0.3) for both humans
// and bots.

#include <amxmodx>
#include <cstrike>
#include <hamsandwich>
#include <fun>
#include <engine>

#define TASK_REAPPLY 1000
#define TASK_REFILL_MONEY 2000

new g_cvarMoney;
new g_cvarArmor;
new g_cvarHealth;
new g_cvarRefillMoney;

public plugin_init()
{
    register_plugin("Full Equip", "1.2", "aiteklabs");

    g_cvarMoney       = register_cvar("fe_money",        "16000");
    g_cvarArmor       = register_cvar("fe_armor",        "1");
    g_cvarHealth      = register_cvar("fe_health",       "125");
    g_cvarRefillMoney = register_cvar("fe_refill_money", "1");

    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawnPost", 1);
    register_event("CurWeapon", "event_curweapon", "be", "1=1");
    register_event("Money", "event_money", "be");
}

public OnPlayerSpawnPost(id)
{
    if (!is_user_alive(id))
        return;

    apply_equip(id);
    set_task(0.3, "task_reapply", id + TASK_REAPPLY);
}

public client_disconnected(id)
{
    remove_task(id + TASK_REAPPLY);
    remove_task(id + TASK_REFILL_MONEY);
}

public task_reapply(taskid)
{
    new id = taskid - TASK_REAPPLY;
    if (is_user_alive(id))
        apply_equip(id);
}

public event_money(id)
{
    if (get_pcvar_num(g_cvarRefillMoney) != 1)
        return;

    new target = get_pcvar_num(g_cvarMoney);
    if (target <= 0)
        return;

    if (read_data(1) < target)
        set_task(0.1, "task_refill_money", id + TASK_REFILL_MONEY);
}

public task_refill_money(taskid)
{
    new id = taskid - TASK_REFILL_MONEY;
    if (!is_user_connected(id))
        return;

    new target = get_pcvar_num(g_cvarMoney);
    if (target > 0 && cs_get_user_money(id) < target)
        cs_set_user_money(id, target, 1);
}

apply_equip(id)
{
    new money = get_pcvar_num(g_cvarMoney);
    if (money > 0)
        cs_set_user_money(id, money, 1);

    if (get_pcvar_num(g_cvarArmor) == 1)
        cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);

    new hp = get_pcvar_num(g_cvarHealth);
    if (hp > 0)
        set_user_health(id, hp);
}

public event_curweapon(id)
{
    new wpn = read_data(2);
    new clip = read_data(3);

    new maxclip = noreload_maxclip(wpn);
    if (maxclip > 0)
    {
        if (clip < maxclip)
        {
            new wname[32];
            get_weaponname(wpn, wname, charsmax(wname));
            new ent = find_ent_by_owner(-1, wname, id);
            if (ent > 0)
                cs_set_weapon_ammo(ent, maxclip);
        }
        return;
    }

    new maxbp = weapon_maxbp(wpn);
    if (maxbp > 0)
        cs_set_user_bpammo(id, wpn, maxbp);
}

noreload_maxclip(wpn)
{
    switch (wpn)
    {
        case CSW_GLOCK18:   return 20;
        case CSW_USP:       return 12;
        case CSW_P228:      return 13;
        case CSW_DEAGLE:    return 7;
        case CSW_FIVESEVEN: return 20;
        case CSW_ELITE:     return 30;
        case CSW_M3:        return 8;
        case CSW_XM1014:    return 7;
    }
    return 0;
}

weapon_maxbp(wpn)
{
    switch (wpn)
    {
        case CSW_AK47, CSW_M4A1, CSW_SG552, CSW_AUG, CSW_FAMAS, CSW_GALIL: return 90;
        case CSW_MP5NAVY, CSW_P90, CSW_UMP45, CSW_TMP, CSW_MAC10:          return 120;
        case CSW_SCOUT, CSW_AWP, CSW_G3SG1, CSW_SG550:                     return 30;
        case CSW_M249:                                                     return 200;
    }
    return 0;
}
