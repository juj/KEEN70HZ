program MB1Patch;

{ Contains patch information for versions of Monster Bash 1 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN1_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='BASH1.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='MB1PATCH';

    { The extension that the game uses }
    Ext='MB1';

type
    { Generic version information structure }
    PVersion=^TVersion;
    TVersion=record
        { The version ID string }
        ID:String[7];

        { The uncompressed length of the game executable image }
        ImageLength:Longint;

        { The compressed length of the game executable image }
        CompImageLength:Longint;

        { Indicates that PKLITE compression is used for compressed EXE }
        IsPKLITECompressed:Boolean;
    end;

const
    { Versions currently supported are 2.1 registered and shareware (not lite) }
    Version:array[0..1] of TVersion=(
        (
            { Monster Bash 1 version 2.1 registered }
            ID:'2.1';
            ImageLength:150059;
            CompImageLength:75257;
            IsPKLITECompressed:true
        ),(
            { Monster Bash 1 version 2.1 shareware (not lite) }
            ID:'2.1s';
            ImageLength:150625;
            CompImageLength:75743;
            IsPKLITECompressed:true
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
