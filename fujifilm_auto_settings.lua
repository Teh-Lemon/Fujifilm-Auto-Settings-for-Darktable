-- Lemon Fork v1.1 (2022/07/19) - https://github.com/Teh-Lemon/Fujifilm-Auto-Settings-for-Darktable/tree/Lemon
-- User Settings
local lut_style_category = "Fujifilm LUTs|" -- Set to "" if not using categories
local dr_style_category = "Fujifilm DR|"
local crop_style_category = "Fujifilm Crops|"

local apply_dr_styles = true -- Whether to apply the DR styles
local apply_crop_styles = true -- Whether to apply the crop styles
local apply_film_styles = true -- Whether to apply the film styles

--[[ fujifilm_auto_settings-0.4

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
simulations. But I created a set of LUTs that emulate them. The LUTs
were created from a set of training images on an X-T3, and generated
using https://github.com/bastibe/LUT-Maker.

In order to apply the film simulations, this plugin loads one of a
number of styles, which are available for download as part of this
repository:
- provia
- astia
- velvia
- classic_chrome
- pro_neg_standard
- pro_neg_high
- eterna
- acros_green
- acros_red
- acros_yellow
- acros
- mono_green
- mono_red
- mono_yellow
- mono
- sepia

These styles apply the chosen film simulation by loading one of the
supplied LUTs. You can replace them with styles of the same name that
implement the film simulations in some other way.

This plugin checks the image's "Film Mode" EXIF parameter for the
color film simulation, and "Saturation" for the black-and-white film
simulation, and applies the appropriate style. If no matching style
exists, no action is taken and no harm is done.

  Crop Factor
  -----------

Fujifilm cameras allow in-camera cropping to one of three aspect
ratios: 2:3 (default), 16:9, and 1:1.

This plugin checks the image's "Raw Image Aspect Ratio" exif
parameter, and applies the appropriate style.

To use, the repository contains another set of styles:
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

These tags have been checked on a Fujifilm X-A5, X-T3, X-T20 and
X-Pro2. Other cameras may behave in other ways.

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

local function exiftool(RAF_filename)
    local exiftool_command = df.check_if_bin_exists("exiftool")
    assert(exiftool_command, "[fujifilm_auto_settings] exiftool not found")
    local command = exiftool_command .. " -AutoDynamicRange -DevelopmentDynamicRange -RawImageAspectRatio -Orientation -FilmMode -Saturation -t " .. RAF_filename
    -- on Windows, wrap the command in another pair of quotes:
    if exiftool_command:find(".exe") then
        command = '"' .. command .. '"'
    end
    dt.print_log("[fujifilm_auto_settings] executing " .. command)

    -- parse the output of exiftool into a table:
    local output = io.popen(command)
    local exifdata = {}
    for line in output:lines("l") do
        local key, value = line:match("^%s*(.-)\t(.-)%s*$")
        if key ~= nil and value ~= nil then
            exifdata[key] = value
        end
    end
    output:close()

    assert(next(exifdata) ~= nil, "[fujifilm_auto_settings] no output returned by exiftool")
    return exifdata
end

local function apply_style(image, style_name)
    for _, s in ipairs(dt.styles) do
        if s.name == style_name then
            dt.styles.apply(s, image)
            return
        end
    end
    dt.print_error("[fujifilm_auto_settings] could not find style " .. style_name)
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


local function detect_auto_settings(event, image)
    if image.exif_maker ~= "FUJIFILM" then
        dt.print_log("[fujifilm_auto_settings] ignoring non-Fujifilm image")
        return
    end
    -- it would be nice to check image.is_raw but this appears to not yet be set
    if not string.match(image.filename, "%.RAF$") then
        dt.print_log("[fujifilm_auto_settings] ignoring non-raw image")
        return
    end
    local RAF_filename = df.sanitize_filename(tostring(image))

    local exifdata = exiftool(RAF_filename)

    -- dynamic range mode
    if apply_dr_styles then
        -- if in DR Auto, the value is saved to Auto Dynamic Range, with a % suffix:
        local auto_dynamic_range = exifdata["Auto Dynamic Range"]
        -- if manually chosen DR, the value is saved to Development Dynamic Range:
        if auto_dynamic_range == nil then
            auto_dynamic_range = exifdata["Development Dynamic Range"] .. '%'
        end
        if auto_dynamic_range == "100%" then
            apply_tag(image, "DR100")
            -- default; no need to change style
        elseif auto_dynamic_range == "200%" then
            apply_style(image, dr_style_category .. "DR200")
            apply_tag(image, "DR200")
            dt.print_log("[fujifilm_auto_settings] applying DR200")
        elseif auto_dynamic_range == "400%" then
            apply_style(image, dr_style_category .. "DR400")
            apply_tag(image, "DR400")
            dt.print_log("[fujifilm_auto_settings] applying DR400")
        end
    end

    -- cropmode
    if apply_crop_styles then
        local raw_aspect_ratio = exifdata["Raw Image Aspect Ratio"]
        local raw_orientation = exifdata["Orientation"]
        if raw_aspect_ratio == "3:2" then
            apply_tag(image, "3:2")
            -- default; no need to apply style
        elseif raw_aspect_ratio == "1:1" then
            if raw_orientation == "Rotate 90 CW" or raw_orientation == "Rotate 270 CW" then
                apply_style(image, crop_style_category .. "1:1 Portrait")
            else
                apply_style(image, crop_style_category .. "1:1 Landscape")
            end
            apply_tag(image, "1:1")
            dt.print_log("[fujifilm_auto_settings] applying square crop")
        elseif raw_aspect_ratio == "16:9" then
            if raw_orientation == "Rotate 90 CW" or raw_orientation == "Rotate 270 CW" then
                apply_style(image, crop_style_category .. "16:9 Portrait")
            else
                apply_style(image, crop_style_category .. "16:9 Landscape")
            end
            apply_tag(image, "16:9")
            dt.print_log("[fujifilm_auto_settings] applying 16:9 crop")
        end
    end

    -- filmmode
    if apply_film_styles then
        local raw_filmmode = exifdata["Film Mode"]
        local raw_saturation = exifdata["Saturation"]
        -- Check if it's a color film mode
        if raw_filmmode then
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
            for key, value in pairs(style_map) do
                if string.find(raw_filmmode, key) then
                    apply_style(image, lut_style_category .. value)
                    apply_tag(image, key)
                    dt.print_log("[fujifilm_auto_settings] applying film simulation " .. key)
                    break
                end
            end
        -- else check if it's a b&w film mode
        elseif raw_saturation then
            local style_map = {
                ["Acros"] = "Acros",
                ["Acros Green Filter"] = "Acros G",
                ["Acros Red Filter"] = "Acros R",
                ["Acros Yellow Filter"] = "Acros Ye",
                ["None (B&W)"] = "Monochrome",
                ["B&W Green Filter"] = "Monochrome G",
                ["B&W Red Filter"] = "Monochrome R",
                ["B&W Yellow Filter"] = "Monochrome Ye",
                ["B&W Sepia"] = "Sepia"
            }
            for key, value in pairs(style_map) do
                if raw_saturation == key then
                    apply_style(image, lut_style_category .. value)
                    apply_tag(image, key)
                    dt.print_log("[fujifilm_auto_settings] applying B&W film simulation " .. key)
                    break
                end
            end
        else
            dt.print_log("[fujifilm_auto_settings] neither Film Mode or Saturation EXIF info was found")
        end
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