(*
  Copyright 2016, MARS-Curiosity - REST Library

  Home: https://github.com/andrea-magni/MARS
*)
{$I COMPILER_DIRECTIVES.INC}
unit Server.Resources;

interface

uses
  SysUtils, Classes

  , MARS.Core.Attributes, MARS.Core.MediaType, MARS.Core.JSON, MARS.Core.Response
  , MARS.Core.URL

  , MARS.Core.Token.Resource //, MARS.Core.Token
;

type
  TNetScoreRecord =
  Record
    Name       : String;
    Score      : String;
    Difficulty : String;
    Hash       : String;
  End;

  TScoreRecord =
  Record
    srName       : String;
    srScore      : Integer;
    srDifficulty : Integer;
    srHash       : String;
  End;

  THighScoreRecord =
  Record
    Name       : String;
    Score      : Int64;
  End;
  PHighScoreRecord = ^THighScoreRecord;


  [Path('rgbquick')]
  TGameServicesResource = class
  protected
  public
    [HeaderParam('user-agent')] AUserAgent: string;

    [POST, Path('postscore'), Produces(TMediaType.APPLICATION_JSON)]
    function RGBquickPostScore([BodyParam] nScore : TNetScoreRecord) : TJSONObject;

    [GET, Path('leaderboard'), Produces(TMediaType.TEXT_PLAIN)]
    function RGBquickLeaderboard : String;

    [GET, Produces(TMediaType.TEXT_HTML)]
    function RedirectToWebsite: String;
  end;

  [Path('token')]
  TTokenResource = class(TMARSTokenResource)
  end;

  TAutoSaveThread = Class(TThread)
    procedure Execute; override;
  public
    ThreadClosed : Boolean;
  End;




procedure RGBquickInitialize;
procedure RGBquickFinalize;
function  RGBquickNewScoreCheck(nScore : TNetScoreRecord) : Integer;
procedure RGBquickLeaderboardToStringList(sList : TStringList);
procedure RGBquickSaveLeaderboard;
procedure RGBquickLoadLeaderboard;
procedure RGBquickParseLeaderboard(sList : TStringList);

function  ValidateHash(var nScore : TNetScoreRecord; hashSalt : String) : Boolean;


implementation


uses
    MARS.Core.Registry, System.Hash, System.Generics.Collections, System.Generics.Defaults, System.SyncObjs, System.Diagnostics, Vcl.ExtCtrls, misc_functions;


const
  RGBquickUserAgent       : String = 'RGBgreen Client/1.0';
  RGBquickLeaderboardPath : String = 'c:\RGBquick\';
  RGBquickLeaderboardFile : String = 'leaderboard.txt';
  RGBquickHashSalt        : String = 'write something here to act as the Hash salt';
  RGBquickLeaderboardSize : Integer = 10000; // maximum entries per leaderboard


var
  RGBquickScoreListEasy   : TList<PHighScoreRecord>;
  RGBquickScoreListMedium : TList<PHighScoreRecord>;
  RGBquickScoreListHard   : TList<PHighScoreRecord>;
  RGBquickScoreChanged    : Boolean = False;
  RGBquickScoreCache      : TStringList;
  autoSaveThread          : TAutoSaveThread;
  listCriticalSection     : TCriticalSection;
  cacheCriticalSection    : TCriticalSection;
  FinalizeTriggered       : Boolean = False;


function TGameServicesResource.RGBquickPostScore(nScore : TNetScoreRecord) : TJSONObject;
const
  codeSuccess        = 200;
  codeFailure        = 400;
var
  newPos             : Integer;
begin
  {$IFDEF SCOREDEBUG}AddDebugEntry('RGBquick post score request (before)');{$ENDIF}
  Result := TJSONObject.Create;
  If AUserAgent = RGBquickUserAgent then
  Begin
    If ValidateHash(nScore,RGBquickHashSalt) = True then
    Begin
      Result.WriteStringValue('status',IntToStr(codeSuccess));
      If FinalizeTriggered = False then
      Begin
        {$IFDEF SCOREDEBUG}AddDebugEntry('Testing new score');{$ENDIF}
        newPos := RGBquickNewScoreCheck(nScore);
        Result.WriteStringValue('position',newPos.ToString);
      End;
    End
      else
    Begin
      {$IFDEF SCOREDEBUG}AddDebugEntry('Invalid hash');{$ENDIF}
      Result.WriteStringValue('status',IntToStr(codeFailure));
    End;
  End
    else
  Begin
    {$IFDEF SCOREDEBUG}AddDebugEntry('Invalid user-agent');{$ENDIF}
    Result.WriteStringValue('status',IntToStr(codeFailure));
  End;
  {$IFDEF SCOREDEBUG}AddDebugEntry('RGBquick post score request (after)');{$ENDIF}
