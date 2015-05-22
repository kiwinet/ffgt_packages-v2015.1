local cbi = require "luci.cbi"
local uci = luci.model.uci.cursor()
local site = require 'gluon.site_config'
local fs = require "nixio.fs"

local sites = {}
local M = {}

function M.section(form)
    local lat = uci:get_first("gluon-node-info", 'location', "latitude")
    local lon = uci:get_first("gluon-node-info", 'location', "longitude")
    if not lat then lat=0 end
    if not lon then lon=0 end
    if ((lat == 0) or (lat == 51)) and ((lon == 0) or (lon == 9)) then
	    local s = form:section(cbi.SimpleSection, nil, [[
	    Geo-Lokalisierung schlug fehl :( Hier hast Du die Möglichkeit,
	    die Community, mit der sich Dein Knoten verbindet, auszuwählen.
	    Bitte denke daran, dass Dein Router sich dann nur mit dem Netz
	    der ausgewählten Community verbindet und ggf. lokales Meshing nicht
	    funktioniert bei falscher Auswahl. Vorzugsweise schließt Du
	    Deinen Freifunk-Knoten jetzt per gelbem Port an Deinen Internet-
	    Router an und startest noch mal von vorn.
	    ]])
	
    	uci:foreach('siteselect', 'site',
    	function(s)
    		table.insert(sites, s['.name'])
    	end
    	)
	
	    local o = s:option(cbi.ListValue, "community", "Community")
    	o.rmempty = false
	    o.optional = false

        local unlocode = uci:get_first("gluon-node-info", "location", "locode")
	    if uci:get_first("gluon-setup-mode", "setup_mode", "configured") == "0" then
	    	o:value(unlocode, uci:get_first('siteselect', unlocode, 'sitename'))
	    else
		    o:value(site.site_code, site.site_name)
	    end

	    for index, site in ipairs(sites) do
	    	o:value(site, uci:get('siteselect', site, 'sitename'))
        end
    else
        local s = form:section(cbi.SimpleSection, nil, [[Geo-Lokalisierung erfolgreich.]])
        local unlocode = uci:get_first("gluon-node-info", "location", "locode")
        local o = s:option(cbi.DummyValue, "community", "Community")
    	o.rmempty = false
        o.optional = false
        o.value = unlocode
        -- FIXME! Why isn't this working below? It works with cbi.Value or cbi.ListValue,
        -- but with cbi.DummyValue I get:
        -- /lib/gluon/config-mode/wizard//0200-site-select.lua:66: bad argument #2 to 'get' (string expected, got nil)
        -- (with line 66: local secret = uci:get_first('siteselect', data.community, 'secret'))
    end
end

function M.handle(data)
    if data.community then
        if data.community ~= site.site_code then
            uci:set('siteselect', site.site_code, "secret", uci:get('fastd', 'mesh_vpn', 'secret'))
            uci:save('siteselect')
            uci:commit('siteselect')

            -- Deleting this unconditionally would leave the node without a secret in case the
            -- check fails later on. Moving the delete down into the if-clauses.
            -- -- uci:delete('fastd', 'mesh_vpn', 'secret')

            local secret = uci:get_first('siteselect', data.community, 'secret')

            if not secret or not secret:match(("%x"):rep(64)) then
                uci:delete('siteselect', data.community, 'secret')
            else
                uci:delete('fastd', 'mesh_vpn', 'secret')
                uci:set('fastd', 'mesh_vpn', "secret", secret)
            end

            uci:save('fastd')
            uci:commit('fastd')

            -- We need to store the selection somewhere. To make this simple,
            -- put it into gluon-node-info:location.siteselect ...
            uci:delete('gluon-node-info', 'location', 'siteselect')
            uci:set('gluon-node-info', 'location', 'siteselect', data.community)
            uci:save('gluon-node-info')
            uci:commit('gluon-node-info')

            fs.copy(uci:get('siteselect', data.community , 'path'), '/lib/gluon/site.conf')
            os.execute('sh "/lib/gluon/site-upgrade"')
        end
    else
        -- The UN/LOCODE is the relevant information. No user servicable parts in the UI ;)
        local unlocode = uci:get_first("gluon-node-info", "location", "locode")
        local current = uci:get_first('gluon-node-info', 'location', 'siteselect')

        local secret = uci:get_first('siteselect', uncode, 'secret')

        if not secret or not secret:match(("%x"):rep(64)) then
            uci:delete('siteselect', uncode, 'secret')
            uci:save('siteselect')
            uci:commit('siteselect')
        else
            uci:delete('fastd', 'mesh_vpn', 'secret')
            uci:set('fastd', 'mesh_vpn', "secret", secret)
            uci:save('fastd')
            uci:commit('fastd')
        end

        -- We need to store the selection somewhere. To make this simple,
        -- put it into gluon-node-info:location.siteselect ...
        uci:delete('gluon-node-info', 'location', 'siteselect')
        uci:set('gluon-node-info', 'location', 'siteselect', unlocode)
        uci:save('gluon-node-info')
        uci:commit('gluon-node-info')

        fs.copy(uci:get('siteselect', unlocode, 'path'), '/lib/gluon/site.conf')
        os.execute('sh "/lib/gluon/site-upgrade"')
    end
end

return M