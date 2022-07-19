-- User Settings
local os_is_windows = true --change to false if you're using Linux
local lut_style_category = "Fujifilm LUTs|" -- Set to "" if not using categories
local dr_style_category = "Fujifilm DR|"

local apply_crop_styles = false -- Set to true if you want the script to apply the crop styles

--[[ fujifilm_auto_settings-0.3

Apply Fujifilm film simulations, in-camera crop mode, and dynamic range.

Copyright (C) 2022 Bastian Bechtold <bastibe.dev@mailbox.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
--]]

--[[About this Plugin
Automatically applies styles that load Fujifilm film simulation LUTs,
copy crop ratios from the JPG, and correct exposure according to the
chosen dynamic range setting in camera.

Dependencies:
- exiftool (https://www.sno.phy.queensu.ca/~phil/exiftool/)

Based on fujifim_dynamic_range by Dan Torop.

  Film Simulations
  ----------------

Fujifilm cameras are famous for their film simulations, such as Provia
or Velvia or Classic Chrome. Indeed it is my experience that they rely
on these film simulations for accurate colors.

Darktable however does not know about or implement these film
simulations. But they are available to download from Stuart Sowerby as
3DL LUTs. (PNG LUTs are also available, but they show a strange
posterization artifact when loaded in Darktable, which the 3DLs do
not).

In order to use this plugin, you must prepare a number of styles:
* Import the styles found in the "Categorized Styles" folder

These styles should apply the according film simulation in a method of
your choosing.

This plugin checks the image's "Film Mode" exif parameter, and applies
the appropriate style. If no matching style exists, no action is taken
and no harm is done.

  Crop Factor
  -----------

Fujifilm cameras allow in-camera cropping to one of three aspect
ratios: 2:3 (default), 16:9, and 1:1.

This plugin checks the image's "Raw Image Aspect Ratio" exif
parameter, and applies the appropriate style.

To use, prepare another four styles:
- square_crop_portrait
- square_crop_landscape
- sixteen_by_nine_crop_portrait
- sixteen_by_nine_crop_landscape

These styles should apply a square crop and a 16:9 crop. If no
matching style exists, no action is taken and no harm is done.

  Dynamic Range
  -------------

Fujifilm cameras have a built-in dynamic range compensation, which
(optionally automatically) reduce exposure by one or two stops, and
compensate by raising the tone curve by one or two stops. These modes
are called DR200 and DR400, respectively.

The plugin reads the raw file's "Auto Dynamic Range" or "Development
Dynamic Range" parameter, and applies one of two styles:
- DR200
- DR400

These styles should raise exposure by one and two stops, respectively,
and expand highlight latitude to make room for additional highlights.
I like to implement them with the tone equalizer in eigf mode, raising
exposure by one/two stops over the lower half of the sliders, then
ramping to zero at 0 EV. If no matching styles exist, no action is
taken and no harm is done.

These tags have been checked on a Fujifilm X-T3 and X-Pro2. Other
cameras may behave in other ways.

--]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"

du.check_min_api_version("7.0.0", "fujifilm_auto_settings")

-- return data structure for script_manager

local script_data = {}

script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them completely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again

local function exiftool_get(exiftool_command, RAF_filename, flag)
    local command = exiftool_command .. " " .. flag .. " -t " .. RAF_filename
    if os_is_windows then
        command = '"' .. command .. '"'
    end
    dt.print_log("[fujifilm_auto_settings] " .. command)

    local output = io.popen(command)
    local exiftool_result = output:read("*all")
    output:close()
    if #exiftool_result == 0 then
        dt.print_error("[fujifilm_auto_settings] no output returned by exiftool")
        return
    end
    local exiftool_result = string.match(exiftool_result, "\t(.*)")
    if not exiftool_result then
        dt.print_error("[fujifilm_auto_settings] could not parse exiftool output")
        return
    end
    exiftool_result = exiftool_result:match("^%s*(.-)%s*$") -- strip whitespace

    --dt.print_log("[fujifilm_auto_settings] exiftool result: " .. exiftool_result)

    return exiftool_result
end

local function apply_style(image, style_name)
    dt.print_log("[fujifilm_auto_settings] Attempting to apply style: " .. style_name)
    for _, s in ipairs(dt.styles) do
        if s.name == style_name then
            dt.styles.apply(s, image)
            return true
        end
    end
    dt.print_error("[fujifilm_auto_settings] could not find style " .. style_name)
    return false
end

local function apply_tag(image, tag_name)
    local tagnum = dt.tags.find(tag_name)
    if tagnum == nil then
        -- create tag if it doesn't exist
        tagnum = dt.tags.create(tag_name)
        dt.print_log("[fujifilm_auto_settings] creating tag " .. tag_name)
    end
    dt.tags.attach(tagnum, image)   
end

-- Lemon fork extra functions

local function find_bw_filmmode(bw_cmd, bw_filename, bw_image)
    local raw_filmmode = exiftool_get(bw_cmd, bw_filename, "-Saturation")
    local style_map = {
        ["Acros Green Filter"] = "Acros G",
        ["Acros Red Filter"] = "Acros R",
        ["Acros Yellow Filter"] = "Acros Ye",
        ["Acros"] = "Acros",
        -- Unsupported film modes since I've never seen anyone use them
        ["None (B&W)"] = "Acros",
        ["B&W Green Filter"] = "Acros G",
        ["B&W Red Filter"] = "Acros R",
        ["B&W Yellow Filter"] = "Acros Ye",
        ["B&W Sepia"] = "Acros"
    }
    local filmmode_success = false

    -- check if -saturation returns anything
    if #raw_filmmode == 0 then
        dt.print_log("[fujifilm_auto_settings] -Saturation did not return anything either")
        return false
    end

    -- See if the -saturation match any supported styles
    for key, value in pairs(style_map) do
        if raw_filmmode == key then
            apply_style(bw_image, lut_style_category .. value)
            apply_tag(bw_image, key)
            filmmode_success = true
            --dt.print_log("[fujifilm_auto_settings] b&w film simulation style map found: " .. key)
            break
        end
    end

    if not filmmode_success then
        dt.print_log("[fujifilm_auto_settings] -Saturation " .. raw_filmmode .. " does not match anything in b&w film style_map")
    end

    return filmmode_success
end

-- Lemon fork end 

local function detect_auto_settings(event, image)
    if image.exif_maker ~= "FUJIFILM" then
        dt.print_log("[fujifilm_auto_settings] ignoring non-Fujifilm image")
        return
    end
    -- it would be nice to check image.is_raw but this appears to not yet be set
    if not string.match(image.filename, "%.RAF$") then
        dt.print_log("[fujifilm_auto_settings] ignoring non-raw non-Fujifilm image")
        return
    end
    local exiftool_command = df.check_if_bin_exists("exiftool")
    if not exiftool_command then
        dt.print_error("[fujifilm_auto_settings] exiftool not found")
        return
    end
    local RAF_filename = df.sanitize_filename(tostring(image))

    -- dynamic range mode
    -- if in DR Auto, the value is saved to Auto Dynamic Range:
    local auto_dynamic_range = exiftool_get(exiftool_command, RAF_filename, "-AutoDynamicRange")

    -- if manually chosen DR, the value is saved to Development Dynamic Range, with a % suffix:
    if auto_dynamic_range == nil then        
        auto_dynamic_range = exiftool_get(exiftool_command, RAF_filename, "-DevelopmentDynamicRange") .. '%'
        --dt.print_log("[fujifilm_auto_settings] Manual DR detected: " .. auto_dynamic_range)
    else
        --dt.print_log("[fujifilm_auto_settings] Auto DR detected: " .. auto_dynamic_range)
    end

    if auto_dynamic_range == "100%" then
        apply_tag(image, "DR100")
        -- default; no need to change style

    elseif auto_dynamic_range == "200%" then
        apply_style(image, dr_style_category .. "DR200")
        apply_tag(image, "DR200")
        --dt.print_log("[fujifilm_auto_settings] DR200 applied")

    elseif auto_dynamic_range == "400%" then
        apply_style(image, dr_style_category .. "DR400")
        apply_tag(image, "DR400")
        --dt.print_log("[fujifilm_auto_settings] DR400 applied")
    end

    -- cropmode
    if apply_crop_styles then
        local raw_aspect_ratio = exiftool_get(exiftool_command, RAF_filename, "-RawImageAspectRatio")
        local raw_orientation = exiftool_get(exiftool_command, RAF_filename, "-Orientation")
        if raw_aspect_ratio == "3:2" then
            apply_tag(image, "3:2")
            -- default; no need to apply style
        elseif raw_aspect_ratio == "1:1" then
            if raw_orientation == "Horizontal (normal)" or raw_orientation == "Rotate 180" then
                apply_style(image, "square_crop_landscape")
            else
                apply_style(image, "square_crop_portrait")
            end
            apply_tag(image, "1:1")
            dt.print_log("[fujifilm_auto_settings] square crop")
        elseif raw_aspect_ratio == "16:9" then
            if raw_orientation == "Horizontal (normal)" or raw_orientation == "Rotate 180" then
                apply_style(image, "sixteen_by_nine_crop_landscape")
            else
                apply_style(image, "sixteen_by_nine_crop_portrait")
            end
            apply_tag(image, "16:9")
            dt.print_log("[fujifilm_auto_settings] 16:9 crop")
        end
    end

    -- filmmode
    local filmmode_success = false
    local raw_filmmode = exiftool_get(exiftool_command, RAF_filename, "-FilmMode")
    local style_map = {
        ["Provia"] = "Provia",
        ["Astia"] = "Astia",
        ["Classic Chrome"] = "Classic Chrome",
        ["Eterna"] = "Eterna",
        ["Pro Neg. Hi"] = "Pro Neg Hi",
        ["Pro Neg. Std"] = "Pro Neg Std",
        ["Velvia"] = "Velvia",
        ["Classic Negative"] = "Classic Negative"
    }

    -- If we get a filmmode back then it's a color simulation
    if raw_filmmode then
        for key, value in pairs(style_map) do
            if string.find(raw_filmmode, key) then
                apply_style(image, lut_style_category .. value)
                apply_tag(image, key)
                filmmode_success = true
                --dt.print_log("[fujifilm_auto_settings] color film simulation style map found: " .. key)
                break
            end
        end

        if not filmmode_success then
            dt.print_log("[fujifilm_auto_settings] -filmmode " .. raw_filmmode .. " does not match anything in color style_map")
        end
    -- If a film returns empty, it might be a black&white simulation    
    else
        --dt.print_log("[fujifilm_auto_settings] -filmmode returned empty")
        --dt.print_log("[fujifilm_auto_settings] checking -saturation in for b&w styles...")
        -- Check to see if it matches a supported b&w film simulation
        filmmode_success = find_bw_filmmode(exiftool_command, RAF_filename, image)
    end
    
    if not filmmode_success then
        dt.print_log("[fujifilm_auto_settings] neither -filmmode or -saturation matched anything in their style_map's")
    end
end

local function detect_auto_settings_multi(event, shortcut)
    local images = dt.gui.selection()
    if #images == 0 then
        dt.print(_("Please select an image"))
    else
        for _, image in ipairs(images) do
            detect_auto_settings(event, image)
        end
    end
end

local function destroy()
    dt.destroy_event("fujifilm_auto_settings", "post-import-image")
    dt.destroy_event("fujifilm_auto_settings", "shortcut")
end

if not df.check_if_bin_exists("exiftool") then
    dt.print_log("Please install exiftool to use fujifilm_auto_settings")
    error "[fujifilm_auto_settings] exiftool not found"
end

dt.register_event("fujifilm_auto_settings", "post-import-image", detect_auto_settings)

dt.register_event("fujifilm_auto_settings", "shortcut", detect_auto_settings_multi, "fujifilm_auto_settings")

dt.print_log("[fujifilm_auto_settings] loaded")

script_data.destroy = destroy

return script_data