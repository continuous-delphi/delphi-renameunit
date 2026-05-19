(*

  delphi-renameunit
  https://github.com/AgileDelphi/delphi-renameunit

  License: MIT
  Copyright (c) 2026 Darian Miller

*)

unit Test.Delphi.RenameUnit.Engine;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.IOUtils,
  Delphi.RenameUnit.Engine;

type

  [TestFixture]
  TRenameEngineTests = class
  private
    FTestDir:string;
    procedure WriteTestFile(const FileName, Content:string);
    function ReadTestFile(const FileName:string):string;
    function RunRename(const FromUnit, ToUnit:string):Integer;
    function RunRenameDryRun(const FromUnit, ToUnit:string):Integer;
    function RunRenameRecurse(const FromUnit, ToUnit:string):Integer;
    function RunRenameWithLog(const FromUnit, ToUnit:string):string;
    function RunRenameMap(const Pairs:TArray<TRenamePair>):Integer;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    // ---- Uses clause ----

    [Test] procedure UsesClause_SimpleUnit_Renamed;
    [Test] procedure UsesClause_DottedUnit_Renamed;
    [Test] procedure UsesClause_MultipleEntries_OnlyMatchRenamed;
    [Test] procedure UsesClause_ContainsKeyword_Renamed;
    [Test] procedure UsesClause_CaseInsensitive_Renamed;

    // ---- Scoped references ----

    [Test] procedure ScopedRef_DotAccess_Renamed;
    [Test] procedure ScopedRef_NotPrecededByDot_Renamed;
    [Test] procedure ScopedRef_PrecededByDot_NotRenamed;

    // ---- Unit declaration ----

    [Test] procedure UnitDecl_MatchingFile_RenamedAndFileRenamed;
    [Test] procedure UnitDecl_NonMatchingFile_RenamedNoFileRename;

    // ---- Strings and comments ----

    [Test] procedure StringLiteral_NotRenamed;
    [Test] procedure Comment_NotRenamed;

    // ---- in 'path' ----

    [Test] procedure InPath_DprEntry_PathRenamed;

    // ---- Full-name invariant ----

    [Test] procedure FullNameInvariant_PartialMatch_NotRenamed;
    [Test] procedure FullNameInvariant_Idempotent;

    // ---- .dproj ----

    [Test] procedure Dproj_DCCReference_Renamed;
    [Test] procedure Dproj_NonMatch_Untouched;

    // ---- Batch rename ----

    [Test] procedure BatchRename_MultiplePairs;

    // ---- Companion file rename ----

    [Test] procedure CompanionDfm_RenamedWithUnit;
    [Test] procedure CompanionFmx_RenamedWithUnit;
    [Test] procedure CompanionNone_NoError;
    [Test] procedure CompanionDfm_DryRun_NotRenamed;

    // ---- Dry-run ----

    [Test] procedure DryRun_FilesNotModified;

    // ---- Recurse ----

    [Test] procedure Recurse_SubdirectoryFilesProcessed;

    // ---- Dotted unit file rename ----

    [Test] procedure UnitDecl_DottedName_FileRenamed;

    // ---- Implementation uses clause ----

    [Test] procedure UsesClause_ImplementationSection_Renamed;

    // ---- .dproj with relative paths ----

    [Test] procedure Dproj_RelativePath_Renamed;

    // ---- Log output ----

    [Test] procedure Log_AfterLine_CorrectWhenNameLengthChanges;

    // ---- Map file ----

    [Test] procedure MapFile_LoadsValidPairs;
    [Test] procedure MapFile_SkipsCommentsAndBlanks;
  end;


implementation


procedure TRenameEngineTests.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath, 'RenameUnitTest_' +
    FormatDateTime('yyyymmddhhnnsszzz', Now));
  TDirectory.CreateDirectory(FTestDir);
end;


procedure TRenameEngineTests.TearDown;
begin
  if TDirectory.Exists(FTestDir) then
    TDirectory.Delete(FTestDir, True);
end;


procedure TRenameEngineTests.WriteTestFile(const FileName, Content:string);
begin
  TFile.WriteAllText(TPath.Combine(FTestDir, FileName), Content, TEncoding.UTF8);
end;


function TRenameEngineTests.ReadTestFile(const FileName:string):string;
begin
  Result := TFile.ReadAllText(TPath.Combine(FTestDir, FileName), TEncoding.UTF8);
