program CK2Patch;

{ Contains patch information for versions of Keen 2 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN2}
{$DEFINE KEEN1_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='KEEN2*.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='CK2PATCH';

    { The extension that the game uses }
    Ext='CK2';

type
    { The version information structure for Keen 2 }
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
    { Versions currently supported are 1.0 and 1.31 }
    Version:array[0..1] of TVersion=(
        (
            { Keen 2 version 1.0 }
            ID:'1.0';
            ImageLength:118114;
            CompImageLength:58275;
            IsPKLITECompressed:false
        ),(
            { Keen 2 version 1.31 }
            ID:'1.31';
            ImageLength:118160;
            CompImageLength:58303;
            IsPKLITECompressed:false
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
