(*

  delphi-renameunit
  https://github.com/continuous-delphi/delphi-renameunit

  A command-line utility that renames Delphi unit references
  across an entire codebase using token-based lexing.

  License: MIT
  Copyright (c) 2026 Darian Miller

*)

unit Delphi.RenameUnit.Engine;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  Delphi.Lexer,
  Delphi.Lexer.Utils,
  Delphi.Token,
  Delphi.Token.Kind,
  Delphi.Token.List,
  Delphi.Keywords;

type

  TRenamePair = record
    FromUnit:string;
    ToUnit:string;
  end;

  TRenameOptions = record
    FromUnit:string;
    ToUnit:string;
    MapFile:string;  // optional batch rename file (one OldUnit=NewUnit per line)
    Dir:string;
    FileSpec:string; // semicolon-separated masks: *.pas;*.dpr;*.dpk
    LogFile:string;  // optional log file path
    Recurse:Boolean;
    DryRun:Boolean;
    Verbose:Boolean;
  end;

  TReplacement = record
    StartOffset:Integer; // 0-based position in original source
    Length:Integer;      // chars to replace
    NewText:string;
    Line:Integer;        // 1-based line number of first token
    Col:Integer;         // 1-based column of first token
  end;


  // Token-based unit rename engine.
  //
  // Uses the raw TDelphiLexer to tokenize each file,
  // then collects replacement records (offset, length, new text) and
  // applies them in reverse order on the original source string.  This
  // ensures all references are renamed regardless of {$IFDEF} state, while
  // naturally avoiding changes inside strings, comments, and directives.
  TRenameEngine = class
  private
    FLexer:TDelphiLexer;
    FPairs:TArray<TRenamePair>;
    FPairParts:TArray<TArray<string>>;  // FFromParts for each pair
    // Active pair index (set during FindReplacements iteration).
    FFromParts:TArray<string>;
    FToUnit:string;
    FReplacements:TList<TReplacement>;
    FLog:TStreamWriter;
    FTotalFiles:Integer;
    FChangedFiles:Integer;
    FTotalReplacements:Integer;
    FTotalFileRenames:Integer;

    class function SplitUnitName(const Name:string):TArray<string>; static;

    // Match a dotted unit name starting at token index I.
    // Returns True and sets EndIndex to the last matched token.
    function MatchTokenSequence(const Tokens:TTokenList; StartIndex:Integer; const Parts:TArray<string>; out EndIndex:Integer):Boolean;

    // Check whether token at Idx is preceded by a dot (skipping trivia).
    function PrecededByDot(const Tokens:TTokenList; Idx:Integer):Boolean;

    // Check whether token at Idx is followed by a dot (skipping trivia).
    function FollowedByDot(const Tokens:TTokenList; Idx:Integer):Boolean;

    // Add a replacement covering tokens StartIdx..EndIdx.
    procedure AddReplacement(const Tokens:TTokenList; StartIdx, EndIdx:Integer; const NewText:string);

    // Scan a single file and collect replacements for one rename pair.
    // Sets UnitDeclMatched if the file's unit declaration matches FromUnit.
    procedure FindReplacements(const Tokens:TTokenList;
      out UnitDeclMatched:Boolean);

    // Apply collected replacements to the source string.
    function ApplyReplacements(const Source:string):string;

    // Build the replacement text for an `in 'path'` string token.
    function RenameInPath(const PathToken:string):string;

    // Extract the source line containing the given 0-based offset.
    class function ExtractSourceLine(const Source:string; Offset:Integer):string; static;

    // Extract a source line by 1-based line number.
    class function ExtractSourceLineByNumber(const Source:string; LineNumber:Integer):string; static;

    // Process one source file (token-based).  Returns replacement count.
    function ProcessFile(const FilePath:string; DryRun, Verbose:Boolean):Integer;

    // Process one .dproj file (text-based XML replacement).
    // Returns replacement count.
    function ProcessDprojFile(const FilePath:string; DryRun, Verbose:Boolean):Integer;
  public
    class function LoadMapFile(const MapPath:string):TArray<TRenamePair>; static;

    constructor Create(const Pairs:TArray<TRenamePair>);
    destructor Destroy; override;

    function Run(const Options:TRenameOptions):Integer;
  end;