end;


function TRenameEngineTests.RunRename(const FromUnit, ToUnit:string):Integer;
var
  Engine:TRenameEngine;
  Options:TRenameOptions;
  Pair:TRenamePair;
begin
  Pair.FromUnit := FromUnit;
  Pair.ToUnit := ToUnit;
  Engine := TRenameEngine.Create([Pair]);
  try
    Options.Dir := FTestDir;
    Options.FileSpec := '*.pas;*.dpr;*.dpk;*.dproj';
    Options.Recurse := False;
    Options.DryRun := False;
    Options.Verbose := False;
    Options.LogFile := '';
    Options.MapFile := '';
    Result := Engine.Run(Options);
  finally
    Engine.Free;
  end;
end;


function TRenameEngineTests.RunRenameDryRun(const FromUnit, ToUnit:string):Integer;
var
  Engine:TRenameEngine;
  Options:TRenameOptions;
  Pair:TRenamePair;
begin
  Pair.FromUnit := FromUnit;
  Pair.ToUnit := ToUnit;
  Engine := TRenameEngine.Create([Pair]);
  try
    Options.Dir := FTestDir;
    Options.FileSpec := '*.pas;*.dpr;*.dpk;*.dproj';
    Options.Recurse := False;
    Options.DryRun := True;
    Options.Verbose := False;
    Options.LogFile := '';
    Options.MapFile := '';
    Result := Engine.Run(Options);
  finally
    Engine.Free;
  end;
end;


function TRenameEngineTests.RunRenameRecurse(const FromUnit, ToUnit:string):Integer;
var
  Engine:TRenameEngine;
  Options:TRenameOptions;
  Pair:TRenamePair;
begin
  Pair.FromUnit := FromUnit;
  Pair.ToUnit := ToUnit;
  Engine := TRenameEngine.Create([Pair]);
  try
    Options.Dir := FTestDir;
    Options.FileSpec := '*.pas;*.dpr;*.dpk;*.dproj';
    Options.Recurse := True;
    Options.DryRun := False;
    Options.Verbose := False;
    Options.LogFile := '';
    Options.MapFile := '';
    Result := Engine.Run(Options);
  finally
    Engine.Free;
  end;
end;


function TRenameEngineTests.RunRenameWithLog(const FromUnit, ToUnit:string):string;
var
  Engine:TRenameEngine;
  Options:TRenameOptions;
  Pair:TRenamePair;
  LogPath:string;
begin
  Pair.FromUnit := FromUnit;
  Pair.ToUnit := ToUnit;
  Engine := TRenameEngine.Create([Pair]);
  try
    LogPath := TPath.Combine(FTestDir, '_rename.log');
    Options.Dir := FTestDir;
    Options.FileSpec := '*.pas;*.dpr;*.dpk;*.dproj';
    Options.Recurse := False;
    Options.DryRun := False;
    Options.Verbose := False;
    Options.LogFile := LogPath;
    Options.MapFile := '';
    Engine.Run(Options);
  finally
    Engine.Free;
  end;
  Result := TFile.ReadAllText(LogPath, TEncoding.UTF8);
end;


function TRenameEngineTests.RunRenameMap(const Pairs:TArray<TRenamePair>):Integer;
var
  Engine:TRenameEngine;
  Options:TRenameOptions;
begin
  Engine := TRenameEngine.Create(Pairs);
  try
    Options.Dir := FTestDir;
    Options.FileSpec := '*.pas;*.dpr;*.dpk;*.dproj';
    Options.Recurse := False;
    Options.DryRun := False;
    Options.Verbose := False;
    Options.LogFile := '';
    Options.MapFile := '';
    Result := Engine.Run(Options);
  finally
    Engine.Free;
  end;
end;


// ---------------------------------------------------------------------------
// Uses clause
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.UsesClause_SimpleUnit_Renamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses MyUnit;'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Consumer.pas'), 'uses NewUnit;');
end;


procedure TRenameEngineTests.UsesClause_DottedUnit_Renamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses Vcl.OldForm;'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('Vcl.OldForm', 'Vcl.NewForm');
  Assert.Contains(ReadTestFile('Consumer.pas'), 'uses Vcl.NewForm;');
end;