end;


function TGameServicesResource.RedirectToWebsite: String;
begin
  Result := '<HTML><HEAD><TITLE></TITLE>'+
            '<META HTTP-EQUIV="Refresh" CONTENT="0; URL=https://inmatrix.com">'+
            '</HEAD></HTML>';
end;


function TGameServicesResource.RGBquickLeaderboard : String;
begin
  {$IFDEF SCOREDEBUG}AddDebugEntry('RGBquick leaderboard request (before)');{$ENDIF}
  If AUserAgent = RGBquickUserAgent then
  Begin
    If RGBquickScoreChanged = True then
    Begin
      cacheCriticalSection.Enter;
      Try
        RGBquickScoreCache.Clear;
        RGBquickLeaderboardToStringList(RGBquickScoreCache);
      Finally
        cacheCriticalSection.Leave;
      End;
    End;
    Result := RGBquickScoreCache.Text;
  End;
  {$IFDEF SCOREDEBUG}AddDebugEntry('RGBquick leaderboard request (after)');{$ENDIF}
end;


procedure TAutoSaveThread.Execute;
const
  WaitCycles = 100;
  //WaitCycles = 10;
var
  I : Integer;
begin
  ThreadClosed := False;
  While Terminated = False do
  Begin
    // Wait 10 seconds
    For I := 0 to WaitCycles-1 do If (RGBquickScoreChanged = False) and (FinalizeTriggered = False) and (Terminated = False) then Sleep(100);
    // Save leaderboard
    If (RGBquickScoreChanged = True) and (FinalizeTriggered = False) and (Terminated = False) then
    Begin
      {$IFDEF TRACEDEBUG}AddDebugEntry('Calling RGBquickSaveLeaderboard from AutoSaveThread');{$ENDIF}
      RGBquickSaveLeaderboard;
    End;
  End;
  ThreadClosed := True;
end;


procedure RGBquickLeaderboardToStringList(sList : TStringList);
var
  I     : Integer;

  function StringFromScordRecord(nScore : PHighScoreRecord; iDifficulty : Integer) : String;
  begin
    Result := 'Entry("Name='+nScore.Name+'",Score='+IntToStr(nScore.Score)+',Difficulty='+IntToStr(iDifficulty)+')';
  end;

begin
  listCriticalSection.Enter;
  Try
    For I := 0 to RGBquickScoreListEasy.Count-1   do sList.Add(StringFromScordRecord(RGBquickScoreListEasy[I]  ,0));
    For I := 0 to RGBquickScoreListMedium.Count-1 do sList.Add(StringFromScordRecord(RGBquickScoreListMedium[I],1));
    For I := 0 to RGBquickScoreListHard.Count-1   do sList.Add(StringFromScordRecord(RGBquickScoreListHard[I]  ,2));
  Finally
    listCriticalSection.Leave;
  End;
end;


procedure RGBquickSaveLeaderboard;
begin
  {$IFDEF TRACEDEBUG}AddDebugEntry('RGBquickSaveLeaderboard (before)');{$ENDIF}
  cacheCriticalSection.Enter;
  Try
    RGBquickScoreCache.Clear;
    RGBquickLeaderboardToStringList(RGBquickScoreCache);
    Try
      RGBquickScoreCache.SaveToFile(RGBquickLeaderboardPath+RGBquickLeaderboardFile);
      RGBquickScoreChanged := False;
    Except
      {$IFDEF TRACEDEBUG}AddDebugEntry('Exception trying to save RGBquick leaderboard to "'+RGBquickLeaderboardPath+RGBquickLeaderboardFile+'"');{$ENDIF}
    End;
  Finally
    cacheCriticalSection.Leave;
  End;
  {$IFDEF TRACEDEBUG}AddDebugEntry('RGBquickSaveLeaderboard (after)');{$ENDIF}
