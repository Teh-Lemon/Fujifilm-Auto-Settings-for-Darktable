## Lemon Fork Changes

* Ported to Windows
* Disabled Aspect Ratio styles (I don't use them)
* Categorized the styles in Darktable
* Converted Bastibe's HaldCLUT LUTs to g'mic compressed LUTs
* Added Acros and Classic Neg LUTs as g'mic compressed LUTs
    * Acros is provided by [Stuart Sowerby](https://blog.sowerby.me/fuji-film-simulation-profiles/)
    * Classic Neg is provided by [Marc R. Photography](https://marcrphoto.wordpress.com/2021/03/25/picturefx-pro-fujifilm-superia-200/)
* Fixes all the broken film simulation detections
    * Note: I did not add support for the Monochrome and Sepia simulations
* Tested using photos from an XT-20
## Lemon Fork Install Instructions

1. Download and extract the Windows version of [exiftools](https://exiftool.org/) somewhere permanent and rename it to `exiftool.exe`.
2. Install exiftools to your PATH variable ([Tutorial](https://www.computerhope.com/issues/ch000549.htm)).
3. Copy `fujifilm_auto_settings.lua` to your `C:\Users\YOUR_NAME\AppData\Local\darktable\lua\contrib` folder.
4. Copy the `Fuji XTrans VII` folder to your `3D lut root folder` (that you set in Darktable's `preferences/processing`).  
    4a. You only need the `.gmz` files. The .png files are not used in this fork.
5. Inside Darktable, import the `DR200.dtstyle` and `DR400.dtstyle` styles found inside the repo's `styles` folder.  
    5a. The crop styles are not used in this fork
6. Inside Darktable, import the styles found inside the `styles/gmz LUTs` folder.
7. Enable the script inside Darktable's LUA panel.

# Fujifilm Auto Settings for Darktable

This repository contains styles and scripts and LUTs to automatically read and apply

- Film Simulation
- 2:3/16:9/1:1 crop
- DR100/DR200/DR400 mode

## Installation

Install `exiftool` and make sure it is available on `$PATH`.

Go to Darktable's settings, in the tab "processing", set a 3D lut root folder. Copy the supplied LUTs into that directory, such that e.g. the Provia LUT is at `$3DLUTROOTFOLDER/Fuji XTrans VII/provia.png`.

Import the styles in the `styles` subdirectory. The film simulation styles rely on the LUTs installed in the previous step.

Activate Darktable's script manager from the Lighttable view in the bottom left.

Copy `fujifilm_auto_settings.lua` to `~/.config/darktable/lua/contrib/`, then start it with the script manager. It should now automatically apply the styles to any imported RAF image.

## Debugging

Start Darktable with `darktable -d lua` to debug. You can run the lua script manually by binding a keyboard shortcut to `fujifilm_auto_settings` in Darktable's settings.

## How it Works

The lua plugin calls `exiftool` to read the film simulation, crop mode, and DR mode from the RAF file. It then applies one of the supplied styles, and sets an appropriate tag.

#### Film Simulations

The following styles apply Fuji film simulations from https://github.com/bastibe/LUT-Maker:

- acros
- astia
- eterna
- classic\_chrome
- pro\_neg\_high
- pro\_neg\_standard
- provia
- sepia
- velvia

These styles activate *LUT 3D*, and set the appropriate LUT.

#### Crop

The following styles apply a 16:9/1:1 crop:

- sixteen\_by\_nine\_crop\_portrait
- sixteen\_by\_nine\_crop\_landscape
- square\_crop\_portrait
- square\_crop\_landscape

2:3 crop does not have its own style, since Fujifilm images are already 2:3.

The crop styles are not pixel-perfect.

#### DR Mode

The following styles apply for DR200 and DR400:

- DR200
- DR400

As far as I can tell, the DR modes reduce the raw exposure by one/two stops to make room for additional highlights, and increase the tone curve for midtones and shadows to compensate.

The supplied styles implement this using the tone equalizer, by raising the -8 EV to -4 EV sliders to +1 EV, then -3 EV to +0.75, -2 EV to +0.5, -1 EV to +0.25 EV, and 0 EV to 0 EV (for DR200; double all values for DR400). I experimented a bit with various *preserve details* functions, and found *eigf* to look most similar to Fuji's embedded JPEGs, so that's what the styles use.

Of course this can only work for properly exposed images, and even then might not be perfectly reliable. But it usually gets the images in the right ballpark in my testing.

## Known Issues

Some of the LUTs may introduce a magenta tint to highlights. Let me know if you know of better-behaved LUTs!

## License

I place these scripts and LUTs under the terms of the GPL license
