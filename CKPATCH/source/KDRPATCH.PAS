program KDRPatch;

{ Contains patch information for versions of Keen Dreams }
{ Written by Brian Rodgers and David Gow.  Requires Keen }
{ Dreams v1.13. UNLZEXE OPTIONAL. Support level.name     }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEND}
{$DEFINE KEEN4_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='KDREAMS*.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='KDRPATCH';

    { The extension that the game uses }
    Ext='KDR';

    { Number of levels featured in this game }
    NumLevels=16;

type
    { Enumerations for each of the resources }
    TDataResource=(
        drAudioHed, { AUDIOHED, index of sound effects in AUDIO.KDR }
        drEGAHead,  { EGAHEAD, index of sprite tiles in EGAGRAPH.KDR }
        drMapHead,  { MAPHEAD, index of levels in GAMEMAPS.KDR }
        drAudioDct, { AUDIODCT, huffman tree for decompressing AUDIO.KDR }
        drEGADict,   { EGADICT, huffman tree for decompressing EGAGRAPH.KDR }
        drTileInfo,   { TILEINFO, external tile properties }
        drWholeMapHead { Whole MAPHEAD, including the TILEINFO data }
        );

    { Contains image offsets of each resource }
    PDataResourceOffset=^TDataResourceOffset;
    TDataResourceOffset=
        array[Low(TDataResource)..High(TDataResource)] of Longint;

    { Contains byte lengths of each resource }
    PDataResourceLength=^TDataResourceLength;
    TDataResourceLength=
        array[Low(TDataResource)..High(TDataResource)] of Longint;

    { Contains the maximum length of the name of each level }
    PLevelStringLength=^TLevelStringLength;
    TLevelStringLength=array[0..NumLevels] of Word;

    { The version information structure for Keen 5 }
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

        { Image offsets of each of the data resources }
        DataResourceOffset:PDataResourceOffset;

        { Byte lengths of each of the data resources }
        DataResourceLength:PDataResourceLength;

        { Image offset of the level name string array }
        LevelNameOffset:Longint;

        { Maximum lengths of each of the level name strings }
        LevelNameLength:PLevelStringLength;

        { Image offset of the level entry string array }
        LevelEntryOffset:Longint;

        { Maximum lengths of each of the level entry strings }
        LevelEntryLength:PLevelStringLength;
    end;

const
    { Resource image offsets for version 1.13 }
    DataResourceOffset_113:TDataResourceOffset=
        ($22880,$1CB20,$1FA50,$2A042,$29846,$1FC46,$1FA50);

    { Resource byte lengths for version 1.13 }
    DataResourceLength_113:TDataResourceLength=
        (352,12080,502,1024,1024,11322,11824);

    { Level name maximum lengths for version 1.13 }
    LevelNameLength_113:TLevelStringLength=
        (20,17,16,15,15,13,8,10,8,12,12,9,20,9,13,16,15);

    { Resource image offsets for version 1.05 }
    DataResourceOffset_105:TDataResourceOffset=
        ($1EB50,$18DF0,$1BD20,$28490,$27C94,$1BF16,$1BD20);

    { Resource byte lengths for version 1.05 }
    DataResourceLength_105:TDataResourceLength=
        (352,12080,502,1024,1024,11322,11824);

    { Level name maximum lengths for version 1.05 }
    LevelNameLength_105:TLevelStringLength=
        (20,17,16,15,15,13,14,10,14,12,12,14,20,14,13,16,15);

    { Unused }
    UnusedLevelEntryLength:TLevelStringLength=
        (48,48,48,48,48,48,48,48,48,48,48,64,48,48,48,64,48);

    { Versions currently supported are 1.13 (Shareware) and 1.05 (CGA) }
    Version:array[0..1] of TVersion=(
        (
            { Keen Dreams version 1.13 }
            ID:'1.13';
            ImageLength:206368;
            CompImageLength:81587;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_113;
            DataResourceLength:@DataResourceLength_113;
            LevelNameOffset:$23FCA;
            LevelNameLength:@LevelNameLength_113;
            LevelEntryOffset:$201F0; { Unused }
            LevelEntryLength:@UnusedLevelEntryLength
        ),(
            { Keen Dreams version 1.05 }
            ID:'1.05';
            ImageLength:196176;
            CompImageLength:78221;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_105;
            DataResourceLength:@DataResourceLength_105;
            LevelNameOffset:$221FA;
            LevelNameLength:@LevelNameLength_105;
            LevelEntryOffset:$201F0; { Unused }
            LevelEntryLength:@UnusedLevelEntryLength
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