end;


function RGBquickNewScoreCheck(nScore : TNetScoreRecord) : Integer;
var
  I           : Integer;
  cList       : TList<PHighScoreRecord>;
  nhScore     : PHighscoreRecord;
  iScore      : Int64;
  iDiffculty  : Integer;
  lbIndex     : Integer;
begin
  {$IFDEF SCOREDEBUG}AddDebugEntry('RGBquickNewScoreCheck (before)');{$ENDIF}
  {$IFDEF SCOREDEBUG}AddDebugEntry('Name       : '+nScore.Name);{$ENDIF}
  {$IFDEF SCOREDEBUG}AddDebugEntry('Score      : '+nScore.Score);{$ENDIF}
  {$IFDEF SCOREDEBUG}AddDebugEntry('Difficulty : '+nScore.Difficulty);{$ENDIF}
  lbIndex    := -1;
  iScore     := StrToInt64Def(nScore.Score,0);
  iDiffculty := StrToIntDef(nScore.Difficulty,0);
  listCriticalSection.Enter;
  Try
    Case iDiffculty of
      0  : cList := RGBquickScoreListEasy;
      1  : cList := RGBquickScoreListMedium;
      else cList := RGBquickScoreListHard;
    End;

    For I := 0 to cList.Count-1 do If iScore > cList[I].Score then
    Begin
      lbIndex := I;
      Break;
    End;
    If (lbIndex = -1) and (cList.Count < RGBquickLeaderboardSize) then lbIndex := cList.Count;

    If lbIndex > -1 then
    Begin
      New(nhScore);
      nhScore^.Score := iScore;
      nhScore^.Name  := nScore.Name;
      cList.Insert(lbIndex,nhScore);
      If cList.Count > RGBquickLeaderboardSize then cList.Delete(cList.Count-1);
      RGBquickScoreChanged := True;
    End;
  Finally
    listCriticalSection.Leave;
  End;
  Result := lbIndex+1;
  {$IFDEF SCOREDEBUG}AddDebugEntry('RGBquickNewScoreCheck (after)');{$ENDIF}
end;


procedure RGBquickParseLeaderboard(sList : TStringList);
var
  I,I1        : Integer;
  S,S1,S2     : String;
  sName       : String;
  iScore      : Int64;
  iDifficulty : Integer;
  nHighScore  : PHighScoreRecord;
begin
  For I := 0 to sList.Count-1 do
  Begin
    S := Lowercase(sList[I]);

    If Pos('entry',S) = 1 then
    Begin
      sName       := '';
      iScore      := -1;
      iDifficulty := -1;
      For I1 := 1 to SParamCount(S) do
      Begin
        S1 := GetSParam(I1,sList[I],False);
        S2 := Lowercase(GetSLeftParam(S1));
        If S2 = 'score'             then iScore      := StrToInt64Def(GetSRightParam(S1,False),-1);
        If S2 = 'difficulty'        then iDifficulty := StrToIntDef(GetSRightParam(S1,False),-1);
        If S2 = 'name'              then sName       := GetSRightParam(S1,False);
      End;
      If (iScore > -1) and (iDifficulty > -1) and (sName <> '') then
      Begin
        New(nHighScore);
        nHighScore^.Name       := sName;
        nHighScore^.Score      := iScore;
        Case iDifficulty of
          0 : RGBquickScoreListEasy  .Add(nHighScore);
          1 : RGBquickScoreListMedium.Add(nHighScore);
          2 : RGBquickScoreListHard  .Add(nHighScore);
        End;
      End;
    End;
  End;
end;


