# Keen 4 sample patch file

# Rename this file to PATCH.PAT and put it in a subdirectory
# along with your GAMEMAPS.CK4 and MAPHEAD.CK4 to load custom
# maps. The same applies with Keen 5-6. When distributing maps,
# you should distribute the PATCH.PAT file as well for convenience.

%ext ck4

%gamemaps gamemaps.ck4
%maphead maphead.ck4

# If you've created your levels with TED5 instead, then comment out
# the %maphead line above and uncomment the following line.  Place the
# CK4MHEAD.OBJ file that TED5 created when it Carmackized the maps in
# the same directory as this patch script file.
#%ckmhead.obj ck4mhead.obj

%end
