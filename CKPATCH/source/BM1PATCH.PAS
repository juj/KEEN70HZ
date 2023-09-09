program BM1Patch;

{ Contains patch information for versions of Biomenace 1 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN1_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='BMENACE1.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='BM1PATCH';

    { The extension that the game uses }
    Ext='BM1';

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
    { Versions currently supported are 1.1 freeware and shareware }
    Version:array[0..1] of TVersion=(
        (
            { Biomenace 1 version 1.1 freeware }
            ID:'1.1';
            ImageLength:223600;
            CompImageLength:90014;
            IsPKLITECompressed:false
        ),(
            { Biomenace 1 version 1.1 shareware }
            ID:'1.1s';
            ImageLength:221856;
            CompImageLength:89134;
            IsPKLITECompressed:false
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
