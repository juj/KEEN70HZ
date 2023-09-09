program CK5Patch;

{ Contains patch information for versions of Keen 5 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN5}
{$DEFINE KEEN4_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='KEEN5*.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='CK5PATCH';

    { The extension that the game uses }
    Ext='CK5';

    { Number of levels featured in this game }
    NumLevels=15;

type
    { Enumerations for each of the resources }
    TDataResource=(
        drAudioHed, { AUDIOHED, index of sound effects in AUDIO.CK5 }
        drEGAHead,  { EGAHEAD, index of sprite tiles in EGAGRAPH.CK5 }
        drMapHead,  { MAPHEAD, index of levels in GAMEMAPS.CK5 }
        drAudioDct, { AUDIODCT, huffman tree for decompressing AUDIO.CK5 }
        drEGADict,   { EGADICT, huffman tree for decompressing EGAGRAPH.CK5 }
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
    { Resource image offsets for EGA version 1.4 }
    DataResourceOffset_14E:TDataResourceOffset=
        ($21C80,$21FC0,$25990,$35EC4,$362C4,$25B22,$25990);

    { Resource byte lengths for EGA version 1.4 }
    DataResourceLength_14E:TDataResourceLength=
        (832,14800,402,1024,1024,23694,24096);

    { Resource image offsets for CGA version 1.4 }
    DataResourceOffset_14C:TDataResourceOffset=
        ($1F4C0,$1F800,$231D0,$33B88,$33F88,$23362,$231D0);

    { Resource byte lengths for CGA version 1.4 }
    DataResourceLength_14C:TDataResourceLength=
        (832,14800,402,1024,1024,23694,24096);

    { Level name maximum lengths for version 1.4 }
    LevelNameLength_14:TLevelStringLength=
        (16,32,16,32,32,32,32,32,32,32,32,32,32,16,16,16);

    { Level entry name maximum lengths for version 1.4 }
    LevelEntryLength_14:TLevelStringLength=
        (48,48,48,48,48,48,48,48,48,48,48,64,48,48,48,64);

    { Versions currently supported are Apogee v1.4 }
    Version:array[0..1] of TVersion=(
        (
            { Keen 5 EGA Apogee version 1.4 }
            ID:'1.4';
            ImageLength:254832;
            CompImageLength:106385;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_14E;
            DataResourceLength:@DataResourceLength_14E;
            LevelNameOffset:$20040;
            LevelNameLength:@LevelNameLength_14;
            LevelEntryOffset:$201F0;
            LevelEntryLength:@LevelEntryLength_14
        ),(
            { Keen 5 CGA Apogee version 1.4 }
            ID:'cga-1.4';
            ImageLength:244496;
            CompImageLength:98848;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_14C;
            DataResourceLength:@DataResourceLength_14C;
            LevelNameOffset:$1D8D0;
            LevelNameLength:@LevelNameLength_14;
            LevelEntryOffset:$1DA80;
            LevelEntryLength:@LevelEntryLength_14
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
