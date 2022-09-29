--[[
    Made a little change to this version
    If you like this version, please don't forget to reply at the bottom of gl0ck's post :3
    The code is hard to read, I hope you don't mind, because I'm not that familiar with lua
    Source:
        gl0ck - [RELEASE] Programmer lines ft. terry a davis
        https://gamesense.pub/forums/viewtopic.php?id=36706
]]

local vector = require("vector")
local ffi = require("ffi")

ffi.cdef [[
    typedef struct { 
        float x; 
        float y; 
        float z; 
    } bbvec3_t;
]]

local pClientEntityList = client.create_interface("client_panorama.dll", "VClientEntityList003") or error("invalid interface", 2)
local fnGetClientEntity = vtable_thunk(3, "void*(__thiscall*)(void*, int)")
local fnGetAttachment = vtable_thunk(84, "bool(__thiscall*)(void*, int, bbvec3_t&)")
local fnGetMuzzleAttachmentIndex1stPerson = vtable_thunk(468, "int(__thiscall*)(void*, void*)")
local fnGetMuzzleAttachmentIndex3stPerson = vtable_thunk(469, "int(__thiscall*)(void*)")

local menu = {
    enable = ui.new_checkbox("LUA", "B", "Enable enemy line"),
    select = ui.new_combobox("Lua", "B", "Select target type", {"All enemy", "Ragebot target", "Near crosshair"}),
    color_select = ui.new_combobox("Lua", "B", "Select color type", {"Static", "Random", "RGB"}),
    static_color_text = ui.new_label("LUA", "B", "Static color picker"),
    static_color_picker = ui.new_color_picker("LUA", "B", "static_color_picker_"),
    rgb_time = ui.new_slider("LUA", "B", "RGB update time", 0, 100, 100, true),
    random_time = ui.new_slider("LUA", "B", "Random update time", 0, 100, 100, true)
}

local reference = {
    third_person = { ui.reference('VISUALS', 'Effects', 'Force third person (alive)') },
}

local lib = {
    hsv_to_rgb = function(b,c,d,e)
        local f,g,h;
        local i = math.floor(b*6)
        local j = b * 6 - i;
        local k = d * (1 -c)
        local l = d * (1 -j * c)
        local m = d * (1 -(1 - j) * c)
        i = i % 6;
    
        if i == 0 then 
            f, g, h = d,m,k 
        elseif i == 1 then 
            f, g, h = l, d, k 
        elseif i == 2 then 
            f, g, h = k, d, m 
        elseif i == 3 then 
            f, g, h = k, l, d 
        elseif i == 4 then 
            f, g, h = m, k, d 
        elseif i == 5 then 
            f, g, h = d, k, l 
        end;
    
        return f * 255, g * 255, h * 255, e * 255 
    end,
    
    deg = function(xdelta, ydelta)
        if xdelta == 0 and ydelta == 0 then
            return 0
        end
    
        return math.deg(math.atan2(ydelta, xdelta))
    end,
    
    normalize_yaw = function(yaw)
        while yaw > 180 do
            yaw = yaw - 360
        end
        while yaw < -180 do
            yaw = yaw + 360
        end
        return yaw
    end,

    -- https://gamesense.pub/forums/viewtopic.php?id=31897
    -- Thanks @noneknowsme
    get_attachment_vector = function(world_model)
        local me = entity.get_local_player()
        local wpn = entity.get_player_weapon(me)
    
        local model =
            world_model and 
            entity.get_prop(wpn, 'm_hWeaponWorldModel') or
            entity.get_prop(me, 'm_hViewModel[0]')
    
        if me == nil or wpn == nil then
            return
        end
    
        local active_weapon = fnGetClientEntity(pClientEntityList, wpn)
        local g_model = fnGetClientEntity(pClientEntityList, model)
    
        if active_weapon == nil or g_model == nil then
            return
        end
    
        local attachment_vector = ffi.new("bbvec3_t[1]")
        local att_index = world_model and
            fnGetMuzzleAttachmentIndex3stPerson(active_weapon) or
            fnGetMuzzleAttachmentIndex1stPerson(active_weapon, g_model)
            
        if att_index > 0 then
            if fnGetAttachment(g_model, att_index, attachment_vector[0]) then
                return vector(attachment_vector[0].x, attachment_vector[0].y, attachment_vector[0].z)
            end
        end
    end
}

-- https://gamesense.pub/forums/viewtopic.php?id=39951
-- Thanks @xkeksbyte!
local function get_nearest_enemy(plocal, enemies)
	local lx, ly, lz = client.eye_position()
	local view_x, view_y, roll = client.camera_angles()

	local bestenemy = nil
    local fov = 180
    for i=1, #enemies do
        local cur_x, cur_y, cur_z = entity.get_prop(enemies[i], "m_vecOrigin")
        local cur_fov = math.abs(lib.normalize_yaw(lib.deg(lx - cur_x, ly - cur_y) - view_y + 180))
        if cur_fov < fov then
			fov = cur_fov
			bestenemy = enemies[i]
		end
	end

	return bestenemy
end

local function ui_setting()
    if not ui.is_menu_open() then return end
    ui.set_visible(menu.select, ui.get(menu.enable))
    ui.set_visible(menu.color_select, ui.get(menu.enable))
    ui.set_visible(menu.static_color_text, ui.get(menu.enable) and ui.get(menu.color_select) == "Static")
    ui.set_visible(menu.static_color_picker, ui.get(menu.enable) and ui.get(menu.color_select) == "Static")
    ui.set_visible(menu.random_time, ui.get(menu.enable) and ui.get(menu.color_select) == "Random")
    ui.set_visible(menu.rgb_time, ui.get(menu.enable) and ui.get(menu.color_select) == "RGB")
