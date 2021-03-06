// Module showing network traffic. Shows how much data has been received (RX) or
// transmitted (TX) since the previous time this script ran.

program netTraffic;
{$modeswitch result+} // Infers result type (I think)
{$mode objfpc}
{$m+}

uses 
    Dos, Sysutils, Dateutils, Math, md5, StrUtils, RegExpr;

(* Keep track of one file *)
type
    TDataPoint = class
    private
        FSourceFile: String;
        FCacheFile: String;

        FSourceModTimestamp: Int32;
        FCachedModTimestamp: Int32;

        FSource: Int32;
        FCached: Int32;
    public
        constructor Init;
        procedure ReadData(src: String);
        procedure CacheData;
        function GetSource: Integer;
        function GetCached: Integer;
        function GetDiff:   Integer;
        function GetDelta:  Integer;
    end;

type
    TStrArray = array of String;

(* Read one line from one file *)
function FileReadLine(FileName: string): string;
var
    F:  TextFile;
begin
    Assign(F, FileName);
    Reset(F);
    ReadLn(F, result);
    Close(F);
end;

(* Write one line to one file *)
procedure FileWriteLine(FileName: string; Store: string);
var
    F:  TextFile;
begin
    Assign(F, FileName);
    ReWrite(F);
    WriteLn(F, Store);
    Close(F);
end;

constructor TDataPoint.Init;
begin
    FSourceModTimestamp := 0;
    FCachedModTimestamp := 0;

    FSource := 0;
    FCached := 0;
end;

procedure TDataPoint.ReadData(Src: String);
begin
    FSourceFile := Src;
    FCacheFile := GetEnv('XDG_RUNTIME_DIR') + '/sysdelta/' + MD5Print(MD5String(Src));
    
    FSourceModTimestamp := FileAge(FSourceFile);
    FCachedModTimestamp := FileAge(FCacheFile);

    FSource := StrToInt(fileReadLine(FSourceFile));

    if FileExists(FCacheFile) then 
    FCached := StrToInt(fileReadLine(FCacheFile));
end;

procedure TDataPoint.CacheData;
begin
    ForceDirectories(GetEnv('XDG_RUNTIME_DIR') + '/sysdelta/');
    FileWriteLine(FCacheFile, IntToStr(FSource));
end;

function TDataPoint.GetSource: Integer;
begin Result := FSource; end;

function TDataPoint.GetCached: Integer;
begin Result := FCached; end;

function TDataPoint.GetDiff: Integer;
begin Result := FCached - FSource; end;

function TDataPoint.GetDelta: Integer;
var
    TimeDiff: Int32;
begin
    TimeDiff := FSourceModTimestamp - FCachedModTimestamp;
    if TimeDiff = 0 then TimeDiff := 1;
    Result := (FCached - FSource) div TimeDiff;
end;

procedure Die(Code: Integer; Message: string);
begin
    WriteLn(Message);
    halt(Code);
end;

procedure WriteHelp();
begin
    WriteLn('Usage: filedelta <format> file...');
    WriteLn('Format: Like pascal string formats. Except placeholder values denotes how to display file data');
    WriteLn('           Supports indenting like usual');
    WriteLn('Values: %a         Plain. Write the file content directly out');
    WriteLn('        %b         Diff from cache');
    WriteLn('        %c         Plain. Returns what was cached');
    WriteLn('        %d[:<n>]   Delta from cache. Default is to show the difference in seconds');
    WriteLn('                       n if set can scale the result to another units of time');
    WriteLn('                       For example setting n to 60 makes the unit of time in minutes rather in seconds');
    WriteLn('                       Sampling (how often to run this program) should somewhat reflect what you set to n');
    WriteLn('                           as data will become inaccurate if sampling to often');
    WriteLn('        %i         IEC Byte rounding. Gains one prefix of [KiB, MiB, GiB, ..., YiB]');
    WriteLn('        %j         IEC Byte rounding + diff');
    WriteLn('        %k[:<n>]   IEC Byte rounding + delta');
    WriteLn('        %l');
    WriteLn('        %s         Si-Byte rounding. Gains one prefix of [KB, MB, GB, ..., YB');
    WriteLn('        %t         Si-Byte rounding + diff');
    WriteLn('        %u[:<n>]   Si-Byte rounding + delta');
    WriteLn('        %v');
end;

procedure MaybeHelp(param: String);
var help: boolean = false;
begin
    case param of
    '-h':       help := true;
    'help':     help := true;
    '--help':   help := true;
    end;

    if help then
    begin
        writeHelp;
        halt(0);
    end;
end;

(*
    Takes an format string and returns a dynamic array of strings, 
    divided by their format functionality. Strings with no format functionality
    is placed in odd cells and strings with format functionality is placed in even 
    cells. Remember that arrays are zero indexed.

    Method will return empty strings inbetween format strings if no contextual
    strings are placed between format strings.
*)
function FormatSplitter(const format: String): TStrArray;
var
    buf: String = '';
    i: Integer = 0;
    ptr: Integer = 0;

