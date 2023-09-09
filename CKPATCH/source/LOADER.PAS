unit Loader;

{$A+,B+,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}

{ Simple unit for loading DOS executables in memory }

interface

type
    { Loader error status enumerated type }
    TLoaderStatus=(
        lsOk,           { No error }
        lsFileNotFound, { File was not found }
        lsFileNotEXE,   { File is not a valid .EXE file }
        lsDiskError,    { Disk error encountered while reading file }
        lsOutOfMemory,  { Insufficient memory to load executable }
        lsWrongCompInd, { Compression indicator differs from expected }
        lsUnknown       { Unknown error }
        );

const
    { Error status variable - Most functions will set this on return }
    LoaderStatus:TLoaderStatus=lsOk;

{ Returns first filename to match given wildcard, or blank if not found.    }
{ FileSpec contains the DOS wildcard specification to search for.           }
function LocateExecutable(const FileSpec:String):String;

{ Returns load image size for given executable file, 0 if not a valid .EXE. }
{ FileName contains the file name of the executable file to examine.        }
function GetLoadImageSize(const FileName:String):Longint;

{ Loads executable into memory but does not execute. Returns pointers to    }
{ image start, code entry point and initial stack location in Base, Code    }
{ and Stack respectively. FileName contains the file name of the executable }
{ file to load. CommandLine contains the command line arguments to supply   }
{ to the executable. ExecutableImageLength contains the executable's load   }
{ image size. ExpectedCompIndicator states if the EXE is expected           }
{ to be compressed or not. UsePKLITECompression states if PKLITE            }
{ was (originally) used for compressing the EXE.                            }

procedure LoadExecutable(const FileName,CommandLine:String;
    ExecutableImageLength:Longint;
    ExpectedCompIndicator:Boolean;
    UsePKLITECompression:Boolean;
    var Base,Code,Stack:Pointer);

{ Runs loaded executable image in memory. Base, Code and Stack contain the  }
{ image start, code entry point and initial stack location respectively.    }
procedure RunExecutable(Base,Code,Stack:Pointer);

{ Unloads executable from memory (only call if it hasn't executed yet).     }
{ Base points to the start of the executable image in memory.               }
procedure UnloadExecutable(Base:Pointer);

implementation

uses Dos,Strings;

const
    { Valid .EXE files have the ID field set to this magic value. In string }
    { form, this reads 'MZ', which is apparently the initials of Mark }
    { Zbikowski, one of the designers behind MS-DOS 2.0 way back in 1983. }
    ValidEXESignature=$5A4D;

    (* USED WITH OLD CODE ONLY *)
(*
    { Executables compressed with LZEXE v0.91 have this 4-byte signature at }
    { offset $001C in the .EXE file. In string form, this reads 'LZ91'. }
    ValidLZEXESignature=$31395A4C;
*)

const
    { Executables compressed with LZEXE v0.91 have this long signature }
    { at the initial CS:IP of the decompressor stub. }
    ValidLZEXE91SignatureOffset=0;
    ValidLZEXE91SignatureLen=232;
    ValidLZEXE91Signature:array[0..ValidLZEXE91SignatureLen-1] of Byte=(
      $06, $0E, $1F, $8B, $0E, $0C, $00, $8B,
      $F1, $4E, $89, $F7, $8C, $DB, $03, $1E,
      $0A, $00, $8E, $C3, $FD, $F3, $A4, $53,
      $B8, $2B, $00, $50, $CB, $2E, $8B, $2E,
      $08, $00, $8C, $DA, $89, $E8, $3D, $00,
      $10, $76, $03, $B8, $00, $10, $29, $C5,
      $29, $C2, $29, $C3, $8E, $DA, $8E, $C3,
      $B1, $03, $D3, $E0, $89, $C1, $D1, $E0,
      $48, $48, $8B, $F0, $8B, $F8, $F3, $A5,
      $09, $ED, $75, $D8, $FC, $8E, $C2, $8E,
      $DB, $31, $F6, $31, $FF, $BA, $10, $00,
      $AD, $89, $C5, $D1, $ED, $4A, $75, $05,
      $AD, $89, $C5, $B2, $10, $73, $03, $A4,
      $EB, $F1, $31, $C9, $D1, $ED, $4A, $75,
      $05, $AD, $89, $C5, $B2, $10, $72, $22,
      $D1, $ED, $4A, $75, $05, $AD, $89, $C5,
      $B2, $10, $D1, $D1, $D1, $ED, $4A, $75,
      $05, $AD, $89, $C5, $B2, $10, $D1, $D1,
      $41, $41, $AC, $B7, $FF, $8A, $D8, $E9,
      $13, $00, $AD, $8B, $D8, $B1, $03, $D2,
      $EF, $80, $CF, $E0, $80, $E4, $07, $74,
      $0C, $88, $E1, $41, $41, $26, $8A, $01,
      $AA, $E2, $FA, $EB, $A6, $AC, $08, $C0,
      $74, $34, $3C, $01, $74, $05, $88, $C1,
      $41, $EB, $EA, $89, $FB, $83, $E7, $0F,
      $81, $C7, $00, $20, $B1, $04, $D3, $EB,
      $8C, $C0, $01, $D8, $2D, $00, $02, $8E,
      $C0, $89, $F3, $83, $E6, $0F, $D3, $EB,
      $8C, $D8, $01, $D8, $8E, $D8, $E9, $72
    );

    { Executables compressed with PKLITE v1.15 have this long signature }
    { at offset 6 from the initial CS:IP of the decompressor stub. }
    ValidPKLITE115SignatureOffset=6;
    ValidPKLITE115SignatureLen=66;
    ValidPKLITE115Signature:array[0..ValidPKLITE115SignatureLen-1] of Byte=(
                                    $05, $00,
      $00, $3B, $06, $02, $00, $72, $1B, $B4,
      $09, $BA, $18, $01, $CD, $21, $CD, $20,
      $4E, $6F, $74, $20, $65, $6E, $6F, $75,
      $67, $68, $20, $6D, $65, $6D, $6F, $72,
      $79, $24, $2D, $20, $00, $8E, $D0, $2D,
      $26, $00, $50, $52, $B9, $37, $01, $BE,
      $B2, $03, $8B, $FE, $FD, $90, $49, $74,
      $07, $AD, $92, $33, $C2, $AB, $EB, $F6
    );

type
    { .EXE file header structure }
    TEXEHeader=record
        ID:Word;                { Signature field, must be $5A4D }
        ImageLengthLow:Word;    { File length modulo 512 }
        ImageLengthHigh:Word;   { File length divided by 512, rounded up }
        NumRelocs:Word;         { Number of relocation entries }
        HeaderSize:Word;        { Size of header divided by 16 }
        MinParagraphs:Word;     { Min # of paragraphs needed to run program }
        MaxParagraphs:Word;     { Desired # of paragraps program would like }
        InitSS:Word;            { Initial stack segment offset }
        InitSP:Word;            { Initial SP register value }
        Checksum:Word;          { Checksum of header, or zero }
        InitIP:Word;            { Initial code entry point offset }
        InitCS:Word;            { Initial code segment offset }
        FirstRelocOffset:Word;  { Offset in header of relocation table }
        OverlayNumber:Word;     { Overlay number, zero for main program }
    end;

    { Structure required for DOS INT 21H/4BH Exec call }
    TExec=record
        { Segment of environment block to inherit for child process }
        Environment:Word;

        { Pointer to command line arguments for child process }
        CommandLine:Pointer;

        { Pointer to FCB structures for child process }
        FCB:array[1..2] of Pointer;

        { Contains the initial SS:SP of the child process on return }
        Stack:Pointer;

        { Contains the initial CS:IP of the child process on return }
        Code:Pointer;
    end;

    { LZEXE uncompressed program information. This is a structure that is }
    { at the start of the code segment of the LZEXE decompressor routine }
    { that contains information needed for executing the uncompressed }
    { program. Although I'm aware of at least two distinct revisions of the }
    { LZEXE decompressor stub code, both seem to have the same 'LZ91' }
    { signature and the same header structure. }
    TLZEXEProgInfo=record
        { Initial IP register value for uncompressed program. }
        InitIP:Word;

        { Initial CS register value for uncompressed program. This value }
        { needs to have the base segment address added to it in order to }
        { determine the actual CS value. }
        InitCS:Word;

        { Initial SP register value for uncompressed program. }
        InitSP:Word;

        { Initial SS register value for uncompressed program. This value }
        { needs to have the base segment address added to it in order to }
        { determine the actual SS value. }
        InitSS:Word;

        { This is a field which I have no idea what it's intended for. It }
        { does get used at one point in the LZEXE decompression stub. }
        MysteryField1:Word;

        { This is the number of paragraphs which the LZEXE decompressor }
        { stub will shift itself upwards in memory by in order to let the }
        { compressed program expand. }
        ShiftParagraphs:Word;

        { This is the size of the LZEXE decompressor stub code segment. The }
        { LZEXE decompressor stub code segment consists of this header, the }
        { decompressor code itself, and the relocatable item table for the }
        { original uncompressed executable which varies in size, hence the }
        { need to know the size of the segment. }
        CodeSegSize:Word;
    end;

    { PKLITE uncompressed program information. This is a structure that is  }
    { at the end of the executable's load image, which contains information }
    { needed for executing the uncompressed program. Seems to apply to }
    { executables packed with PKLITE versions 1.05, 1.12 and 1.15. }
    TPKLITEProgInfo=record
        { Initial SS register value for uncompressed program. This value }
        { needs to have the base segment address added to it in order to }
        { determine the actual SS value. }
        InitSS:Word;

        { Initial SP register value for uncompressed program. }
        InitSP:Word;

        { Initial CS register value for uncompressed program. This value }
        { needs to have the base segment address added to it in order to }
        { determine the actual CS value. }
        InitCS:Word;

        { Initial IP register value for uncompressed program. }
        InitIP:Word;
    end;

    { Structure used to access 16-bit components of a 32-bit doubleword in }
    { memory. }
    MemLong=record
        Lo,Hi:Word;
    end;

    { Structure used to access 16-bit segment/offset components of a 32-bit }
    { real mode pointer in memory. }
    MemPtr=record
        MemOfs,MemSeg:Word;
    end;

var
    { Storage space for saving the SS, SP and BP register contents while }
    { executing the LZEXE decompression stub and the game itself. These }
    { need to be stored at a fixed location inside the DATA segment, since }
    { the stack location will get moved in the above process. }
    SaveSS,SaveSP,SaveBP:Word;

{ Checks if an executable is compressed. FileName contains the file name }
{ of the executable to check. Signature is an array with data, which }
{ is SignatureLen bytes long, and is compared to the contents beginning
{ at offset SignatureOffset after address CS:IP in the EXE image. }
{ True is returned if the executable is compressed; False is returned }
{ otherwise. Note that the file is already presumed to be an .EXE file. }
function IsCompressed(const FileName:String;var Signature:Array of Byte;SignatureLen,SignatureOffset:Integer):Boolean;
var
    { Input file variable }
    InputFile:File;

    { USED WITH OLD CODE ONLY }
(*
    { Storage for the LZEXE signature read from the executable file }
    LZEXESignature:Longint;
*)
    { Stores the .EXE file header }
    EXEHeader:TEXEHeader;

    { Ret. value (from ASM snippet) }
    RetFromAsm:Boolean;

    { Storage for the signature read from the executable file. }
    { Note the bound on the length, which is enforced below }
    { (used as an alternative to dynamic allocation). }
    Buffer:Array[0..231] of Byte;
begin
    { Initially assume the executable is not LZEXE-compressed }
    IsCompressed:=False;

    { Verify buffer has enough room }
    if SizeOf(Buffer)<SignatureLen then
    begin
        WriteLn('Error in IsCompressed: Internal buffer size of ',SizeOf(Buffer),'is too small (got ',SignatureLen,').');
        Halt;
    end;

    { Open files for reading only }
    FileMode:=0;

    { Open the executable file }
    Assign(InputFile,FileName);
    Reset(InputFile,1);

    { Check if the file opened successfully }
    if IOResult=0 then
    begin
        (* OLD CODE - Closer to behaviors of UNLZEXE 0.7 and specific to LZEXE compression *)
(*
        { Skip to offset $001C in the header and read the LZEXE signature }
        Seek(InputFile,$001C);
        BlockRead(InputFile,LZEXESignature,4);

        { Check if the signature read was successful }
        if IOResult=0 then
        begin
            { Compare the signatures and set the return status }
            IsLZEXECompressed:=(LZEXESignature=ValidLZEXESignature);
        end;
*)
        (* NEW CODE - Based on UNLZEXE 0.8 and also re-used for PKLITE-compressed EXEs *)

        { Read the header }
        BlockRead(InputFile,EXEHeader,SizeOf(TEXEHeader));

        { Check if the header read operation succeeded }
        if IOResult=0 then
        begin
            RetFromAsm:=false;
            { Seek to offset of signature and read the extended signature. }
            { Note that it's possible that $10*CS+IP is $100000, }
            { and then CS:IP effectively wraps around to 0000:0000. }
            Seek(InputFile,
                 (Longint(EXEHeader.HeaderSize) shl 4)+Longint(SignatureOffset)
                 +((Longint(EXEHeader.InitCs) shl 4)+EXEHeader.InitIP) mod $100000
            );
            { Do read signature }
            BlockRead(InputFile,Buffer,SignatureLen);
            { Check if the signature read was successful }
            if IOResult=0 then
            asm
                { Compare Buffer to Signature. Unfortunately there }
                { isn't exactly a function like C's memcmp... }

                { Note that Turbo Pascal expects the DS register }
                { to be preserved, so temporarily store }
                { its original value on the stack. }
                PUSH DS
                { Set pointers to compared buffers }
                LES DI,Signature
                MOV DX,SS
                MOV DS,DX
                LEA SI,Buffer
                { Set buffer lengths to check }
                MOV CX,[SignatureLen]
                { Clear direction flag so DI increments }
                CLD
                { Do compare buffers }
                REPE CMPSB
                JNZ @finish

                MOV [RetFromAsm],true
@finish:
                POP DS
            end;
            IsCompressed:=RetFromAsm;
        end;

        { Close the input file }
        Close(InputFile);
    end;
end;

{ Decompresses an LZEXE-compressed executable in memory. Base points to the }
{ start of the compressed executable in memory. Code contains the entry     }
{ point of the decompression stub. Stack contains the stack location of the }
{ decompression stub. On return, NewCode and NewStack will contain the      }
{ entry point and stack location of the uncompressed program.               }
procedure DecompressLZEXEExecutable(
    Base,Code,Stack:Pointer;var NewCode,NewStack:Pointer); assembler;
asm
    { Patch the decompressor stub header in memory so it will make a far }
    { jump back to us instead of jumping to the entry point of the }
    { uncompressed program. Nifty trick, eh? :) Saves me from having to }
    { implement my own LZEXE decompressor, something I actually once tried }
    { to do from scratch several years ago, before I stumbled across UNP. }
    { Needless to say, that attempt never succeeded. I've still got my }
    { annotated dissassembly printouts of the LZEXE decompressor stub, }
    { helped me write this routine here. It's amazing how it manages to get }
    { the whole job done in just 330 bytes. }

    { Turbo Pascal expects the BP register to be preserved }
    MOV SaveBP,BP

    { DS will point to the code segment of the decompressor stub }
    MOV DS,MemPtr(Code).MemSeg

    { SI will contain the base segment address of the program }
    MOV SI,MemPtr(Base).MemSeg

    { Load unadjusted entry point of the uncompressed program into DX:AX. }
    { Relocate the entry point and save it into NewCode. }
    MOV AX,TLZEXEProgInfo([$0000]).InitIP
    MOV DX,TLZEXEProgInfo([$0000]).InitCS
    ADD DX,SI
    LES DI,NewCode
    MOV MemPtr(ES:[DI]).MemOfs,AX
    MOV MemPtr(ES:[DI]).MemSeg,DX

    { Load unadjusted stack location of the uncompressed program into }
    { DX:AX. Relocate the stack location and save it into NewStack. }
    MOV AX,TLZEXEProgInfo([$0000]).InitSP
    MOV DX,TLZEXEProgInfo([$0000]).InitSS
    ADD DX,SI
    LES DI,NewStack
    MOV MemPtr(ES:[DI]).MemOfs,AX
    MOV MemPtr(ES:[DI]).MemSeg,DX

    { Now patch the uncompressed program entry point in the LZEXE program }
    { header so it will jump back to us instead of the uncompressed }
    { program when it's done decompressing and fixing the relocatable }
    { items. }
    MOV TLZEXEProgInfo([$0000]).InitIP,OFFSET @ReturnPoint
    MOV TLZEXEProgInfo([$0000]).InitCS,SEG @ReturnPoint
    SUB TLZEXEProgInfo([$0000]).InitCS,SI

    { Also patch the uncompressed program stack location in the LZEXE }
    { program header so it will restore the stack back to ours when it }
    { returns. While I could save the SS and SP registers myself, I just }
    { wanted to let the LZEXE decompressor stub itself do this task }
    { instead, just to show to myself how well I understand the workings }
    { of the stub :) }
    MOV TLZEXEProgInfo([$0000]).InitSP,SP
    MOV TLZEXEProgInfo([$0000]).InitSS,SS
    SUB TLZEXEProgInfo([$0000]).InitSS,SI

    { Load the decompression stub stack location into DX:AX and the entry }
    { point into BX:CX. Switch stacks and push the stub entry point onto }
    { the stack so we can pop it off when we jump to the stub routine. }
    MOV AX,MemPtr(Stack).MemOfs
    MOV DX,MemPtr(Stack).MemSeg
    MOV CX,MemPtr(Code).MemOfs
    MOV BX,MemPtr(Code).MemSeg
    MOV SS,DX
    MOV SP,AX
    PUSH BX
    PUSH CX

    { SI now contains the PSP segment address of the child process }
    SUB SI,$0010

    { Set DS and ES to point to the PSP segment of the child process. Zero }
    { out all the other registers, since all DOS programs expect them to be }
    { set to zero when launched. Then jump (or is that return?) to the }
    { decompression stub entry point. }
    MOV DS,SI
    MOV ES,SI
    XOR AX,AX
    XOR BX,BX
    XOR CX,CX
    XOR DX,DX
    XOR SI,SI
    XOR DI,DI
    XOR BP,BP
    RETF

    { --- Child program will return here when it terminates --- }
@ReturnPoint:

    { Restore DS and BP registers }
    MOV AX,SEG @Data
    MOV DS,AX
    MOV BP,SaveBP
end;

{ Decompresses a PKLITE-compressed executable in memory. Base points to the  }
{ start of the compressed executable in memory. Code contains the entry      }
{ point of the decompression stub. Stack contains the stack location of the  }
{ decompression stub. ProgInfo contains the location of the program info     }
{ after the compressed data. On return, NewCode and NewStack will contain    }
{ the entry point and stack location of the uncompressed program.            }
procedure DecompressPKLITEExecutable(
    Base,Code,Stack,ProgInfo:Pointer;var NewCode,NewStack:Pointer); assembler;
asm
    { Patch the decompressor stub header in memory so it will make a far }
    { jump back to us instead of jumping to the entry point of the }
    { uncompressed program. This should be similar to DecompressLZEXEExecutable. }

    { Turbo Pascal expects the BP register to be preserved }
    MOV SaveBP,BP

    { DS will point to the code segment of the program data }
    MOV DS,MemPtr(ProgInfo).MemSeg

    { BX will point to the code offset of the program data }
    MOV BX,MemPtr(ProgInfo).MemOfs

    { SI will contain the base segment address of the program }
    MOV SI,MemPtr(Base).MemSeg

    { Load unadjusted entry point of the uncompressed program into DX:AX. }
    { Relocate the entry point and save it into NewCode. }
    MOV AX,TPKLITEProgInfo([BX]).InitIP
    MOV DX,TPKLITEProgInfo([BX]).InitCS
    ADD DX,SI
    LES DI,NewCode
    MOV MemPtr(ES:[DI]).MemOfs,AX
    MOV MemPtr(ES:[DI]).MemSeg,DX

    { Load unadjusted stack location of the uncompressed program into }
    { DX:AX. Relocate the stack location and save it into NewStack. }
    MOV AX,TPKLITEProgInfo([BX]).InitSP
    MOV DX,TPKLITEProgInfo([BX]).InitSS
    ADD DX,SI
    LES DI,NewStack
    MOV MemPtr(ES:[DI]).MemOfs,AX
    MOV MemPtr(ES:[DI]).MemSeg,DX

    { Now patch the uncompressed program entry point in the PKLITE program }
    { footer so it will jump back to us instead of the uncompressed }
    { program when it's done decompressing and fixing the }
    { relocatable items. }
    MOV TPKLITEProgInfo([BX]).InitIP,OFFSET @ReturnPoint
    MOV TPKLITEProgInfo([BX]).InitCS,SEG @ReturnPoint
    SUB TPKLITEProgInfo([BX]).InitCS,SI

    { Also patch the uncompressed program stack location in the PKLITE }
    { program footer so it will restore the stack back to ours when it }
    { returns. }
    MOV TPKLITEProgInfo([BX]).InitSP,SP
    MOV TPKLITEProgInfo([BX]).InitSS,SS
    SUB TPKLITEProgInfo([BX]).InitSS,SI

    { Load the decompression stub stack location into DX:AX and the entry }
    { point into BX:CX. Switch stacks and push the stub entry point onto }
    { the stack so we can pop it off when we jump to the stub routine. }
    MOV AX,MemPtr(Stack).MemOfs
    MOV DX,MemPtr(Stack).MemSeg
    MOV CX,MemPtr(Code).MemOfs
    MOV BX,MemPtr(Code).MemSeg
    MOV SS,DX
    MOV SP,AX
    PUSH BX
    PUSH CX

    { SI now contains the PSP segment address of the child process }
    SUB SI,$0010

    { Set DS and ES to point to the PSP segment of the child process. Zero }
    { out all the other registers, since all DOS programs expect them to be }
    { set to zero when launched. Then jump (or is that return?) to the }
    { decompression stub entry point. }
    MOV DS,SI
    MOV ES,SI
    XOR AX,AX
    XOR BX,BX
    XOR CX,CX
    XOR DX,DX
    XOR SI,SI
    XOR DI,DI
    XOR BP,BP
    RETF

    { --- Child program will return here when it terminates --- }
@ReturnPoint:

    { Restore DS and BP registers }
    MOV AX,SEG @Data
    MOV DS,AX
    MOV BP,SaveBP
end;

function LocateExecutable(const FileSpec:String):String;
var
    { Holds search state information when looking for files }
    Search:SearchRec;
begin
    { Find the first file that matches the given wildcard }
    FindFirst(FileSpec,AnyFile,Search);

    if DosError=0 then
    begin
        { Match was found. Return the matching executable file name. }
        LocateExecutable:=Search.Name;
        LoaderStatus:=lsOk;
    end else begin
        { No match was found. Return blank string and flag an error. }
        LocateExecutable:='';
        LoaderStatus:=lsFileNotFound;
    end;
end;

function GetLoadImageSize(const FileName:String):Longint;
var
    { Stores the .EXE file header }
    EXEHeader:TEXEHeader;

    { Input file variable }
    InputFile:File;
begin
    { Initially assume that the operation was not successful }
    GetLoadImageSize:=0;

    { Open files for reading only }
    FileMode:=0;

    { Open the executable file }
    Assign(InputFile,FileName);
    Reset(InputFile,1);

    if IOResult=0 then
    begin
        { Read the header }
        BlockRead(InputFile,EXEHeader,SizeOf(TEXEHeader));

        { Check if the header read operation succeeded }
        if IOResult=0 then
        begin
            { Check if the ID field matches the required magic value }
            if EXEHeader.ID=ValidEXESignature then
            begin
                { Compute the size of the .EXE file image. This is done by }
                { obtaining the supposed file length from the .EXE header }
                { and subtracting the length of the header from it. }
                GetLoadImageSize:=Longint(EXEHeader.ImageLengthHigh-1)*512
                    +Longint(EXEHeader.ImageLengthLow)
                    -Longint(EXEHeader.HeaderSize*16);
                LoaderStatus:=lsOk;
            end else begin
                { The executable doesn't have the required magic value in }
                { its header ID field, so it isn't a valid .EXE file. }
                LoaderStatus:=lsFileNotEXE;
            end;
        end else begin
            { Encountered a disk error while reading the executable header }
            LoaderStatus:=lsDiskError;
        end;

        { Close the executable file }
        Close(InputFile);
    end else begin
        { The executable file was not found }
        LoaderStatus:=lsFileNotFound;
    end;
end;

procedure LoadExecutable(const FileName,CommandLine:String;
    ExecutableImageLength:Longint;
    ExpectedCompIndicator:Boolean;
    UsePKLITECompression:Boolean;
    var Base,Code,Stack:Pointer);
var
    { Paragraph address of child Program Segment Prefix (PSP) }
    ChildPrefixSeg:Word;

    { The executable file name, as a null-terminated string }
    ASCIIZProgramName:array[0..63] of Char;

    { The command line arguments, as a null-terminated string }
    ASCIIZCommandLine:array[0..127] of Char;

    { Structure used for the DOS INT 21H/4BH Exec call }
    ProgramExec:TExec;

    { This flag will be set if the executable is compressed }
    CompressedFlag:Boolean;
begin
    { Check if the executable is compressed }
    if UsePKLITECompression then
        CompressedFlag:=IsCompressed(FileName,ValidPKLITE115Signature,ValidPKLITE115SignatureLen,ValidPKLITE115SignatureOffset)
    else
        CompressedFlag:=IsCompressed(FileName,ValidLZEXE91Signature,ValidLZEXE91SignatureLen,ValidLZEXE91SignatureOffset);

    if CompressedFlag<>ExpectedCompIndicator then
    begin;
        LoaderStatus:=lsWrongCompInd;
        Exit;
    end;

    { Convert the executable file name and command line arguments into }
    { null-terminated strings so they can be passed to DOS }
    StrPCopy(ASCIIZProgramName,FileName);
    StrPCopy(ASCIIZCommandLine,CommandLine);

    { Let the child process inherit our own environment and FCB structures }
    ProgramExec.Environment:=0;
    ProgramExec.CommandLine:=@ASCIIZCommandLine;
    ProgramExec.FCB[1]:=Ptr(PrefixSeg,$005C);
    ProgramExec.FCB[2]:=Ptr(PrefixSeg,$006C);

    { Load executable as child process into memory, but do not execute. }
    { This is done using DOS interrupt 21H, service 4BH, subservice 01H }
    { (load but don't execute). DS:DX points to the executable file name as }
    { a null-terminated string. ES:BX points to the ProgramExec structure }
    { that contains the command line arguments, environment block and FCB }
    { structures for the child process, and will contain the initial entry }
    { point and stack location of the child process on return. When the }
    { call returns, the carry flag will be set if an error occured. If }
    { there was one, then AX will contain the DOS error code. We will }
    { record this error code in the DOSError global variable. If no error }
    { occured, then DOSError will be set to zero. Note that Turbo Pascal }
    { expects the DS register to be preserved so we have to save it on the }
    { stack temporarily. }
    asm
        PUSH DS
        MOV AX,SS
        MOV DS,AX
        MOV ES,AX
        LEA DX,ASCIIZProgramName
        LEA BX,ProgramExec
        MOV AX,$4B01
        INT $21
        POP DS
        JNC @NoError
    @Error:
        MOV DOSError,AX
        JMP @Done
    @NoError:
        MOV DOSError,0
    @Done:
    end;

    { Check if the load operation succeeded }
    if DOSError=0 then
    begin
        asm
            { Get the prefix segment of the child process }
            MOV AH,$62
            INT $21
            MOV ChildPrefixSeg,BX

            { Set current prefix segment back to our own }
            MOV BX,PrefixSeg
            MOV AH,$50
            INT $21
        end;

        { Obtain the base, code and stack pointers }
        Base:=Ptr(ChildPrefixSeg+$10,$0000);
        Code:=ProgramExec.Code;
        Stack:=ProgramExec.Stack;
        LoaderStatus:=lsOk;

        { Check if the executable needs decompressing }
        if CompressedFlag then
        begin
            { Decompress the executable in memory and obtain the stack and }
            { entry point for the uncompressed executable. }
            if UsePKLITECompression then
                DecompressPKLITEExecutable(Base,Code,Stack,
                    Ptr(MemPtr(Base).MemSeg+((ExecutableImageLength-SizeOf(TPKLITEProgInfo)) shr 4)
                        ,((ExecutableImageLength-SizeOf(TPKLITEProgInfo)) and 15)
                    ),
                    Code,Stack
                )
            else
                DecompressLZEXEExecutable(Base,Code,Stack,Code,Stack);
        end;
    end else begin
        { There was an error while loading the executable }
        case DOSError of
            2: LoaderStatus:=lsFileNotFound;
            8: LoaderStatus:=lsOutOfMemory;
            else LoaderStatus:=lsUnknown;
        end;
    end;
end;

procedure RunExecutable(Base,Code,Stack:Pointer); assembler;
asm
    { Set active process back to child }
    MOV BX,MemPtr(Base).MemSeg
    SUB BX,$0010
    MOV AH,$50
    INT $21

    { Set INT 22 return address for child process. ES will contain the }
    { segment address of the child process PSP. }
    MOV BX,MemPtr(Base).MemSeg
    SUB BX,$0010
    MOV ES,BX
    MOV MemPtr(ES:[$000A]).MemOfs,OFFSET @ReturnPoint
    MOV MemPtr(ES:[$000A]).MemSeg,SEG @ReturnPoint

    { Turbo Pascal expects the SS, SP and BP registers to be preserved }
    MOV SaveBP,BP
    MOV SaveSS,SS
    MOV SaveSP,SP

    { Switch the stack over to the one used by the child process. Push the }
    { entry point of the child process onto the new stack, so we can use a }
    { far return instruction to jump to the child process entry point. }
    MOV AX,MemPtr(Stack).MemOfs
    MOV DX,MemPtr(Stack).MemSeg
    MOV CX,MemPtr(Code).MemOfs
    MOV BX,MemPtr(Code).MemSeg
    MOV SS,DX
    MOV SP,AX
    PUSH BX
    PUSH CX

    { Set DS to point to the PSP segment of the child process, which ES }
    { already contains. Zero out all the other registers, since all DOS }
    { programs expect the registers to be set to zero when launched. Then }
    { jump (or is that return?) to the child process entry point. }
    MOV AX,ES
    MOV DS,AX
    XOR AX,AX
    XOR BX,BX
    XOR CX,CX
    XOR DX,DX
    XOR SI,SI
    XOR DI,DI
    XOR BP,BP
    RETF

    { --- Child program will return here when it terminates --- }
@ReturnPoint:

    { Restore the DS, SS, SP and BP registers to satisfy Turbo Pascal }
    MOV AX,SEG @Data
    MOV DS,AX
    MOV BP,SaveBP
    MOV SS,SaveSS
    MOV SP,SaveSP
end;

procedure UnloadExecutable(Base:Pointer); assembler;
asm
    { Free the memory block owned by the child process }
    MOV AX,MemPtr(Base).MemSeg
    SUB AX,$0010
    MOV ES,AX
    MOV AH,$49
    INT $21
end;

end.
