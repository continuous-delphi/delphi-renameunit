(*

  delphi-lexer
  https://github.com/continuous-delphi/delphi-lexer

  A lightweight, lossless lexer for Delphi source code.
  Includes TokenDump, TokenStats, and TokenCompare utilities
  plus a syntax highlighter for SynEdit.

  License: MIT
  Copyright (c) 2026 Darian Miller

*)

program Delphi.RenameUnit;
{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  Delphi.RenameUnit.Engine in '..\..\source\Delphi.RenameUnit.Engine.pas',
  Delphi.Token in '..\..\submodules\delphi-lexer\source\Delphi.Token.pas',
  Delphi.Token.TriviaSpan in '..\..\submodules\delphi-lexer\source\Delphi.Token.TriviaSpan.pas',
  Delphi.Tokenizer in '..\..\submodules\delphi-lexer\source\Delphi.Tokenizer.pas',
  Delphi.Keywords in '..\..\submodules\delphi-lexer\source\Delphi.Keywords.pas',
  Delphi.Lexer.MyersDiff in '..\..\submodules\delphi-lexer\source\Delphi.Lexer.MyersDiff.pas',
  Delphi.Lexer in '..\..\submodules\delphi-lexer\source\Delphi.Lexer.pas',
  Delphi.Lexer.Scanner in '..\..\submodules\delphi-lexer\source\Delphi.Lexer.Scanner.pas',
  Delphi.Lexer.Utils in '..\..\submodules\delphi-lexer\source\Delphi.Lexer.Utils.pas',
  Delphi.Token.Kind in '..\..\submodules\delphi-lexer\source\Delphi.Token.Kind.pas',
  Delphi.Token.List in '..\..\submodules\delphi-lexer\source\Delphi.Token.List.pas';

procedure PrintUsage;
begin
  Writeln('Usage: Delphi.Lexer.RenameUnit <from-unit> <to-unit> [options]');
  Writeln;
  Writeln('Renames unit references in uses clauses and scoped expressions.');
  Writeln;
  Writeln('Updates uses clause entries, scoped references (e.g. MyUnit.Func),');
  Writeln('and in "path" strings within .dpr files.  Uses the raw lexer for');
  Writeln('token-safe replacement -- strings, comments, and directives are');
  Writeln('never modified.');
  Writeln;
  Writeln('Options:');
  Writeln('  --dir <path>       Directory to scan (default: current directory)');
  Writeln('  --recurse          Recurse into subdirectories (default: off)');
  Writeln('  --filespec <mask>  File masks, semicolon-separated');
  Writeln('                     (default: *.pas;*.dpr;*.dpk;*.dproj)');
  Writeln('  --map <file>       Batch rename from file (one OldUnit=NewUnit per line)');
  Writeln('  --dry-run          Show changes without modifying files');
  Writeln('  --verbose          Print each file and replacement');
  Writeln('  --log <file>       Write detailed change log to <file>');
  Writeln('  -?, --help         Show usage');
  Writeln;
  Writeln('Examples:');
  Writeln('  Delphi.RenameUnit MyUnit NewUnit');
  Writeln('  Delphi.RenameUnit MyCompany.OldUnit MyCompany.NewUnit --dir C:\MyProject --recurse');
  Writeln('  Delphi.RenameUnit OldUnit NewUnit --dry-run --verbose');
  Writeln('  Delphi.RenameUnit --map renames.txt --dir C:\MyProject --recurse');
end;

var
  Options:TRenameOptions;
  Positionals:array [0 .. 1] of string;
  PosCount:Integer;
  I:Integer;
  Arg:string;
  Engine:TRenameEngine;
  Pairs:TArray<TRenamePair>;
  Pair:TRenamePair;

begin
  try
    // Defaults.
    Options.Dir := GetCurrentDir;
    Options.FileSpec := '*.pas;*.dpr;*.dpk;*.dproj';
    Options.MapFile := '';
    Options.Recurse := False;
    Options.DryRun := False;
    Options.Verbose := False;
    Options.LogFile := '';
    PosCount := 0;

    I := 1;
    while I <= ParamCount do
    begin
      Arg := ParamStr(I);

      if SameText(Arg, '-?') or SameText(Arg, '--help') then
      begin
        PrintUsage;
        Exit;
      end
      else if SameText(Arg, '--recurse') then
        Options.Recurse := True
      else if SameText(Arg, '--dry-run') then
        Options.DryRun := True
      else if SameText(Arg, '--verbose') then
        Options.Verbose := True
      else if SameText(Arg, '--dir') then
      begin
        Inc(I);
        if I > ParamCount then
        begin
          Writeln(ErrOutput, 'Error: --dir requires a path argument.');
          System.ExitCode := 1;
          Exit;
        end;
        Options.Dir := ParamStr(I);
      end
      else if SameText(Arg, '--filespec') then
      begin
        Inc(I);
        if I > ParamCount then
        begin
          Writeln(ErrOutput, 'Error: --filespec requires a mask argument.');
          System.ExitCode := 1;
          Exit;
        end;
        Options.FileSpec := ParamStr(I);
      end
      else if SameText(Arg, '--map') then
      begin
        Inc(I);
        if I > ParamCount then
        begin
          Writeln(ErrOutput, 'Error: --map requires a filename argument.');
          System.ExitCode := 1;
          Exit;
        end;
        Options.MapFile := ParamStr(I);
      end
      else if SameText(Arg, '--log') then
      begin
        Inc(I);
        if I > ParamCount then
        begin
          Writeln(ErrOutput, 'Error: --log requires a filename argument.');
          System.ExitCode := 1;
          Exit;
        end;
        Options.LogFile := ParamStr(I);
      end
      else if (Length(Arg) > 0) and (Arg[1] = '-') then
      begin
        Writeln(ErrOutput, 'Error: Unknown option: ' + Arg);
        PrintUsage;
        System.ExitCode := 1;
        Exit;
      end
      else
      begin
        if PosCount > 1 then
        begin
          Writeln(ErrOutput, 'Error: Too many positional arguments.');
          PrintUsage;
          System.ExitCode := 1;
          Exit;
        end;
        Positionals[PosCount] := Arg;
        Inc(PosCount);
      end;

      Inc(I);
    end;

    // Build rename pairs from either positional args or --map file.
    if Options.MapFile <> '' then
    begin
      if PosCount > 0 then
      begin
        Writeln(ErrOutput, 'Error: --map cannot be combined with positional <from> <to> arguments.');
        System.ExitCode := 1;
        Exit;
      end;
      if not FileExists(Options.MapFile) then
      begin
        Writeln(ErrOutput, 'Error: Map file not found: ' + Options.MapFile);
        System.ExitCode := 1;
        Exit;
      end;
      Pairs := TRenameEngine.LoadMapFile(Options.MapFile);
      if System.Length(Pairs) = 0 then
      begin
        Writeln(ErrOutput, 'Error: No valid rename pairs found in ' + Options.MapFile);
        System.ExitCode := 1;
        Exit;
      end;
      Writeln(Format('Loaded %d rename pair(s) from %s', [System.Length(Pairs), Options.MapFile]));
    end
    else
    begin
      if PosCount < 2 then
      begin
        if PosCount = 0 then
          Writeln(ErrOutput, 'Error: Missing <from-unit> and <to-unit> arguments.')
        else
          Writeln(ErrOutput, 'Error: Missing <to-unit> argument.');
        PrintUsage;
        System.ExitCode := 1;
        Exit;
      end;
      Options.FromUnit := Positionals[0];
      Options.ToUnit := Positionals[1];
      Pair.FromUnit := Options.FromUnit;
      Pair.ToUnit := Options.ToUnit;
      Pairs := [Pair];
    end;

    if not TDirectory.Exists(Options.Dir) then
    begin
      Writeln(ErrOutput, 'Error: Directory not found: ' + Options.Dir);
      System.ExitCode := 1;
      Exit;
    end;

    Engine := TRenameEngine.Create(Pairs);
    try
      System.ExitCode := Engine.Run(Options);
    finally
      Engine.Free;
    end;

  except
    on E:Exception do
    begin
      Writeln(ErrOutput, E.ClassName + ': ' + E.Message);
      System.ExitCode := 1;
    end;
  end;

end.
