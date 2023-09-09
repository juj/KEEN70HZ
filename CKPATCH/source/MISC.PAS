unit Misc;

{$A+,B+,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}

{ Miscellaneous functions/procedures that don't go anywhere else }

interface

type
{ Used to classify a given file specification }
    TFileType=(
        ftNotFound,     { File spec is non-existant }
        ftFile,         { File spec refers to a file }
        ftDirectory     { File spec refers to a directory }
        );

{ Determines whether a given file spec is a file or directory. FileSpec     }
{ contains the file specification to test. If FileSpec contains wildcard    }
{ characters, then the first matching file or directory will be used. A     }
{ TFileType enumerated value is returned which identifies what the file     }
{ specification refers to.                                                  }
function GetFileType(const FileSpec:String):TFileType;

{ Returns true if given file spec is a relative path. FileSpec contains the }
{ path to test. A relative path is one that does not start with a backslash }
{ (does not start from root directory) and does not start with a drive      }
{ letter.                                                                   }
function IsRelativePath(const FileSpec:String):Boolean;

{ Makes the path appendable. This is done by ensuring that it ends in a     }
{ backslash, or in the case of the empty path (which refers to the current  }
{ directory), that it remains empty. PathSpec contains the path to make     }
{ appendable. The appendable version of PathSpec is returned.               }
function MakeAppendablePath(const PathSpec:String):String;

{ Applies a relative path to a base path. BasePath must be appendable (see  }
{ MakeAppendablePath), Relpath may either be absolute or relative. The      }
{ return value will be BasePath and RelPath concatenated if RelPath is a    }
{ relative path (see IsRelativePath). If RelPath is an absolute path, then  }
{ the return value will be RelPath, BasePath will be ignored.               }
function AdjustRelativePath(const BasePath,RelPath:String):String;

{ Returns path of given file specification, in appendable form (see         }
{ MakeAppendablePath). FileSpec contains the file specification to extract  }
{ the path component of.                                                    }
function GetPathOf(const FileSpec:String):String;

{ Returns a range of command line arguments concatenated as one string,     }
{ seperated by spaces. First is the first command line argument (starting   }
{ from 1) in the range, Last is the last command line argument in the       }
{ range. If the range specified spans beyond the available command line     }
{ arguments, then non-existant arguments will be returned as zero-length    }
{ strings, with no space separation.                                        }
function ParamStrRange(First,Last:Integer):String;

{ Converts a character to lowercase }
function LoCase(C:Char):Char;

{ Converts a string to uppercase }
function UpperCase(const S:String):String;

{ Converts a string to lowercase }
function LowerCase(const S:String):String;

implementation

uses Dos;

function GetFileType(const FileSpec:String):TFileType;
var
    Search:SearchRec;
begin
    { Find the first file or directory that matches the given file spec }
    FindFirst(FileSpec,ReadOnly+Hidden+SysFile+Directory+Archive,Search);

    if DosError=0 then
    begin
        { Found a match }
        if (Search.Attr and Directory)=Directory then
        begin
            { The file spec refers to a directory }
            GetFileType:=ftDirectory;
        end else begin
            { The file spec refers to a file }
            GetFileType:=ftFile;
        end;
    end else begin
        { Found no match }
        DosError:=0;
        GetFileType:=ftNotFound;
    end
end;

function IsRelativePath(const FileSpec:String):Boolean;
begin
    if Length(FileSpec)>0 then
    begin
        { The path is relative only if it does not contain a colon and does }
        { not begin with a backslash. }
        IsRelativePath:=(Pos(':',FileSpec)=0) or (FileSpec[1]<>'\');
    end else begin
        { Zero-length paths refer to the current directory }
        IsRelativePath:=True;
    end;
end;

function MakeAppendablePath(const PathSpec:String):String;
begin
    { Check if PathSpec is empty or already ends in a backslash }
    if (Length(PathSpec)=0) or (PathSpec[Length(PathSpec)]='\') then
    begin
        { Leave PathSpec as-is }
        MakeAppendablePath:=PathSpec;
    end else begin
        { Add a backslash to the end of PathSpec }
        MakeAppendablePath:=PathSpec+'\';
    end;
end;

function AdjustRelativePath(const BasePath,RelPath:String):String;
begin
    { Check if RelPath is a relative path }
    if IsRelativePath(RelPath) then
    begin
        { RelPath is a relative path. Concatenate the two paths. }
        AdjustRelativePath:=BasePath+RelPath;
    end else begin
        { RelPath is actually an absolute path. There is no point in }
        { merging it with BasePath since RelPath is not dependent on }
        { BasePath, so simply return RelPath as-is. }
        AdjustRelativePath:=RelPath;
    end;
end;

function GetPathOf(const FileSpec:String):String;
var
    { The directory component of FileSpec }
    Dir:DirStr;

    { The file name component of FileSpec }
    Name:NameStr;

    { The file extension component of FileSpec }
    Ext:ExtStr;
begin
    { Split FileSpec into its directory, file name and extension components }
    FSplit(FileSpec,Dir,Name,Ext);

    { Make sure the path component is appendable }
    GetPathOf:=MakeAppendablePath(Dir);
end;

function ParamStrRange(First,Last:Integer):String;
var
    { Concatenate the arguments into this string buffer }
    S:String;

    { Current argument index }
    Index:Integer;
begin
    { Initially set concatenation buffer to empty }
    S:='';

    { Check if the range spans beyond the last argument }
    if Last>ParamCount then
    begin
        { Clamp the range so it ends at the last argument }
        Last:=ParamCount;
    end;

    { Check if the range starts before or on the last argument }
    if First<=ParamCount then
    begin
        { Copy the first argument in the range to the concatenation buffer }
        S:=ParamStr(First);

        for Index:=First+1 to Last do
        begin
            { For each remaining argument in the range, append it to the }
            { concatenation buffer, with a space preceding it. }
            S:=S+' '+ParamStr(Index);
        end;
    end;

    { Return the contents of the concatenation buffer }
    ParamStrRange:=S;
end;

function LoCase(C:Char):Char;
begin
    { Check if C is an uppercase letter }
    if C in ['A'..'Z'] then
    begin
        { Convert C to a lowercase letter }
        LoCase:=Chr(Ord(C)+32);
    end else begin
        { Otherwise return C as-is }
        LoCase:=C;
    end;
end;

function UpperCase(const S:String):String;
var
    { Work buffer for converting the string to uppercase }
    Result:String;

    { Current index into the string }
    I:Integer;
begin
    { Copy the string to the work buffer, since it's a constant parameter }
    Result:=S;

    for I:=1 to Length(Result) do
    begin
        { Convert each character in the work buffer to uppercase }
        Result[I]:=UpCase(Result[I]);
    end;

    { Return the contents of the work buffer }
    UpperCase:=Result;
end;

function LowerCase(const S:String):String;
var
    { Work buffer for converting the string to lowercase }
    Result:String;

    { Current index into the string }
    I:Integer;
begin
    { Copy the string to the work buffer, since it's a constant parameter }
    Result:=S;

    for I:=1 to Length(Result) do
    begin
        { Convert each character in the work buffer to lowercase }
        Result[I]:=LoCase(Result[I]);
    end;

    { Return the contents of the work buffer }
    LowerCase:=Result;
end;

end.
