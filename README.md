# delphi-renameunit

A command-line utility that renames Delphi unit references across an entire codebase.
It uses a token-based lexer to safely update `uses` clauses, scoped references, 
`in 'path'` strings, and `.dproj` file entries -- without touching strings,
comments, or compiler directives.

## Features

- Renames unit references in `uses` and `contains` clauses
- Renames scoped references (e.g. `MyUnit.DoStuff` becomes `NewUnit.DoStuff`)
- Updates `in 'path'` strings in `.dpr` files
- Updates `DCCReference Include="..."` entries in `.dproj` files
- Renames the physical `.pas` file when its unit declaration matches
- Supports dotted unit names (e.g. `Vcl.OldForm` to `Vcl.NewForm`)
- Case-insensitive matching
- Batch rename via map file
- Dry-run mode to preview changes before applying
- Detailed change log output

## How it works

The engine tokenizes each source file using [delphi-lexer](https://github.com/continuous-delphi/delphi-lexer),
then walks the token stream to find unit name matches.
Replacements are collected as offset/length records and applied in reverse order so earlier offsets remain valid.
Because it operates on tokens rather than raw text, references inside string literals, comments, and compiler
directives are never modified.

A full-name invariant ensures that only complete unit names are matched.
Renaming `Utils` will not affect `System.Utils`, and renaming `SynAccessibility` will not match `cd.SynAccessibility`.

## Usage

```
Delphi.RenameUnit <from-unit> <to-unit> [options]
Delphi.RenameUnit --map <file> [options]
```

### Positional arguments

| Argument      | Description                        |
|---------------|------------------------------------|
| `<from-unit>` | Current unit name to find          |
| `<to-unit>`   | New unit name to replace it with   |

### Options

| Option              | Description                                                  |
|---------------------|--------------------------------------------------------------|
| `--dir <path>`      | Directory to scan (default: current directory)               |
| `--recurse`         | Recurse into subdirectories                                  |
| `--filespec <mask>` | File masks, semicolon-separated (default: `*.pas;*.dpr;*.dpk;*.dproj`) |
| `--map <file>`      | Batch rename from a map file (one `OldUnit=NewUnit` per line)|
| `--dry-run`         | Show changes without modifying files                         |
| `--verbose`         | Print each file and replacement                              |
| `--log <file>`      | Write detailed change log to a file                          |
| `-?`, `--help`      | Show usage                                                   |

### Exit codes

| Code | Meaning |
|------|---------|
| 0    | Changes were made (or dry-run found matches) |
| 1    | Error (bad arguments, missing directory, etc.) |
| 2    | No matching references found |

### Examples

Rename a single unit:

```
Delphi.RenameUnit MyUnit NewUnit
```

Rename a dotted unit with directory recursion:

```
Delphi.RenameUnit MyCompany.OldUnit MyCompany.NewUnit --dir C:\MyProject --recurse
```

Preview changes without modifying files:

```
Delphi.RenameUnit OldUnit NewUnit --dry-run --verbose
```

Batch rename using a map file:

```
Delphi.RenameUnit --map renames.txt --dir C:\MyProject --recurse
```

### Map file format

A map file contains one rename pair per line in `OldUnit=NewUnit` format. Blank lines and lines starting with `#` or `;` are ignored.

```
# Rename pairs for v2 migration
App.OldAuth=App.NewAuth
App.OldConfig=App.NewConfig

; Legacy units
DeprecatedUtils=ModernUtils
```

### Log output

When `--log` is specified, the log file records each replacement with before/after source lines and file rename operations:

```
src\Consumer.pas(3,6)
  - uses App.OldAuth;
  + uses App.NewAuth;

FILE RENAME: src\App.OldAuth.pas -> src\App.NewAuth.pas
```

