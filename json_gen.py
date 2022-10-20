import os
import json

shapesetFolders = [
    "C:/Program Files (x86)/Steam/steamapps/common/Scrap Mechanic/Data/Objects/Database/ShapeSets/",
    "C:/Program Files (x86)/Steam/steamapps/common/Scrap Mechanic/Survival/Objects/Database/ShapeSets/"
]
modShapeSet = "C:/Users/claas/AppData/Roaming/Axolot Games/Scrap Mechanic/User/User_76561198207895823/Mods/Bedwars Custom Game/Objects/Database/ShapeSets/generated.shapeset"

recipeUuuids = []

extraItems = "C:/Users/claas/AppData/Roaming/Axolot Games/Scrap Mechanic/User/User_76561198207895823/Mods/Bedwars Custom Game/extra_items.json"
with open(extraItems) as f:
    data = json.loads(f.read())
    recipeUuuids = data
    

bedwarsRecipes = "C:/Users/claas/AppData/Roaming/Axolot Games/Scrap Mechanic/User/User_76561198207895823/Mods/Bedwars Custom Game/bedwars.json"
with open(bedwarsRecipes) as f:
    data = json.loads(f.read())
    for recipe in data:
        recipeUuuids.append(recipe["itemId"])

OldShapesetFolders = [
    "C:/Program Files (x86)/Steam/steamapps/workshop/content/387990/2429097726/Scrap Mechanic/Data/Objects/Database/ShapeSets/",
    "C:/Program Files (x86)/Steam/steamapps/workshop/content/387990/2429097726/Scrap Mechanic/Survival/Objects/Database/ShapeSets/"
]
destroyTimes = {}
stackSizes = {}
for folder in OldShapesetFolders:
    for file in os.listdir(folder):
        #check if file is dir, but not neccessary
        with open(folder + file) as f:
            data = json.loads(f.read())

            for part in data["partList"]:
                if "destroyTime" in part:
                    destroyTimes[part["uuid"]] = part["destroyTime"]
                
                if "stackSize" in part:
                    stackSizes[part["uuid"]] = part["stackSize"]




newShapeSets = { "blockList": [], "partList": []}

for folder in shapesetFolders:
    for file in os.listdir(folder):
        #check if file is dir, but not neccessary
        with open(folder + file) as f:
            data = json.loads(f.read())

            if "blockList" in data:
                for block in data["blockList"]:
                    if not block["uuid"] in recipeUuuids:
                        if not "restrictions" in block:
                            block["restrictions"] = {"erasable": False}
                        else: #not "ersable" in part["restrictions"]:
                            block["restrictions"]["erasable"] = False

                    newShapeSets["blockList"].append(block)

            if "partList" in data:
                for part in data["partList"]:
                    if part["uuid"] in destroyTimes:
                        part["destroyTime"] = destroyTimes[part["uuid"]]

                    if part["uuid"] in stackSizes:
                        part["stackSize"] = stackSizes[part["uuid"]]

                    if not part["uuid"] in recipeUuuids:
                        if not "restrictions" in part:
                            part["restrictions"] = {"erasable": False}
                        else: #not "ersable" in part["restrictions"]:
                            part["restrictions"]["erasable"] = False

                    newShapeSets["partList"].append(part)

with open(modShapeSet, "w") as f:
    f.write(json.dumps(newShapeSets, indent=4))
    print("json generated")