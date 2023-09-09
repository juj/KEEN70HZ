program CK6Patch;

{ Contains patch information for versions of Keen 6 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN6}
{$DEFINE KEEN4_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='KEEN6*.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='CK6PATCH';

    { The extension that the game uses }
    Ext='CK6';

    { Number of levels featured in this game }
    NumLevels=18;

type
    { Enumerations for each of the resources }
    TDataResource=(
        drAudioHed, { AUDIOHED, index of sound effects in AUDIO.CK6 }
        drEGAHead,  { EGAHEAD, index of sprite tiles in EGAGRAPH.CK6 }
        drMapHead,  { MAPHEAD, index of levels in GAMEMAPS.CK6 }
        drAudioDct, { AUDIODCT, huffman tree for decompressing AUDIO.CK6 }
        drEGADict,   { EGADICT, huffman tree for decompressing EGAGRAPH.CK6 }
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

    { The version information structure for Keen 6 }
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
    { Resource image offsets for EGA version 1.0 }
    DataResourceOffset_10E:TDataResourceOffset=
        ($1F820,$1FB20,$23C50,$35912,$35D12,$23DE2,$23C50);

    { Resource image offsets for EGA version 1.4 }
    DataResourceOffset_14E:TDataResourceOffset=
        ($20C50,$20F50,$25080,$36EEE,$372EE,$25212,$25080);

    { Resource image offsets for EGA version 1.5 }
    DataResourceOffset_15E:TDataResourceOffset=
        ($256B0,$259B0,$29AE0,$36B4E,$36F4E,$29C72,$29AE0);

    { Resource byte lengths for EGA versions 1.0, 1.4 and 1.5 }
    DataResourceLength_CommonE:TDataResourceLength=
        (768,16688,402,1024,1024,23918,24320);

    { Resource image offsets for CGA version 1.4 }
    DataResourceOffset_14C:TDataResourceOffset=
        ($1E830,$1EB30,$22C50,$35030,$35430,$22DE2,$22C50);

    { Resource image offsets for CGA version 1.5 }
    DataResourceOffset_15C:TDataResourceOffset=
        ($1E5A0,$1E8A0,$229C0,$34DA0,$351A0,$22B52,$229C0);

    { Resource byte lengths for CGA versions 1.0, 1.4 and 1.5 }
    DataResourceLength_CommonC:TDataResourceLength=
        (768,16672,402,1024,1024,23918,24320);

    { Level name maximum lengths, same for versions 1.0, 1.4 and 1.5 }
    LevelNameLength_Common:TLevelStringLength=
        (16,32,16,32,32,16,32,16,32,16,16,16,32,32,32,32,16,32,16);

    { Level entry name maximum lengths, same for versions 1.0, 1.4 and 1.5 }
    LevelEntryLength_Common:TLevelStringLength=
        (32,48,48,48,48,48,48,32,48,48,48,80,48,64,64,64,48,48,48);

    { Versions currently supported are 1.0, 1.4 and 1.5 }
    Version:array[0..4] of TVersion=(
        (
            { Keen 6 EGA version 1.0 }
            ID:'1.0';
            ImageLength:254768;
            CompImageLength:104906;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_10E;
            DataResourceLength:@DataResourceLength_CommonE;
            LevelNameOffset:$1DA70;
            LevelNameLength:@LevelNameLength_Common;
            LevelEntryOffset:$1DC40;
            LevelEntryLength:@LevelEntryLength_Common
        ),(
            { Keen 6 EGA version 1.4 }
            ID:'1.4';
            ImageLength:260432;
            CompImageLength:107687;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_14E;
            DataResourceLength:@DataResourceLength_CommonE;
            LevelNameOffset:$1EF40;
            LevelNameLength:@LevelNameLength_Common;
            LevelEntryOffset:$1F110;
            LevelEntryLength:@LevelEntryLength_Common
        ),(
            { Keen 6 CGA version 1.4 }
            ID:'cga-1.4';
            ImageLength:251232;
            CompImageLength:100932;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_14C;
            DataResourceLength:@DataResourceLength_CommonC;
            LevelNameOffset:$1CB70;
            LevelNameLength:@LevelNameLength_Common;
            LevelEntryOffset:$1CD40;
            LevelEntryLength:@LevelEntryLength_Common
        ),(
            { Keen 6 EGA version 1.5 }
            ID:'1.5';
            ImageLength:259632;
            CompImageLength:109026;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_15E;
            DataResourceLength:@DataResourceLength_CommonE;
            LevelNameOffset:$1EBA0;
            LevelNameLength:@LevelNameLength_Common;
            LevelEntryOffset:$1ED70;
            LevelEntryLength:@LevelEntryLength_Common
        ),(
            { Keen 6 CGA version 1.5 }
            ID:'cga-1.5';
            ImageLength:250704;
            CompImageLength:102134;
            IsPKLITECompressed:false;
            DataResourceOffset:@DataResourceOffset_15C;
            DataResourceLength:@DataResourceLength_CommonC;
            LevelNameOffset:$1C8E0;
            LevelNameLength:@LevelNameLength_Common;
            LevelEntryOffset:$1CAB0;
            LevelEntryLength:@LevelEntryLength_Common
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
