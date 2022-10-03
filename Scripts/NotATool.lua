NotATool = class()

function NotATool.client_onEquip( self ) 
    sm.tool.forceTool( nil )
end

function NotATool.client_onUnequip( self ) end