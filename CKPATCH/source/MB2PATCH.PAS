program MB2Patch;

{ Contains patch information for versions of Monster Bash 2 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN1_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='BASH2.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='MB2PATCH';

    { The extension that the game uses }
    Ext='MB2';

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
    { Only version currently supported is 2.1 }
    Version:array[0..0] of TVersion=(
        (
            { Monster Bash 2 version 2.1 }
            ID:'2.1';
            ImageLength:148681;
            CompImageLength:74900;
            IsPKLITECompressed:true
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
