{$I COMPILER_DIRECTIVES.INC}
unit misc_functions;

interface

uses System.Types, System.Classes, System.SysUtils, System.StrUtils, System.UITypes, System.Math, System.Diagnostics, System.SyncObjs,
  System.Generics.Collections;


procedure Split(S : String; Ch : Char; sList : TStrings);
function  ValidLine(S : String) : Boolean;
function  sParamCount(S : String) : Integer;
function  GetSParam(PItem : Integer; PList : String; StripSpace : Boolean) : String;
function  GetSLeftParam(S : String) : String;
function  GetSRightParam(S : String; StripSpace : Boolean) : String;


{$IFDEF TRACEDEBUG}
procedure AddDebugEntry(S : String);
{$IFDEF TRACEDEBUGMEMORY}
procedure FinalizeMemoryDebug;
{$ENDIF}{$ENDIF}

var
  clientStopWatch : TStopWatch;

implementation

{$IFDEF TRACEDEBUG}
const
  clientDebugFile      : String  = 'debuginfo.txt';
  clientDebugPath      : String  = 'c:\GameServices\';


var
  csDebug              : TCriticalSection = nil;
  {$IFDEF TRACEDEBUGMEMORY}
  MemDebugList         : TStringList;
  {$ENDIF}
{$ENDIF}

{$ZEROBASEDSTRINGS OFF}
procedure Split(S : String; Ch : Char; sList : TStrings);
var
  I     : Integer;
  lCopy : Integer;
  sLen  : Integer;
begin
  lCopy := 1;
  sLen  := Length(S);
  For I := 1 to sLen do
  Begin
    If S[I] = Ch then
    begin
      sList.Add(Copy(S,lCopy,I-lCopy));
      lCopy := I+1;
    end;
  End;
  If lCopy <= sLen then sList.Add(Copy(S,lCopy,sLen-(lCopy-1)));
end;

function ValidLine(S : String) : Boolean;
begin
  Result := False;
  If Length(S) > 0 then If (S[1] <> '/') and (S[1] <> '#') and (S[1] <> ';') then Result := True;
end;


function sParamCount(S : String) : Integer;
var
  I,I1    : Integer;
  inBlock : Boolean;
  sLen    : Integer;
begin
  I1 := 0;
  sLen := Length(S);
  If sLen > 0 then
  Begin
    If Pos('"',S) > 0 then
    Begin
      inBlock := False;
      For I := 1 to sLen do
      Begin
        If (S[I] = '"') and (I = 1) then inBlock := True
          else
        If (S[I] = '(') and (I < sLen) then
        Begin
          If S[I+1] = '"' then inBlock := True;
        End
          else
        If (S[I] = ',') and (I < sLen) and (inBlock = False) then
        Begin
          Inc(I1);
          If S[I+1] = '"' then inBlock := True;
        End
          else
        If (inBlock = True) and (I < sLen) then
        Begin
          If (S[I+1] = '"') then inBlock := False;
        End;
      End;
    End
    Else For I := 1 to sLen do If S[I] = ',' then Inc(I1);
    Result := I1+1;
  End
  Else Result := 0;
end;



function GetSParam(PItem : Integer; PList : String; StripSpace : Boolean) : String;
var
  I,I1   : Integer;
  iStart : Integer;
  iEnd   : Integer;
  pPos   : Integer;
  pEnd   : Integer;
  Count  : Integer;
  sLen   : Integer;
  inBlock: Boolean;
