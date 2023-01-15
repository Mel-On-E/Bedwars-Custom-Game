import os
import json

shapesetFolders = [
    "C:/Program Files (x86)/Steam/steamapps/common/Scrap Mechanic/Data/Objects/Database/ShapeSets/",
    "C:/Program Files (x86)/Steam/steamapps/common/Scrap Mechanic/Survival/Objects/Database/ShapeSets/"
]
modShapeSet = "/Objects/Database/ShapeSets/generated.shapeset"

recipeUuuids = []

extraItems = "/extra_items.json"
with open(os.getcwd() + extraItems) as f:
    data = json.loads(f.read())
    recipeUuuids = data


bedwarsRecipes = "/bedwars.json"
with open(os.getcwd() + bedwarsRecipes) as f:
    data = json.loads(f.read())
    for recipe in data:
        recipeUuuids.append(recipe["itemId"])

oldCreativeItems = []
with open(os.getcwd() + "/creative_interactives.json") as f:
    data = json.loads(f.read())
    oldCreativeItems = data

upgradeableItems = []
with open("C:/Program Files (x86)/Steam/steamapps/common/Scrap Mechanic/Survival/Objects/Database/ShapeSets/" + "/interactive_upgradeable.json") as f:
    data = json.loads(f.read())
    for item in data["partList"]:
        upgradeableItems.append(item["uuid"])


OldShapesetFolders = [
    "C:/Program Files (x86)/Steam/steamapps/workshop/content/387990/2429097726/Scrap Mechanic/Data/Objects/Database/ShapeSets/",
    "C:/Program Files (x86)/Steam/steamapps/workshop/content/387990/2429097726/Scrap Mechanic/Survival/Objects/Database/ShapeSets/"
]
destroyTimes = {}
stackSizes = {}
for folder in OldShapesetFolders:
    for file in os.listdir(folder):
        # check if file is dir, but not neccessary
        with open(folder + file) as f:
            data = json.loads(f.read())

            for part in data["partList"]:
                if "destroyTime" in part:
                    destroyTimes[part["uuid"]] = part["destroyTime"]

                if "stackSize" in part:
                    stackSizes[part["uuid"]] = part["stackSize"]


def restrict_item(obj):
    if not "restrictions" in obj:
        obj["restrictions"] = {"erasable": False, "destructable": False}
    else:
        obj["restrictions"]["erasable"] = False
        obj["restrictions"]["destructable"] = False


newShapeSets = {"blockList": [], "partList": []}

for folder in shapesetFolders:
    for file in os.listdir(folder):
        # check if file is dir, but not neccessary
        with open(folder + file) as f:
            data = json.loads(f.read())

            if "blockList" in data:
                for block in data["blockList"]:
                    if not block["uuid"] in recipeUuuids:
                        restrict_item(block)
                    else:
                        block["showInInventory"] = False

                    if block["uuid"] in oldCreativeItems:
                        # janky check for framework block
                        block["showInInventory"] = True

                    newShapeSets["blockList"].append(block)

            if "partList" in data:
                for part in data["partList"]:
                    if part["uuid"] in destroyTimes:
                        part["destroyTime"] = destroyTimes[part["uuid"]]

                    if part["uuid"] in stackSizes:
                        part["stackSize"] = stackSizes[part["uuid"]]

                    if part["uuid"] in upgradeableItems:
                        part["showInInventory"] = False

                    if not part["uuid"] in recipeUuuids:
                        restrict_item(part)
                    else:
                        part["showInInventory"] = False

                    if part["uuid"] in oldCreativeItems:
                        part["showInInventory"] = True

                        if not "restrictions" in part:
                            part["restrictions"] = {}

                        part["restrictions"]["erasable"] = False
                        part["restrictions"]["connectable"] = False
                        part["restrictions"]["destructable"] = False

                    newShapeSets["partList"].append(part)

with open(os.getcwd() + modShapeSet, "w") as f:
    f.write(json.dumps(newShapeSets, indent=4))
    print("json generated")
