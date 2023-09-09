program CK4Patch;

{ Contains patch information for versions of Keen 4 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN4}
{$DEFINE KEEN4_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='KEEN4*.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='CK4PATCH';

    { The extension that the game uses }
    Ext='CK4';

    { Number of levels featured in this game }
    NumLevels=18;

type
    { Enumerations for each of the resources }
    TDataResource=(
        drAudioHed, { AUDIOHED, index of sound effects in AUDIO.CK4 }
        drEGAHead,  { EGAHEAD, index of sprite tiles in EGAGRAPH.CK4 }
        drMapHead,  { MAPHEAD, index of levels in GAMEMAPS.CK4 }
        drAudioDct, { AUDIODCT, huffman tree for decompressing AUDIO.CK4 }
        drEGADict,   { EGADICT, huffman tree for decompressing EGAGRAPH.CK4 }
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

    { Contains image offsets for each Princess Lindsey hint message }
    PLevelHintOffset=^TLevelHintOffset;
    TLevelHintOffset=array[0..1] of Longint;

    { Contains max string lengths for each Princess Lindsey hint message }
    PLevelHintLength=^TLevelHintLength;
    TLevelHintLength=array[0..1] of Word;

    { The version information structure for Keen 4 }
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

        { Image offsets of each of the Princess Lindsey hint messages }
        LevelHintOffset:PLevelHintOffset;

        { Maximum lengths of each of the Princess Lindsey hint message }
        LevelHintLength:PLevelHintLength;
    end;

const
    { Contains a mapping of level numbers to hint messages. The value of }
    { each element in this array is the index into the LevelHintOffset and }
    { LevelHintLength arrays of the hint message for a particular level. An }
    { entry of $FF indicates there is no hint string for this level. }
    LevelHintMap:array[0..NumLevels] of Byte=(
        $FF,$FF,$FF,$FF,$FF,0,$FF,1,
        $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,
        $FF,$FF,$FF
        );

    { Resource image offsets for EGA version 1.4 }
    DataResourceOffset_14E:TDataResourceOffset=
        ($20DF0,$21080,$24830,$354F6,$358F6,$249C2,$24830);

    { Resource byte lengths for EGA version 1.4 }
    DataResourceLength_14E:TDataResourceLength=
        (656,14256,402,1024,1024,23006,23408);

    { Resource image offsets for CGA version 1.4 }
    DataResourceOffset_14C:TDataResourceOffset=
        ($1E7A0,$1EA30,$221E0,$3335C,$3375C,$22372,$221E0);

    { Resource byte lengths for CGA version 1.4 }
    DataResourceLength_14C:TDataResourceLength=
        (656,14256,402,1024,1024,23006,23408);

    { Level name maximum lengths for version 1.4 }
    LevelNameLength_14:TLevelStringLength=
        (16,16,16,32,32,16,16,16,16,16,16,32,32,48,32,16,16,16,32);

    { Level entry name maximum lengths for version 1.4 }
    LevelEntryLength_14:TLevelStringLength=
        (32,48,32,48,64,48,48,32,48,32,48,48,48,64,64,48,48,48,64);

    { Hint offsets and lengths for version 1.4 }
    LevelHintOffset_14E:TLevelHintOffset=($30999,$3094C);
    LevelHintOffset_14C:TLevelHintOffset=($2E259,$2E20C);
    LevelHintLength_14:TLevelHintLength=(74,77);

    { Versions currently supported are Apogee v1.4 }
    Version:array[0..1] of TVersion=(
        (
            { Keen 4 EGA Apogee version 1.4 }
            ID:'1.4';
            ImageLength:251712;
            CompImageLength:105076;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_14E;
            DataResourceLength:@DataResourceLength_14E;
            LevelNameOffset:$1F040;
            LevelNameLength:@LevelNameLength_14;
            LevelEntryOffset:$1F1F0;
            LevelEntryLength:@LevelEntryLength_14;
            LevelHintOffset:@LevelHintOffset_14E;
            LevelHintLength:@LevelHintLength_14
        ),(
            { Keen 4 CGA Apogee version 1.4 }
            ID:'cga-1.4';
            ImageLength:241792;
            CompImageLength:97975;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_14C;
            DataResourceLength:@DataResourceLength_14C;
            LevelNameOffset:$1CA40;
            LevelNameLength:@LevelNameLength_14;
            LevelEntryOffset:$1CBF0;
            LevelEntryLength:@LevelEntryLength_14;
            LevelHintOffset:@LevelHintOffset_14C;
            LevelHintLength:@LevelHintLength_14
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
