-- Mining for WoW Forever, from Wowhead (wowhead.com/forever/skill=186). Made by tools\profession-data\build.py:
-- don't change it here, run that again.
local _, ns = ...

ns.AddProfession(186, "Mining", {
-- spell, name, item made, how many, learned at, yellow at, grey at, how (T trainer, V vendor's plan, D dropped
-- plan, Q quest, "" known or unknown), its price (trainer or vendor), specialization, plan item, then item, n ...
-- and, where it needs tools, tools = { { the tool, any other item that does for it ... }, ... }
{2657,"Smelt Copper",2840,1,1,25,70,"",0,0,0,2770,1},
{1230161,"Lodestone",279960,1,20,20,20,"T",105,0,0,2835,1,2840,1},
{2659,"Smelt Bronze",2841,2,65,65,115,"T",200,0,0,2840,1,3576,1},
{3304,"Smelt Tin",3576,1,65,55,75,"T",50,0,0,2771,1},
{2658,"Smelt Silver",2842,1,75,100,125,"T",200,0,0,2775,1},
{3307,"Smelt Iron",3575,1,125,130,140,"T",500,0,0,2772,1},
{1262975,"Rock Garden",279948,1,140,140,140,"D",0,0,0,2838,2,2772,1,2842,1},
{3308,"Smelt Gold",3577,1,155,170,185,"T",2500,0,0,2776,1},
{3569,"Smelt Steel",3859,1,165,165,165,"T",2500,0,0,3575,1,3857,1},
{10097,"Smelt Mithril",3860,1,175,175,175,"T",5000,0,0,3858,1},
{10098,"Smelt Truesilver",6037,1,230,230,230,"T",10526,0,0,7911,1},
{14891,"Smelt Dark Iron",11371,1,230,230,230,"",0,0,0,11370,8},
{16153,"Smelt Thorium",12359,1,250,250,250,"T",20000,0,0,10620,1},
{1249637,"Smelt Azerothium",249726,1,275,275,275,"T",52631,0,0,249426,2,3857,1},
{1263071,"Molten Foundry",279952,1,300,300,300,"D",0,0,0,12359,5,12365,2,6037,1},
{1306126,"Smelt Heavy Thorium",251291,1,300,300,315,"T",52631,0,0,248815,1},
{22967,"Smelt Elementium",17771,1,310,310,320,"",0,0,0,18562,1,12360,10,17010,1,18567,3},
}, {
-- [item] = { name, quality, a vendor's price (0: not from a vendor), a vendor pays, 2 weapon / 4 armour,
-- its kind (mail 3, plate 4, sword 7...), slot, level needed, item level }
[2770]={"Copper Ore",1,0,5,0,0,0,0,0},
[2771]={"Tin Ore",1,0,25,0,0,0,0,0},
[2772]={"Iron Ore",1,0,150,0,0,0,0,0},
[2775]={"Silver Ore",2,0,75,0,0,0,0,0},
[2776]={"Gold Ore",2,0,500,0,0,0,0,0},
[2835]={"Rough Stone",1,0,2,0,0,0,0,0},
[2838]={"Heavy Stone",1,0,60,0,0,0,0,0},
[2840]={"Copper Bar",1,0,10,0,0,0,0,0},
[2841]={"Bronze Bar",1,0,50,0,0,0,0,0},
[2842]={"Silver Bar",2,0,100,0,0,0,10,0},
[3575]={"Iron Bar",1,0,200,0,0,0,0,0},
[3576]={"Tin Bar",1,0,35,0,0,0,15,0},
[3577]={"Gold Bar",2,0,600,0,0,0,0,0},
[3857]={"Coal",1,500,125,0,0,0,0,0},
[3858]={"Mithril Ore",1,0,250,0,0,0,0,0},
[3859]={"Steel Bar",1,0,60,0,0,0,0,0},
[3860]={"Mithril Bar",1,0,400,0,0,0,0,0},
[6037]={"Truesilver Bar",2,0,1250,0,0,0,0,0},
[7911]={"Truesilver Ore",2,0,500,0,0,0,0,0},
[10620]={"Thorium Ore",1,0,250,0,0,0,0,0},
[11370]={"Dark Iron Ore",1,0,500,0,0,0,0,0},
[11371]={"Dark Iron Bar",1,0,600,0,0,0,0,0},
[12359]={"Thorium Bar",1,0,600,0,0,0,0,0},
[12360]={"Arcanite Bar",2,0,5000,0,0,0,0,0},
[12365]={"Dense Stone",1,0,250,0,0,0,0,0},
[17010]={"Fiery Core",3,0,2000,0,0,0,0,0},
[17771]={"Elementium Bar",5,0,100000,0,0,0,0,0},
[18562]={"Elementium Ore",4,0,100000,0,0,0,0,0},
[18567]={"Elemental Flux",1,150000,37500,0,0,0,0,0},
[248815]={"Heavy Thorium Ore",1,0,375,0,0,0,0,0},
[249426]={"Pitchblende",2,0,375,0,0,0,0,0},
[249726]={"Azerothium Bar",2,0,3000,0,0,0,0,0},
[251291]={"Heavy Thorium Bar",2,0,1500,0,0,0,0,0},
[279948]={"Rock Garden",1,0,0,0,0,0,0,0},
[279952]={"Molten Foundry",1,0,0,0,0,0,0,0},
[279960]={"Lodestone",1,0,0,0,0,0,0,0},
}, {
-- [plan] = { faction needed, standing needed (4 neutral ... 8 exalted), vendors { name, zone, who they
-- sell to (1 Alliance, 2 Horde, 3 both, 0 unknown), 1 if only a few in stock, ... }, quest, dropped by }
})
