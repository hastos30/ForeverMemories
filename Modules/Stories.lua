-- Modules/Stories.lua
-- Discovery Stories (v0.18.0): a few lines about a zone, shown on the
-- "New location" notification at the first visit of each character and
-- on the location card of History / Locations. Keyed by AreaTable ID, the
-- same IDs as Modules/ZoneCatalog.lua. Short original texts written for
-- ForeverMemories (DRAFT: lore to be checked by Nedisan). Zones of WoW:
-- Forever whose story is not known to us (Riverglades, Shen'dralas,
-- Zephras Isle) have none: nothing is invented, and a zone without a
-- story is tracked the same way.
local _, ns = ...

local Stories = {}
ns.Stories = Stories

Stories.TEXT = {
    -- Eastern Kingdoms
    [1] = { enUS = "Snow-covered valleys around Ironforge, home of the dwarves and gnomes. Troggs and frost wolves roam the passes, and the smoke of Kharanos promises a warm hearth and strong ale.",
            ruRU = "Заснеженные долины вокруг Стальгорна, родина дворфов и гномов. На перевалах бродят троги и снежные волки, а дым над Караносом обещает тёплый очаг и крепкий эль." },
    [3] = { enUS = "A sun-scorched land of red rock and canyons. Ogres, dragons and Dark Iron dwarves dig among old Titan ruins in search of buried power.",
            ruRU = "Выжженный солнцем край красных скал и каньонов. Огры, драконы и дворфы Чёрного Железа роются в древних руинах титанов в поисках скрытой силы." },
    [4] = { enUS = "Scarred ground beneath the Dark Portal, through which the orcish Horde first came into Azeroth. The sky is red and demons still linger near the great gate.",
            ruRU = "Израненная земля у Тёмного портала, через который орочья Орда впервые пришла в Азерот. Небо здесь красное, а у великих врат до сих пор бродят демоны." },
    [8] = { enUS = "A misty swamp south of Duskwood, haunted by grief. Black dragonkin and the forsaken Sunken Temple wait in its murky waters.",
            ruRU = "Туманное болото к югу от Сумеречного леса, полное печали. В его мутных водах ждут чёрные драконы и Затонувший храм." },
    [10] = { enUS = "A forest of eternal twilight. Worgen howl in the shadows, the dead rise in Raven Hill, and the town of Darkshire keeps its lanterns burning through the night.",
             ruRU = "Лес вечных сумерек. В тенях воют ворги, на Вороньем холме встают мертвецы, а Темнолесье всю ночь не гасит свои фонари." },
    [11] = { enUS = "Rain-soaked marshes between the dwarven lands and the north. Murlocs, raptors and dragons share the bogs, and Menethil Harbor guards the road by the sea.",
             ruRU = "Промокшие болота между землями дворфов и севером. Мурлоки, ящеры и драконы делят трясину, а гавань Менетил стережёт дорогу у моря." },
    [12] = { enUS = "Gentle green hills around Stormwind, where many human heroes take their first steps. Kobolds in the mines and gnolls at the farms are only the beginning.",
             ruRU = "Мягкие зелёные холмы вокруг Штормграда, где делают первые шаги многие герои-люди. Кобольды в шахтах и гноллы на фермах — только начало." },
    [28] = { enUS = "Once fertile fields, now poisoned by the Plague. The Scourge holds Andorhal, while the Argent Dawn and the Scarlet Crusade fight in their own ways.",
             ruRU = "Когда-то плодородные поля, теперь отравленные Чумой. Плеть держит Андорал, а Серебряный Рассвет и Алый орден сражаются каждый по-своему." },
    [33] = { enUS = "A vast jungle full of tigers, trolls and pirates. Hunters seek trophies, and the goblin port of Booty Bay welcomes anyone with gold.",
             ruRU = "Огромные джунгли, полные тигров, троллей и пиратов. Охотники ищут трофеи, а гоблинская Пиратская Бухта рада любому, у кого есть золото." },
    [36] = { enUS = "Cold mountains of the fallen kingdom of Alterac. Ogres and Syndicate thieves hide among the ruins where a traitor king once ruled.",
             ruRU = "Холодные горы павшего королевства Альтерак. Огры и воры Синдиката прячутся среди руин, где когда-то правил король-предатель." },
    [38] = { enUS = "A quiet valley of lakes behind a great dam. Dwarven explorers dig here for relics, and Thelsamar greets travelers on the road east.",
             ruRU = "Тихая долина озёр за огромной плотиной. Дворфы-исследователи ищут здесь реликвии, а Телсамар встречает путников на дороге на восток." },
    [40] = { enUS = "Farmland left to bandits and harvest golems. The Defias Brotherhood plots below Moonbrook, and the People's Militia guards Sentinel Hill.",
             ruRU = "Брошенные фермы, где хозяйничают бандиты и жнецы. Братство Справедливости строит планы под Луноречьем, а Народное ополчение стережёт Сторожевой холм." },
    [41] = { enUS = "A silent, lifeless pass. Long ago the last Guardian of Tirisfal fought here, and the tower of Karazhan still keeps its secrets.",
             ruRU = "Безмолвный и безжизненный перевал. Здесь давным-давно сражался последний Страж Тирисфаля, и башня Каражан всё ещё хранит свои тайны." },
    [44] = { enUS = "Red cliffs and a broad lake east of Elwynn. Blackrock orcs and gnolls press on Lakeshire, and its people need every brave hand.",
             ruRU = "Красные скалы и широкое озеро к востоку от Элвинна. Орки Чёрной горы и гноллы теснят Приозерье, и его жителям нужна каждая смелая рука." },
    [45] = { enUS = "Rolling highlands where the human kingdom of Arathor once stood. Stromgarde lies in ruins, and ogres and trolls fight over the old stones.",
             ruRU = "Холмистое нагорье, где когда-то стояло человеческое королевство Аратор. Стромгард в руинах, а огры и тролли спорят из-за старых камней." },
    [46] = { enUS = "A land of ash and fire around Blackrock Mountain. The black dragonflight and the Dark Iron dwarves rule here among burning fields.",
             ruRU = "Край пепла и огня вокруг Чёрной горы. Здесь, среди горящих полей, правят чёрные драконы и дворфы Чёрного Железа." },
    [47] = { enUS = "Green hills and forests, home of the Wildhammer dwarves and their gryphons. Forest trolls guard their temples in the heights.",
             ruRU = "Зелёные холмы и леса, родина дворфов Громового Молота и их грифонов. Лесные тролли охраняют свои храмы в горах." },
    [51] = { enUS = "A molten gorge of slag and fire. Dark Iron dwarves work their mines here, and fire elementals walk freely among the rivers of lava.",
             ruRU = "Огненное ущелье шлака и пламени. Дворфы Чёрного Железа разрабатывают здесь шахты, а огненные элементали свободно бродят среди рек лавы." },
    [85] = { enUS = "Grey forests and fields where the Forsaken awoke. Brill and the ruins of Lordaeron lie under a sky that never feels quite alive.",
             ruRU = "Серые леса и поля, где пробудились Отрёкшиеся. Брилл и руины Лордерона лежат под небом, которое никогда не кажется по-настоящему живым." },
    [130] = { enUS = "Dark pines along a cold coast. The Forsaken hold the Sepulcher, and the wall of Gilneas rises to the south.",
              ruRU = "Тёмные сосны вдоль холодного побережья. Отрёкшиеся держат Гробницу, а на юге поднимается стена Гилнеаса." },
    [139] = { enUS = "The heart of the Plague. Stratholme burns, the Scourge rules the land, and the Argent Dawn holds out at Light's Hope Chapel.",
              ruRU = "Сердце Чумы. Стратхольм в огне, Плеть правит этой землёй, а Серебряный Рассвет держится у Часовни Последней Надежды." },
    [267] = { enUS = "Rolling hills between Alliance and Horde. Southshore and Tarren Mill stand close enough to see each other's banners.",
              ruRU = "Холмы между Альянсом и Ордой. Южнобережье и Мельница Таррен стоят так близко, что видят знамёна друг друга." },
    [1497] = { enUS = "The capital of the Forsaken, built in the crypts beneath the ruined throne of Lordaeron. Green light and quiet footsteps fill its halls.",
               ruRU = "Столица Отрёкшихся в склепах под разрушенным троном Лордерона. Его залы полны зелёного света и тихих шагов." },
    [1519] = { enUS = "The proud capital of the human kingdom. White walls, canals and the Cathedral of Light welcome heroes of the Alliance.",
               ruRU = "Гордая столица королевства людей. Белые стены, каналы и Собор Света встречают героев Альянса." },
    [1537] = { enUS = "The great dwarven city carved into the mountain. The Great Forge never cools, and the gnomes of Tinker Town are always busy.",
               ruRU = "Великий город дворфов, высеченный в горе. Великая Кузня никогда не остывает, а гномы Города Механиков всегда заняты." },
    [16756] = { enUS = "Behind the Greymane Wall lies a kingdom that closed its gates to the world. Fog, rain and the curse of the worgen remain among the ruins.",
                ruRU = "За стеной Седогрива лежит королевство, закрывшее ворота от мира. Среди руин остались туман, дождь и проклятие воргенов." },

    -- Kalimdor
    [14] = { enUS = "Red earth and rocky shores, the homeland of the Horde in Kalimdor. Orc and troll heroes begin their journey in the Valley of Trials.",
             ruRU = "Красная земля и каменистые берега, родина Орды в Калимдоре. Герои-орки и тролли начинают свой путь в Долине Испытаний." },
    [15] = { enUS = "A vast marsh on the eastern coast. Theramore stands on its island, and the black dragon Onyxia waits in her lair.",
             ruRU = "Огромное болото на восточном побережье. Терамор стоит на своём острове, а чёрная драконица Ониксия ждёт в логове." },
    [16] = { enUS = "A coast of ancient elven ruins under a strange sky. Naga and satyrs walk where the Highborne once lived, and the sea still remembers the fall of their city.",
             ruRU = "Побережье древних эльфийских руин под странным небом. Наги и сатиры ходят там, где когда-то жили высокорождённые, а море всё ещё помнит падение их города." },
    [17] = { enUS = "Endless dry savanna between Orgrimmar and the south. The Crossroads stands at its heart, and the road always seems longer than it looks.",
             ruRU = "Бескрайняя сухая саванна между Оргриммаром и югом. В её сердце стоит Перекрёсток, а дорога всегда кажется длиннее, чем выглядит." },
    [141] = { enUS = "The World Tree of the night elves. Under its glowing leaves young druids and sentinels learn to protect nature.",
              ruRU = "Мировое древо ночных эльфов. Под его светящимися листьями юные друиды и часовые учатся защищать природу." },
    [148] = { enUS = "A long, moonlit coast of the night elves. Auberdine watches the sea, and old ruins hint at a darker past.",
              ruRU = "Длинное, залитое луной побережье ночных эльфов. Аубердин смотрит на море, а старые руины напоминают о тёмном прошлом." },
    [215] = { enUS = "Golden plains under a wide sky, the homeland of the tauren. Kodo herds graze near Bloodhoof Village, and the wind carries the voice of the Earth Mother.",
              ruRU = "Золотые равнины под широким небом, родина тауренов. У деревни Кровавого Копыта пасутся стада кодо, а ветер несёт голос Матери-Земли." },
    [331] = { enUS = "An ancient forest guarded by the night elves. Orc woodcutters and furbolgs fight over every tree, and the forest remembers.",
              ruRU = "Древний лес под защитой ночных эльфов. Орки-лесорубы и фурболги спорят за каждое дерево, а лес всё помнит." },
    [357] = { enUS = "Tall forests and wild coasts in the south-west. The ruins of Dire Maul hide ogres, demons and forgotten elven magic.",
              ruRU = "Высокие леса и дикие берега на юго-западе. Руины Забытого Города скрывают огров, демонов и забытую магию эльфов." },
    [361] = { enUS = "A forest corrupted by demonic magic. Satyrs lurk in the poisoned groves, and the Cenarion Circle tries to heal the land.",
              ruRU = "Лес, осквернённый демонической магией. В отравленных рощах прячутся сатиры, а Круг Кенария пытается исцелить землю." },
    [400] = { enUS = "Tall stone pillars rise from a deep canyon. Centaurs ride below, and on the salt flats in the east goblins hold their races.",
              ruRU = "Высокие каменные столбы поднимаются из глубокого каньона. Внизу скачут кентавры, а на соляных равнинах на востоке гоблины устраивают гонки." },
    [405] = { enUS = "A grey, dying land of bones and dust. Centaur clans wage war, and the shadow of the demigod Zaetar lies over Maraudon.",
              ruRU = "Серая, умирающая земля костей и пыли. Кланы кентавров воюют между собой, а над Мародоном лежит тень полубога Зайтара." },
    [406] = { enUS = "High peaks and burned forests. Venture Co. goblins cut and dig without mercy, while druids and the Horde try to stop them.",
              ruRU = "Высокие пики и сожжённые леса. Гоблины Торговой компании рубят и копают без жалости, а друиды и Орда пытаются их остановить." },
    [440] = { enUS = "A great desert with a goblin town at its edge. Gadgetzan keeps order, while the Caverns of Time hide beneath the dunes.",
              ruRU = "Огромная пустыня с гоблинским городом на краю. Прибамбасск следит за порядком, а под дюнами скрываются Пещеры Времени." },
    [490] = { enUS = "A deep crater untouched by time. Dinosaurs roam its jungles, and strange crystals pulse with ancient power.",
              ruRU = "Глубокий кратер, нетронутый временем. В его джунглях бродят динозавры, а странные кристаллы пульсируют древней силой." },
    [493] = { enUS = "A peaceful glade sacred to the druids. Nighthaven rests by a quiet lake, and no one may raise a weapon here in anger.",
              ruRU = "Мирная поляна, священная для друидов. Ночная Гавань стоит у тихого озера, и здесь никто не поднимет оружия в гневе." },
    [616] = { enUS = "The sacred mountain of the night elves, crowned by the World Tree Nordrassil. Few travelers ever reach its slopes.",
              ruRU = "Священная гора ночных эльфов, увенчанная Мировым древом Нордрассил. Немногие путники добираются до её склонов." },
    [618] = { enUS = "A land of snow and silence in the far north. Everlook's goblins trade with all, and frostsabers hunt among the frozen trees.",
              ruRU = "Край снега и тишины на крайнем севере. Гоблины Круговзора торгуют со всеми, а ледопарды охотятся среди замёрзших деревьев." },
    [1377] = { enUS = "A desert at the edge of the world, full of insect hives. The silithid stir beneath the sand, and Ahn'Qiraj waits behind its wall.",
               ruRU = "Пустыня на краю мира, полная ульев насекомых. Под песком шевелятся силитиды, а за своей стеной ждёт Ан'Кираж." },
    [1637] = { enUS = "The red-walled capital of the Horde, built by Thrall in Durotar. Warriors, shamans and traders fill its streets.",
               ruRU = "Столица Орды с красными стенами, построенная Траллом в Дуротаре. Его улицы наполняют воины, шаманы и торговцы." },
    [1638] = { enUS = "The tauren capital atop high mesas, joined by rope bridges. The wind blows freely, and the elders keep the old ways.",
               ruRU = "Столица тауренов на высоких плато, связанных верёвочными мостами. Здесь свободно гуляет ветер, а старейшины хранят древние обычаи." },
    [1657] = { enUS = "The night elf capital in the branches of Teldrassil. Moonlight falls through the leaves on the Temple of the Moon.",
               ruRU = "Столица ночных эльфов в ветвях Тельдрассила. Лунный свет падает сквозь листву на Храм Луны." },
}

-- Story of a catalog area in the active language, or nil.
function Stories.Get(area)
    local t = area and Stories.TEXT[area]
    if not t then
        return nil
    end
    return t[ns.activeLocaleCode] or t.enUS
end
