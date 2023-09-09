# Commander Keen 4-6 source

This repository contains a Git copy of Keen 4-6 source code recreated by K1n9_Duk3 in this PCKF forum post: https://pckf.com/viewtopic.php?t=11505&sid=736f20ec1ee9afc7c479b67d6f1672db , i.e. the file http://k1n9duk3.shikadi.net/files/modding/keensource456.zip , obtained on 7th of September 2023.

See [readme.txt](readme.txt) for K1n9_Duk3's original readme in the zip file.

# Quick Setup for getting started compiling Keen 4 EGA Shareware.

1. Git clone this repository.
2. Either:
	a) Download and install DOSBox-X from https://dosbox-x.com/ . Mount the root of this repository as the root C:\ drive of DOSBox-X. This can be done easily by right-clicking in the cloned directory and choosing "Open with DOSBox-X." On Windows 11, you may need to choose the "More Options..." dropdown item first. An alternative way to open is to drag-and-drop the cloned repository folder onto the DOSBox-X executable icon.
	b) Alternatively deploy the files in this repository to your vintage MS-DOS 6.22 PC.
3. Run B4.BAT to open the Keen 4 EGA project.
4. Press F9 to compile the project.
5. Press Alt-X to quit back to DOS after compilation.
6. Run K4.BAT to launch the compiled Keen 4 executable.

When finished running the code, rerun B4.BAT to return back to the IDE.

# This repository uses...

- Like mentioned above, K1n9_Duk3's Keen 4-6 sources, modified. Licensed under GPL2.

- A deployment of CKPATCH v0.11.3 (unofficial), in directory [CKPATCH/](CKPATCH/), downloaded from http://ny.duke4.net/files.html , licensed under GPL2.

- A pre-deployment and extract of Commander Keen 4 EGA v1.4, in directory [K4E-14/](K4E-14/), downloaded from https://keenwiki.shikadi.net/wiki/Keen_4_Versions . Keen 4 is licensed Shareware from Apogee.

- Borland C++ 3.0, place it in directory BC30/. Copyright of Borland. Please acquire legal rights to Borland C++ 3.0 compiler, see [CONTACT.txt](BC30/ZIP/CONTACT.txt) for contacting Borland.

# I wish to compile other Keen versions than the prebundled Keen 4 EGA Shareware?

1. Purchase Commander Keen from [GOG.com: Commander Keen Complete Pack](https://www.gog.com/en/game/commander_keen_complete_pack) or from [Steam: Commander Keen](https://store.steampowered.com/app/9180/Commander_Keen/), or source it from your own purchased DOS copy.

2. Follow K1n9_Duk3's full instructions at [readme.txt](readme.txt) on how to unpack and extract the game data files.

3. Run one of the `RCK*.bat` files to open the relevant project files in the compiler IDE.
