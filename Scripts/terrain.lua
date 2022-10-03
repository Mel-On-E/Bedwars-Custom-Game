dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )

function Init()
	print( "Init terrain" )
end

function Create( xMin, xMax, yMin, yMax, seed, data )

	g_uuidToPath = {}
	g_cellData = {
		bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax },
		seed = seed,
		-- Per Cell
		uid = {},
		xOffset = {},
		yOffset = {},
		rotation = {}
	}

	for cellY = yMin, yMax do
		g_cellData.uid[cellY] = {}
		g_cellData.xOffset[cellY] = {}
		g_cellData.yOffset[cellY] = {}
		g_cellData.rotation[cellY] = {}

		for cellX = xMin, xMax do
			g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
			g_cellData.xOffset[cellY][cellX] = 0
			g_cellData.yOffset[cellY][cellX] = 0
			g_cellData.rotation[cellY][cellX] = 0
		end
	end

	local jWorld = sm.json.open( "$CONTENT_DATA/Terrain/Worlds/example.world")
	for _, cell in pairs( jWorld.cellData ) do
		if cell.path ~= "" then
			local uid = sm.terrainTile.getTileUuid( cell.path )
			g_cellData.uid[cell.y][cell.x] = uid
			g_cellData.xOffset[cell.y][cell.x] = cell.offsetX
			g_cellData.yOffset[cell.y][cell.x] = cell.offsetY
			g_cellData.rotation[cell.y][cell.x] = cell.rotation

			g_uuidToPath[tostring(uid)] = cell.path
		end
	end

	sm.terrainData.save( { g_uuidToPath, g_cellData } )
end

function Load()
	if sm.terrainData.exists() then
		local data = sm.terrainData.load()
		g_uuidToPath = data[1]
		g_cellData = data[2]
		return true
	end
	return false
end

function GetTilePath( uid )
	if not uid:isNil() then
		return g_uuidToPath[tostring(uid)]
	end
	return ""
end

function GetCellTileUidAndOffset( cellX, cellY )
	if InsideCellBounds( cellX, cellY ) then
		return	g_cellData.uid[cellY][cellX],
				g_cellData.xOffset[cellY][cellX],
				g_cellData.yOffset[cellY][cellX]
	end
	return sm.uuid.getNil(), 0, 0
end

function GetTileLoadParamsFromWorldPos( x, y, lod )
	local cellX, cellY = GetCell( x, y )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE, y - cellY * CELL_SIZE )
	if lod then
		return  uid, tileCellOffsetX, tileCellOffsetY, lod, rx, ry
	else
		return  uid, tileCellOffsetX, tileCellOffsetY, rx, ry
	end
end

function GetTileLoadParamsFromCellPos( cellX, cellY, lod )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if lod then
		return  uid, tileCellOffsetX, tileCellOffsetY, lod
	else
		return  uid, tileCellOffsetX, tileCellOffsetY
	end
end

function GetHeightAt( x, y, lod )
	return sm.terrainTile.getHeightAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
end

function GetColorAt( x, y, lod )
	return sm.terrainTile.getColorAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
end

function GetMaterialAt( x, y, lod )
	return sm.terrainTile.getMaterialAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
end

function GetClutterIdxAt( x, y )
	return sm.terrainTile.getClutterIdxAt( GetTileLoadParamsFromWorldPos( x, y ) )
end

function GetAssetsForCell( cellX, cellY, lod )
	local assets = sm.terrainTile.getAssetsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, asset in ipairs( assets ) do
		local rx, ry = RotateLocal( cellX, cellY, asset.pos.x, asset.pos.y )
		asset.pos = sm.vec3.new( rx, ry, asset.pos.z )
		asset.rot = GetRotationQuat( cellX, cellY ) * asset.rot
	end
	return assets
end

function GetNodesForCell( cellX, cellY )
	local nodes = sm.terrainTile.getNodesForCell( GetTileLoadParamsFromCellPos( cellX, cellY ) )
	for _, node in ipairs( nodes ) do
		local rx, ry = RotateLocal( cellX, cellY, node.pos.x, node.pos.y )
		node.pos = sm.vec3.new( rx, ry, node.pos.z )
		node.rot = GetRotationQuat( cellX, cellY ) * node.rot
	end
	return nodes
end

function GetCreationsForCell( cellX, cellY )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local cellCreations = sm.terrainTile.getCreationsForCell( uid, tileCellOffsetX, tileCellOffsetY )
		for i,creation in ipairs( cellCreations ) do
			local rx, ry = RotateLocal( cellX, cellY, creation.pos.x, creation.pos.y )

			creation.pos = sm.vec3.new( rx, ry, creation.pos.z )
			creation.rot = GetRotationQuat( cellX, cellY ) * creation.rot
		end

		return cellCreations
	end

	return {}
end

function GetHarvestablesForCell( cellX, cellY, lod )
	local harvestables = sm.terrainTile.getHarvestablesForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, harvestable in ipairs( harvestables ) do
		local rx, ry = RotateLocal( cellX, cellY, harvestable.pos.x, harvestable.pos.y )
		harvestable.pos = sm.vec3.new( rx, ry, harvestable.pos.z )
		harvestable.rot = GetRotationQuat( cellX, cellY ) * harvestable.rot
	end
	return harvestables
end

function GetKinematicsForCell( cellX, cellY, lod )
	local kinematics = sm.terrainTile.getKinematicsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, kinematic in ipairs( kinematics ) do
		local rx, ry = RotateLocal( cellX, cellY, kinematic.pos.x, kinematic.pos.y )
		kinematic.pos = sm.vec3.new( rx, ry, kinematic.pos.z )
		kinematic.rot = GetRotationQuat( cellX, cellY ) * kinematic.rot
	end
	return kinematics
end

function GetDecalsForCell( cellX, cellY, lod )
	local decals = sm.terrainTile.getDecalsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	for _, decal in ipairs( decals ) do
		local rx, ry = RotateLocal( cellX, cellY, decal.pos.x, decal.pos.y )
		decal.pos = sm.vec3.new( rx, ry, decal.pos.z )
		decal.rot = GetRotationQuat( cellX, cellY ) * decal.rot
	end
	return decals
end