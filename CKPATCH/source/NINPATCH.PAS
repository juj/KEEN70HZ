program NINPatch;

{ Contains patch information for versions of Shadow Knights }
{ Based on CK1PATCH.PAS by Admiral Bob; Hacked by Shadow Master }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN1_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='SHADOW.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='NINPATCH';

    { The extension that the game uses }
    Ext='NIN';

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
    { Only version currently supported is 1.0}
    Version:array[0..0] of TVersion=(
        (
            { Shadow Knights version 1.0 }
            ID:'1.0';
            ImageLength:88960;
            CompImageLength:41434;
            IsPKLITECompressed:false
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
