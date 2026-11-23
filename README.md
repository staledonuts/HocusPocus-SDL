# Hocus Pocus SDL3

## Features
- _Smooth Motion_, interpolation between engine timesteps for a smoother experience. (disabled by default)
- Scanlines. (disabled by default)
- Gamepad Support.
- Input re-mapping for keyboard.
- Aspect Ratio settings.
- Interger Scale for pixel perfect visuals.

## Installation

In the data folder you can find the shareware version of Hocus Pocus, the compiled executable will search for the hocus.dat file in these folders.
- <base_dir>/data/
- Linux:   ~/.local/share/HocusPocusSDL/ (respects $XDG_DATA_HOME)
- Windows: %APPDATA%\HocusPocusSDL\
user data directory is primary for config, savegames, and HOCUS.DAT;
bundled Shareware data next to the executable (<base_dir>/data/) is secondary.

## Compilation

You need [ODIN](https://odin-lang.org/docs/install/) installed and setup correctly and access to the [SDL3 DLL/Library file](https://github.com/libsdl-org/SDL) for the OS you are building on. then you basically just run "odin build ." in sourcecode folder and plop the dll / library in the same folder as the compiled executable.

## Context/Credits

Codebase for this port was [K1n9_Duk3](http://k1n9duk3.shikadi.net/)'s reconstruction of Hocus Pocus's source code that can be found in [this PCKF thread](https://pckf.com/viewtopic.php?t=18675). I poked a look at the code and thought it would be a fun learning project to try to port / re-write to SDL3 / Odin Lang.

Almost all code used here was based on the work of K1n9_Duk3 whom released it under GNU GPL license and it continues to be released under the terms of the GNU GPL for this re-write.
