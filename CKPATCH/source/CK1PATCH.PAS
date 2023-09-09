program CK1Patch;

{ Contains patch information for versions of Keen 1 }

{$A+,B+,E-,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2304,0,0}

{$DEFINE KEEN1}
{$DEFINE KEEN1_ARCH}

uses Loader,Parser,Patcher,Misc,Dos,Strings;

const
    { The search pattern to use when looking for the game executable }
    ExecutableFileSpec='KEEN1*.EXE';

    { The name of the CKPatch program for this episode }
    ProgramName='CK1PATCH';

    { The extension that the game uses }
    Ext='CK1';

type
    { Holds the size of each line of text for the Yorp/Garg hint messages }
    PHintTextGridLineSize=^THintTextGridLineSize;
    THintTextGridLineSize=array[0..44] of Byte;

    { The offset into the text grid for each level hint message. A value of }
    { $FF in this array indicates that there is no hint message for that }
    { particular level. }
    PHintTextGridLineIndex=^THintTextGridLineIndex;
    THintTextGridLineIndex=array[1..16] of Byte;

    { The number of lines in the hint message for each level. A value of }
    { $FF in this array indicates that there is no hint message for that }
    { particular level. }
    PHintTextGridLineSpan=^THintTextGridLineSpan;
    THintTextGridLineSpan=array[1..16] of Byte;

    { The version information structure for Keen 1 }
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

        { The offset in the image of the Yorp/Garg statue hint messages }
        HintOffset:Longint;

        { The sizes of each line of text in the hint messages }
        HintTextGridLineSize:PHintTextGridLineSize;

        { The index in the text grid of each level's hint message }
        HintTextGridLineIndex:PHintTextGridLineIndex;

        { The number of lines of each level's hint message }
        HintTextGridLineSpan:PHintTextGridLineSpan;
    end;

const
    { Hint line sizes for version 1.1 }
    HintTextGridLineSize_11:THintTextGridLineSize=(
        22,22,22,22,22,22,22,   { Level 2, 7x20 chars }
        22,22,22,22,22,22,22,   { Level 6, 7x20 chars }
        22,22,22,22,22,22,22,   { Level 9, 7x20 chars }
        22,22,22,22,22,22,22,   { Level 10, 7x20 chars }
        22,22,22,22,            { Level 11, 4x20 chars }
        22,22,22,23,22,22,22,   { Level 12, 7x20 chars, line 4 is 21 chars }
        22,22,22,22,22,22       { Level 15, 6x20 chars }
        );

    { Hint grid level message indexes for version 1.1 }
    HintTextGridLineIndex_11:THintTextGridLineIndex=(
        $FF,0,$FF,$FF,$FF,7,$FF,$FF,14,21,28,32,$FF,$FF,39,$FF);

    { Hint grid level message line lengths for version 1.1 }
    HintTextGridLineSpan_11:THintTextGridLineSpan=(
        $FF,7,$FF,$FF,$FF,7,$FF,$FF,7,7,4,7,$FF,$FF,6,$FF);

    { Versions currently supported are 1.1 and 1.31 }
    Version:array[0..1] of TVersion=(
        (
            { Keen 1 version 1.1 }
            ID:'1.1';
            ImageLength:99762;
            CompImageLength:51194;
            IsPKLITECompressed:false;
            HintOffset:$15144;
            HintTextGridLineSize:@HintTextGridLineSize_11;
            HintTextGridLineIndex:@HintTextGridLineIndex_11;
            HintTextGridLineSpan:@HintTextGridLineSpan_11
        ),(
            { Keen 1 version 1.31, uses same hint grid as v1.1 }
            ID:'1.31';
            ImageLength:99972;
            CompImageLength:51158;
            IsPKLITECompressed:false;
            HintOffset:$15080;
            HintTextGridLineSize:@HintTextGridLineSize_11;
            HintTextGridLineIndex:@HintTextGridLineIndex_11;
            HintTextGridLineSpan:@HintTextGridLineSpan_11
        ));

{$I CKXPATCH.INC}

begin
    Main;
end.