procedure TRenameEngineTests.UsesClause_MultipleEntries_OnlyMatchRenamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses System.SysUtils, MyUnit, System.Classes;'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  var Content := ReadTestFile('Consumer.pas');
  Assert.Contains(Content, 'NewUnit');
  Assert.Contains(Content, 'System.SysUtils');
  Assert.Contains(Content, 'System.Classes');
end;


procedure TRenameEngineTests.UsesClause_ContainsKeyword_Renamed;
begin
  WriteTestFile('Test.dpk',
    'package Test;'#13#10 +
    'contains'#13#10 +
    '  MyUnit;'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Test.dpk'), 'NewUnit');
end;


procedure TRenameEngineTests.UsesClause_CaseInsensitive_Renamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses myunit;'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Consumer.pas'), 'NewUnit');
end;


// ---------------------------------------------------------------------------
// Scoped references
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.ScopedRef_DotAccess_Renamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses MyUnit;'#13#10 +
    'implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  MyUnit.DoStuff;'#13#10 +
    'end;'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Consumer.pas'), 'NewUnit.DoStuff');
end;


procedure TRenameEngineTests.ScopedRef_NotPrecededByDot_Renamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  MyUnit.DoStuff;'#13#10 +
    'end;'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Consumer.pas'), 'NewUnit.DoStuff');
end;


procedure TRenameEngineTests.ScopedRef_PrecededByDot_NotRenamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  Prefix.MyUnit.DoStuff;'#13#10 +
    'end;'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  // Should NOT be renamed because MyUnit is preceded by a dot.
  Assert.Contains(ReadTestFile('Consumer.pas'), 'Prefix.MyUnit.DoStuff');
end;


// ---------------------------------------------------------------------------
// Unit declaration
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.UnitDecl_MatchingFile_RenamedAndFileRenamed;
begin
  WriteTestFile('MyUnit.pas',
    'unit MyUnit;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.IsFalse(FileExists(TPath.Combine(FTestDir, 'MyUnit.pas')),
    'old file should not exist');
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'NewUnit.pas')),
    'new file should exist');
  Assert.Contains(ReadTestFile('NewUnit.pas'), 'unit NewUnit;');
end;


procedure TRenameEngineTests.UnitDecl_NonMatchingFile_RenamedNoFileRename;
begin
  WriteTestFile('Other.pas',
    'unit MyUnit;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  // Unit decl renamed but file not renamed (filename doesn't match).
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'Other.pas')),
    'file should keep original name');
  Assert.Contains(ReadTestFile('Other.pas'), 'unit NewUnit;');
end;