end

local random_color_cache = {
    r = client.random_int(0, 255),
    g = client.random_int(0, 255),
    b = client.random_int(0, 255),
    a = 255
}
local cache_random_time = globals.realtime()

local function color_function()
    
    local return_color = { r = 255, g = 255, b = 255, a = 255}

    if ui.get(menu.color_select) == "Static" then
        return_color = {
            r = ({ui.get(menu.static_color_picker)})[1],
            g = ({ui.get(menu.static_color_picker)})[2],
            b = ({ui.get(menu.static_color_picker)})[3],
            a = ({ui.get(menu.static_color_picker)})[4]
        }
    elseif ui.get(menu.color_select) ==  "Random" then
        if globals.realtime() - cache_random_time >= ui.get(menu.random_time) / 500 then
            return_color = {
                r = client.random_int(0, 255),
                g = client.random_int(0, 255),
                b = client.random_int(0, 255),
                a = 255
            }
            random_color_cache = return_color
            cache_random_time = globals.realtime()
        else
            return random_color_cache
        end 
    elseif ui.get(menu.color_select) ==  "RGB" then
        local r, g, b = lib.hsv_to_rgb(globals.realtime() * ui.get(menu.rgb_time) / 100, 1, 1, 1)
        return_color = {
            r = r,
            g = g,
            b = b,
            a = 255
        }
    end

    return return_color

end

local function origin_to_screen(origin)
    local origin_type = type(origin)
    if origin_type == "number" then
        local check_origin = vector(entity.get_origin(origin))
        if check_origin == nil or check_origin.y == 0 or check_origin.y == nil or check_origin.z == 0 or check_origin.z == nil then 
            error("Error type")
            return
        end
        local screen_table = vector(renderer.world_to_screen(origin.x, origin.y, origin.z))
        return screen_table
    elseif origin_type == "table" then
        local screen_table = vector(renderer.world_to_screen(origin[1], origin[2], origin[3]))
        return screen_table
    elseif origin_type == "cdata" then
        local screen_table = vector(renderer.world_to_screen(origin.x, origin.y, origin.z))
        return screen_table
    end
end

local function return_player_origin_to_screen(enemies)
    if entity.is_alive(enemies) and not entity.is_dormant(enemies) and entity.is_enemy(enemies) then
        local enemy_origin = vector(entity.hitbox_position(enemies, 2))
        local enemy_origin_to_screen = origin_to_screen(enemy_origin)
        if (enemy_origin_to_screen ~= nil and enemy_origin_to_screen.x ~= nil and enemy_origin_to_screen.y ~= nil) then
            return enemy_origin_to_screen
        end
    end
end

local function local_player_origin()
    local third_person = ui.get(reference.third_person[1]) and ui.get(reference.third_person[2])
    if third_person then
        local local_player = entity.get_local_player()
        local local_player_origin = vector(entity.hitbox_position(local_player, 2))
        local local_player_origin_to_screen = origin_to_screen(local_player_origin)
        return local_player_origin_to_screen
    else
        local muzzle_vec = lib.get_attachment_vector(false)
        if not muzzle_vec then
            local screen = vector(client.screen_size())
            return screen / 2
        end
        local muzzle_pos = vector(renderer.world_to_screen(muzzle_vec:unpack()))
        if not muzzle_vec then
            local screen = vector(client.screen_size())
            return screen / 2
        end
        return muzzle_pos
    end
end

local function paint()

    if not ui.get(menu.enable) then return end

    local local_player = entity.get_local_player()
    if local_player == nil or not entity.is_alive(local_player) then return end

    local enemies = entity.get_players(true)
    if enemies == nil then return end
    
    local color = color_function()
    if color == nil then return end

    local local_player_origin_to_screen = local_player_origin()
    if local_player_origin_to_screen == nil then return end

    if ui.get(menu.select) == "All enemy" then
        for enemy_index, enemy_value in ipairs(enemies) do
            local enemy_origin_to_screen = return_player_origin_to_screen(enemy_value)
            if (enemy_origin_to_screen ~= nil and enemy_origin_to_screen.x ~= nil and enemy_origin_to_screen.y ~= nil and enemy_origin_to_screen.x ~= 0 and enemy_origin_to_screen.y ~= 0) then
                renderer.line(local_player_origin_to_screen.x, local_player_origin_to_screen.y, enemy_origin_to_screen.x, enemy_origin_to_screen.y, color.r, color.g, color.b, color.a)
            end
        end
    elseif ui.get(menu.select) == "Ragebot target" then

        local ragebot_target = client.current_threat();
        if ragebot_target == nil then return end

        local screen_origin = return_player_origin_to_screen(ragebot_target)
        renderer.line(local_player_origin_to_screen.x, local_player_origin_to_screen.y, screen_origin.x, screen_origin.y, color.r, color.g, color.b, color.a)

    elseif ui.get(menu.select) == "Near crosshair" then

        local best_enemy = get_nearest_enemy(entity.get_local_player(), enemies)
        if best_enemy == nil then return; end

        local screen_origin = return_player_origin_to_screen(best_enemy)
        renderer.line(local_player_origin_to_screen.x, local_player_origin_to_screen.y, screen_origin.x, screen_origin.y, color.r, color.g, color.b, color.a)
    end


end

local Callbacks = {
    ["paint_ui"] = ui_setting,
    ["paint"] = paint
}

for key, handle in pairs(Callbacks) do
    client.set_event_callback(key, handle)
end
