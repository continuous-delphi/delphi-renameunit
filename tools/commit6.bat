@echo off
setlocal
REM Session actions for v0.1.6

REM --- Ticket notes ---
pwsh -NoProfile -File "C:\code\dev-automation-tooling\add-ticket-note.ps1" ^
  -RepoUrl https://github.com/continuous-delphi/delphi-renameunit ^
  -Issue 1 ^
  -Note "Fixed: PrintUsage said Delphi.Lexer.RenameUnit instead of Delphi.RenameUnit."

pwsh -NoProfile -File "C:\code\dev-automation-tooling\add-ticket-note.ps1" ^
  -RepoUrl https://github.com/continuous-delphi/delphi-renameunit ^
  -Issue 2 ^
  -Note "Fixed: Both Engine.pas and .dpr had delphi-lexer boilerplate header. Replaced with delphi-renameunit project name, URL, and description."

REM --- Close completed tickets ---
pwsh -NoProfile -File "C:\code\dev-automation-tooling\close-ticket.ps1" ^
  -RepoUrl https://github.com/continuous-delphi/delphi-renameunit ^
  -Issue 1 ^
  -TicketListFile tools\repo_tickets.txt ^
  -Comment "Completed in v0.1.6.0"

pwsh -NoProfile -File "C:\code\dev-automation-tooling\close-ticket.ps1" ^
  -RepoUrl https://github.com/continuous-delphi/delphi-renameunit ^
  -Issue 2 ^
  -TicketListFile tools\repo_tickets.txt ^
  -Comment "Completed in v0.1.6.0"

REM --- Commit ---
echo fix: correct copy/paste errors in help text and file headers> "%TEMP%\commit_msg.txt"
echo.>> "%TEMP%\commit_msg.txt"
echo PrintUsage referenced Delphi.Lexer.RenameUnit instead of>> "%TEMP%\commit_msg.txt"
echo Delphi.RenameUnit. Engine.pas and .dpr had the delphi-lexer>> "%TEMP%\commit_msg.txt"
echo boilerplate header instead of delphi-renameunit.>> "%TEMP%\commit_msg.txt"
echo.>> "%TEMP%\commit_msg.txt"
echo Resolves #1>> "%TEMP%\commit_msg.txt"
echo Resolves #2>> "%TEMP%\commit_msg.txt"
echo.>> "%TEMP%\commit_msg.txt"
echo v0.1.6.0>> "%TEMP%\commit_msg.txt"
git add -A
git commit -F "%TEMP%\commit_msg.txt"
del "%TEMP%\commit_msg.txt"

endlocal
