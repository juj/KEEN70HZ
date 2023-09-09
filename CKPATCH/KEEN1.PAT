# Sample Keen 1 patch file
# All text after # characters are ignored to end of line
%ext ck1

# If you uncomment the following line, the level files in the same directory
# as this script file will be used. By default, the level files in the same
# directory as the game executable will be used.
#%level.dir .

# Swaps levels 1 and 4 around. This is to demonstrate how the %level.file
# command works. If you have replacement levels, you'd specify them here.
%level.file 1 level04.ck1
%level.file 4 level01.ck1

%level.hint 2
Escape comments
and commands
like this:

\#Mlah
\%Mlah

%level.hint 6
Yorp tech support
says:

Remember to RTFM!

%level.hint 11
Garg says:

All your base are
belong to Garg!

%level.hint 15
# Leaving the message part blank effectively blanks the string
# (user will get a blank dialog box)

%end
