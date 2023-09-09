unit Parser;

{$A+,B+,F-,G-,I-,P+,Q-,R-,S-,T-,V-,X+}

{ Simple patch script parsing unit }

interface

type
    { Parser error status codes }
    TParserStatus=(
        prsOK,                   { No error }
        prsErrorOpeningFile,     { Error opening file }
        prsEndOfFile,            { End of file encountered }
        prsInvalidNumericFormat, { Numeric token not in valid format }
        prsMissingParameter,     { Found a command when parameter expected }
        prsParameterTooLong,     { Parameter is too long to parse }
        prsCommandExpected,      { Found junk instead of a command }
        prsMissingQuote,         { Can't find closing double quote }
        prsEOLExpected,          { Found junk instead of end-of-line }
        prsWhitespaceExpected    { Found junk instead of whitespace }
        );

const
    { Error status variable, set by all procedures here on return }
    ParserStatus:TParserStatus=prsOk;

{ Sets base memory location for segment relocation. NewBase contains the    }
{ memory location to use as the new base memory location. This procedure    }
{ must be called before calling any other patching functions, otherwise     }
{ undefined behaviour will result.                                          }
procedure SetParserBase(NewBase:Word);

{ Opens a script file and initialises parser state. FileName contains the   }
{ file name of the file to open. If the file could not be opened, then      }
{ ParserStatus will be set to prsErrorOpeningFile.                          }
procedure OpenParserFile(const FileName:String);

{ Closes the parser file. This will leave the parser in an undefined state  }
{ until another call is made to OpenParserFile.                             }
procedure CloseParserFile;

{ Returns the line number of the last token read. Note that this function   }
{ does not leave an error code in ParserStatus on return.                   }
function GetLastTokenLineNumber:Integer;

{ Returns the column number of the last token read. Note that this function }
{ does not leave an error code in ParserStatus on return.                   }
function GetLastTokenColumn:Integer;

{ Scans for and returns a macro command (prefixed by '%'). Skips whitespace }
{ and comments. Any junk that is encountered is flagged as an error by      }
{ setting ParserStatus to an error state on return. String returned         }
{ includes leading '%' and is converted to lowercase. File pointer is left  }
{ at whitespace following macro command. Check ParserStatus variable to     }
{ find out if end of file is reached.                                       }
function GetCommand:String;

{ Scans for and returns a long integer (can be in decimal format or have a  }
{ leading '$' or '0x' to denote hex notation). Whitespace leading up to     }
{ number is ignored, file pointer is left at whitespace following integer.  }
{ Check ParserStatus variable to find out if the number is valid format.    }
function GetLongint:Longint;

{ Scans for and returns a word string, delimted by whitespace at both ends. }
{ Backslash escapes are only processed if the word is quoted with double    }
{ quote characters. Therefore backslashes in filenames will not be          }
{ interpreted unless in quotes, and any hashes that appear unquoted will    }
{ be interpreted as comments. If the word string starts with a '%'          }
{ character and is the first non-whitespace character on the line, it will  }
{ be seen as a macro command instead and the word will be considered        }
{ non-existant (null string returned and ParserStatus=prsMissingParameter). }
function GetWord:String;

{ Reads in a stream of characters and returns a string. Leading/trailing    }
{ whitespace at start/end of stream and at the end of each line are         }
{ removed. Embedded EOL characters are returned as a newline (#10)          }
{ character embedded inside the string. The stream of characters is         }
{ terminated either by a macro command or the end of file. Backslash        }
{ escapes are always processed. Unescaped hashes are considered comments to }
{ the end of line. Leading '%' characters must be escaped to avoid          }
{ interpretation as a macro command. The text stream may be up to a maximum }
{ of 255 characters.                                                        }
function GetText:String;

{ Reads in a stream of characters and returns a byte array. The stream of   }
{ characters is expected to be whitespace-seperated words, each word is     }
{ either an integer (parseable by GetInteger()) or a string surrounded by   }
{ double quotes which may contain backslash escape sequences. Each integer  }
{ encountered is considered a single byte (0..255) and each character (or   }
{ backslash escape) in a quoted string is considered a singe byte. The      }
{ DataLength parameter on return it contains number of bytes actually read. }
{ The sequence of bytes is terminated either by a macro command or end of   }
{ file. Check the ParserStatus variable for possible numeric format errors. }
procedure GetByteArray(var DataLength:Word;var Data:array of Byte);

{ Reads in a stream of characters and returns an integer. The stream of     }
{ characters is expected to be a decimal or hexadecimal value, and can be   }
{ suffixed with W (for Word), RW (for relative word), L (for long), or RL   }
{ (for relative long).                                                        }
procedure ParseLiteralInt(const NStr:String; var Size:Integer; var N:Longint);

implementation

uses Misc;

const
    { Width of tab stops }
    TabSize=8;

type
    { Parser state type }
    TReadMode=(
        rmDone,                 { Not looking for anything }
        rmLookingForCommand,    { Looking for a macro command }
        rmReadingCommand,       { Reading a macro command }
        rmLookingForKeyword,    { Looking for a keyword }
        rmReadingKeyword,       { Reading a keyword }
        rmReadingQuotedString,  { Reading a quoted string }
        rmLookingForTextStream, { Looking for a text stream }
        rmReadingTextStream,    { Reading a text stream }
        rmError                 { Encountered an error state, ParserStatus }
                                { will be set to the relevant error code. }
        );

    { This structure holds state information needed to parse a script file. }
    { There should only be one instance of this structure per script file. }
    TParserFile=record
        { The text file variable for the script file }
        F:Text;

        { Current line number. This is always monotonically increasing. }
        CurrentLineNumber:Integer;

        { This is the current column position on the current line in the }
        { input stream. This needs to be retained in order to be able to }
        { expand tab characters correctly. }
        CurrentColumn:Integer;

        { This is the line number of the last token that was read. This is }
        { used to highlight the location of erroneous text to the user. }
        LastTokenLineNumber:Integer;

        { This is the column position of the starting character of the last }
        { token that was read. This is used to highlight the location of }
        { erroneous text to the user. }
        LastTokenColumn:Integer;

        { This is the number of non-whitespace characters that have been }
        { encountered on the current line. This variable is used to ensure }
        { that macro commands only appear as the first word on each line. }
        NonWhitespaceCharCount:Integer;

        { Last character that was read. This needs to be retained in order }
        { to detect the two-character CR/LF end-of-line sequence. }
        LastChar:Char;

        { Current character that was read. This needs to be retained in }
        { order to detect the two-character CR/LF end-of-line sequence. }
        ThisChar:Char;

        { This is the amount of whitespace that has currently been }
        { accumulated. This needs to be retained so we can intelligently }
        { remove trailing whitespace off the end of the line, without }
        { losing whitespace that separates tokens on the same line. }
        PendingSpaces:Integer;

        { If this flag is set, then the column position is at the end of }
        { the current line. Upon reading the next character, the column }
        { position needs to be reset and the line number incremented. }
        AtEndOfLine:Boolean;

        { Current parser state. This reflects what kind of token we are }
        { currently parsing. }
        ReadMode:TReadMode;

        { Number of whitespace characters read since the last }
        { non-whitespace character was read in a text stream. This variable }
        { is used to help remove trailing whitespace prior to a comment. }
        { This variable must only be used when the parser is in the }
        { rmReadingTextStream state. }
        TextStreamPendingSpaces:Integer;

        { Number of lines that have been read since the last line that }
        { contained non-whitespace characters in a text stream. This }
        { variable is used to help remove trailing newlines prior to the }
        { next macro command or end of file. This variable must only be }
        { used when the parser is in the rmReadingTextStream state. }
        TextStreamPendingNewlines:Integer;

        { If this flag is set, then there is an additional pending }
        { non-whitespace character available in TextStreamPendingChar once }
        { all pending whitespace has been flushed. This variable must only }
        { be used when the parser is in the rmReadingTextStream state. }
        TextStreamPendingCharAvailable:Boolean;

        { If TextStreamPendingCharAvailable is set, then this variable }
        { contains the next non-whitespace character in the text stream }
        { after all the pending newlines and whitespace has been read. This }
        { variable must only be used when the parser is in the }
        { rmReadingTextStream state. }
        TextStreamPendingChar:Char;
    end;

var
    { Contains parser state information for a script file. Note that }
    { normally such a structure should be explicitly left up to the user }
    { to allocate, with them passing a reference to this structure on each }
    { parser procedure call. However since in this context memory is at a }
    { tight premium, only a single parser state structure will be allocated }
    { globally in order to allow more compact code to be generated by the }
    { compiler. If your application requires more than one script file to }
    { be open simultaneously, you'll need to remove this global declaration }
    { and add a 'var ParserFile:TParserFile' parameter to each procedure in }
    { this unit. }
    ParserFile:TParserFile;

    { Base memory segment address for parsing routines }
    ParserBase:Word;

{ Reads a character from the input stream. CR/LF sequences are condensed }
{ into a single LF character, and tab characters are expanded to multiple }
{ space characters. A Ctrl-Z character is returned if the end-of-file is }
{ reached. }
function ReadChar:Char;
begin
    { Retain previous character }
    ParserFile.LastChar:=ParserFile.ThisChar;

    if Eof(ParserFile.F) then
    begin
        { If the end of file has been reached, then return an EOF character }
        ParserFile.ThisChar:=#26;
    end else if ParserFile.PendingSpaces>0 then begin
        { Currently expanding a tab; keep returning a space character }
        { until the expansion is complete. }
        ParserFile.ThisChar:=#32;
        Dec(ParserFile.PendingSpaces);
        Inc(ParserFile.CurrentColumn);
    end else begin
        { Check if this is the start of a new line }
        if ParserFile.AtEndOfLine then
        begin
            { Move the column position back to the start and increment the }
            { current line number. }
            ParserFile.CurrentColumn:=1;
            Inc(ParserFile.CurrentLineNumber);
            ParserFile.AtEndOfLine:=False;
            ParserFile.NonWhitespaceCharCount:=0;
        end else begin
            { Increment the column position }
            Inc(ParserFile.CurrentColumn);
        end;

        { Filter the input stream for tabs and EOL sequences }
        repeat
            { Read next character }
            Read(ParserFile.F,ParserFile.ThisChar);

            { Check for newline or tab sequence }
            case ParserFile.ThisChar of
                #10,#13: begin
                    { Found either a CR or an LF, but we first do a check }
                    { to avoid double-counting DOS's CR+LF sequence as two }
                    { separate lines. }
                    if not ((ParserFile.ThisChar=#10)
                        and (ParserFile.LastChar=#13)) then
                    begin
                        { Set the end-of-line flag so we can reset the }
                        { column position and increment the line number }
                        { upon reading the next character. }
                        ParserFile.AtEndOfLine:=True;
                        Break;
                    end;
                end;
                #9: begin
                    { Tabs expand into spaces filling up to the next }
                    { multiple of 8 columns. Return a space character. }
                    ParserFile.PendingSpaces:=TabSize
                        -ParserFile.CurrentColumn mod TabSize-1;
                    ParserFile.ThisChar:=#32;
                    Break;
                end;
                #32: begin
                    { Return space characters as-is }
                    Break;
                end;
                else begin
                    { Return all other characters verbatim, and count them }
                    { towards the non-whitespace character count for the }
                    { current line. }
                    Inc(ParserFile.NonWhitespaceCharCount);
                    Break;
                end;
            end;
        until False;
    end;

    if ParserFile.ThisChar=#13 then
    begin
        { CR's need to be returned as LF's, since the rest of the parser }
        { code expects all EOL sequences to be a single LF character. }
        ReadChar:=#10;
    end else begin
        { Return current character unchanged }
        ReadChar:=ParserFile.ThisChar;
    end;
end;

{ Skips up to either the end of the current line or the end of the input }
{ stream. The input stream is either positioned at the first character on }
{ the next line, or the end of stream upon return respectively. }
procedure SkipToEol;
begin
    { Continue reading characters from the input stream until we either }
    { encounter a LF or EOF character. }
    repeat until ReadChar in [#10,#26];
end;

{ Returns the C-style backslash escape subsitution character for the given }
{ escape sequence character. This allows embedding of non-printable }
{ characters in strings. C contains the character following the backslash }
{ character. }
function BackslashEscape(C:Char):Char;
begin
    case C of
        '0': BackslashEscape:=#0;   { '\0' (Null character) }
        'a': BackslashEscape:=#7;   { '\a' (Bell character) }
        'b': BackslashEscape:=#8;   { '\b' (Backspace character) }
        't': BackslashEscape:=#9;   { '\t' (Tab character) }
        'n': BackslashEscape:=#10;  { '\n' (Line Feed character) }
        'r': BackslashEscape:=#13;  { '\r' (Carriage return character) }
        else BackslashEscape:=C;    { Return other characters verbatim }
    end;
end;

{ Marks the position of the last token. This effectively copies the }
{ current line number and column to the last token line number and column, }
{ so when highlighting the error location to the user, we can point to the }
{ start of the token rather than the end. }
procedure MarkTokenPosition;
begin
    ParserFile.LastTokenLineNumber:=ParserFile.CurrentLineNumber;
    ParserFile.LastTokenColumn:=ParserFile.CurrentColumn;
end;

{ Returns the next character of interest in the input file stream }
function GetNextChar:Char;
var
    { Contains the current character read from the input stream }
    C:Char;
begin
    { Action to take depends on current parser state }
    case ParserFile.ReadMode of
        rmLookingForCommand: begin
            { Keep reading until we either find the start of a macro }
            { command or hit the end of the stream. Comments are skipped if }
            { encountered. }
            repeat
                { Read the next character from the input stream }
                C:=ReadChar;

                case C of
                    #10,#32: begin
                        { Skip any whitespace }
                    end;
                    '#': begin
                        { Comment encountered, skip to start of next line }
                        SkipToEol;
                    end;
                    '%': begin
                        { Encountered a '%' character. Check if this is the }
                        { first non-whitespace character on the line. }
                        if ParserFile.NonWhitespaceCharCount=1 then
                        begin
                            { Found the start of a macro command. The }
                            { parser will enter the rmReadingCommand state. }
                            ParserFile.ReadMode:=rmReadingCommand;
                            ParserStatus:=prsOk;
                        end else begin
                            { Found what would have been the start of a }
                            { macro command, but it's not at the start of }
                            { the line. Flag it as junk instead. }
                            ParserFile.ReadMode:=rmError;
                            ParserStatus:=prsEOLExpected;
                        end;
                        Break;
                    end;
                    #26: begin
                        { Hit the end of the input stream }
                        ParserFile.ReadMode:=rmError;
                        ParserStatus:=prsEndOfFile;
                        Break;
                    end;
                    else begin
                        { Any other character is encountered is deemed to }
                        { be junk, so the parser will enter an error state. }
                        ParserFile.ReadMode:=rmError;
                        if ParserFile.NonWhitespaceCharCount=1 then
                        begin
                            { If this is the first non-whitespace character }
                            { on the current line, then we were expecting a }
                            { macro command. }
                            ParserStatus:=prsCommandExpected;
                        end else begin
                            { Otherwise we were expecting an end-of-line }
                            { sequence instead. }
                            ParserStatus:=prsEOLExpected;
                        end;
                        Break;
                    end;
                end;
            until False;

            { Mark the starting position of the keyword or junk }
            MarkTokenPosition;

            { Return '%' to indicate a macro command has been found, the }
            { parser will be in the rmReadingCommand state. If either the }
            { end of file was reached, or some junk characters were }
            { encountered, then the parser will be in the rmError state and }
            { ParserStatus will contain the error code. In this case the }
            { return value will be meaningless. }
            GetNextChar:=C;
        end;
        rmReadingCommand: begin
            { Read the next character of the macro command. A macro command }
            { is terminated by either whitespace, end-of-line, end of file }
            { or a comment. }
            C:=ReadChar;

            case C of
                '#': begin
                    { Comment encountered; terminate the macro command here }
                    { and skip to the beginning of the next line. }
                    SkipToEol;
                    ParserStatus:=prsOk;
                    ParserFile.ReadMode:=rmDone;
                end;
                #10,#26,#32: begin
                    { Either whitespace, EOL or EOF encountered. Terminate }
                    { the macro command here. }
                    ParserStatus:=prsOk;
                    ParserFile.ReadMode:=rmDone;
                end;
            end;

            { If the parser remains in the rmReadingCommand state, then the }
            { return value will be the next character in the macro command. }
            { Otherwise if the end of the macro command was encountered, }
            { then the parser will be in the rmDone state and the return }
            { value will be irrelevant. }
            GetNextChar:=C;
        end;
        rmLookingForKeyword: begin
            { Search for the start of a keyword. Keywords start with any }
            { non-whitespace character, with the exception of '#', which is }
            { interpreted as a comment, and '%' at the start of a line, }
            { which is interpreted as a macro command. If a macro command }
            { is encountered, then the keyword is deemed to be omitted. }
            repeat
                { Read the next character in the input stream }
                C:=ReadChar;

                case C of
                    '#': begin
                        { A comment was encountered. Skip to the start of }
                        { the next line. }
                        SkipToEol;
                    end;
                    #10,#32: begin
                        { Ignore whitespace and EOL characters }
                    end;
                    #26: begin
                        { If EOF encountered, then end the search and }
                        { indicate that the end of file has been reached. }
                        ParserFile.ReadMode:=rmError;
                        ParserStatus:=prsEndOfFile;
                        Break;
                    end;
                    '"': begin
                        { If a double quote character is encountered, then }
                        { enter double-quote parsing state. The first }
                        { character of the keyword will be the first }
                        { character in the double-quote sequence. }
                        ParserFile.ReadMode:=rmReadingQuotedString;
                        ParserStatus:=prsOk;
                        C:=GetNextChar;
                        Break;
                    end;
                    '%': begin
                        { Encountered a '%' character. Check if this is the }
                        { first non-whitespace character on the line. }
                        if ParserFile.NonWhitespaceCharCount=1 then
                        begin
                            { Encountered the start of a macro command. The }
                            { parser will enter the rmReadingCommand state, }
                            { expecting to parse the command. The keyword }
                            { that was being searched for is deemed to be }
                            { non-existant. }
                            ParserFile.ReadMode:=rmReadingCommand;
                            ParserStatus:=prsMissingParameter;
                        end else begin
                            { If the '%' character is not the first }
                            { non-whitespace character on the line, then }
                            { it is deemed to be the start of the keyword. }
                            ParserFile.ReadMode:=rmReadingKeyword;
                            ParserStatus:=prsOk;
                        end;
                        Break;
                    end;
                    else begin
                        { Any other character is encountered is deemed to }
                        { be the start of the keyword. }
                        ParserFile.ReadMode:=rmReadingKeyword;
                        ParserStatus:=prsOk;
                        Break;
                    end;
                end;
            until False;

            { Mark the starting position of the keyword/command }
            MarkTokenPosition;

            { If the parser entered the either the rmReadingKeyword or }
            { rmReadingQuotedString state, then the return value will be }
            { the first character of the keyword that was encountered. If }
            { the parser entered the rmReadingCommand state, then the }
            { return value will be a '%' character. Otherwise the parser }
            { hit the end of the input stream, so the parser will be in the }
            { rmError state and the return value will be meaningless. }
            GetNextChar:=C;
        end;
        rmReadingKeyword: begin
            { Read the next character from the input stream }
            C:=ReadChar;

            case C of
                '#': begin
                    { A comment was encountered. Terminate the keyword here }
                    { and skip to the start of the next line. }
                    SkipToEol;
                    ParserFile.ReadMode:=rmDone;
                    ParserStatus:=prsOk;
                end;
                #10,#26,#32: begin
                    { Either whitespace, EOL or EOF encountered. Terminate }
                    { the keyword here. }
                    ParserFile.ReadMode:=rmDone;
                    ParserStatus:=prsOk;
                end;
            end;

            { If the parser remains in the rmReadingKeyword state, then the }
            { return value will be the next character in the keyword. }
            { Otherwise if the end of the keyword was encountered, then the }
            { parser will be in the rmDone state and the return value will }
            { be irrelevant. }
            GetNextChar:=C;
        end;
        rmReadingQuotedString: begin
            { Read the next character within the double-quoted string. The }
            { double-quoted string is deemed to be terminated successfully }
            { if there is a double-quote character followed by a whitespace }
            { or comment. The double-quoted string is deemed to be }
            { terminated incorrectly if the end of the line or end of the }
            { file is encountered, or there is junk directly following the }
            { terminating double quote. Within the double-quoted string, }
            { C-style backslash escapes will be interpreted. }
            C:=ReadChar;

            case C of
                '"': begin
                    { Encountered the trailing double-quote character. }
                    { Terminate the double-quoted string here. Check if the }
                    { following character is either whitespace or the end }
                    { of file. }
                    C:=ReadChar;
                    if C in [#10,#26,#32] then
                    begin
                        { The double-quoted string has been successfully }
                        { terminated, so the parser will revert back to the }
                        { rmDone state. }
                        ParserFile.ReadMode:=rmDone;
                        ParserStatus:=prsOk;
                    end else if C='#' then begin
                        { If a comment directly follows the trailing }
                        { double-quoted string, then skip the comment and }
                        { set the parser back into the rmDone state. }
                        SkipToEol;
                        ParserFile.ReadMode:=rmDone;
                        ParserStatus:=prsOk;
                    end else begin
                        { Found some junk directly trailing the }
                        { double-quoted string. Flag an error. }
                        ParserFile.ReadMode:=rmError;
                        ParserStatus:=prsWhitespaceExpected;
                        MarkTokenPosition;
                    end;
                end;
                '\': begin
                    { Encountered a backslash character. The following }
                    { character is interpeted as a C-style escape sequence. }
                    { The next character in the keyword will be the }
                    { character that is formed from the escape sequence. }
                    C:=BackslashEscape(ReadChar);
                    ParserStatus:=prsOk;
                end;
                #26,#10: begin
                    { Encountered either the end of the line or the end of }
                    { the input stream. This means the quoted string is }
                    { unterminated, so the parser will enter the error }
                    { state. }
                    ParserFile.ReadMode:=rmError;
                    ParserStatus:=prsMissingQuote;
                    MarkTokenPosition;
                end;
                else begin
                    { Encountered an ordinary character }
                    ParserStatus:=prsOk;
                end;
            end;

            { If the parser remains in the rmReadingQuotedString state, }
            { then the return value will be the next character in the }
            { keyword. If the end of the double-quoted string was }
            { encountered, then the parser will be either in the rmDone }
            { or rmError state and the return value will be irrelevant. }
            GetNextChar:=C;
        end;
        rmLookingForTextStream: begin
            { Searching for the start of a text stream sequence. A text }
            { stream sequence starts with a non-whitespace character that }
            { is not a '#' character or a '%' character that is the first }
            { on the line. Comments leading up to the start of the text }
            { stream are skipped over. If a macro command is encountered or }
            { the end of the input stream is encountered, then the text }
            { stream is deemed to have zero length. }
            repeat
                { Read the next character from the input stream }
                C:=ReadChar;

                case C of
                    '#': begin
                        { Comment encountered; skip to the start of the }
                        { next line. }
                        SkipToEol;
                    end;
                    '%': begin
                        { Encountered a '%' character. Check if this is the }
                        { first non-whitespace character on the line. }
                        if ParserFile.NonWhitespaceCharCount=1 then
                        begin
                            { Encountered the start of a macro command. The }
                            { parser will enter the rmReadingCommand state, }
                            { expecting to parse the command. The text }
                            { stream that was being searched for is deemed }
                            { to be of zero length. }
                            ParserFile.ReadMode:=rmReadingCommand;
                            ParserStatus:=prsOk;
                        end else begin
                            { If the '%' character is not the first }
                            { non-whitespace character on the line, then }
                            { it is deemed to be the start of the text }
                            { stream. }
                            ParserFile.ReadMode:=rmReadingTextStream;
                            ParserStatus:=prsOk;
                        end;
                        Break;
                    end;
                    #10,#32: begin
                        { Ignore any whitespace or end-of-line sequences }
                        { leading up to the start of the text stream. }
                    end;
                    #26: begin
                        { If the end of the input stream is encounterd, }
                        { then the text stream is deemed to be of zero }
                        { length. }
                        ParserFile.ReadMode:=rmDone;
                        ParserStatus:=prsOk;
                        Break;
                    end;
                    '\': begin
                        { If a backslash character is encountered, then the }
                        { C-style escape sequence that follows forms the }
                        { first character of the text stream. This may be }
                        { required if the first character of the text }
                        { stream is either '#', '%' or a space. }
                        C:=BackslashEscape(ReadChar);
                        ParserFile.ReadMode:=rmReadingTextStream;
                        ParserStatus:=prsOk;
                        Break;
                    end;
                    else begin
                        { If any other character is encountered, then the }
                        { character forms the start of the text stream. }
                        ParserFile.ReadMode:=rmReadingTextStream;
                        ParserStatus:=prsOk;
                        Break;
                    end;
                end;
            until False;

            { Mark the starting position of the text stream/command }
            MarkTokenPosition;

            { If the parser is in the state rmReadingTextStream, the return }
            { value will be the first character of the text stream. If the }
            { parser is in the state rmReadingCommand, then the return }
            { value will be '%'. Otherwise the parser will be in the rmDone }
            { state and the return value will be irrelevant. }
            GetNextChar:=C;
        end;
        rmReadingTextStream: begin
            { Read the next character in the text stream. The text stream }
            { is terminated by either a macro command or the end of file. }
            { Comments appearing in the text stream are filtered out. }
            { Trailing whitespace leading up to comments and trailing }
            { blank lines leading up to the following macro command or end }
            { of file are also filtered out. C-style backslash escape }
            { sequences may also appear within the text stream in order to }
            { specify non-printable characters or the '%', '#' and space }
            { characters, to prevent them from being interpreted as macro }
            { commands, comments and trailing whitespace respectively. }

            { Check if we already haven't accumulated some pending }
            { characters. If we have, then they need to be returned first }
            { before reading further on in the input file. }
            if (ParserFile.TextStreamPendingNewlines=0)
                and (ParserFile.TextStreamPendingSpaces=0)
                and not ParserFile.TextStreamPendingCharAvailable then
            begin
                { Search for the next character in the text stream. Collect }
                { up trailing whitespace and newlines if necessary. Stop }
                { searching when we either encounter a macro command or the }
                { end of file (which terminates the text stream), or a }
                { non-whitespace character (which requires all pending }
                { whitespace to be flushed first). }

                repeat
                    { Read the next character from the input stream }
                    C:=ReadChar;

                    case C of
                        #32: begin
                            { Accumulate another space character }
                            Inc(ParserFile.TextStreamPendingSpaces);
                        end;
                        #10: begin
                            { Encountered a newline. Remove all pending }
                            { spaces, since they're trailing, and }
                            { accumulate another newline. }
                            ParserFile.TextStreamPendingSpaces:=0;
                            Inc(ParserFile.TextStreamPendingNewlines);
                        end;
                        '#': begin
                            { Encountered a comment. Skip to the start of }
                            { the next line, clear all pending whitespace }
                            { (since it's trailing) and add a pending }
                            { newline. }
                            SkipToEol;
                            ParserFile.TextStreamPendingSpaces:=0;
                            Inc(ParserFile.TextStreamPendingNewlines);
                        end;
                        '%': begin
                            { Check if this is the first non-whitespace }
                            { character on the current line. }
                            if ParserFile.NonWhitespaceCharCount=1 then
                            begin
                                { Encountered the start of a macro command. }
                                { The parser will enter the }
                                { rmReadingCommand state, expecting to }
                                { parse the command. The text stream }
                                { terminates here, so remove all pending }
                                { characters. }
                                ParserFile.ReadMode:=rmReadingCommand;
                                ParserFile.TextStreamPendingSpaces:=0;
                                ParserFile.TextStreamPendingNewlines:=0;
                                ParserFile.TextStreamPendingCharAvailable:=
                                    False;
                            end else begin
                                { This is not the first non-whitespace }
                                { character on the current line, so it is }
                                { still considered part of the text stream. }
                                ParserFile.TextStreamPendingChar:='%';
                                ParserFile.TextStreamPendingCharAvailable:=
                                    True;
                            end;
                            Break;
                        end;
                        '\': begin
                            { Found a C-style backslash escape sequence. }
                            { Expand it to form the next non-whitespace }
                            { character in the text stream. Flush all }
                            { pending whitespace, since it's not trailing. }
                            { This character will be returned once all }
                            { pending whitespace is returned. }
                            ParserFile.TextStreamPendingChar:=
                                BackslashEscape(ReadChar);
                            ParserFile.TextStreamPendingCharAvailable:=True;
                            Break;
                        end;
                        #26: begin
                            { Encountered the end of the input stream. The }
                            { text stream is terminated here, so remove all }
                            { pending characters. }
                            ParserFile.ReadMode:=rmDone;
                            ParserFile.TextStreamPendingSpaces:=0;
                            ParserFile.TextStreamPendingNewlines:=0;
                            ParserFile.TextStreamPendingCharAvailable:=False;
                            Break;
                        end;
                        else begin
                            { Found a non-whitespace character. Flush all }
                            { pending whitespace. This character will be }
                            { returned once all pending whitespace is }
                            { returned. }
                            ParserFile.TextStreamPendingChar:=C;
                            ParserFile.TextStreamPendingCharAvailable:=True;
                            Break;
                        end;
                    end;
                until False;
            end;

            { Check if there are any pending characters that need flushing }
            if ParserFile.TextStreamPendingNewlines>0 then
            begin
                { If there are pending newlines that need to be included }
                { in the text stream, then return them one at a time. }
                GetNextChar:=#10;
                Dec(ParserFile.TextStreamPendingNewlines);
            end else if ParserFile.TextStreamPendingSpaces>0 then begin
                { If there are pending spaces that need to be included in }
                { the text stream, then return them one at a time. }
                GetNextChar:=#32;
                Dec(ParserFile.TextStreamPendingSpaces);
            end else if ParserFile.TextStreamPendingCharAvailable then begin
                { If there is a pending non-whitespace character that }
                { needs to be read, then return it. }
                GetNextChar:=ParserFile.TextStreamPendingChar;
                ParserFile.TextStreamPendingCharAvailable:=False;
            end else begin
                { The text stream was terminated, so return either a '%' }
                { character if a macro command was found, or an EOF }
                { character if the end of the input stream was reached. }
                GetNextChar:=C;
            end;

            { If the parser is still in the state rmReadingTextStream, the }
            { return value will be the next character of the text stream. }
            { If the parser is in the state rmReadingCommand, then the }
            { return value will be '%'. Otherwise the parser will be in the }
            { rmDone state and the return value will be irrelevant. }
            ParserStatus:=prsOk;
        end;
        else begin
            { Parser is in either the rmDone or rmError states. No reads }
            { are supposed to be performed in these states. }
            GetNextChar:=#0;
        end;
    end;
end;

{ Parses a variable-size integer in string form. }
procedure ParseLiteralInt(const NStr:String; var Size:Integer; var N:Longint);
var
    { Storage for assembling the string form of the integer }
    S:String;

    { Whether the parsed integer should be offset by the base segment; }
    { only supported for 16-bit words. }
    NeedsOffset:Boolean;

    { Contains the index of the first erroneous character when parsing }
    Code:Integer;

    { The segment offset, shifted into the upper word }
    BigOffset:Longint;
begin
    { Copy the string into a mutable string buffer }
    S:=NStr;
    
    { Shift the segment offset into the upper word for 32-bit relative values }
    BigOffset:=ParserBase;
    BigOffset:=(BigOffset shl 16);

    { Check if the string begins with the '0x' C-style hex base specifier }
    if (Length(S)>=2) and (S[1]='0') and (UpCase(S[2])='X') then
    begin
        { Replace the '0x' with the Pascal-style '$' hex base specifier so }
        { the Val procedure can recognise the hexadecimal base. }
        Delete(S,1,2);
        Insert('$',S,1);
    end;

    { Now check the size of the string, based on the suffix }
    if (Length(S)>=1) then
    begin
        if (UpCase(S[Length(S)])='W') then
        begin
            { Remove the 'W'; we're dealing with a word }
            Delete(S,Length(S),1);
            Size:=2
        end else if (UpCase(S[Length(S)])='L') then
        begin
            { Remove the 'L'; we're dealing with a long }
            Delete(S,Length(S),1);
            Size:=4
        end else
        begin
            { We're dealing with a byte }
            Size:=1
        end;
    end;

    { Check if the string ends with an 'R' }
    if (Length(S)>=1) and (UpCase(S[Length(S)])='R') then
    begin
        { Remove the 'R' and remember that it was there }
        Delete(S,Length(S),1);
        NeedsOffset:=True;
    end else begin
        NeedsOffset:=False;
    end;

    { Parse the string into an integer }
    Val(S,N,Code);

    { Check if the attempt to parse the string was successful }
    ParserStatus:=prsOk;
    if Code<>0 then
    begin
        { Some or none of the characters in the string were successfully }
        { parsed as an integer, so flag a numeric format error. The return }
        { value will be meaningless. }
        ParserStatus:=prsInvalidNumericFormat;
        N:=0;
    end else begin
        { Check if we need to adjust the base offset for a 16-bit integer }
        if NeedsOffset then
        begin
            if Size=2 then
            begin
                N:=N+ParserBase;
            end else if Size=4 then
            begin
                N:=N+BigOffset;
            end else begin
                { Flag a numeric format error. The return value will be meaningless. }
                ParserStatus:=prsInvalidNumericFormat;
                N:=0;
            end;
        end;

        { Do a sanity check on the size of the value }
        if (ParserStatus=prsOk) and ((Size=1) and (N > 255)) or ((Size=2) and (N > 65535)) then
        begin
            { Flag a numeric format error. The return value will be meaningless. }
            ParserStatus:=prsInvalidNumericFormat;
            N:=0;
        end;

        { The entire string was successfully parsed into an integer. The }
        { return value will be the parsed integer. }
    end;
end;

{ Parses an integer in string form. C-style '0x' hex base prefixes are also }
{ recognised. If parsing is successful, then ParserStatus will be set to }
{ prsOk and the parsed integer will be returned. If parsing fails, then }
{ ParserStatus will be set to prsInvalidNumericFormat and the return value }
{ will be meaningless. }
function ParseLongint(const NStr:String):Longint;
var
    { Storage for assembling the string form of the integer }
    S:String;

    { Storage for the parsed integer }
    N:Longint;

    { Contains the index of the first erroneous character when parsing }
    Code:Integer;
begin
    { Copy the string into a mutable string buffer }
    S:=NStr;

    { Check if the string begins with the '0x' C-style hex base specifier }
    if (Length(S)>=2) and (S[1]='0') and (UpCase(S[2])='X') then
    begin
        { Replace the '0x' with the Pascal-style '$' hex base specifier so }
        { the Val procedure can recognise the hexadecimal base. }
        Delete(S,1,2);
        Insert('$',S,1);
    end;

    { Parse the string into an integer }
    Val(S,N,Code);

    { Check if the attempt to parse the string was successful }
    if Code<>0 then
    begin
        { Some or none of the characters in the string were successfully }
        { parsed as an integer, so flag a numeric format error. The return }
        { value will be meaningless. }
        ParserStatus:=prsInvalidNumericFormat;
        ParseLongint:=0;
    end else begin
        { The entire string was successfully parsed into an integer. The }
        { return value will be the parsed integer. }
        ParseLongint:=N;
        ParserStatus:=prsOk;
    end;
end;

procedure SetParserBase(NewBase:Word);
begin
    ParserBase:=NewBase;
end;

procedure OpenParserFile(const FileName:String);
begin
    { Open the script file in read-only mode }
    FileMode:=0;
    Assign(ParserFile.F,FileName);
    Reset(ParserFile.F);

    { Check if the file opened successfully }
    if IOResult=0 then
    begin
        { If the file opened successfully, initialise parser state. }
        ParserFile.CurrentLineNumber:=1;
        ParserFile.CurrentColumn:=0;
        ParserFile.LastTokenLineNumber:=1;
        ParserFile.LastTokenColumn:=0;
        ParserFile.NonWhitespaceCharCount:=0;
        ParserFile.LastChar:=#0;
        ParserFile.ThisChar:=#0;
        ParserFile.PendingSpaces:=0;
        ParserFile.AtEndOfLine:=False;
        ParserFile.ReadMode:=rmDone;
        ParserFile.TextStreamPendingSpaces:=0;
        ParserFile.TextStreamPendingNewlines:=0;
        ParserFile.TextStreamPendingCharAvailable:=False;
        ParserFile.TextStreamPendingChar:=#0;
        ParserStatus:=prsOk;
    end else begin
        { Couldn't open the script file }
        ParserStatus:=prsErrorOpeningFile;
    end;
end;

procedure CloseParserFile;
begin
    { Close the script file and return successful status }
    Close(ParserFile.F);
    ParserStatus:=prsOk;
end;

function GetLastTokenLineNumber:Integer;
begin
    { Return the line number that the last token read was on }
    GetLastTokenLineNumber:=ParserFile.LastTokenLineNumber;
end;

function GetLastTokenColumn:Integer;
begin
    { Return the column number that the last token read was on }
    GetLastTokenColumn:=ParserFile.LastTokenColumn;
end;

function GetCommand:String;
var
    { Storage for assembling the macro command name }
    S:String;

    { Storage for current character in input stream }
    C:Char;
begin
    { Initially the macro command string is zero length }
    S:='';

    { Check if we have already found the start of a command }
    if ParserFile.ReadMode<>rmReadingCommand then
    begin
        { Search for the start of the next macro command, and read the }
        { first character of it. }
        ParserFile.ReadMode:=rmLookingForCommand;
        C:=GetNextChar;
    end else begin
        { The '%' character has already been read, because it was stumbled }
        { upon while reading something else. Add it to the start of the }
        { macro command name. }
        C:='%';

        { Mark the token position of the command as well, since text }
        { that are terminated only by macro commands still need to retain }
        { their token position so errors can be reported to the user with }
        { the correct context. }
        MarkTokenPosition;
    end;

    { If we had to search for the start of the next macro command, then }
    { only try to read the macro command name if we managed to find one. If }
    { the input stream was already positioned at the start of the macro }
    { command when this function was called, then continue reading the name }
    { of the macro command. }
    while ParserFile.ReadMode=rmReadingCommand do
    begin
        { Check if there is room in the string to add another character }
        if Length(S)<High(S) then
        begin
            { Add the last character to the macro command. Read the next }
            { character and convert it to lowercase. }
            S:=S+C;
            C:=LoCase(GetNextChar);
        end else begin
            { The string has overflowed }
            ParserFile.ReadMode:=rmError;
            ParserStatus:=prsParameterTooLong;
        end;
    end;

    { If the attempt to read the macro command succeeded, then the return }
    { value will contain the macro command name. Otherwise either the end }
    { of the input file was reached, the command name was too long, or junk }
    { was encountered, so the return value will be meaningless. }
    GetCommand:=S;
end;

function GetLongint:Longint;
var
    { Storage for assembling the string form of the integer }
    S:String;
begin
    { Read the next word from the input stream }
    S:=GetWord;

    { If we successfully read a word, try parsing it into an integer }
    if ParserStatus=prsOk then
    begin
        { Parse the string into an integer. If the parse attempt is }
        { successful, then ParserStatus will remain set to prsOk and the }
        { parsed value will be returned. Otherwise ParserStatus will be set }
        { to prsInvalidNumericFormat and the return value will be }
        { meaningless. }
        GetLongint:=ParseLongint(S);
    end else begin
        { We weren't even able to find the next word in the input file. }
        { Either we reached the end of file or encountered a macro command. }
        { The return value will be meaningless. }
        GetLongint:=0;
    end;
end;

function GetWord:String;
var
    { Storage for assembling the word }
    S:String;

    { Storage for the current character in the input stream }
    C:Char;
begin
    { Initially assume the word is non-existant }
    S:='';

    { Check if the parser hasn't already stumbled across a macro command }
    if ParserFile.ReadMode<>rmReadingCommand then
    begin
        { Find the start of the next word in the input file and read the }
        { first character of it. If the parser stumbles across a macro }
        { command, then we'll end up reading the first character of that }
        { instead. If we hit the end of file, then the contents of C will }
        { be meaningless. }
        ParserFile.ReadMode:=rmLookingForKeyword;
        C:=GetNextChar;
    end else begin
        { The keyword is deemed to be omitted }
        ParserStatus:=prsMissingParameter;
    end;

    { Providing the parser hasn't encountered a macro command or the }
    { end of the file, then add the first character to the word string }
    { and read the remaining characters that make up the word. Keep }
    { adding characters to the word string until we read past the last }
    { character in the word. }
    while ParserFile.ReadMode in [rmReadingKeyword,rmReadingQuotedString] do
    begin
        { Check if there is room in the string to add another character }
        if Length(S)<High(S) then
        begin
            { Add the last character to the word string and read the next }
            S:=S+C;
            C:=GetNextChar;
        end else begin
            { The string has overflowed }
            ParserFile.ReadMode:=rmError;
            ParserStatus:=prsParameterTooLong;
        end;
    end;

    { The return value will only be meaningful if a word was found }
   GetWord:=S;
end;

function GetText:String;
var
    { Storage for the text stream }
    S:String;

    { Storage for the current character in the input file }
    C:Char;
begin
    { Initially the text stream starts out empty }
    S:='';

    { Check if the parser hasn't already stumbled across a macro command }
    if ParserFile.ReadMode<>rmReadingCommand then
    begin
        { If the parser hasn't found a macro command, then search for the }
        { start of the text stream and read the first character of it. If }
        { we encounter a macro command instead, then we'll end up reading }
        { the first character of it. If we hit the end of file, then what }
        { we read will be meaningless. }
        ParserFile.ReadMode:=rmLookingForTextStream;
        C:=GetNextChar;
    end;

    { Providing the parser hasn't encountered a macro command or the }
    { end of the file, then add the first character to the text stream }
    { and read the remaining characters that make up the text stream. }
    { Keep adding characters to the text stream until we read past the }
    { last character in the text stream. }
    while ParserFile.ReadMode=rmReadingTextStream do
    begin
        { Check if there is room in the string to add another character }
        if Length(S)<High(S) then
        begin
            { Add the last character to the text stream and read the next }
            S:=S+C;
            C:=GetNextChar;
        end else begin
            { The string has overflowed }
            ParserFile.ReadMode:=rmError;
            ParserStatus:=prsParameterTooLong;
        end;
    end;

    { Return the resulting text stream to the caller }
    GetText:=S;
end;

procedure GetByteArray(var DataLength:Word;var Data:array of Byte);
var
    { Storage for assembling the current keyword }
    S:String;

    { Storage for the current character in the input stream }
    C:Char;

    { Storage for the parsed byte values }
    N:Longint;

    { Size of the parsed byte value }
    Size:Integer;
    
    { Byte for storing partial value }
    B:Byte;
begin
    { Initially the byte array starts off empty }
    DataLength:=0;

    { Check if the parser hasn't already stumbled across a macro command }
    if ParserFile.ReadMode=rmReadingCommand then
    begin
        { If the parser has already encountered a macro command, then the }
        { byte array is deemed to be omitted. }
        ParserStatus:=prsMissingParameter;
    end;

    { Keep reading byte and string keywords until either a macro command is }
    { encountered, the end of the input stream is reached, or an error }
    { parsing the byte array is encountered. }
    while ParserStatus=prsOk do
    begin
        { Search for the next keyword in the input stream and read the }
        { first character of it. If we encounter a macro command instead, }
        { then the parser will be in the rmReadingCommand state. If we hit }
        { the end of the input stream, then the parser will be in the }
        { rmDone state. }
        ParserFile.ReadMode:=rmLookingForKeyword;
        C:=GetNextChar;

        { Check what we actually encountered }
        case ParserFile.ReadMode of
            rmReadingKeyword: begin
                { Encountered a keyword, which is to be interpreted as a }
                { one, two, or four byte value. Initialise the byte string }
                 { buffer in order to assemble the byte string. }
                S:='';

                { Continue reading remaining characters of the byte string }
                while ParserFile.ReadMode=rmReadingKeyword do
                begin
                    { Check if there is room in the string to add another }
                    { character. }
                    if Length(S)<High(S) then
                    begin
                        { Add the last character to the byte string and }
                        { read the next character from the input stream. }
                        S:=S+C;
                        C:=GetNextChar;
                    end else begin
                        { The string has overflowed }
                        ParserFile.ReadMode:=rmError;
                        ParserStatus:=prsParameterTooLong;
                    end;
                end;

                { Check if the integer was read successfully }
                if ParserStatus=prsOk then
                begin
                    { Parse the byte string into an integer }
                    ParseLiteralInt(S, Size, N);
                end;

                { Check if the byte was successfully parsed }
                if ParserStatus=prsOk then
                begin
                    { Check if there is room in the byte array }
                    if DataLength+Size<High(Data)-Low(Data)+1 then
                    begin
                        { Add the bytes to the byte array, lo byte first }
                        while Size<>0 do
                        begin
                            B:=(N and $ff);
                            Data[DataLength]:=B;
                            Inc(DataLength);
                            N:=(N div 256);
                            Dec(Size);
                        end;
                    end else begin
                        { The byte array is too long, flag an error. }
                        ParserStatus:=prsParameterTooLong;
                        Break;
                    end;
                end;
            end;
            rmReadingQuotedString: begin
                { Encountered a quoted string, which is to be interpreted }
                { as a string of bytes. Keep reading characters until we }
                { reach the end of the word, and add each character }
                { directly into the byte array. }
                while (ParserFile.ReadMode=rmReadingQuotedString)
                    and (ParserStatus=prsOk) do
                begin
                    { Check if there is room in the byte array }
                    if DataLength<High(Data)-Low(Data)+1 then
                    begin
                        { Add the last character read to the byte array }
                        Data[DataLength]:=Ord(C);
                        Inc(DataLength);
                    end else begin
                        { The byte array is too long, flag an error and }
                        { stop parsing the byte array. }
                        ParserStatus:=prsParameterTooLong;
                    end;

                    { Read the next character from the input stream }
                    C:=GetNextChar;
                end;
            end;
        end;
    end;

    { Check if at least one byte was read, but ParserStatus is set to }
    { prsMissingParameter or prsEndOfFile. }
    if (DataLength>0)
        and (ParserStatus in [prsMissingParameter,prsEndOfFile]) then
    begin
        { The missing parameter is flagged because we tried to check for }
        { the presence of another byte or string, but there wasn't one. }
        { Since we already have at least one byte in the byte array, then }
        { this isn't an error condition, so return successful status. }
        ParserStatus:=prsOk;
    end;
end;

end.