procedure RGBquickLoadLeaderboard;
begin
  // Load leaderboard
  If FileExists(RGBquickLeaderboardPath+RGBquickLeaderboardFile) = True then
  Begin
    cacheCriticalSection.Enter;
    Try
      Try
        RGBquickScoreCache.LoadFromFile(RGBquickLeaderboardPath+RGBquickLeaderboardFile);
      Except
        {$IFDEF TRACEDEBUG}AddDebugEntry('Exception trying to Load leaderboard from "'+RGBquickLeaderboardPath+RGBquickLeaderboardFile+'"');{$ENDIF}
      End;
      RGBquickParseLeaderboard(RGBquickScoreCache);
    Finally
      cacheCriticalSection.Leave;
    End;

    // Sort lists by Score
    RGBquickScoreListEasy.Sort(TComparer<PHighScoreRecord>.Construct(function(const Left, Right: PHighScoreRecord) : Integer
    begin
      Result := Right^.Score-Left^.Score;
    end));
    RGBquickScoreListMedium.Sort(TComparer<PHighScoreRecord>.Construct(function(const Left, Right: PHighScoreRecord) : Integer
    begin
      Result := Right^.Score-Left^.Score;
    end));
    RGBquickScoreListHard.Sort(TComparer<PHighScoreRecord>.Construct(function(const Left, Right: PHighScoreRecord) : Integer
    begin
      Result := Right^.Score-Left^.Score;
    end));
  End;
end;


procedure RGBquickInitialize;
begin
  {$IFDEF TRACEDEBUG}AddDebugEntry('RGBquickInitialize (before)');{$ENDIF}
  RGBquickScoreListEasy     := TList<PHighScoreRecord>.Create;
  RGBquickScoreListMedium   := TList<PHighScoreRecord>.Create;
  RGBquickScoreListHard     := TList<PHighScoreRecord>.Create;

  RGBquickScoreCache        := TStringList.Create;

  If DirectoryExists(RGBquickLeaderboardPath) = False then
  Begin
    Try
      ForceDirectories(RGBquickLeaderboardPath);
    Except
      {$IFDEF TRACEDEBUG}AddDebugEntry('Exception creating path "'+RGBquickLeaderboardPath+'"');{$ENDIF}
    End;
  End;

  RGBquickLoadLeaderboard;

  {$IFDEF TRACEDEBUG}AddDebugEntry('RGBquickInitialize (after)');{$ENDIF}
end;


procedure RGBquickFinalize;
var
  I : Integer;
begin
  {$IFDEF TRACEDEBUG}AddDebugEntry('RGBquickFinalize (before)');{$ENDIF}
  RGBQuickSaveLeaderboard;

  For I := 0 to RGBquickScoreListEasy.Count-1   do Dispose(RGBquickScoreListEasy[I]);
  For I := 0 to RGBquickScoreListMedium.Count-1 do Dispose(RGBquickScoreListMedium[I]);
  For I := 0 to RGBquickScoreListHard.Count-1   do Dispose(RGBquickScoreListHard[I]);
  RGBquickScoreListEasy.Free;
  RGBquickScoreListMedium.Free;
  RGBquickScoreListHard.Free;
  RGBquickScoreCache.Free;
  {$IFDEF TRACEDEBUG}AddDebugEntry('RGBquickFinalize (after)'#13#10);{$ENDIF}
end;


procedure InitializeGameServices;
begin
  // Initialize the stopwatch used for timestamping
  clientStopWatch := TStopWatch.Create;
  clientStopWatch.Start;

  listCriticalSection     := TCriticalSection.Create;
  cacheCriticalSection    := TCriticalSection.Create;

  RGBquickInitialize;

  autoSaveThread := TAutoSaveThread.Create(False);
end;


procedure FinalizeGameServices;
var
  I : Integer;
begin
  FinalizeTriggered := True;
  autoSaveThread.Terminate;
  I := 0;
  While (autoSaveThread.ThreadClosed = False) and (I < 110) do
  Begin
    Sleep(100);
    Inc(I);
  End;
  autoSaveThread.Free;

  RGBquickFinalize;

  listCriticalSection.Free;
  cacheCriticalSection.Free;
end;


function ValidateHash(var nScore : TNetScoreRecord; hashSalt : String) : Boolean;
var
  HashSHA2: THashSHA2;
begin
  HashSHA2 := THashSHA2.create;
  HashSHA2.Update(nScore.Name+nScore.Score+nScore.Difficulty+hashSalt);
  Result   := HashSHA2.HashAsString = nScore.Hash;
end;


initialization
  TMARSResourceRegistry.Instance.RegisterResource<TGameServicesResource>;
  TMARSResourceRegistry.Instance.RegisterResource<TTokenResource>;
  InitializeGameServices;

finalization
  FinalizeGameServices;
end.