implementation


class function TRenameEngine.SplitUnitName(const Name:string):TArray<string>;
begin
  Result := Name.Split(['.']);
end;


constructor TRenameEngine.Create(const Pairs:TArray<TRenamePair>);
var
  I:Integer;
begin
  inherited Create;
  FLexer := TDelphiLexer.Create;
  FReplacements := TList<TReplacement>.Create;
  FPairs := Pairs;
  SetLength(FPairParts, System.Length(Pairs));
  for I := 0 to High(Pairs) do
    FPairParts[I] := SplitUnitName(Pairs[I].FromUnit);
end;


class function TRenameEngine.LoadMapFile(const MapPath:string):TArray<TRenamePair>;
var
  Lines:TStringList;
  I, EqPos:Integer;
  Line:string;
  Pair:TRenamePair;
  ResultList:TList<TRenamePair>;
begin
  Lines := TStringList.Create;
  ResultList := TList<TRenamePair>.Create;
  try
    Lines.LoadFromFile(MapPath, TEncoding.UTF8);
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] = '#') or (Line[1] = ';') then
        Continue;
      EqPos := Pos('=', Line);
      if EqPos = 0 then
      begin
        Writeln(ErrOutput, Format('Warning: skipping invalid map line %d: %s', [I + 1, Line]));
        Continue;
      end;
      Pair.FromUnit := Trim(Copy(Line, 1, EqPos - 1));
      Pair.ToUnit := Trim(Copy(Line, EqPos + 1, MaxInt));
      if (Pair.FromUnit <> '') and (Pair.ToUnit <> '') then
        ResultList.Add(Pair);
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
    Lines.Free;
  end;
end;


destructor TRenameEngine.Destroy;
begin
  FReplacements.Free;
  FLexer.Free;
  inherited;
end;


function TRenameEngine.MatchTokenSequence(const Tokens:TTokenList; StartIndex:Integer; const Parts:TArray<string>; out EndIndex:Integer):Boolean;
var
  I, J:Integer;
begin
  Result := False;
  I := StartIndex;
  if (I < 0) or (I >= Tokens.Count) then
    Exit;

  // First part must be an identifier matching Parts[0].
  if not (Tokens[I].Kind in [tkIdentifier, tkStrictKeyword, tkContextKeyword]) then
    Exit;
  if not SameText(Tokens[I].Text, Parts[0]) then
    Exit;

  // Match remaining parts: each separated by a dot.
  for J := 1 to High(Parts) do
  begin
    // Advance past trivia to find the dot.
    Inc(I);
    while (I < Tokens.Count) and (Tokens[I].Kind in [tkWhitespace, tkEOL]) do
      Inc(I);
    if (I >= Tokens.Count) or (Tokens[I].Kind <> tkSymbol) or (Tokens[I].Text <> '.') then
      Exit;
    // Advance past trivia to find the next identifier.
    Inc(I);
    while (I < Tokens.Count) and (Tokens[I].Kind in [tkWhitespace, tkEOL]) do
      Inc(I);
    if (I >= Tokens.Count) then
      Exit;
    if not (Tokens[I].Kind in [tkIdentifier, tkStrictKeyword, tkContextKeyword]) then
      Exit;
    if not SameText(Tokens[I].Text, Parts[J]) then
      Exit;
  end;

  EndIndex := I;
  Result := True;
end;


function TRenameEngine.PrecededByDot(const Tokens:TTokenList; Idx:Integer):Boolean;
var
  I:Integer;
