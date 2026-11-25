extends RefCounted

# Official Red Alert structure definitions (cost, build_time sec, hp, power (+prod/-use), w_tiles, h_tiles, prereq)
const STRUCTURES := {
	"powr": { "name": "Power Plant", "cost": 300, "time": 4.0, "hp": 600.0, "power": 100, "w": 2, "h": 2, "prereq": ["fact"] },
	"apwr": { "name": "Adv. Power", "cost": 500, "time": 6.0, "hp": 900.0, "power": 200, "w": 3, "h": 2, "prereq": ["powr"] },
	"proc": { "name": "Ore Refinery", "cost": 1400, "time": 8.0, "hp": 1100.0, "power": -30, "w": 3, "h": 3, "prereq": ["powr"] },
	"tent": { "name": "Barracks", "cost": 400, "time": 4.5, "hp": 800.0, "power": -20, "w": 2, "h": 2, "prereq": ["powr"], "faction": "allies" },
	"barr": { "name": "Barracks", "cost": 400, "time": 4.5, "hp": 800.0, "power": -20, "w": 2, "h": 2, "prereq": ["powr"], "faction": "soviet" },
	"weap": { "name": "War Factory", "cost": 1500, "time": 8.0, "hp": 1400.0, "power": -30, "w": 3, "h": 2, "prereq": ["proc"] },
	"dome": { "name": "Radar Dome", "cost": 1000, "time": 6.5, "hp": 900.0, "power": -40, "w": 2, "h": 2, "prereq": ["proc"] },
	"hpad": { "name": "Helipad", "cost": 1200, "time": 7.0, "hp": 850.0, "power": -10, "w": 2, "h": 2, "prereq": ["weap"] },
	"afld": { "name": "Airfield", "cost": 1000, "time": 6.5, "hp": 950.0, "power": -20, "w": 3, "h": 2, "prereq": ["dome"] },
	"pbox": { "name": "Pillbox", "cost": 400, "time": 4.0, "hp": 500.0, "power": 0, "w": 1, "h": 1, "prereq": ["tent", "barr"], "defense": true, "range": 6.0, "dmg": 16.0, "rate": 0.45, "weapon": "bullet" },
	"gun":  { "name": "Turret", "cost": 600, "time": 5.0, "hp": 650.0, "power": -15, "w": 1, "h": 1, "prereq": ["tent", "barr"], "faction": "allies", "defense": true, "range": 7.0, "dmg": 48.0, "rate": 1.6, "weapon": "shell" },
	"tsla": { "name": "Tesla Coil", "cost": 1200, "time": 7.5, "hp": 850.0, "power": -75, "w": 1, "h": 1, "prereq": ["weap"], "faction": "soviet", "defense": true, "range": 8.5, "dmg": 115.0, "rate": 2.4, "weapon": "tesla" },
	"sam":  { "name": "SAM Site", "cost": 700, "time": 5.5, "hp": 550.0, "power": -20, "w": 2, "h": 1, "prereq": ["dome"], "defense": true, "range": 9.0, "dmg": 55.0, "rate": 1.4, "weapon": "missile", "aa_only": true },
	"pdox": { "name": "Chronosphere","cost": 2200, "time": 10.0, "hp": 900.0, "power": -120, "w": 2, "h": 2, "prereq": ["dome"], "faction": "allies" },
	"iron": { "name": "Iron Curtain","cost": 2200, "time": 10.0, "hp": 900.0, "power": -120, "w": 2, "h": 2, "prereq": ["dome"], "faction": "soviet" },
	"mslo": { "name": "Missile Silo","cost": 2500, "time": 11.0, "hp": 1000.0, "power": -100, "w": 2, "h": 1, "prereq": ["dome"] },
}

const RTS_UNITS := {
	"infantry":  { "name": "Rifleman", "cost": 100, "time": 2.0, "prereq": ["tent", "barr"], "cameo": "e1" },
	"rocket":    { "name": "Rocket",   "cost": 300, "time": 3.0, "prereq": ["tent", "barr"], "cameo": "e3" },
	"engineer":  { "name": "Engineer", "cost": 500, "time": 3.5, "prereq": ["tent", "barr"], "cameo": "e6" },
	"harv":      { "name": "Harvester","cost": 1100,"time": 6.5, "prereq": ["weap", "proc"], "cameo": "harv" },
	"tank":      { "name": "Tank",     "cost": 700, "time": 4.5, "prereq": ["weap"], "cameo_allies": "2tnk", "cameo_soviet": "3tnk" },
	"heavy":     { "name": "Mammoth",  "cost": 1400,"time": 7.5, "prereq": ["weap", "dome"], "cameo": "4tnk" },
	"artillery": { "name": "Artillery","cost": 650, "time": 5.0, "prereq": ["weap"], "cameo_allies": "arty", "cameo_soviet": "v2rl" },
	"heli":      { "name": "Gunship",  "cost": 1100,"time": 6.5, "prereq": ["hpad"], "cameo_allies": "heli", "cameo_soviet": "hind" },
	"plane":     { "name": "Fighter",  "cost": 1300,"time": 7.0, "prereq": ["afld"], "cameo_allies": "yak", "cameo_soviet": "mig" },
	"mcv":       { "name": "MCV",      "cost": 1800,"time": 9.0, "prereq": ["weap", "dome"], "cameo": "mcv" },
}

static func get_structure_order(faction: String) -> Array[String]:
	if faction == "soviet":
		return ["powr", "apwr", "proc", "barr", "weap", "dome", "hpad", "afld", "pbox", "tsla", "sam", "iron", "mslo"]
	return ["powr", "apwr", "proc", "tent", "weap", "dome", "hpad", "afld", "pbox", "gun", "sam", "pdox", "mslo"]

static func get_unit_order() -> Array[String]:
	return ["infantry", "rocket", "engineer", "harv", "tank", "heavy", "artillery", "heli", "plane", "mcv"]

static func get_unit_cameo(key: String, faction: String) -> String:
	var d: Dictionary = RTS_UNITS.get(key, {})
	if d.has("cameo"):
		return String(d["cameo"])
	return String(d.get("cameo_" + faction, "e1"))
