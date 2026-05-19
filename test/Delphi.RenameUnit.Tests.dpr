(*

  delphi-renameunit
  https://github.com/AgileDelphi/delphi-renameunit

  License: MIT
  Copyright (c) 2026 Darian Miller

*)

program Delphi.RenameUnit.Tests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Xml.NUnit,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  {$ENDIF }
  DUnitX.TestFramework,
  Delphi.RenameUnit.Engine in '..\source\Delphi.RenameUnit.Engine.pas',
  Delphi.Lexer in '..\submodules\delphi-lexer\source\Delphi.Lexer.pas',
  Delphi.Lexer.Scanner in '..\submodules\delphi-lexer\source\Delphi.Lexer.Scanner.pas',
  Delphi.Lexer.Utils in '..\submodules\delphi-lexer\source\Delphi.Lexer.Utils.pas',
  Delphi.Lexer.MyersDiff in '..\submodules\delphi-lexer\source\Delphi.Lexer.MyersDiff.pas',
  Delphi.Token in '..\submodules\delphi-lexer\source\Delphi.Token.pas',
  Delphi.Token.TriviaSpan in '..\submodules\delphi-lexer\source\Delphi.Token.TriviaSpan.pas',
  Delphi.Tokenizer in '..\submodules\delphi-lexer\source\Delphi.Tokenizer.pas',
  Delphi.Token.Kind in '..\submodules\delphi-lexer\source\Delphi.Token.Kind.pas',
  Delphi.Token.List in '..\submodules\delphi-lexer\source\Delphi.Token.List.pas',
  Delphi.Keywords in '..\submodules\delphi-lexer\source\Delphi.Keywords.pas',
  Test.Delphi.RenameUnit.Engine in 'Test.Delphi.RenameUnit.Engine.pas';

{ keep comment here to protect the following conditional from being removed by the IDE when adding a unit }
{$IFNDEF TESTINSIGHT}
var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
{$ENDIF}
begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    TDUnitX.CheckCommandLine;
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    runner.FailsOnNoAsserts := True;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}
end.