begin
  Result := False;
  I := Idx - 1;
  while (I >= 0) and (Tokens[I].Kind in [tkWhitespace, tkEOL]) do
    Dec(I);
  if (I >= 0) and (Tokens[I].Kind = tkSymbol) and (Tokens[I].Text = '.') then
    Result := True;
end;


function TRenameEngine.FollowedByDot(const Tokens:TTokenList; Idx:Integer):Boolean;
var
  I:Integer;
begin
  Result := False;
  I := Idx + 1;
  while (I < Tokens.Count) and (Tokens[I].Kind in [tkWhitespace, tkEOL]) do
    Inc(I);
  if (I < Tokens.Count) and (Tokens[I].Kind = tkSymbol) and (Tokens[I].Text = '.') then
    Result := True;
end;


procedure TRenameEngine.AddReplacement(const Tokens:TTokenList; StartIdx, EndIdx:Integer; const NewText:string);
var
  R:TReplacement;
begin
  R.StartOffset := Tokens[StartIdx].StartOffset;
  R.Length := (Tokens[EndIdx].StartOffset + Tokens[EndIdx].Length) - Tokens[StartIdx].StartOffset;
  R.NewText := NewText;
  R.Line := Tokens[StartIdx].Line;
  R.Col := Tokens[StartIdx].Col;
  FReplacements.Add(R);
end;


// PathToken is the full token text including quotes, e.g. 'OldUnit.pas'
// Replace the filename portion (without extension) if it matches.
function TRenameEngine.RenameInPath(const PathToken:string):string;
var
  Inner, Dir, FileName, BaseName, Ext:string;
  Quote:Char;
begin
  Result := PathToken;
  if System.Length(PathToken) < 3 then
    Exit;

  Quote := PathToken[1];
  Inner := Copy(PathToken, 2, System.Length(PathToken) - 2);

  // Split into directory and filename.
  FileName := ExtractFileName(Inner);
  Dir := Copy(Inner, 1, System.Length(Inner) - System.Length(FileName));
  Ext := ExtractFileExt(FileName);
  BaseName := ChangeFileExt(FileName, '');

  // Match: the base name should equal the from-unit (with dots).
  // Dotted unit names use dots in filenames too: System.SysUtils.pas
  if not SameText(BaseName, string.Join('.', FFromParts)) then
    Exit;

  Result := Quote + Dir + FToUnit + Ext + Quote;
end;


procedure TRenameEngine.FindReplacements(const Tokens:TTokenList;
  out UnitDeclMatched:Boolean);
var
  I, EndIdx, NextI:Integer;
  InUsesClause:Boolean;
  T:TToken;
