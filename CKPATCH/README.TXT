  ____ _  ______       _       _
 / ___| |/ /  _ \ __ _| |_ ___| |__
| |   | ' /| |_) / _` | __/ __| '_ \
| |___| . \|  __/ (_| | || (__| | | |
 \____|_|\_\_|   \__,_|\__\___|_| |_|

-----------------------------------------------------------------------

CKPatch v0.11.3 beta
Copyright (C) 2001-2003 Bryan Rodgers <rodgersb@ses.curtin.edu.au>
Copyright (C) 2007 Andrew Durdin <me@andy.durdin.net>
Released to the public under GNU GPL

KNOWN ISSUES (README.TXT)

-----------------------------------------------------------------------

*** TABLE OF CONTENTS ***

[1] Syntax additions in v0.10.0
[2] Syntax changes between CKPatch v0.5.x and v0.9.0
[3] Issues with transparent LZEXE decompression
[4] Versions of Commander Keen currently supported
[5] Known working operating environments for CKPatch
[6] Problems with antivirus background monitors
[7] Memory overhead of CKPatch
[8] Currently known bugs
[9] Getting TED5-saved maps to work
[10] Building the source code

-----------------------------------------------------------------------

[1] Syntax additions in v0.10.0

Because Keen 4, 5, 6 and Dreams use the Medium memory model, many
patches need to alter far pointers, which requires the actual address
patched to reflect the base address where the image was loaded.

To support this, the %patch command, in addition to byte and string
literals, will now take 16-bit and 32-bit literals, which will be
written out in little-endian order.  These literals are marked with
a 'W' or 'L' suffix (uppercase or lowercase).

In addition, 16- and 32-bit literals can have an 'R' suffix (uppercase
or lowercase) before the 'W' or 'L', to indicate that it is an image-
relative segment or far pointer.  When patching the file, CKPatch will
add the base memory address to the 16-bit value (or to the high word of
a 32-bit value) to convert it to a memory-relative segment or far pointer.

Existing patches written for CKPatch v0.9.0 should still work; however
if you had given a byte value > 255 to a %patch command (which would only
have patched the lowest 8 bits anyway), you'll now get an error message.

[2] Syntax changes between CKPatch v0.5.x and v0.9.0

I discovered a number of problems with the script file parsing
routines in CKPatch v0.5.x.  While they worked fine for
syntactically correct files, handing of files with syntax errors was
not as graceful as you would normally expect it to be.  For
instance, if you forgot to close off a double-quoted string, the
rest of the file would get silently quoted as part of the string,
and any following commands would get ignored.

In order to simplify the parser and eliminate problems like these,
I've made the parsing rules more strict than they were in CKPatch
v0.5.x.  The syntax changes are still backwards compatible, so any
files that were corrected for CKPatch v0.9.0 will still work with
CKPatch v0.5.x.  The syntax changes encourage well-formatted layout,
so if you've been following the layout style of the example patch
files I've created, then you shouldn't have to make any changes.

Here's a list of changes that you may need to make to your patch
script files in order to get them to work with CKPatch v0.9.0:

- Commands now must be the first word on the line (any leading
  whitespace before the command is still ok).  Only one command can
  be on a line at most.  You can no longer chain multiple commands
  together on the same line.  Arguments, however can be on the same
  line or lines following the command, all the way up to the next
  command.
- To ensure that your patch scripts are compatible with future
  versions of CKPatch, the first command in the script file must be
  %ext, and the game extension must be correctly set.  The %ext
  command must appear only once.
- All patch scripts must end with the %end command.  If you fail to
  specify an %end command, then CKPatch will terminate with an error
  message.  This is an added safety measure in case the parser gets
  confused and ends up silently misinterpreting or ignoring the rest
  of the file, so you don't end up with a corrupted image that
  crashes the system.
- Double quoted strings may not span over more than one line.  If a
  string argument to a %patch command is too long, then you can
  break the string up by closing it off, starting a new line, then
  continuing the string with another double-quote character.  For
  example:

    %patch 0x00001234 "This is one line\n"
        "This is another\n" 0x00

[3] Issues with transparent LZEXE decompression

While implementing this feature in CKPatch, I noticed that there are
at least two distinct versions of the LZEXE v0.91 decompression
stub.  Both have the 'LZ91' signature in the EXE file header, but
the code is slightly different.  The LZEXE decompression stub in the
original Keen 1-6 game executables is an earlier version, whereas
the stub in executables that I've compressed with the most recent
version of LZEXE seems to be a later version.

This raises a slight issue.  On the original media that I store my
copies of Keen 1-6 on, I've stored the executable in uncompressed
form for the purpose of developing CKPatch.  However since CKPatch
can only determine the game executable version by checking the EXE
image length, I had to recompress the game executables using the
newer version of LZEXE and then key in the compressed image sizes
into the CKPatch source code (so CKPatch can recognise the game
executables in LZEXE-compressed form).

As a result, I'm making the assumption that the image sizes of the
compressed game executables are the same for both the older and
newer versions of LZEXE.  This is because I don't have any way of
obtaining the older version of LZEXE in order to regenerate the
exact original executable, byte-for-byte.

This means that there might be the possibility of your original Keen
game executable not being recognised in its LZEXE-compressed form
(you'll get the "unrecognised version" error message).

If this happens to you, then I'll need you to run UNP on your game
executable so I can obtain the correct LZEXE-compressed image
length.  Download UNP at the following FTP location:

ftp://ftp.simtel.net/pub/simtelnet/msdos/execomp/unp411.zip

Then run the following command on your game executable (where x is
the episode number, x=1-6):

UNP i KEENx.EXE

Send me a bug report, and include the output of the above command in
your email.  As a temporary workaround, you can also use UNP to
decompress the executable, so CKPatch can recognise it properly.
Simply type the following command:

UNP KEENx.EXE

If you're finding that CKPatch is causing the game to crash, or
exhibit unusual behaviour when your game executable is
LZEXE-compressed, first try decompressing it by running the above
command and see if this fixes the problem.  If it does, let me know,
as it means that the method that CKPatch employs to decompress the
executable isn't as reliable as I hoped it would be.

[4] Versions of Commander Keen currently supported

The following versions of each Keen game are currently recognised:
    Keen 1: v1.1, v1.31
    Keen 2: v1.0, v1.31
    Keen 3: v1.0, v1.31
    Keen 4: v1.4
    Keen 5: v1.4
    Keen 6 (full version): v1.0, v1.4

Keen 6 (full version) is currently untested, since I still can't get
the levels to load into TED5.  I'm wanting to know how the
GFXINFOE.CKx files are generated.  If someone could shed some light
on how you generate these files, that would be much appreciated.

If you have other versions of the registered games (Keen 2,3,5,6)
that are not yet recognised, please email me, and I can either give
you instructions for locating the offsets in the executable, or you
can send me your game executable for me to work out the offsets
myself.

I don't consider the shareware games as much of a priority (as long
as the latest version is recognised), since users can simply
download the latest version off the internet.  Especially if you've
got Keen 4 v1.0; if you do, you should upgrade to v1.4 right now,
since v1.0 has got that damn annoying bug which causes it to lose
all gems when loading saved games.

[5] Known working operating environments for CKPatch

Currently I've only been able to verify the operation of CKPatch
under MS-DOS 6.22 and Win98 DOS box, which they both work as
expected without any problems.  CKPatch is primarily developed and
tested under MS-DOS 6.22, so I can guarantee it should work at least
under this environment.

Under DOSBox v0.50 (http://dosbox.sourceforge.net), CKPatch seemed
to have no effect at all; the game would run with absolutely no sign
of any modifications, yet CKPatch didn't report any errors.  My
suspicion is that DOSBox doesn't yet support the DOS interrupt 21H
service AH=4BH/AL=01H, and instead maps it to the service
AH=4BH/AL=00H, which runs the executable straight away, then
terminates.  I might try CKPatch under more recent DOSBox versions,
or examine the DOSBox source code to verify my above suspicions.

[6] Problems with antivirus background monitors

Keep in mind that some idiotic antivirus background monitors may
raise false alarms when CKPatch is run, since CKPatch uses similar
DOS system calls that common viruses use.  CKPatch itself is of
course not a virus - it doesn't modify any of your program files and
unloads from memory when the game exits.  You can download the
source code and prove it yourself if you don't trust my words!  :)

[7] Memory overhead of CKPatch

CKPatch adds some extra memory overhead when running the game, since
it needs to stay resident while the game is running so it can clean
up the interrupt handler when the game exits.  Currently you'll need
about 20KB more conventional than the game itself requires (Keen
1-3: 540KB, Keen 4-6: 580KB).

I might be able to optimise the code so it uses less memory at some
point in the future.  Perhaps rewriting it in assembler might do the
trick (reduce it to a few kilobytes, though the code will be a lot
more difficult to maintain).  Any one want to help out?

If you have enough memory to run the game by itself but not with
CKPatch, then you could also try the LOADHIGH command when running
CKPatch, to load CKPatch into upper memory.

[8] Currently known bugs

I'm hoping these bugs don't resurface.  I spent hours and hours
scratching my head in Turbo Debugger trying to figure out why the
heck my interrupt handler was crashing the game at random locations.
After lots of reboots and resets, I realised I was forgetting to
re-enable CPU interrupts on return to the game ;) I think that
problem's gone now, everything seems to be ok.

If you have any other features you want to suggest (like other
strings or resources in Keen 1-6 that can be patched), just drop
me an email about it.

[9] Getting TED5-saved maps to work

I've added a %ckmhead.obj command to CKPatch in order so you can
load the correct MAPHEAD resource data into the game without having
to use a hex editor on the CKxMHEAD.OBJ file.  See section 4.2 in
CKPATCH.TXT for more information on loading TED5-saved maps into
Keen 4-6.  Don't use the MAPHEAD.CKx file that TED5 also saves, this
file for some unknown reason contains incorrect information, which
will cause the game to fail.

I've tested this out with simple modifications made to the Keen
4/Keen 5 maps, and everything seems to be working as expected so
far. The version of TED5 that I've used is the one that can be
downloaded off Apogee's/3DRealms' website, which was modified
slightly for use with ROTT.

[10] Building the source code

To build the source code, you need Borland Turbo Pascal 6.0 or later
and Netwide Assembler (available from http://nasm.sourceforge.net).
The makefile is set up to build all six executables and optionally
LZEXE and zip them up as well (if you have LZEXE and PKZIP
available) ready for distribution.  Just type 'make all' to build
all six executables.

-----------------------------------------------------------------------

*** END OF README.TXT ***
