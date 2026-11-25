-- Locales/ZoneNames.lua
-- v1.0.0-beta.7: Russian names of the open-world zones, shown when the
-- addon speaks Russian but the game client is English (the client names
-- zones in its own language). From the ZONE_CATALOG.json draft
-- (draft-2); zones without an approved Russian name keep their English
-- name. Only the text on screen changes: saved data and the matching of
-- zones always use the client's own names.
local _, ns = ...

ns.ZONE_NAMES_RU = {
    ["Duskwood"] = "Сумеречный лес",
    ["Elwynn Forest"] = "Элвиннский лес",
    ["Westfall"] = "Западный Край",
    ["Redridge Mountains"] = "Красногорье",
    ["Stormwind City"] = "Штормград",
    ["Dun Morogh"] = "Дун Морог",
    ["Ironforge"] = "Стальгорн",
    ["Loch Modan"] = "Лок Модан",
    ["Wetlands"] = "Болотина",
    ["Arathi Highlands"] = "Нагорье Арати",
    ["The Hinterlands"] = "Внутренние земли",
    ["Hillsbrad Foothills"] = "Предгорья Хилсбрада",
    ["Alterac Mountains"] = "Альтеракские горы",
    ["Silverpine Forest"] = "Серебряный бор",
    ["Tirisfal Glades"] = "Тирисфальские леса",
    ["Undercity"] = "Подгород",
    ["Western Plaguelands"] = "Западные Чумные земли",
    ["Eastern Plaguelands"] = "Восточные Чумные земли",
    ["Badlands"] = "Бесплодные земли",
    ["Searing Gorge"] = "Тлеющее ущелье",
    ["Burning Steppes"] = "Пылающие степи",
    ["Blasted Lands"] = "Выжженные земли",
    ["Deadwind Pass"] = "Перевал Мёртвого Ветра",
    ["Swamp of Sorrows"] = "Болото Печали",
    ["Stranglethorn Vale"] = "Тернистая долина",
    ["Durotar"] = "Дуротар",
    ["Orgrimmar"] = "Оргриммар",
    ["The Barrens"] = "Степи",
    ["Mulgore"] = "Мулгор",
    ["Thunder Bluff"] = "Громовой Утёс",
    ["Stonetalon Mountains"] = "Когтистые горы",
    ["Desolace"] = "Пустоши",
    ["Feralas"] = "Фералас",
    ["Thousand Needles"] = "Тысяча Игл",
    ["Tanaris"] = "Танарис",
    ["Un'Goro Crater"] = "Кратер Ун'Горо",
    ["Silithus"] = "Силитус",
    ["Dustwallow Marsh"] = "Пылевые топи",
    ["Ashenvale"] = "Ясеневый лес",
    ["Darkshore"] = "Тёмные берега",
    ["Teldrassil"] = "Тельдрассил",
    ["Darnassus"] = "Дарнас",
    ["Felwood"] = "Осквернённый лес",
    ["Moonglade"] = "Лунная поляна",
    ["Azshara"] = "Азшара",
    ["Winterspring"] = "Зимние Ключи",
    ["Mount Hyjal"] = "Гора Хиджал",
    ["Ruins of Gilneas"] = "Руины Гилнеаса",
}

-- The name of a zone as shown on screen.
function ns.ZoneText(name)
    if type(name) ~= "string" or ns.activeLocaleCode ~= "ruRU" then
        return name
    end
    return ns.ZONE_NAMES_RU[name] or name
end