begin
  FReplacements.Clear;
  UnitDeclMatched := False;
  InUsesClause := False;
  I := 0;

  while I < Tokens.Count do
  begin
    T := Tokens[I];

    // Skip trivia tokens.
    if T.Kind in [tkWhitespace, tkEOL, tkComment, tkDirective, tkBOM, tkInactiveCode] then
    begin
      Inc(I);
      Continue;
    end;

    // Detect and rename the unit declaration: unit <name>;
    if (T.KeywordKind = kwUnit) then
    begin
      NextI := I + 1;
      while (NextI < Tokens.Count) and
            (Tokens[NextI].Kind in [tkWhitespace, tkEOL]) do
        Inc(NextI);
      if MatchTokenSequence(Tokens, NextI, FFromParts, EndIdx) then
      begin
        UnitDeclMatched := True;
        AddReplacement(Tokens, NextI, EndIdx, FToUnit);
        I := EndIdx + 1;
        Continue;
      end;
      Inc(I);
      Continue;
    end;

    // Track uses/contains clause boundaries.
    if (T.KeywordKind = kwUses) or (T.KeywordKind = kwContains) then
    begin
      InUsesClause := True;
      Inc(I);
      Continue;
    end;

    if InUsesClause then
    begin

      // Semicolon ends the uses clause.
      if (T.Kind = tkSymbol) and (T.Text = ';') then
      begin
        InUsesClause := False;
        Inc(I);
        Continue;
      end;

      // Skip commas.
      if (T.Kind = tkSymbol) and (T.Text = ',') then
      begin
        Inc(I);
        Continue;
      end;

      // Try to match a uses/contains clause entry.
      //
      // INVARIANT: only match complete unit names, never partial.
      // "SynAccessibility" must not match inside "cd.SynAccessibility".
      // The PrecededByDot/FollowedByDot guards enforce this by
      // rejecting matches that are a prefix or suffix of a longer
      // dotted name.  A future regex mode would need to preserve
      // this invariant or explicitly opt out of it.
      if MatchTokenSequence(Tokens, I, FFromParts, EndIdx) and
         not PrecededByDot(Tokens, I) and
         not FollowedByDot(Tokens, EndIdx) then
      begin

        AddReplacement(Tokens, I, EndIdx, FToUnit);

        // Check for `in 'path'` suffix after the unit name.
        NextI := EndIdx + 1;
        while (NextI < Tokens.Count) and (Tokens[NextI].Kind in [tkWhitespace, tkEOL]) do
          Inc(NextI);

        if (NextI < Tokens.Count) and (Tokens[NextI].Kind in [tkStrictKeyword, tkContextKeyword, tkIdentifier]) and SameText(Tokens[NextI].Text, 'in') then
        begin

          Inc(NextI);
          while (NextI < Tokens.Count) and (Tokens[NextI].Kind in [tkWhitespace, tkEOL]) do
            Inc(NextI);

          if (NextI < Tokens.Count) and (Tokens[NextI].Kind = tkString) then
          begin
            // Replace the path string.
            var NewPath := RenameInPath(Tokens[NextI].Text);
            if NewPath <> Tokens[NextI].Text then
            begin
              var R:TReplacement;
              R.StartOffset := Tokens[NextI].StartOffset;
              R.Length := Tokens[NextI].Length;
              R.NewText := NewPath;
              R.Line := Tokens[NextI].Line;
              R.Col := Tokens[NextI].Col;
              FReplacements.Add(R);
            end;
            I := NextI + 1;
            Continue;
          end;
        end;

        I := EndIdx + 1;
        Continue;
      end;

      // Not a match -- skip this identifier (part of a different entry).
      Inc(I);
      Continue;
    end;

    // Outside uses clause: look for scoped references.
    // Same full-name invariant: PrecededByDot rejects suffix matches
    // (e.g. "SynAccessibility" inside "cd.SynAccessibility.DoStuff").
    // FollowedByDot is NOT checked here because in code context a
    // following dot is the member-access operator, not a name
    // continuation -- "MyUnit.Func" should match "MyUnit".
    if T.Kind in [tkIdentifier, tkStrictKeyword, tkContextKeyword] then
    begin
      if not PrecededByDot(Tokens, I) and
         MatchTokenSequence(Tokens, I, FFromParts, EndIdx) then
      begin
        AddReplacement(Tokens, I, EndIdx, FToUnit);
        I := EndIdx + 1;
        Continue;
      end;
    end;

    Inc(I);
  end;
end;


function TRenameEngine.ApplyReplacements(const Source:string):string;
var
  I:Integer;
  Sorted:TArray<TReplacement>;
  R:TReplacement;
begin
  Result := Source;
  if FReplacements.Count = 0 then
    Exit;

  // Sort by offset descending so replacements don't invalidate later offsets.
  Sorted := FReplacements.ToArray;
  TArray.Sort<TReplacement>(Sorted, TComparer<TReplacement>.Construct(function(const A, B:TReplacement):Integer begin Result := B.StartOffset - A.StartOffset; end));

  for I := 0 to High(Sorted) do
  begin
    R := Sorted[I];
    // StartOffset is 0-based, but Delphi strings are 1-based.
    Delete(Result, R.StartOffset + 1, R.Length);
    Insert(R.NewText, Result, R.StartOffset + 1);
  end;
