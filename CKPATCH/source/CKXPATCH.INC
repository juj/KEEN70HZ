{ This file contains common code that is used by each of the six patching   }
{ programs. It contains the main program body responsible for parsing       }
{ command-line arguments and script file routines, and facilitating         }
{ loading and executing the game. Note that this file is not compilable by  }
{ itself, it needs to be included by each of the six patch program source   }
{ files (CKxPATCH.PAS).                                                     }
{                                                                           }
{ Note that the symbol KEENx will be defined to indicate which episode is   }
{ to be supported by the target CKPatch executable that is being compiled,  }
{ where x is the episode number. The symbol KEEN1_ARCH will also be defined }
{ if episodes 1, 2 or 3 are being targeted. The symbol KEEN4_ARCH will also }
{ be defined if episodes 4, 5 or 6 are being targeted.                      }

const
    { Components of the help message that are subject to change }
    ProgramVersion='v0.11.3 beta';
    CopyrightDate='2001-2016';
    AuthorEmail='rodgersb@ses.curtin.edu.au, me@andy.durdin.net';

    { The help message for CKPatch }
    HelpMessage=
        'Commander Keen Patch-Loading Utility '+ProgramVersion+#13#10
        +'Copyright (C) '+CopyrightDate
        +' Bryan Rodgers <'+AuthorEmail+'>'+#13#10
        +#13#10
        +'Usage: '+ProgramName+' {patchfile|patchdir} [game arguments]';

    { The name of the patch file to use inside the given directory when }
    { the user specifies a directory on the command line. }
    DefaultPatchScript='PATCH.PAT';

    { This is the maximum length of the byte string supplied as the }
    { argument to the %patch macro. }
    MaxPatchByteArraySize=256;