// ---------------------------------------------------------------------------
// Strings and comments
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.StringLiteral_NotRenamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  WriteLn(''MyUnit is great'');'#13#10 +
    'end;'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Consumer.pas'), '''MyUnit is great''');
end;


procedure TRenameEngineTests.Comment_NotRenamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    '// MyUnit reference'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Consumer.pas'), '// MyUnit reference');
end;


// ---------------------------------------------------------------------------
// in 'path'
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.InPath_DprEntry_PathRenamed;
begin
  WriteTestFile('Test.dpr',
    'program Test;'#13#10 +
    'uses'#13#10 +
    '  MyUnit in ''Source\MyUnit.pas'';'#13#10 +
    'begin'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  var Content := ReadTestFile('Test.dpr');
  Assert.Contains(Content, 'NewUnit in');
  Assert.Contains(Content, '''Source\NewUnit.pas''');
end;


// ---------------------------------------------------------------------------
// Full-name invariant
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.FullNameInvariant_PartialMatch_NotRenamed;
// Renaming "Utils" should NOT match "System.Utils" in a uses clause.
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses System.Utils;'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('Utils', 'NewUtils');
  Assert.Contains(ReadTestFile('Consumer.pas'), 'System.Utils',
    'System.Utils should not be partially renamed');
end;


procedure TRenameEngineTests.FullNameInvariant_Idempotent;
// Running the same rename twice should produce no changes on the second run.
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses MyUnit;'#13#10 +
    'implementation'#13#10 +
    'procedure Foo;'#13#10 +
    'begin'#13#10 +
    '  MyUnit.DoStuff;'#13#10 +
    'end;'#13#10 +
    'end.');
  RunRename('MyUnit', 'cd.MyUnit');
  var After1 := ReadTestFile('Consumer.pas');
  RunRename('MyUnit', 'cd.MyUnit');
  var After2 := ReadTestFile('Consumer.pas');
  Assert.AreEqual(After1, After2, 'second rename should produce no changes');
end;


// ---------------------------------------------------------------------------
// .dproj
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.Dproj_DCCReference_Renamed;
begin
  WriteTestFile('Test.dproj',
    '<Project>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DCCReference Include="MyUnit.pas"/>'#13#10 +
    '        <DCCReference Include="..\..\source\OtherUnit.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>');
  RunRename('MyUnit', 'NewUnit');
  var Content := ReadTestFile('Test.dproj');
  Assert.Contains(Content, 'Include="NewUnit.pas"');
  Assert.Contains(Content, 'Include="..\..\source\OtherUnit.pas"',
    'non-matching reference should be untouched');
end;


procedure TRenameEngineTests.Dproj_NonMatch_Untouched;
begin
  WriteTestFile('Test.dproj',
    '<Project>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DCCReference Include="SomeOther.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Test.dproj'), 'Include="SomeOther.pas"');
end;


// ---------------------------------------------------------------------------
// Batch rename
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.BatchRename_MultiplePairs;
var
  Pair1, Pair2:TRenamePair;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses UnitA, UnitB;'#13#10 +
    'implementation'#13#10 +
    'end.');
  Pair1.FromUnit := 'UnitA';
  Pair1.ToUnit := 'NewA';
  Pair2.FromUnit := 'UnitB';
  Pair2.ToUnit := 'NewB';
  RunRenameMap([Pair1, Pair2]);
  var Content := ReadTestFile('Consumer.pas');
  Assert.Contains(Content, 'NewA');
  Assert.Contains(Content, 'NewB');
  Assert.DoesNotContain(Content, 'UnitA');
  Assert.DoesNotContain(Content, 'UnitB');
end;


// ---------------------------------------------------------------------------
// Companion file rename
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.CompanionDfm_RenamedWithUnit;
begin
  WriteTestFile('MyForm.pas',
    'unit MyForm;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'end.');
  WriteTestFile('MyForm.dfm', 'object Form1: TForm1'#13#10'end');
  RunRename('MyForm', 'NewForm');
  Assert.IsFalse(FileExists(TPath.Combine(FTestDir, 'MyForm.dfm')),
    'old .dfm should not exist');
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'NewForm.dfm')),
    'new .dfm should exist');
end;


procedure TRenameEngineTests.CompanionFmx_RenamedWithUnit;
begin
  WriteTestFile('MyForm.pas',
    'unit MyForm;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'end.');
  WriteTestFile('MyForm.fmx', 'object Form1: TForm1'#13#10'end');
  RunRename('MyForm', 'NewForm');
  Assert.IsFalse(FileExists(TPath.Combine(FTestDir, 'MyForm.fmx')),
    'old .fmx should not exist');
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'NewForm.fmx')),
    'new .fmx should exist');
end;


procedure TRenameEngineTests.CompanionNone_NoError;
// Renaming a unit file with no companion form should not error.
begin
  WriteTestFile('MyUnit.pas',
    'unit MyUnit;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'NewUnit.pas')),
    'renamed .pas should exist');
  Assert.IsFalse(FileExists(TPath.Combine(FTestDir, 'NewUnit.dfm')),
    'no .dfm should be created');
end;


procedure TRenameEngineTests.CompanionDfm_DryRun_NotRenamed;
begin
  WriteTestFile('MyForm.pas',
    'unit MyForm;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'end.');
  WriteTestFile('MyForm.dfm', 'object Form1: TForm1'#13#10'end');
  RunRenameDryRun('MyForm', 'NewForm');
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'MyForm.pas')),
    '.pas should still exist after dry-run');
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'MyForm.dfm')),
    '.dfm should still exist after dry-run');
end;


// ---------------------------------------------------------------------------
// Dry-run
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.DryRun_FilesNotModified;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses MyUnit;'#13#10 +
    'implementation'#13#10 +
    'end.');
  var Original := ReadTestFile('Consumer.pas');
  RunRenameDryRun('MyUnit', 'NewUnit');
  Assert.AreEqual(Original, ReadTestFile('Consumer.pas'), 'file should be unchanged after dry-run');
end;


// ---------------------------------------------------------------------------
// Recurse
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.Recurse_SubdirectoryFilesProcessed;
var
  SubDir:string;
begin
  SubDir := TPath.Combine(FTestDir, 'sub');
  TDirectory.CreateDirectory(SubDir);
  TFile.WriteAllText(TPath.Combine(SubDir, 'Deep.pas'),
    'unit Deep;'#13#10 +
    'interface'#13#10 +
    'uses MyUnit;'#13#10 +
    'implementation'#13#10 +
    'end.', TEncoding.UTF8);
  RunRenameRecurse('MyUnit', 'NewUnit');
  var Content := TFile.ReadAllText(TPath.Combine(SubDir, 'Deep.pas'), TEncoding.UTF8);
  Assert.Contains(Content, 'uses NewUnit;', 'subdirectory file should be renamed');
end;


// ---------------------------------------------------------------------------
// Dotted unit file rename
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.UnitDecl_DottedName_FileRenamed;
begin
  WriteTestFile('Vcl.OldForm.pas',
    'unit Vcl.OldForm;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'end.');
  RunRename('Vcl.OldForm', 'Vcl.NewForm');
  Assert.IsFalse(FileExists(TPath.Combine(FTestDir, 'Vcl.OldForm.pas')),
    'old file should not exist');
  Assert.IsTrue(FileExists(TPath.Combine(FTestDir, 'Vcl.NewForm.pas')),
    'new file should exist');
  Assert.Contains(ReadTestFile('Vcl.NewForm.pas'), 'unit Vcl.NewForm;');
end;


// ---------------------------------------------------------------------------
// Implementation uses clause
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.UsesClause_ImplementationSection_Renamed;
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'uses MyUnit;'#13#10 +
    'end.');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Consumer.pas'), 'uses NewUnit;');
end;


// ---------------------------------------------------------------------------
// .dproj with relative paths
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.Dproj_RelativePath_Renamed;
begin
  WriteTestFile('Test.dproj',
    '<Project>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DCCReference Include="..\..\source\MyUnit.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>');
  RunRename('MyUnit', 'NewUnit');
  Assert.Contains(ReadTestFile('Test.dproj'), 'Include="..\..\source\NewUnit.pas"');
end;


// ---------------------------------------------------------------------------
// Log output
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.Log_AfterLine_CorrectWhenNameLengthChanges;
// Renaming a short name to a longer name shifts offsets.  The log after-line
// must reflect the modified source, not garbage from a stale offset.
begin
  WriteTestFile('Consumer.pas',
    'unit Consumer;'#13#10 +
    'interface'#13#10 +
    'uses X;'#13#10 +
    'implementation'#13#10 +
    'end.');
  var Log := RunRenameWithLog('X', 'VeryLongUnitName');
  // The after-line in the log should contain the new unit name.
  Assert.Contains(Log, 'uses VeryLongUnitName;', 'after-line should show renamed unit');
  // The before-line should contain the original.
  Assert.Contains(Log, 'uses X;', 'before-line should show original');
end;


// ---------------------------------------------------------------------------
// Map file
// ---------------------------------------------------------------------------

procedure TRenameEngineTests.MapFile_LoadsValidPairs;
begin
  WriteTestFile('renames.txt',
    'OldUnit=NewUnit'#13#10 +
    'Vcl.OldForm=Vcl.NewForm');
  var Pairs := TRenameEngine.LoadMapFile(TPath.Combine(FTestDir, 'renames.txt'));
  Assert.AreEqual(NativeInt(2), NativeInt(Length(Pairs)));
  Assert.AreEqual('OldUnit', Pairs[0].FromUnit);
  Assert.AreEqual('NewUnit', Pairs[0].ToUnit);
  Assert.AreEqual('Vcl.OldForm', Pairs[1].FromUnit);
  Assert.AreEqual('Vcl.NewForm', Pairs[1].ToUnit);
end;


procedure TRenameEngineTests.MapFile_SkipsCommentsAndBlanks;
begin
  WriteTestFile('renames.txt',
    '# This is a comment'#13#10 +
    #13#10 +
    '; Another comment'#13#10 +
    'OldUnit=NewUnit'#13#10 +
    #13#10);
  var Pairs := TRenameEngine.LoadMapFile(TPath.Combine(FTestDir, 'renames.txt'));
  Assert.AreEqual(NativeInt(1), NativeInt(Length(Pairs)));
  Assert.AreEqual('OldUnit', Pairs[0].FromUnit);
end;


initialization

TDUnitX.RegisterTestFixture(TRenameEngineTests);

end.