begin    
    (* Guess the needed array capacity *)
    for i := 1 to Length(format) do
        if format[i] = '%' then
            ptr := ptr + 2;
    SetLength(result, ptr + 1);

    (* For loop with mutable i *)
    i := 1;
    ptr := 0;
    while i <= Length(format) do
    begin
        if (ptr mod 2) = 1 then                         (* State is odd *)
        begin
            buf := buf + format[i];                     (* Append anything and delim *)
            if format[i] in ['A'..'Z', 'a'..'z'] then   (* Switch state and flush buffer *)
            begin
                result[ptr] := buf;                     
                inc(ptr);
                buf := '';
            end
        end                                             (* State is even *)
        else if format[i] <> '%' then                   (* Not format delimeter so safe to append *)
            buf := buf + format[i]
        else if i = Length(format) then                 (* Check for  out of bounds and throw error*)
            raise Exception.Create('Malformed format string. Format contains no rules')
        else if format[i+1] = '%' then                  (* Lookahead for escaped % and append it *)
        begin
            buf := buf + '%';
            Inc(i);
        end
        else  
        begin                                           (* Switch state and flush buffer *)
            result[ptr] := buf;
            inc(ptr);
            buf := '';
        end;

        Inc(i);
    end;

    if buf = '' then
        ptr := ptr - 1          (* Move pointer back to last used cell *)
    else if (ptr mod 2) = 1 then
        raise Exception.Create('Malformed format string. Format has no ending character')
    else
        result[ptr] := buf;     (* Putting in leftovers from buffer *)

    SetLength(result, ptr + 1); (* Shrink array to actual needed capacity *)
end;

(* 
    Round a float to a certain number of characters, removing '.' 
    if no decimal fits
*)
function RoundFloat(X: Double; Len: Integer): string;
var
    Buf: String;
begin
    Buf := Copy(FloatToStr(X), 1, Len);
    if RightStr(Buf, 1)='.' then
    begin
       Insert(' ', Buf, 1);
       SetLength(Buf, Length(Buf) -1);
    end;
    Result := buf;
end;

(* Rounds up bytes to largest byte power *)
function PostFixBytes(bytes: Int64): string;
const
    Suffixes: array of string=('B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB');
var
    I: Integer = 0;
begin
    while bytes >> (10 * I) >= 1024 do Inc(I);
    Result := RoundFloat(bytes / power(1024, i), 5) + Suffixes[I];
end;

var
    I:          Integer;
    DataPoints: array of TDataPoint;
    DataPoint:  TDataPoint;
    DataPtr:    Integer = 0;
    DataStr:    String;
    FormArr:    TStrArray;
    FormArg:    String;
    FormEnd:    String;

begin
    if (ParamCount < 1) or (Length(ParamStr(1)) = 0) then
    begin
        writeHelp;
        halt(1);
    end;

    (* Check for help option and exit *)
    for I := 1 to ParamCount-1 do
        maybeHelp(ParamStr(I));

    (* Initiate array of Data objects with *)
    SetLength(DataPoints, ParamCount - 1);
    for I := 0 to Length(DataPoints)-1 do // Skip format section
    begin
        DataPoints[I] := TDataPoint.Init;
        DataPoints[I].ReadData(ParamStr(I+2));
    end;

    FormArr := FormatSplitter(ParamStr(1));
    for I := 0 to Length(FormArr) -1 do
        if (I mod 2) = 0 then
            Write(Format('%s', [FormArr[I]]))
        else
        begin
            FormArg := '%' + Copy(FormArr[I], 1, Length(FormArr[I]) -1) + 's';
            FormEnd := formArr[I][Length(FormArr[I])];

            DataPoint := DataPoints[DataPtr];

            case FormEnd of
                'a': DataStr := IntToStr(DataPoint.GetSource);
                'b': DataStr := IntToStr(DataPoint.GetDiff);
                'c': DataStr := IntToStr(DataPoint.GetCached);
                'd': DataStr := IntToStr(DataPoint.GetDelta);
                'i': DataStr := PostFixBytes(DataPoint.GetSource);
                'j': DataStr := PostFixBytes(DataPoint.GetDiff);
                'k': DataStr := PostFixBytes(DataPoint.GetCached);
                'l': DataStr := PostFixBytes(DataPoint.GetDelta);
                'n': if FormArg = '%s' then 
                begin 
                    WriteLn;
                    continue;
                end
                else Die(1, 'Newline takes no format argument');
            //  's': WriteLn(DataPoint);
            //  't': WriteLn(DataPoint);
            //  'u': WriteLn(DataPoint);
            else
                WriteLn;
                Die(1, 'Not a legal placeholder value: ' + FormArr[I]);
            end;

            Write(Format(FormArg, [DataStr]));
            Inc(DataPtr);
        end;

    (* Save in cache *)
    for I := 0 to Length(DataPoints) -1 do
        DataPoints[I].CacheData;
end.