type
    { All variables in this structure pertain to program state. There }
    { should be only one instance of this structure. }
    TOptions=record
        { Base contains a pointer to the start of the program image in }
        { memory. All byte offsets specified by the %patch and %patchfile }
        { macros are relative to this pointer. Code and Stack contain the }
        { initial entry point and stack location for the game executable. }
        Base,Code,Stack:Pointer;

        { Points to the version information structure of the game version }
        { that was detected. Note that the TVersion structure differs for }
        { each of the six Keen episodes. }
        CurrentVersion:PVersion;

        { States if the loaded executable is compressed }
        IsCompressed:Boolean;

        { During ParsePatchScript, this variable will be set to true if }
        { patching the executable in memory is enabled. Patching can be }
        { disabled by the %version command so patches that are targeted at }
        { other game executable versions get parsed but aren't performed. }
        VersionEnabled:Boolean;

        { File name of the patch script }
        ScriptFileName:String[79];

        { This is the base path of all file specifications in the patch }
        { file. All relative paths are to be taken from this directory. }
        { This string must be readily appendable in order to generate }
        { file names relative to the base path. That is, it must end in }
        { a backslash unless the base path is the null string. }
        ScriptBaseDir:String[79];
    end;

    { Structure used to access 16-bit segment/offset components of a 32-bit }
    { real mode pointer in memory. }
    MemPtr=record
        MemOfs,MemSeg:Word;
    end;

const
    { Messages to use for various parser errors }
    ParserStatusMessage:
        array[Low(TParserStatus)..High(TParserStatus)] of PChar=(
        'No error',                         { prsOk }
        'Error opening file',               { prsErrorOpeningFile }
        'Missing expected parameter',       { prsEndOfFile }
        'Invalid numeric format',           { prsInvalidNumericFormat }
        'Missing expected parameter',       { prsMissingParameter }
        'Parameter is too long',            { prsParameterTooLong }
        'Command expected here',            { prsCommandExpected }
        'Terminating double quote missing', { prsMissingQuote }
        'End of line expected here',        { prsEOLExpected }
        'Whitespace expected here'          { prsWhitespaceExpected }
        );

    { Messages to use for various patcher errors }
    PatcherStatusMessage:
        array[Low(TPatcherStatus)..High(TPatcherStatus)] of PChar=(
        'No error',                         { ptsOk }
        'File not found',                   { ptsFileNotFound }
        'File creation error',              { ptsFileCreationError }
        'Disk error while reading file',    { ptsDiskError }
        'Out of disk space',                { ptsOutOfSpace }
        'Message is too long',              { ptsMessageTruncated }
        'Unknown error'                     { ptsUnknown }
        );

var
    { Contains program state information. Normally when writing programs, }
    { I'd actually allocate such a structure on the stack (as a local in }
    { the main procedure) and pass around a reference to each other }
    { procedure that needs to read or modify the state, so we can prevent }
    { procedures that don't need the state information from having access }
    { to it. However in the case of CKPatch, memory is at a tight premium, }
    { and the machine code required to push and dereference reference }
    { parameters on the stack for each procedure is costly. In this case, }
    { it's better to place this structure in the data segment so it has a }
    { constant memory address, which will generate smaller code. }
    Options:TOptions;

{$IFDEF KEEN1_ARCH}
const
    { Maximum number of level files that can be redirected }
    MaxLevelFileCount=24;

type
    { Enumerations for each of the data files }
    TDataFile=(
        dfEGAHead,  { EGAHEAD.CK?, tile index }
        dfEGASprit, { EGASPRIT.CK?, foreground sprite tiles }
        dfEGALatch  { EGALATCH.CK?, background sprite tiles }
        );

    { Structure used to access 16-bit components of a 32-bit doubleword in }
    { memory. }
    MemLong=record
        Lo,Hi:Word;
    end;

const
    { Number of level files that are being redirected. This is also the }
    { index of the next available element in the LevelFile and }
    { LevelFileIndex arrays. }
    LevelFileCount:Word=0;

    { Level files start with this prefix }
    LevelFilePrefix:PChar='LEVEL';

    { Directory that remaining level files are contained in. This is to }
    { retain compatibility with CKPatch 0.5.x. }
    LevelDir:array[0..79] of Char=#0;

    { Contains the prefix name for each of the data files }
    DataFilePrefix:array[Low(TDataFile)..High(TDataFile)] of PChar=(
        'EGAHEAD','EGASPRIT','EGALATCH');

    { Contains the lengths of each of the data file prefix names. This is }
    { to eliminate having to determine the length at runtime inside the }
    { interrupt handler, since stack space is at a premium here. }
    DataFilePrefixLength:array[Low(TDataFile)..High(TDataFile)] of Word=
        (7,8,8);

    { Contains the replacement file name to substitute for each of the }
    { game files files. }
    DataFileReplacement:
        array[Low(TDataFile)..High(TDataFile),0..79] of Char=(
        'EGAHEAD.'+Ext+#0,
        'EGASPRIT.'+Ext+#0,
        'EGALATCH.'+Ext+#0);

var
    { Each element in this array corresponds to the same index element in }
    { the LevelFile array. The value of the element at each index in this }
    { array is the level number that the file name contained at the same }
    { index in the LevelFile array represents. }
    LevelFileIndex:array[0..MaxLevelFileCount-1] of Byte;

    { Each element in this array contains the file name of a replacement }
    { level. The level number that corresponds to each element in this }
    { array is the value of the element with the same index in the }
    { LevelFileIndex array. }
    LevelFile:array[0..MaxLevelFileCount-1,0..79] of Char;

    { Storage for replacement file name when concatenating LevelDir to }
    { the level file name. }
    TargetFile:array[0..79] of Char;

    { Storage for element index into the DataFilePrefix, }
    { DataFilePrefixLength and DataFileReplacement arrays during the }
    { comparison loop. This variable is located in the data segment in }
    { order to minimise the stack usage in the file redirector routine. }
    DataFileIndex:Word;

{ Filters requests to open files by providing an replacement file name if }
{ the given name in FileName matches certain file names. A pointer to the }
{ filtered file name is returned, which may be the same as FileName. }
function RedirectFile(FileName:PChar):PChar; assembler;
asm
    { Note that stack space here is at a premium because Keen 1-3 only }
    { allocate a 128 byte stack which is just enough for the game itself to }
    { run. Try to minimise stack usage as much as possible. }

    { Check if the name of the file being opened begins with 'LEVEL' }
@CheckLevelFile:
    { Call StrLIComp(FileName,LevelFilePrefix,5) and jump ahead if the }
    { return result is not zero (the level file name does not begin with }
    { the substring 'LEVEL'). }
    PUSH MemPtr(FileName).MemSeg
    PUSH MemPtr(FileName).MemOfs
    PUSH MemPtr(LevelFilePrefix).MemSeg
    PUSH MemPtr(LevelFilePrefix).MemOfs
    MOV AX,5
    PUSH AX
    CALL StrLIComp
    OR AX,AX
    JNZ @CheckDataFile

    { Obtain the level number of the file being opened }
@GetLevelNumber:
    { ES:DI points to FileName }
    LES DI,FileName

    { AH contains the 6th character of the level file name, which is the }
    { tens digit of the level number. Convert it from ASCII '0'..'9' to }
    { decimal 0..9 in order to do the packed decimal conversion. }
    MOV AH,ES:[DI+5]
    SUB AH,'0'

    { AL contains the 7th character of the level file name, which is the }
    { ones digit of the level number. Convert it from ASCII '0'..'9' to }
    { decimal 0..9 in order to do the packed decimal conversion. }
    MOV AL,ES:[DI+6]
    SUB AL,'0'

    { Convert AH:AL to a packed decimal, so the level number will be in AL. }
    AAD

    { Look for an entry in LevelFileIndex that contains the level number }
    { that we want. If we find a match, then subsitute the replacement }
    { file name for the level file name. If we don't find a match, then }
    { instead append the level file name to the level file directory, to }
    { emulate the behaviour of CKPatch 0.5.x. }
@FindReplacementFile:
    { CX contains the number of entries in the LevelFile and LevelFileIndex }
    { arrays. Skip the comparison beforehand if there are zero entries, }
    { otherwise the comparsion loop would iterate 65,536 times. }
    MOV CX,LevelFileCount
    JCXZ @AddLevelDir

    { ES:DI points to LevelFileIndex[0] }
    MOV BX,DS
    MOV ES,BX
    MOV DI,OFFSET LevelFileIndex

    { DS:BX points to LevelFile[0] }
    MOV BX,OFFSET LevelFile

    { Clear direction flag so DI increments }
    CLD

@FindReplacementFileLoop:
    { Compare AL to ES:[DI], increment DI }
    SCASB

    { Jump ahead if match found }
    JE @FoundReplacementFile

    { Otherwise advance to next LevelFile entry, and loop back. If we have }
    { exausted all the entries in the LevelFile array, then instead we'll }
    { append the level file name to the level directory. }
    ADD BX,80
    LOOP @FindReplacementFileLoop

@AddLevelDir:
    { Copy the level directory to the target file name buffer by calling }
    { StrECopy(TargetFile,LevelDir). Upon return from StrECopy, DX:AX will }
    { be pointing to the null terminator byte at the end of the string }
    { contained in TargetFile. }
    PUSH DS
    MOV AX,OFFSET TargetFile
    PUSH AX
    PUSH DS
    MOV AX,OFFSET LevelDir
    PUSH AX
    CALL StrECopy

    { Append the level file name to the target file name buffer by calling }
    { StrECopy(DX:AX,FileName). Although we don't make use of the return }
    { value of StrECopy, calling StrECopy will save us from having to link }
    { in the StrCopy function as well. }
    PUSH DX
    PUSH AX
    PUSH MemPtr(FileName).MemSeg
    PUSH MemPtr(FileName).MemOfs
    CALL StrECopy

    { Return the concatenated filename in the target file name buffer as }
    { the replacement file name to open. }
    MOV AX,OFFSET TargetFile
    MOV DX,DS
    JMP @Done

    { Since we found a replacement file in the LevelFile array for the }
    { level that is being loaded, DS:BX will point to the replacement file }
    { name to use. Return this pointer in DX:AX. }
@FoundReplacementFile:
    MOV AX,BX
    MOV DX,DS
    JMP @Done

    { Check if a game data file is being opened instead }
@CheckDataFile:
    MOV DataFileIndex,0

    { Compare the current data file prefix with the file name by calling }
    { StrLIComp(FileName,DataFilePrefix[DataFileIndex], }
    { DataFilePrefixLength[DataFileIndex]). If there is a match, then }
    { return DataFileReplacement[DataFileIndex] as the replacement file }
    { name. If no match is found, compare the file name with the next data }
    { file prefix. If we exhaust the list of data file prefixes, then just }
    { return the file name unmodified. }
@CheckDataFileLoop:
    { Push the pointer to FileName }
    PUSH MemPtr(FileName).MemSeg
    PUSH MemPtr(FileName).MemOfs

    { Load the current array index into CX }
    MOV CX,DataFileIndex

    { Push the pointer contained in DataFilePrefix[DataFileIndex] }
    MOV BX,CX
    SHL BX,1
    SHL BX,1
    PUSH MemPtr([DataFilePrefix+BX]).MemSeg
    PUSH MemPtr([DataFilePrefix+BX]).MemOfs

    { Push the word contained in DataFilePrefixLength[DataFileIndex] }
    MOV BX,CX
    SHL BX,1
    PUSH Word([DataFilePrefixLength+BX])

    { Perform the comparsion }
    CALL StrLIComp

    { Check if a match has been found. If so, jump ahead. }
    OR AX,AX
    JZ @ReturnReplacementDataFileName

    { Advance to the next data file prefix }
    INC DataFileIndex

    { Check if we have exhausted the list of data file prefixes. If we }
    { haven't, then jump back to the start of the loop. If we have, then }
    { return the file name unmodified. }
    CMP DataFileIndex,3
    JB @CheckDataFileLoop
    JMP @ReturnOriginalFileName

    { Return the address of DataFileReplacement[DataFileIndex] }
@ReturnReplacementDataFileName:
    { Compute the address of DataFileReplacement[DataFileIndex] }
    MOV AX,80
    MUL DataFileIndex
    ADD AX,OFFSET DataFileReplacement
    MOV DX,DS
    JMP @Done

    { Return the original file name pointer }
@ReturnOriginalFileName:
    MOV AX,MemPtr(FileName).MemOfs
    MOV DX,MemPtr(FileName).MemSeg

    { Replacement file pointer will be in DX:AX }
@Done:
end;
{$ENDIF}

{$IFDEF KEEN4_ARCH}
type
    { Enumerations for each of the data files }
    TDataFile=(
        dfGameMaps, { GAMEMAPS.CK?, compressed levels }
        dfEGAGraph, { EGAGRAPH.CK?, compressed sprite tiles }
        dfAudio     { AUDIO.CK?, compressed sound effects }
        );

const
    { Contains the prefix name for each of the resource files }
    DataFilePrefix:array[Low(TDataFile)..High(TDataFile)] of PChar=(
        'GAMEMAPS','EGAGRAPH','AUDIO');

    { Contains the lengths of each of the prefix names. This is to }
    { eliminate having to determine the length at runtime inside the }
    { interrupt handler, since stack space is at a premium here. }
    DataFilePrefixLength:array[Low(TDataFile)..High(TDataFile)] of Word=
        (8,8,5);

    { Contains the replacement file name to substitute for each of the }
    { resource files. }
    DataFileReplacement:
        array[Low(TDataFile)..High(TDataFile),0..79] of Char=(
        'GAMEMAPS.'+Ext+#0,
        'EGAGRAPH.'+Ext+#0,
        'AUDIO.'+Ext+#0);

{ Filters requests to open files by providing an replacement file name if }
{ the given name in FileName matches certain file names. A pointer to the }
{ filtered file name is returned, which may be the same as FileName. }
function RedirectFile(FileName:PChar):PChar;
var
    { Loop counter variable for scanning loop }
    I:TDataFile;
begin
    { Initially assume that file name is unrecognised }
    RedirectFile:=FileName;

    { Scan through the resource list }
    for I:=Low(TDataFile) to High(TDataFile) do
    begin
        { Check if the file name matches the current resource prefix }
        if StrLIComp(FileName,DataFilePrefix[I],
            DataFilePrefixLength[I])=0 then
        begin
            { If a match is found, return the replacement file name }
            RedirectFile:=@DataFileReplacement[I];
            Break;
        end;
    end;
end;
{$ENDIF}

procedure Int21HandlerInit; external;
procedure Int21HandlerRun; external;
procedure Int21HandlerDone; external;
{$L REDIR.OBJ}

{ Parses command line arguments, checks for the script file existance, }
{ obtains the base directory, loads the game executable into memory and }
{ then opens the script file ready for parsing. The Options structure is }
{ considered to be uninitialised. }
procedure InitOptions;
var
    { File name of the game executable }
    ExecutableFileName:String[79];

    { Image length of the game executable }
    ExecutableImageLength:Longint;

    { Command line arguments to pass to the game executable }
    CommandLine:String[127];

    { Counter for various loops }
    I:Integer;
begin
    { Get initial script file spec and command line arguments for game }
    if ParamCount>=1 then
    begin
        { Script file spec is first argument, game arguments are the second }
        { and onward arguments. }
        Options.ScriptFileName:=ParamStr(1);
        CommandLine:=ParamStrRange(2,ParamCount);
    end else begin
        { Print help message and exit if no arguments specified }
        Writeln(HelpMessage);
        Halt;
    end;

    { Perform expansion on the script file spec argument. Find out if it }
    { either refers to a file, a directory, or is non-existant. }
    case GetFileType(Options.ScriptFileName) of
        ftNotFound: begin
            { Script file spec is non-existant. Exit with error message. }
            Writeln('Error: Can''t find script file ',
                Options.ScriptFileName);
            Halt;
        end;
        ftFile: begin
            { Script file spec points to a file. Obtain the path component }
            { of the script file specification. }
            Options.ScriptBaseDir:=GetPathOf(Options.ScriptFileName);
        end;
        ftDirectory: begin
            { Script file spec points to a directory. Use this as the }
            { script base directory. }
            Options.ScriptBaseDir:=
                MakeAppendablePath(Options.ScriptFileName);

            { Generate the script file name by adding the default patch }
            { script file name to the end. }
            Options.ScriptFileName:=Options.ScriptBaseDir+DefaultPatchScript;

            { Check if the patch script file exists }
            if GetFileType(Options.ScriptFileName)<>ftFile then
            begin
                { No default script file resides in the given directory. }
                { Print an error message and exit. }
                Writeln('Error: Can''t find script file ',
                    Options.ScriptFileName);
                Halt;
            end;
        end;
    end;

    { Find the game executable using the wildcard search pattern }
    ExecutableFileName:=LocateExecutable(ExecutableFileSpec);

    { Check if the game executable was found }
    if LoaderStatus<>lsOk then
    begin
        { Can't find the game executable. Print an error message and exit. }
        Writeln('Error: Game executable matching ',ExecutableFileSpec,
            ' not found');
        Halt;
    end;

    { If the executable was found, find out its image size }
    ExecutableImageLength:=GetLoadImageSize(ExecutableFileName);

    { Check if we were able to retrieve the executable image size }
    if LoaderStatus<>lsOk then
    begin
        { Can't obtain the executable image size. Print an error message }
        { describing the error that occured and then exit. }
        case LoaderStatus of
            lsFileNotEXE: begin
                { Game executable is not a valid .EXE file }
                Writeln('Error: ',ExecutableFileName,
                    ' is not a valid EXE file');
            end;
            lsDiskError: begin
                { Encountered a disk error while attempting to read the }
                { game executable. }
                Writeln('Error: Disk error encountered while loading ',
                    ExecutableFileName);
            end;
        end;
        Halt;
    end;

    { Initially assume we don't recognise the version }
    Options.CurrentVersion:=nil;

    { Scan the version table for a matching image size to determine the }
    { version of the game executable. }
    for I:=Low(Version) to High(Version) do
    begin
        if (Version[I].ImageLength=ExecutableImageLength)
            or (Version[I].CompImageLength=ExecutableImageLength) then
        begin
            { If a match is found, then record the version by setting the }
            { CurrentVersion pointer. }
            Options.CurrentVersion:=@Version[I];
            Options.IsCompressed:=
                (Version[I].ImageLength<>ExecutableImageLength);
        end;
    end;

    if Options.CurrentVersion=nil then
    begin
        { If the version is still unrecognised, then print an error message }
        { and exit. }
        Writeln('Error: Unrecognised version of ',ExecutableFileName);
        Writeln('fff ',ExecutableImageLength);
        Halt;
    end;

    { Attempt to load game executable into memory }
    LoadExecutable(ExecutableFileName,CommandLine,
        ExecutableImageLength,Options.IsCompressed,
        Options.CurrentVersion^.IsPKLITECompressed,
        Options.Base,Options.Code,Options.Stack);

    { Check if the game executable loaded successfully }
    if LoaderStatus<>lsOk then
    begin
        case LoaderStatus of
            lsOutOfMemory: begin
                { Insufficient memory to load the game executable. Print an }
                { error message and exit. }
                Writeln('Error: Insufficient memory to load ',
                    ExecutableFileName);
            end;
            lsWrongCompInd: begin
                { Got inconsistent result in compression check. Print an error }
                { message and exit. }
                Writeln('Error: Inconsistent compression indicator for ',
                    ExecutableFileName,', expected ',Options.IsCompressed);
            end;
            lsUnknown: begin
                { Some other error encountered while loading the game }
                { executable. Print an error message and exit. Under most }
                { circumstances these kinds of errors shouldn't happen. }
                Writeln(
                    'Error: Unknown error code encountered while loading ',
                    ExecutableFileName);
            end;
        end;
        Halt;
    end;

    { Set parser base segment address }
    SetParserBase(MemPtr(Options.Base).MemSeg);

    { Set patching base location in memory }
    SetPatcherBase(Options.Base);
end;

{ Prints error preamble specifying the file name and error location in }
{ order to make error output more meaningful. }
procedure PrintErrorHeader;
begin
    Write('Error: ',Options.ScriptFileName,
        ':',GetLastTokenLineNumber,
        ':',GetLastTokenColumn,': ');
end;

{ Unloads the game executable from memory and exits }
procedure TerminateSafely;
begin
    UnloadExecutable(Options.Base);
    Halt;
end;

{ Prints a line of context in the script file to help the user pinpoint }
{ where the error is. }
procedure PrintErrorContext;
var
    { The text file variable for the script file }
    F:Text;

    { Storage for the current line when reading through the file }
    S:String;

    { The line number that the error has occured on }
    LastTokenLineNumber:Integer;

    { The column number that the error has occured on }
    LastTokenColumn:Integer;

    { Loop counter variable used to locate error position in file }
    I:Integer;
begin
    { Open the script file in read-only mode }
    FileMode:=0;
    Assign(F,Options.ScriptFileName);
    Reset(F);

    { Obtain the line number and column that the error occured on }
    LastTokenLineNumber:=GetLastTokenLineNumber;
    LastTokenColumn:=GetLastTokenColumn;

    { Skip up to the line the error occurred on }
    for I:=1 to LastTokenLineNumber do
    begin
        Readln(F, S);
    end;

    { Print the contents of the line the error occurred on }
    Writeln(S);

    { Print a marker to point to the token that caused the error }
    for I:=1 to LastTokenColumn-1 do
    begin
        Write(#32);
    end;
    Writeln('^');

    { Close the script file }
    Close(F);
end;

{ Prints a parser-related error message and terminates }
procedure PrintParserError;
begin
    { Print current script file location }
    PrintErrorHeader;

    { Print a message describing the current parser error state }
    Writeln(ParserStatusMessage[ParserStatus]);

    { Print the error context }
    PrintErrorContext;

    { Unload game executable and exit }
    TerminateSafely;
end;

{ Prints a patcher-related error message and terminates }
procedure PrintPatcherError;
begin
    { Print current script file location }
    PrintErrorHeader;

    { Print a message describing the current patcher error state }
    Writeln(PatcherStatusMessage[PatcherStatus]);

    { Print the error context }
    PrintErrorContext;

    { Unload game executable and exit }
    TerminateSafely;
end;

{ Prints a error message regarding an invalid level number and exits }
procedure PrintLevelError(Level:Integer);
begin
    PrintErrorHeader;
    Writeln('Command not supported for level ',Level);
    PrintErrorContext;
    TerminateSafely;
end;

{ Parses %ext macro arguments }
procedure ScriptExt;
var
    { The episode extension supplied in the patch script }
    PatchScriptExt:String[3];
begin
    { Parse the extension }
    PatchScriptExt:=GetWord;

    { Validate the extension }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the episode extension }
        PrintParserError;
    end else if UpperCase(PatchScriptExt)<>Ext then begin
        { This executable doesn't support this episode }
        PrintErrorHeader;
        Writeln('Episode not recognised');
        PrintErrorContext;
        TerminateSafely;
    end;
end;

{ Parses %patch macro arguments }
procedure PatchInline;
var
    { Offset in image to write byte string to }
    Offset:Longint;

    { Byte string to write to image }
    Data:array[0..MaxPatchByteArraySize-1] of Byte;

    { Length of byte string to write }
    Length:Word;
begin
    { Parse the image offset }
    Offset:=GetLongint;

    { Check if the image offset parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the offset }
        PrintParserError;
    end;

    { Parse the byte string }
    GetByteArray(Length,Data);

    { Check if the byte string parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the byte string }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Write the byte string to the image }
        PatchBytes(Offset,Length,Data);
    end;
end;

{ Parses %patchfile macro arguments }
procedure PatchFromFile;
var
    { Offset in image to load file contents }
    Offset:Longint;

    { Name of the input file }
    InputFileName:String[79];

    { Seek offset in the input file }
    InputSeek:Longint;

    { Maximum number of bytes to read from the input file }
    InputLength:Longint;
begin
    { Parse the image offset }
    Offset:=GetLongint;

    { Check if the image offset parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the image offset }
        PrintParserError;
    end;

    { Parse the input file name }
    InputFileName:=GetWord;

    { Check if the input file name parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the input file name }
        PrintParserError;
    end;

    { Parse the seek offset }
    InputSeek:=GetLongint;

    { Check if the seek offset parsed successfully }
    if ParserStatus in [prsMissingParameter,prsEndOfFile] then
    begin
        { If no seek offset was specified, then load the file starting from }
        { the beginning. }
        InputSeek:=0;
        ParserStatus:=prsOk;
    end else if ParserStatus<>prsOk then begin
        { Couldn't parse the seek offset }
        PrintParserError;
    end;

    { Parse the maximum read length }
    InputLength:=GetLongint;

    { Check if the maximum read length parsed successfully }
    if ParserStatus in [prsMissingParameter,prsEndOfFile] then
    begin
        { If no maximum read length was specified, then load the remainder }
        { of the file. }
        InputLength:=MaxInputLength;
        ParserStatus:=prsOk;
    end else if ParserStatus<>prsOk then begin
        { Couldn't parse the maximum read length }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Any relative paths are taken from the base directory }
        InputFileName:=AdjustRelativePath(Options.ScriptBaseDir,
            InputFileName);

        { Load the file contents into the image }
        PatchFile(Offset,InputSeek,InputLength,InputFileName);

        if PatcherStatus<>ptsOk then
        begin
            { Couldn't load the file }
            PrintPatcherError;
        end;
    end;
end;

{ Parses %version macro arguments }
procedure GetVersion;
var
    NewVersion:String[7];
begin
    { Parse the version string }
    NewVersion:=LowerCase(GetWord);

    { Check if the version string parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the version string }
        PrintParserError;
    end;

    { If the version string matches the game executable version ID or is }
    { the 'all' keyword, then enable image patching; otherwise disable }
    { image patching. }
    Options.VersionEnabled:=(NewVersion=Options.CurrentVersion^.ID)
        or (NewVersion='all');
end;

{ Parses %dump macro arguments }
procedure DumpImage;
var
    { Name of the output file }
    OutputFileName:String[79];

    { Offset and length of the image region to dump }
    Offset,Length:Longint;
begin
    { Parse the output file name }
    OutputFileName:=GetWord;

    { Check if the output file name parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the output file name }
        PrintParserError;
    end;

    { Any relative paths are taken from the base directory }
    OutputFileName:=AdjustRelativePath(Options.ScriptBaseDir,
        OutputFileName);

    { Parse the offset }
    Offset:=GetLongint;

    { Check if the offset parsed successfully }
    if ParserStatus in [prsMissingParameter,prsEndOfFile] then
    begin
        { If no offset specified, then dump from the start }
        Offset:=0;
        ParserStatus:=prsOk;
    end else if ParserStatus<>prsOk then begin
        { Offset was not in valid numeric format }
        PrintParserError;
    end;

    { Parse the length only if an offset was specified }
    Length:=GetLongint;

    { Check if the length parsed successfully }
    if ParserStatus in [prsMissingParameter,prsEndOfFile] then
    begin
        { If no length specified then dump rest of the image }
        Length:=Options.CurrentVersion^.ImageLength-Offset;
        ParserStatus:=prsOk;
    end else if ParserStatus<>prsOk then begin
        { Length was not in valid format }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Write the image range to the output file }
        Writeln('Writing program image from offset ',Offset,
            ', length ',Length,' to file ',OutputFileName);
        WriteImage(Offset,Length,OutputFileName);

        { Check if the dump operation was successful }
        if PatcherStatus<>ptsOk then
        begin
            { Error encountered while writing the file }
            PrintPatcherError;
        end;
    end;
end;

{$IFDEF KEEN1_ARCH}
{ Parses %level.dir macro arguments for Keen 1-3 }
procedure PatchLevelDir;
var
    { New level directory }
    NewDir:String[79];
begin
    { Parse the new level directory }
    NewDir:=GetWord;

    { Check if the level directory was parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the new level directory }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Relative paths are taken from the base directory }
        StrPCopy(LevelDir,MakeAppendablePath(AdjustRelativePath(
            Options.ScriptBaseDir,NewDir)));
    end;
end;

{ Parses %level.file macro arguments for Keen 1-3 }
procedure PatchLevelFile;
var
    { Level number to patch }
    Level:Integer;

    { Replacement file name }
    NewFileName:String[79];
begin
    { Parse level number }
    Level:=GetLongint;

    { Check if the level number was parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the level number }
        PrintParserError;
    end;

    { Check that the level number is within range }
    if (Level<0) or (Level>99) then
    begin
        { Level number was not between 0-99 }
        PrintLevelError(Level);
    end;

    { Parse replacement file name }
    NewFileName:=GetWord;

    { Check if the replacement file name parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the replacement file name }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Check if another file can be added to the redirection table }
        if LevelFileCount>=MaxLevelFileCount then
        begin
            { Can't add any more files to the redirection table }
            PrintErrorHeader;
            Writeln('Maximum number of redirected level files is ',
                MaxLevelFileCount);
            PrintErrorContext;
            TerminateSafely;
        end;

        { Add the level file to the redirection table. Relative paths are }
        { taken from the base directory. }
        LevelFileIndex[LevelFileCount]:=Level;
        StrPCopy(LevelFile[LevelFileCount],
            AdjustRelativePath(Options.ScriptBaseDir,NewFileName));
        Inc(LevelFileCount);
    end;
end;

{ Parse %egahead, %egasprit and %egalatch macro arguments for Keen 1-3. }
{ DataFile specifies the type of file that is being replaced (either }
{ EGAHEAD.CK?, EGASPRIT.CK? or EGALATCH.CK? respectively). }
procedure PatchDataFile(DataFile:TDataFile);
var
    { Replacement file name }
    NewFileName:String[79];
begin
    { Parse replacement file name }
    NewFileName:=GetWord;

    { Check if the replacement file name parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the replacement file name }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Relative paths are taken from the base directory }
        StrPCopy(DataFileReplacement[DataFile],
            AdjustRelativePath(Options.ScriptBaseDir,NewFileName));
    end;
end;
{$ENDIF}

{$IFDEF KEEN1}
{ Parses %level.hint macro for Keen 1 }
procedure PatchLevelHint;
var
    { Level number to patch }
    Level:Integer;

    { Hint message to write to the image }
    Message:String;
begin
    { Parse level number }
    Level:=GetLongint;

    { Check if the level number was parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the level number }
        PrintParserError;
    end;

    { Check that a hint message exists for the given level }
    if (Level<1) or (Level>16)
        or (Options.CurrentVersion^.HintTextGridLineIndex^[Level]=$FF) then
    begin
        { No hint message exists for this level }
        PrintLevelError(Level);
    end;

    { Parse hint message }
    Message:=GetText;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Write the hint message to the image }
        PatchTextGrid(Options.CurrentVersion^.HintOffset,
            Options.CurrentVersion^.HintTextGridLineIndex^[Level],
            Options.CurrentVersion^.HintTextGridLineSpan^[Level],
            Options.CurrentVersion^.HintTextGridLineSize^,
            Message);

        { Check if the hint message was successfully written }
        if PatcherStatus<>ptsOk then
        begin
            { The hint message is too long }
            PrintPatcherError;
        end;
    end;
end;
{$ENDIF}

{$IFDEF KEEN4_ARCH}
{ Parses %level.name and %level.entry macro arguments for Keen 4-6. Offset }
{ contains the image offset of the start of the message arrays, }
{ LevelStringLength points to an array containing maximum allowed length of }
{ messages for each individual level. }
procedure PatchLevelString(
    Offset:Longint;
    LevelStringLength:PLevelStringLength);
var
    { Level number to patch }
    Level:Integer;

    { Message to write to image }
    Message:String;

    { Counter used for various loops }
    I:Integer;
begin
    { Parse level number }
    Level:=GetLongint;

    { Check if the level number parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the level number }
        PrintParserError;
    end;

    { Check if the level number is valid }
    if (Level<0) or (Level>NumLevels) then
    begin
        { No message exists for this level }
        PrintLevelError(Level);
    end;

    { Parse message }
    Message:=GetText;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Locate the message offset for the specified level }
        for I:=0 to Level-1 do
        begin
            Inc(Offset,LevelStringLength^[I]);
        end;

        { Write the message into the image }
        PatchASCIIZ(Offset,LevelStringLength^[Level],Message);

        { Check if the patch operation succeeded }
        if PatcherStatus<>ptsOk then
        begin
            { The message is too long }
            PrintPatcherError;
        end;
    end;
end;

{ Parse %egagraph, %gamemaps and %audio macro arguments. DataFile specifies }
{ the type of file that is being replaced (either EGAGRAPH.CK?, }
{ GAMEMAPS.CK? or AUDIO.CK? respectively). }
procedure PatchDataFile(DataFile:TDataFile);
var
    { Replacement file name }
    NewFileName:String[79];
begin
    { Parse replacement file name }
    NewFileName:=GetWord;

    { Check if the replacement file name parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the replacement file name }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Relative paths are taken from the base directory }
        StrPCopy(DataFileReplacement[DataFile],
            AdjustRelativePath(Options.ScriptBaseDir,NewFileName));
    end;
end;

{ Parse %audiohed, %egahead, %maphead, %audiodct, %egadict macro arguments. }
{ DataResource specifies the data resource that is to be patched. Seek }
{ specifies the offset into the file at which to start loading from. The }
{ number of bytes read from file into the image is dependant on the type of }
{ resource specified; this is to prevent files that are too large from }
{ overwriting neighbouring resources. }
procedure PatchDataResource(DataResource:TDataResource;Seek:Longint);
var
    { Resource input file name }
    InputFileName:String[79];
begin
    { Parse resource input file name }
    InputFileName:=GetWord;

    { Check if the input file name parsed successfully }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the resource input file name }
        PrintParserError;
    end;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Relative paths are taken from the base directory }
        InputFileName:=AdjustRelativePath(Options.ScriptBaseDir,
            InputFileName);

        { Check if the resource offset is known for this version }
        if Options.CurrentVersion^.DataResourceOffset^[DataResource]
            =$FFFFFFFF then
        begin
            { Print an error message stating that the specified resource }
            { image offset is unknown, then terminate. }
            PrintErrorHeader;
            Writeln('Resource offset unknown for this game version');
            PrintErrorContext;
            TerminateSafely;
        end;

        { Only load the resource input file contents into the image if the }
        { resource offset is known for this game executable version. }
        PatchFile(Options.CurrentVersion^.DataResourceOffset^[DataResource],
            Seek,Options.CurrentVersion^.DataResourceLength^[DataResource],
            InputFileName);

        { Check if the file loading operation succeeded }
        if PatcherStatus<>ptsOk then
        begin
            { Couldn't load the resource file }
            PrintPatcherError;
        end;
    end;
end;
{$ENDIF}

{$IFDEF KEEN4}
{ Parse %level.hint macro arguments for Keen 4 }
procedure PatchLevelHint;
var
    { Level number }
    Level:Integer;

    { Hint array index }
    Hint:Integer;

    { Hint message }
    Message:String;
begin
    { Parse level number }
    Level:=GetLongint;

    { Check if the level number was successfully parsed }
    if ParserStatus<>prsOk then
    begin
        { Couldn't parse the level number }
        PrintParserError;
    end;

    { Find hint array index for this level }
    Hint:=LevelHintMap[Level];

    { Check if a hint message exists for this level }
    if Hint=$FF then
    begin
        { No hint message exists for this level }
        PrintLevelError(Level);
    end;

    { Parse hint message }
    Message:=GetText;

    { Check if patching is enabled }
    if Options.VersionEnabled then
    begin
        { Write the hint message into the image }
        PatchASCIIZ(Options.CurrentVersion^.LevelHintOffset^[Hint],
            Options.CurrentVersion^.LevelHintLength^[Hint],
            Message);
    end;
end;
{$ENDIF}

{ Parses patch script file, executing patching operations contained within. }
procedure ParsePatchScript;
var
    { Contains current command being parsed in the script file }
    Command:String[16];
begin
    { Initially patching is enabled for all versions }
    Options.VersionEnabled:=True;

    { Open the script file }
    OpenParserFile(Options.ScriptFileName);

    { Check if the script file opened successfully }
    if ParserStatus<>prsOk then
    begin
        { Can't open the script file. Print an error message and exit. }
        Writeln('Error: Cannot open script file ',
            Options.ScriptFileName);
        TerminateSafely;
    end;

    { The first command must be %ext for future compatibility }
    Command:=GetCommand;
    if (ParserStatus=prsOk) and (Command='%ext') then
    begin
        { %ext <game-extension> }
        { Specifies the episode that is being patched. The following string }
        { argument is checked to see if it matches the extension of the }
        { episode that this CKPatch executable supports. Although this }
        { doesn't provide any new information now, the extension is }
        { validated regardless for future compatibility, in case all six }
        { executables are combined into one, so CKPatch knows what episode }
        { it is patching. }
        ScriptExt;
    end else begin
        { The first command in the script file was not %ext }
        PrintErrorHeader;
        Writeln('First command must be %ext');
        PrintErrorContext;
        TerminateSafely;
    end;

    repeat
        { Parse the next command in the file }
        Command:=GetCommand;

        if ParserStatus=prsOK then
        begin
            if Command='%ext' then
            begin
                { %ext can only be specified once }
                PrintErrorHeader;
                Writeln('%ext must only appear once');
                PrintErrorContext;
                TerminateSafely;
            end else if Command='%patch' then begin
                { %patch <offset> <bytestring> }
                { Allows a byte string to be written into the image. }
                { Following arguments are the image offset (integer) and }
                { the byte string. }
                PatchInline;
            end else if Command='%patchfile' then begin
                { %patchfile <offset> <filename> [seek [length]] }
                { Allows the contents of a file to be written into the }
                { image. Following arguments are the image offset }
                { (integer), the input file name (string), the seek offset }
                { into the input file (integer), and the maximum number of }
                { bytes to read from the input file (integer). The seek and }
                { length parameters are optional. If the seek parameter is }
                { omitted, then the input file is read from the start. If }
                { the length parameter is omitted, then the remainder of }
                { the input file will be read. }
                PatchFromFile;
            end else if Command='%version' then begin
                { %version <version> }
                { Allows following macros to be conditionally executed for }
                { specific game executable versions. The following string }
                { argument is either a version ID string or the 'all' }
                { keyword to match all versions. }
                GetVersion;
            end else if Command='%dump' then begin
                { %dump <filename> [offset [length]] }
                { Dumps a region of the image to a file. Following }
                { arguments are the output file name (string), followed by }
                { the image offset and length (both integers) if a }
                { sub-range of the image is to be written. The offset and }
                { length parameters are optional. If the length is omitted, }
                { the remainder of the image is written to the output file. }
                { If both the offset and length are omitted, then the }
                { entire image is written to the output file. }
                DumpImage;
            end else if Command='%abort' then begin
                { %abort }
                { Halts patching and terminates CKPatch. An error message }
                { is printed to indicate patching was aborted. }
                if Options.VersionEnabled then
                begin
                    Writeln('%abort encountered at ',
                        Options.ScriptFileName,
                        ':',GetLastTokenLineNumber,
                        ':',GetLastTokenColumn,#13#10,
                        'Patching halted at this point.');
                    TerminateSafely;
                end;
            end else if Command='%end' then begin
                { %end }
                { Specifies end of patch file. Patching ends at this point }
                { and the game is executed. }
                Break;
        {$IFDEF KEEN1_ARCH}
            end else if Command='%level.dir' then begin
                { %level.dir <dir> }
                { Specifies base directory for level files. Following }
                { argument is a string that contains the path relative to }
                { the script base directory that contains the LEVEL??.CK? }
                { files. }
                PatchLevelDir;
            end else if Command='%level.file' then begin
                { %level.file <level> <file> }
                { Specifies the file to use for a given level. Following }
                { arguments are the level number (integer, 1-16 for levels }
                { 1-16, 80 for world map, 81 for ending sequence, 90 for }
                { title screen), and the name of the file to use for this }
                { level (string). If the path component of the file name is }
                { relative, then it is taken relative to the script base }
                { directory. Note that the %level.file command takes }
                { precedence over the %level.dir command. }
                PatchLevelFile;
            end else if Command='%egahead' then begin
                { %egahead <file> }
                { Specifies the replacement file for the EGAHEAD.CK? file. }
                { Following argument is the replacement file name (string), }
                { relative to the directory the script file is in. }
                PatchDataFile(dfEGAHead);
            end else if Command='%egasprit' then begin
                { %egasprit <file> }
                { Specifies the replacement file for the EGASPRIT.CK? file. }
                { Following argument is the replacement file name (string), }
                { relative to the directory the script file is in. }
                PatchDataFile(dfEGASprit);
            end else if Command='%egalatch' then begin
                { %egalatch <file> }
                { Specifies the replacement file for the EGALATCH.CK? file. }
                { Following argument is the replacement file name (string), }
                { relative to the directory the script file is in. }
                PatchDataFile(dfEGALatch);
        {$ENDIF}
        {$IFDEF KEEN1}
            end else if Command='%level.hint' then begin
                { %level.hint <n> [text] }
                { Specifies messages that the Yorp or Garg statues give you }
                { for a particular level. Following arguments are the level }
                { number (integer) followed by the message string. }
                PatchLevelHint;
        {$ENDIF}
        {$IFDEF KEEN4_ARCH}
            end else if Command='%level.name' then begin
                { %level.name <n> [text] }
                { Modifies the name of a level. Following arguments are the }
                { level number (integer) and the name (string). }
                PatchLevelString(Options.CurrentVersion^.LevelNameOffset,
                    Options.CurrentVersion^.LevelNameLength);
            end else if Command='%level.entry' then begin
                { %level.entry <n> [text] }
                { Modifies the entry text of a level. Following arguments }
                { are the level number (integer) and the message (string). }
                PatchLevelString(Options.CurrentVersion^.LevelEntryOffset,
                    Options.CurrentVersion^.LevelEntryLength);
            end else if Command='%gamemaps' then begin
                { %gamemaps <file> }
                { Specifies the replacement file for the GAMEMAPS.CK? file. }
                { Following argument is the replacement file name (string), }
                { relative to the directory the script file is in. }
                PatchDataFile(dfGameMaps);
            end else if Command='%egagraph' then begin
                { %egagraph <file> }
                { Specifies the replacement file for the EGAGRAPH.CK? file. }
                { Following argument is the replacement file name (string), }
                { relative to the directory the script file is in. }
                PatchDataFile(dfEGAGraph);
            end else if Command='%audio' then begin
                { %audio <file> }
                { Specifies the replacement file for the AUDIO.CK? file. }
                { Following argument is the replacement file name (string), }
                { relative to the directory the script file is in. }
                PatchDataFile(dfAudio);
            end else if Command='%audiohed' then begin
                { %audiohed <file> }
                { Loads the contents of the file into the AUDIOHED resource }
                { in the image. Following argument is the input file name. }
                { The AUDIOHEAD resource contains the offsets in the }
                { AUDIO.CK? file for each sound effect. }
                PatchDataResource(drAudioHed,0);
            end else if Command='%egahead' then begin
                { %egahead <file> }
                { Loads the contents of the file into the EGAHEAD resource }
                { in the image. Following argument is the input file name. }
                { The EGAHEAD resource contains the offsets in the }
                { EGAGRAPH.CK? file for each sprite tile. }
                PatchDataResource(drEGAHead,0);
            end else if Command='%maphead' then begin
                { %maphead <file> }
                { Loads the contents of the file into the MAPHEAD }
                { resource in the image, ignoring the tileinfo. }
                { Following argument is the input file name. }
                { The MAPHEAD resource contains the offsets }
                { in the GAMEMAPS.CK? file for each level. }
                PatchDataResource(drMapHead,0);
            end else if Command='%audiodct' then begin
                { %audiodct <file> }
                { Loads the contents of the file into the AUDIODCT resource }
                { in the image. Following argument is the input file name. }
                { The AUDIODCT resource contains the Huffman tree used to }
                { decompress chunks in the AUDIO.CK? file. }
                PatchDataResource(drAudioDct,0);
            end else if Command='%egadict' then begin
                { %egadict <file> }
                { Loads the contents of the file into the EGADICT resource }
                { in the image. Following argument is the input file name. }
                { The EGADICT resource contains the Huffman tree used to }
                { decompress chunks in the EGADICT.CK? file. }
                PatchDataResource(drEGADict,0);
            end else if Command='%ckmhead.obj' then begin
                { %ckmhead.obj <file> }
                { This command is similar to %maphead, but it starts }
                { reading from offset 122 in the file. This is to allow the }
                { MAPHEAD data that is contained in the CK?MHEAD.OBJ file }
                { that TED5 generates to be loaded into the game, without }
                { having to convert the file to one that can be read }
                { directly by the %maphead command. }
                PatchDataResource(drMapHead,122);
            end else if Command='%tileinfo' then begin
                { %tileinfo <file> }
                { Loads the contents of the file into the TILEINFO resource }
                { in the image. Following argument is the input file name. }
                { The TILEINFO resource contains the tile properties. }
                PatchDataResource(drTileInfo,0);
            end else if Command='%wholemaphead' then begin
                { %wholemaphead <file> }
                { This command is similar to %wholemaphead, }
                { but it also loads the TILEINFO data. }
                PatchDataResource(drWholeMapHead,0);
        {$ENDIF}
        {$IFDEF KEEN4}
            end else if Command='%level.hint' then begin
                { %level.hint <n> [text] }
                { Specifies messages that Princess Lindsey gives you for a }
                { particular level. Following arguments are the level }
                { number (integer) followed by the message string. }
                PatchLevelHint;
        {$ENDIF}
            end else begin
                { Unrecognised macro command encountered. Print an error }
                { message and terminate. }
                PrintErrorHeader;
                Writeln('Unrecognised command');
                PrintErrorContext;
                TerminateSafely;
            end;
        end else if ParserStatus=prsEndOfFile then begin
            { Hit the end of the file, script lacks %end command }
            PrintErrorHeader;
            Writeln('Script must terminate with %end');
            PrintErrorContext;
            TerminateSafely;
        end else begin
            { Encountered some other kind of parser error }
            PrintParserError;
        end;
    until False;

    { Close the patch script file }
    CloseParserFile;
end;

{ Installs the file redirector and runs the game }
procedure RunGame;
begin
    { Install the file redirector by hooking interrupt 21H }
    Int21HandlerRun;

    { Jump to the image entry point to run the game }
    RunExecutable(Options.Base,Options.Code,Options.Stack);
end;

{ Invoked by main procedure in each CKxPATCH.PAS source file. This }
{ procedure is needed because you can only specify the main procedure in }
{ the top-level source file, not an included one. }
procedure Main;
begin
    { Tell Dos unit to release its interrupt handlers since we will be }
    { launching off child processes. }
    SwapVectors;

    { Tell the file redirector to hook the DOS interrupt 21H }
    Int21HandlerInit;

    { Parse command line arguments }
    InitOptions;

    { Parse the patch script file }
    ParsePatchScript;

    { Run the game }
    RunGame;

    { Tell the file redirector to unhook the DOS interrupt 21H }
    Int21HandlerDone;

    { Restore the Dos unit's interrupt handlers, so it can unhook them }
    { properly on exit. }
    SwapVectors;
end;
