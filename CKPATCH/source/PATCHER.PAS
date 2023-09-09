unit Patcher;

{$A+,B+,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}

{ Simple unit for patching DOS executables in memory }

interface

const
    { Used to tell PatchFile to read as many bytes as possible }
    MaxInputLength=$7FFFFFFF;

type
    { Patcher error status codes }
    TPatcherStatus=(
        ptsOk,                  { No error }
        ptsFileNotFound,        { Can't find patch data file }
        ptsFileCreateError,     { Can't create dump file }
        ptsDiskError,           { Disk error while reading/writing }
        ptsOutOfSpace,          { Insufficient space for dump file }
        ptsMessageTruncated,    { Message was too long }
        ptsUnknown              { Unknown error }
        );

const
{ Error status variable, set by all functions appropiately }
    PatcherStatus:TPatcherStatus=ptsOk;

{ Sets base memory location for patching offsets. NewBase contains the      }
{ memory location to use as the new base memory location. The Offset        }
{ parameter in all other patching functions is taken to be an offset from   }
{ the base memory location. This procedure must be called before calling    }
{ any other patching functions, otherwise undefined behaviour will result.  }
procedure SetPatcherBase(NewBase:Pointer);

{ Writes a multi-line message into a text grid. A text grid is a sequence   }
{ of null-terminated strings in memory, referred to as grid rows. Each grid }
{ row has a maximum length that is independent of all other grid rows. Grid }
{ rows are consecutively numbered from zero. The memory offset of the first }
{ character of a grid row is the byte after the last character of the       }
{ previous grid row. Each grid row must be terminated by a LF (ASCII 10)    }
{ and NULL (ASCII 0) byte, so the maximum number of characters that can be  }
{ written into a grid row is two less than its actual length. Grid rows     }
{ that hold less characters than their maximum will be padded with spaces   }
{ to the right.                                                             }
{                                                                           }
{ Offset contains the linear memory offset of the first grid row. StartLine }
{ contains the first grid row number to write the message to. NumLines      }
{ contains the number of grid rows that the message spans. LineSize points  }
{ to an array that contains the maximum length of each grid row (including  }
{ the LF+NULL terminator characterts. Message contains the text to write    }
{ into the text grid, each line is delimited by LF characters. If the       }
{ number of lines in the message is less than NumLines, then the remaining  }
{ grid rows will be space-padded. If the message contains more lines than   }
{ NumLines, or a line in the message overflows a grid row, then             }
{ PatcherStatus will be set to ptsMessageTruncated on return.               }
procedure PatchTextGrid(Offset:Longint;StartLine,NumLines:Integer;
    var LineSize:array of Byte;const Message:String);

{ Writes a null-terminated string. Offset contains the linear memory offset }
{ of the start of the null terminated string. MaxLength contains the        }
{ maximum length of the null-terminated string, including the NULL          }
{ terminator byte. Message contains the characters to write to the          }
{ null-terminated string. If Message contains more characters than          }
{ MaxLength minus one, then PatcherStatus will be set to                    }
{ ptsMessageTruncated on return.                                            }
procedure PatchASCIIZ(Offset:Longint;MaxLength:Word;const Message:String);

{ Loads patch data from a binary file into a given memory location. Offset  }
{ contains the linear memory offset at which to load the patch data at.     }
{ InputSeek contains the offset which to seek forward into the file before  }
{ loading it into memory, specify 0 to load from the start of the file.     }
{ InputLength contains the maximum number of bytes to read into memory,     }
{ specify MaxInputLength to read as many bytes as possible. FileName        }
{ contains the name of the file to load. Check the PatcherStatus variable   }
{ on return to see if any errors were encountered while loading the file.   }
procedure PatchFile(Offset,InputSeek,InputLength:Longint;
    const InputFileName:String);

{ Patches from an array of byte values. This simply copies an array of      }
{ bytes to a location in memory. Offset contains the linear memory offset   }
{ at which to copy the byte array to. Length specifies the length of the    }
{ byte array. Data points to the actual byte array to copy.                 }
procedure PatchBytes(Offset:Longint;Length:Word;var Data:array of Byte);

{ Dumps program image to a disk file for debugging purposes. Offset         }
{ contains the linear memory offset at which to start writing memory        }
{ contents to file. OutputLength contains the number of bytes beginning     }
{ from Offset to write to the file. OutputFileName contains the name of the }
{ file to write the memory contents to. Check the PatcherStatus variable on }
{ return to see if any errors were encountered while writing the file.      }
procedure WriteImage(Offset,OutputLength:Longint;
    const OutputFileName:String);

implementation

uses Strings;

const
    { Maximum size for individual BlockRead/BlockWrite requests }
    TransferBlockSize=65520;

type
    { Structure used to access 16-bit components of a doubleword }
    MemLong=record
        Lo,Hi:Word;
    end;

    { Structure used to access 16-bit segment/offset components of a pointer }
    MemPtr=record
        MemOfs,MemSeg:Word;
    end;

var
    { Base memory pointer for patching routines }
    PatcherBase:Pointer;

{ Returns a normalised pointer. Normalising a pointer in 16-bit 80x86 }
{ architecture involves adding the upper 12 bits of the offset component to }
{ the segment component, then zeroing out the upper 12 bits of the segment }
{ component. This keeps the pointer pointing to the same memory location as }
{ before, but allows you to access at least up to 65,520 bytes beyond it }
{ using the same segment address. }
function Normalise(P:Pointer):Pointer; assembler;
asm
    MOV BX,MemPtr(P).MemOfs
    MOV DX,MemPtr(P).MemSeg
    MOV AX,BX
    AND AX,$000F
    MOV CL,4
    SHR BX,CL
    ADD DX,BX
end;

{ Returns PatcherBase+Offset as a normalised pointer. This function }
{ computes the memory location that is LinearOffset bytes beyond }
{ PatcherBase, then normalises the pointer for convenience. }
function PointerOffset(LinearOffset:Longint):Pointer; assembler;
asm
    { Convert PatcherBase to a linear memory offset in DX:AX }
    MOV AX,16
    MUL MemPtr(PatcherBase).MemSeg
    ADD AX,MemPtr(PatcherBase).MemOfs
    ADC DX,$0000

    { Add LinearOffset to DX:AX }
    ADD AX,MemLong(LinearOffset).Lo
    ADC DX,MemLong(LinearOffset).Hi

    { Convert DX:AX to a normalised segment:offset index }
    AND DX,$000F
    MOV BX,AX
    AND BX,$000F
    MOV CX,16
    DIV CX
    MOV DX,AX
    MOV AX,BX
end;

procedure SetPatcherBase(NewBase:Pointer);
begin
    PatcherBase:=NewBase;
end;

procedure PatchTextGrid(Offset:Longint;StartLine,NumLines:Integer;
    var LineSize:array of Byte;const Message:String);
var
    { Points to the start of the text grid }
    Dest:PChar;

    { The current character index in Message }
    SourceIndex:Integer;

    { The current character offset in the text grid }
    DestIndex:Integer;

    { The current grid row that is being written to }
    CurrentRow:Integer;

    { The number of characters in the current grid row }
    CurrentColumn:Integer;

    { Used as a loop counter variable }
    I:Integer;
begin
    { Find the memory offset of the first character in the first grid row }
    { to write to. }
    for I:=0 to StartLine-1 do
    begin
        Inc(Offset,LineSize[I]);
    end;
    Dest:=PointerOffset(Offset);

    { Prepare to start writing the message into the text grid }
    CurrentColumn:=0;
    CurrentRow:=0;
    SourceIndex:=1;
    DestIndex:=0;
    PatcherStatus:=ptsOk;

    { Each loop iteration deals with one character in Message string }
    while (SourceIndex<=Length(Message)) and (CurrentRow<NumLines) do
    begin
        { Check if we encountered a newline delimiter in the message string }
        if Message[SourceIndex]=#10 then
        begin
            { If there are still characters left in the current grid row, }
            { then pad them out with spaces. }
            while CurrentColumn<LineSize[StartLine+CurrentRow]-2 do
            begin
                Dest[DestIndex]:=#32;
                Inc(DestIndex);
                Inc(CurrentColumn);
            end;

            { Terminate the current grid row with a LF+NULL byte sequence, }
            { then move on to the next grid row. }
            Dest[DestIndex]:=#10;
            Dest[DestIndex+1]:=#0;
            Inc(DestIndex,2);
            CurrentColumn:=0;
            Inc(CurrentRow);
        end else begin
            { Writing an ordinary character. Check if there is enough room }
            { on the current grid row first. }
            if CurrentColumn<LineSize[StartLine+CurrentRow]-2 then
            begin
                { If there is sufficient room on the current grid row for }
                { the current character in the message string, write it }
                { to the grid row and advance the grid row character }
                { current position. }
                Dest[DestIndex]:=Message[SourceIndex];
                Inc(DestIndex);
                Inc(CurrentColumn);
            end else begin
                { The current line in the message overflowed the current }
                { grid row, flag an error condition. }
                PatcherStatus:=ptsMessageTruncated;
            end;
        end;

        { Get next character from message }
        Inc(SourceIndex);
    end;

    { Fill all remaining characters in the current grid row and any further }
    { unused grid rows with spaces. }
    while CurrentRow<NumLines do
    begin
        { Pad the current grid row with spaces if needed }
        while CurrentColumn<LineSize[StartLine+CurrentRow]-2 do
        begin
            Dest[DestIndex]:=#32;
            Inc(DestIndex);
            Inc(CurrentColumn);
        end;

        { Terminate the current grid row with a LF+NULL sequence and move }
        { on to the next unused grid row. }
        Dest[DestIndex]:=#10;
        Dest[DestIndex+1]:=#0;
        Inc(DestIndex,2);
        CurrentColumn:=0;
        Inc(CurrentRow);
    end;

    if SourceIndex<=Length(Message) then
    begin
        { If there are still characters in the message that have not been }
        { written into the text grid, then flag an error condition, since }
        { the message overflowed the allocated space in the text grid. }
        PatcherStatus:=ptsMessageTruncated;
    end;
end;

procedure PatchASCIIZ(Offset:Longint;MaxLength:Word;const Message:String);
begin
    { Check if the message exceeds the maximum string length }
    if Length(Message)>MaxLength-1 then
    begin
        { If the message exceeds the maximum string length, then truncate }
        { it to the maximum length and flag an error condition. }
        StrPCopy(PointerOffset(Offset),Copy(Message,1,MaxLength-1));
        PatcherStatus:=ptsMessageTruncated;
    end else begin
        { The message is less than or equal to the maximum string length. }
        { Write the message and return successful status. }
        StrPCopy(PointerOffset(Offset),Message);
        PatcherStatus:=ptsOk;
    end;
end;

procedure PatchFile(Offset,InputSeek,InputLength:Longint;
    const InputFileName:String);
var
    { The input file variable }
    InputFile:File;

    { The size of the next block to read from the file }
    InputBufSize:Word;
begin
    { Initially assume successful status }
    PatcherStatus:=ptsOk;

    { Open the file in read-only mode }
    FileMode:=0;
    Assign(InputFile,InputFileName);
    Reset(InputFile,1);

    { Check if the file was successfully opened }
    if IOResult=0 then
    begin
        { Seek to the start offset in the file }
        Seek(InputFile,InputSeek);

        { Check if there's less bytes remaining in the file than specified }
        if FileSize(InputFile)-InputSeek<InputLength then
        begin
            { Adjust the InputLength parameter so we don't end up trying to }
            { read beyond the end of the input file. }
            InputLength:=FileSize(InputFile)-InputSeek;
        end;

        { Initially try to read as many bytes as possible }
        InputBufSize:=TransferBlockSize;

        { Keep reading blocks from the file until we hit the end of the }
        { file or encounter a disk error. }
        while (InputLength>0) and (PatcherStatus=ptsOk) do
        begin
            { Check if the number of bytes remaining in the file is less }
            { than the maximum transfer block size. }
            if InputLength<TransferBlockSize then
            begin
                { If there are less bytes remaining in the file than the }
                { maximum transfer block size, then reduce the transfer }
                { block size to avoid an end-of-file overrun error. }
                InputBufSize:=InputLength;
            end;

            { Read as many bytes from the file as possible into memory }
            BlockRead(InputFile,PointerOffset(Offset)^,InputBufSize);

            { Check if the last read operation succeeded }
            if IOResult=0 then
            begin
                { The last read operation succeeded, so advance to the next }
                { block in the input file. }
                Inc(Offset,InputBufSize);
                Dec(InputLength,InputBufSize);
            end else begin
                { A disk error occurred, so flag an error condition and }
                { stop reading the file. }
                PatcherStatus:=ptsDiskError;
            end;
        end;

        { Close the input file }
        Close(InputFile);
    end else begin
        { The file was not found, so flag an error condition. }
        PatcherStatus:=ptsFileNotFound;
    end;
end;

procedure PatchBytes(Offset:Longint;Length:Word;var Data:array of Byte);
begin
    { Copy the byte array into the target memory location }
    Move(Data,PointerOffset(Offset)^,Length);

    { Nothing can go wrong here, so return successful status }
    PatcherStatus:=ptsOk;
end;

procedure WriteImage(Offset,OutputLength:Longint;
    const OutputFileName:String);
var
    { The output file variable }
    OutputFile:File;

    { The size of the next block to write to the file }
    OutputBufSize:Word;
begin
    { Initially assume successful status }
    PatcherStatus:=ptsOk;

    { Create the output file }
    Assign(OutputFile,OutputFileName);
    Rewrite(OutputFile,1);

    { Check if the create operation succeeded }
    if IOResult=0 then
    begin
        { Initially try to write as many bytes as possible }
        OutputBufSize:=TransferBlockSize;

        { Keep writing blocks of bytes to the file until we reach the end }
        { of the memory block range or encounter a disk error. }
        while (OutputLength>0) and (PatcherStatus=ptsOk) do
        begin
            { Check if the number of bytes remaining in the memory block }
            { is smaller than the maximum transfer block size }
            if OutputLength<TransferBlockSize then
            begin
                { If there are less bytes remaining in the memory block }
                { range than the maximum transfer block size, then reduce }
                { the transfer block size to avoid writing too many bytes. }
                OutputBufSize:=OutputLength;
            end;

            { Write as many bytes as possible from memory to the file }
            BlockWrite(OutputFile,PointerOffset(Offset)^,OutputBufSize);

            { Check if the last write operation succeeded }
            if IOResult=0 then
            begin
                { The last write operation succeeded, so advance to the }
                { next block in the memory range. }
                Inc(Offset,OutputBufSize);
                Dec(OutputLength,OutputBufSize);
            end else begin
                { Insufficient disk space to write the output file, so flag }
                { an error condition and stop writing the file. }
                PatcherStatus:=ptsOutOfSpace;
            end;
        end;

        { Close the output file }
        Close(OutputFile);
    end else begin
        { The output file could not be created, so flag an error. }
        PatcherStatus:=ptsFileCreateError;
    end;
end;

end.