begin
  I1 := 0;
  sLen := High(PList);
  For I := sLen downto 1 do If PList[I] = ')' then
  Begin
    I1 := I;
    Break;
  End;

  I  := Pos('(',PList);
  If (I > 0) and (I1 > 0) then
  Begin
    iStart  := I+1;  // Starting Position
    pPos    := iStart;
    iEnd    := I1-1; // End Position
    Count   := 1;    // Parameter Count
    inBlock := False;

    If PosEx('"',PList,iStart) > 0 then // Special processing for strings
    Begin
      If pItem > Count then // Find Parameter Position
      Begin
        For I := iStart to iEnd do
        Begin
          If (PList[I] = '"') and (I = iStart) then inBlock := True
            else
          If (PList[I] = ',') and (I < sLen) and (inBlock = False) then
          Begin
            Inc(Count);
            If PList[I+1] = '"' then inBlock := True;
          End
            else
          If (inBlock = True) and (I < sLen) then
          Begin
            If (PList[I+1] = '"') then inBlock := False;
          End;
          If Count = PItem then
          Begin
            pPos := I+1;
            Break;
          End;
        End;
      End
        else
      Begin
        pPos := iStart;
        If PList[iStart] = '"' then inBlock := True;
      End;
      // Find End Position of Parameter
      If inBlock = True then
        pEnd := PosEx('"',PList,pPos+1) else
        pEnd := PosEx(',',PList,pPos+1)-1;

      If pEnd <= 0 then pEnd := iEnd; // In case this is the last Parameter
      If (PList[pPos] = '"') and (PList[pEnd] = '"') then
      Begin
        Inc(pPos);
        Dec(pEnd);
      End;
    End
      else
    Begin
      If pItem > Count then // Find Parameter Position
      Begin
        For I := IStart to iEnd do If PList[I] = ',' then
        Begin
          Inc(Count);
          If Count = PItem then
          Begin
            pPos := I+1;
            Break;
          End;
        End;
      End
      Else pPos := iStart;
      pEnd := PosEx(',',PList,pPos)-1; // Find End Position of Parameter
      If pEnd <= 0 then pEnd := iEnd;   // In case this is the last Parameter
    End;

    If Count = PItem then
    Begin
      Result := Copy(PList,pPos,(pEnd+1)-pPos);

      If (StripSpace = True) and (Pos(#32,Result) > 0) then
      Begin
        For I := 1 to Length(Result) do
        Begin
          iStart := I;
          If Result[I] <> #32 then Break;
        End;
        For I := Length(Result) downto iStart do
        Begin
          iEnd := I;
          If Result[I] <> #32 then Break;
        End;
        Result := Copy(Result,iStart,(iEnd+1)-iStart);
      End
    End
    Else Result := '';
  End;
end;


function GetSLeftParam(S : String) : String;
var
  sP : Integer;
begin
  sP := Pos('=',S)-1;
  If sP > 0 then
  Begin
    Result := Trim(Copy(S,1,sP));
  End
  Else Result := '';
end;


function GetSRightParam(S : String; StripSpace : Boolean) : String;
var
  sP   : Integer;
begin
  sP := Pos('=',S)+1;
  If sP > 0 then
  Begin
    Result := Copy(S,sP,Length(S)-(SP-1));
    If StripSpace = True then Result := Trim(Result);
  End
  Else Result := '';
end;
{$ZEROBASEDSTRINGS ON}


{$IFDEF TRACEDEBUG}
    procedure AddDebugEntry(S : String);
    const
      UTF8BOM  : Array[0..2] of Byte = ($EF,$BB,$BF);
    Var
      FileName : String;
      fStream  : TFileStream;
      sAnsi    : UTF8String;
      S1       : String;
      fileSufx : String;
      iPos     : Integer;
    begin
      iPos := Pos(#9,S);
      If iPos > 0 then
      Begin
        fileSufx := Copy(S,1,iPos-1);
        S        := Copy(S,iPos+1,Length(S)-iPos);
      End
      Else fileSufx := '';
      {$IFDEF TRACEDEBUGMEMORY}
        S1 := IntToStr(clientStopWatch.ElapsedMilliseconds);
        While Length(S1) < 12 do S1 := ' '+S1;
        S  := DateToStr(Date)+' '+TimeToStr(Time)+' ['+S1+'] : '+S;
        MemDebugList.Add(S);
      {$ELSE}
        If csDebug <> nil then csDebug.Enter;
        Try
          If DirectoryExists(clientDebugPath) = False then ForceDirectories(clientDebugPath);

          FileName := clientDebugPath+fileSufx+clientDebugFile;

          If FileExists(FileName) = True then
          Begin
            Try fStream := TFileStream.Create(FileName,fmOpenWrite); Except fStream := nil; End;
          End
            else
          Begin
            Try
              fStream := TFileStream.Create(FileName,fmCreate);
              fStream.Write(UTF8BOM,3);
            Except
              fStream := nil;
            End;
          End;
          If fStream <> nil then
          Begin
            S1 := IntToStr(clientStopWatch.ElapsedMilliseconds);
            While Length(S1) < 12 do S1 := ' '+S1;
            S  := DateToStr(Date)+' '+TimeToStr(Time)+' ['+S1+'] : '+S;

            sAnsi := UTF8Encode(S)+#13#10;
            fStream.Seek(0,soFromEnd);
            fStream.Write(sAnsi[Low(sAnsi)],Length(sAnsi));
            fStream.Free;
          End;
        Finally
          If csDebug <> nil then csDebug.Leave;
        End;
      {$ENDIF}
    end;

  {$IFDEF TRACEDEBUGMEMORY}
    procedure FinalizeMemoryDebug;
    const
      UTF8BOM  : Array[0..2] of Byte = ($EF,$BB,$BF);
    Var
      FileName : String;
      fStream  : TFileStream;
      sAnsi    : UTF8String;
    begin
      FileName := UserDataPath+clientDebugFile;

      If FileExists(FileName) = True then
      Begin
        Try fStream := TFileStream.Create(FileName,fmOpenWrite); Except fStream := nil; End;
      End
        else
      Begin
        Try
          fStream := TFileStream.Create(FileName,fmCreate);
          fStream.Write(UTF8BOM,3);
        Except
          fStream := nil;
        End;
      End;
      If fStream <> nil then
      Begin
        sAnsi := UTF8Encode(MemDebugList.Text);
        fStream.Seek(0,soFromEnd);
        fStream.Write(sAnsi[Low(sAnsi)],Length(sAnsi));
        fStream.Free;
      End;
      MemDebugList.Free;
    end;
  {$ENDIF}
{$ENDIF}



initialization
  {$IFDEF TRACEDEBUG}
  csDebug := TCriticalSection.Create;
  {$ENDIF}


finalization;
  {$IFDEF TRACEDEBUG}
  csDebug.Free;
  {$ENDIF}


end.