end;


class function TRenameEngine.ExtractSourceLine(const Source:string;
  Offset:Integer):string;
var
  LineStart, LineEnd, Len:Integer;
begin
  Len := System.Length(Source);
  // Offset is 0-based; convert to 1-based for string indexing.
  LineStart := Offset + 1;
  while (LineStart > 1) and not CharInSet(Source[LineStart - 1], [#10, #13]) do
    Dec(LineStart);
  LineEnd := Offset + 1;
  while (LineEnd <= Len) and not CharInSet(Source[LineEnd], [#10, #13]) do
    Inc(LineEnd);
  Result := TrimRight(Copy(Source, LineStart, LineEnd - LineStart));
end;


class function TRenameEngine.ExtractSourceLineByNumber(const Source:string; LineNumber:Integer):string;
var
  I, Len, CurrentLine, LineStart:Integer;
begin
  Len := System.Length(Source);
  CurrentLine := 1;
  LineStart := 1;
  I := 1;
  while I <= Len do
  begin
    if CurrentLine = LineNumber then
    begin
      // Find end of this line.
      while (I <= Len) and not CharInSet(Source[I], [#10, #13]) do
        Inc(I);
      Result := TrimRight(Copy(Source, LineStart, I - LineStart));
      Exit;
    end;
    if Source[I] = #13 then
    begin
      Inc(I);
      if (I <= Len) and (Source[I] = #10) then
        Inc(I);
      Inc(CurrentLine);
      LineStart := I;
    end
    else if Source[I] = #10 then
    begin
      Inc(I);
      Inc(CurrentLine);
      LineStart := I;
    end
    else
      Inc(I);
  end;
  // If we reached the end and we're on the target line, return remainder.
  if CurrentLine = LineNumber then
    Result := TrimRight(Copy(Source, LineStart, Len - LineStart + 1))
  else
    Result := '';
end;


function TRenameEngine.ProcessFile(const FilePath:string; DryRun, Verbose:Boolean):Integer;
var
  Source, Modified:string;
  Tokens:TTokenList;
  I, P:Integer;
  UnitDeclMatched, PairDeclMatched:Boolean;
  BaseName, Ext, Dir, NewPath:string;
  BeforeLine, AfterLine:string;
  AllReplacements:TList<TReplacement>;
  MatchedPairIndex:Integer;
begin
  Source := TLexerUtils.ReadAllText(FilePath, TEncoding.UTF8, False);
  AllReplacements := TList<TReplacement>.Create;
  try
    UnitDeclMatched := False;
    MatchedPairIndex := -1;

    // Run each rename pair against the current source, applying
    // replacements sequentially so later pairs see earlier changes.
    for P := 0 to High(FPairs) do
    begin
      FFromParts := FPairParts[P];
      FToUnit := FPairs[P].ToUnit;

      Tokens := FLexer.Tokenize(Source);
      try
        FindReplacements(Tokens, PairDeclMatched);
        if FReplacements.Count = 0 then
          Continue;

        if PairDeclMatched then
        begin
          UnitDeclMatched := True;
          MatchedPairIndex := P;
        end;

        for I := 0 to FReplacements.Count - 1 do
          AllReplacements.Add(FReplacements[I]);

        if Verbose or DryRun then
        begin
          Writeln(FilePath);
          for I := 0 to FReplacements.Count - 1 do
            Writeln(Format('  offset %d: %s -> %s', [FReplacements[I].StartOffset, Copy(Source, FReplacements[I].StartOffset + 1, FReplacements[I].Length), FReplacements[I].NewText]));
        end;

        // Log replacements with before/after source lines.
        Modified := ApplyReplacements(Source);
        if FLog <> nil then
        begin
          for I := 0 to FReplacements.Count - 1 do
          begin
            BeforeLine := ExtractSourceLine(Source, FReplacements[I].StartOffset);
            AfterLine := ExtractSourceLineByNumber(Modified, FReplacements[I].Line);
            FLog.WriteLine(Format('%s(%d,%d)', [FilePath, FReplacements[I].Line, FReplacements[I].Col]));
            FLog.WriteLine('  - ' + BeforeLine);
            FLog.WriteLine('  + ' + AfterLine);
          end;
        end;

        // Update source for subsequent pairs.
        Source := Modified;
      finally
        Tokens.Free;
      end;
    end;

    Result := AllReplacements.Count;
    if Result = 0 then
      Exit;

    if not DryRun then
      TFile.WriteAllText(FilePath, Source, TEncoding.UTF8);

    // Rename the physical file when the unit declaration matched and
    // the filename corresponds to the old unit name.
    if UnitDeclMatched and (MatchedPairIndex >= 0) then
    begin
      FFromParts := FPairParts[MatchedPairIndex];
      FToUnit := FPairs[MatchedPairIndex].ToUnit;
      BaseName := ChangeFileExt(ExtractFileName(FilePath), '');
      Ext := ExtractFileExt(FilePath);
      if SameText(BaseName, string.Join('.', FFromParts)) then
      begin
        Dir := ExtractFilePath(FilePath);
        NewPath := Dir + FToUnit + Ext;
        if DryRun then
          Writeln(Format('  rename: %s -> %s', [ExtractFileName(FilePath), FToUnit + Ext]))
        else
        begin
          TFile.Move(FilePath, NewPath);
          Writeln(Format('  renamed: %s -> %s', [ExtractFileName(FilePath), FToUnit + Ext]));
        end;
        if FLog <> nil then
          FLog.WriteLine(Format('FILE RENAME: %s -> %s', [FilePath, NewPath]));
        Inc(FTotalFileRenames);
      end;
    end;
  finally
    AllReplacements.Free;
  end;
end;


function TRenameEngine.ProcessDprojFile(const FilePath:string;
  DryRun, Verbose:Boolean):Integer;
// Text-based replacement in .dproj XML files.  Scans for DCCReference
// Include attributes and replaces unit filenames that match any rename pair.
// No XML parser needed -- the patterns are simple and well-defined.
var
  Source, Modified, Line, OldFileName, NewFileName, OldBase, Ext:string;
  Lines:TStringList;
  I, P, Pos1, Pos2:Integer;
  Changed:Boolean;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    Source := TLexerUtils.ReadAllText(FilePath, TEncoding.UTF8, False);
    Lines.Text := Source;
    Changed := False;

    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      // Look for DCCReference Include="..." or Include="...\..."
      Pos1 := Pos('Include="', Line);
      if Pos1 = 0 then
        Continue;
      Pos1 := Pos1 + System.Length('Include="');
      Pos2 := PosEx('"', Line, Pos1);
      if Pos2 = 0 then
        Continue;

      OldFileName := Copy(Line, Pos1, Pos2 - Pos1);
      Ext := ExtractFileExt(OldFileName);
      OldBase := ChangeFileExt(ExtractFileName(OldFileName), '');

      for P := 0 to High(FPairs) do
      begin
        if SameText(OldBase, string.Join('.', FPairParts[P])) then
        begin
          // Replace the filename portion, preserving directory path.
          NewFileName := Copy(OldFileName, 1,
            System.Length(OldFileName) - System.Length(ExtractFileName(OldFileName)))
            + FPairs[P].ToUnit + Ext;
          Lines[I] := Copy(Line, 1, Pos1 - 1) + NewFileName +
                      Copy(Line, Pos2, MaxInt);
          Changed := True;
          Inc(Result);

          if Verbose or DryRun then
          begin
            if Result = 1 then
              Writeln(FilePath);
            Writeln(Format('  %s -> %s', [OldFileName, NewFileName]));
          end;
          if FLog <> nil then
          begin
            FLog.WriteLine(Format('%s(%d)', [FilePath, I + 1]));
            FLog.WriteLine('  - ' + TrimLeft(Line));
            FLog.WriteLine('  + ' + TrimLeft(Lines[I]));
          end;
          Break;
        end;
      end;
    end;

    if Changed and not DryRun then
    begin
      Modified := Lines.Text;
      TFile.WriteAllText(FilePath, Modified, TEncoding.UTF8);
    end;
  finally
    Lines.Free;
  end;
end;


function TRenameEngine.Run(const Options:TRenameOptions):Integer;
var
  Masks:TArray<string>;
  Files:TList<string>;
  Mask, FilePath:string;
  SearchOpt:TSearchOption;
  FoundFiles:TArray<string>;
  FileReplacements:Integer;
  Summary:string;
begin
  FTotalFiles := 0;
  FChangedFiles := 0;
  FTotalReplacements := 0;
  FTotalFileRenames := 0;
  FLog := nil;

  if Options.LogFile <> '' then
    FLog := TStreamWriter.Create(Options.LogFile, False, TEncoding.UTF8);
  try
    // Log header.
    if FLog <> nil then
    begin
      if System.Length(FPairs) = 1 then
        FLog.WriteLine(Format('Delphi.RenameUnit  %s  "%s" -> "%s"  dir="%s"  filespec="%s"  recurse=%s  dry-run=%s',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
           FPairs[0].FromUnit, FPairs[0].ToUnit, Options.Dir, Options.FileSpec,
           BoolToStr(Options.Recurse, True), BoolToStr(Options.DryRun, True)]))
      else
        FLog.WriteLine(Format('Delphi.RenameUnit  %s  map=%d pair(s)  dir="%s"  filespec="%s"  recurse=%s  dry-run=%s',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
           System.Length(FPairs), Options.Dir, Options.FileSpec,
           BoolToStr(Options.Recurse, True), BoolToStr(Options.DryRun, True)]));
      FLog.WriteLine('');
    end;

    if Options.Recurse then
      SearchOpt := TSearchOption.soAllDirectories
    else
      SearchOpt := TSearchOption.soTopDirectoryOnly;

    // Collect files matching all masks.
    Masks := Options.FileSpec.Split([';']);
    Files := TList<string>.Create;
    try
      for Mask in Masks do
      begin
        if Trim(Mask) = '' then
          Continue;
        FoundFiles := TDirectory.GetFiles(Options.Dir, Trim(Mask), SearchOpt);
        for FilePath in FoundFiles do
          if Files.IndexOf(FilePath) < 0 then
            Files.Add(FilePath);
      end;

      Files.Sort;
      FTotalFiles := Files.Count;

      for FilePath in Files do
      begin
        if SameText(ExtractFileExt(FilePath), '.dproj') then
          FileReplacements := ProcessDprojFile(FilePath, Options.DryRun, Options.Verbose)
        else
          FileReplacements := ProcessFile(FilePath, Options.DryRun, Options.Verbose);
        if FileReplacements > 0 then
        begin
          Inc(FChangedFiles);
          Inc(FTotalReplacements, FileReplacements);
        end;
      end;
    finally
      Files.Free;
    end;

    if Options.DryRun then
      Summary := Format('Dry run: %d replacement(s) in %d file(s) of %d scanned, %d file(s) renamed.',
        [FTotalReplacements, FChangedFiles, FTotalFiles, FTotalFileRenames])
    else
      Summary := Format('%d replacement(s) in %d file(s) of %d scanned, %d file(s) renamed.',
        [FTotalReplacements, FChangedFiles, FTotalFiles, FTotalFileRenames]);
    Writeln(Summary);

    // Log footer.
    if FLog <> nil then
    begin
      FLog.WriteLine('');
      FLog.WriteLine(Summary);
    end;

  finally
    FLog.Free;
    FLog := nil;
  end;

  Result := 0;
end;


end.
