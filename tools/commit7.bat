@echo off
setlocal
set GITHUB_TOKEN=
REM Session actions for v0.1.7

REM --- Ticket notes ---
pwsh -NoProfile -File "C:\code\dev-automation-tooling\add-ticket-note.ps1" ^
  -RepoUrl https://github.com/continuous-delphi/delphi-renameunit ^
  -Issue 3 ^
  -Note "Fixed by adding ExtractSourceLineByNumber that uses 1-based line number instead of byte offset. Line numbers are stable across source and modified text since replacements don't add/remove lines. Added test that renames X to VeryLongUnitName and verifies the log after-line."

REM --- Close completed tickets ---
pwsh -NoProfile -File "C:\code\dev-automation-tooling\close-ticket.ps1" ^
  -RepoUrl https://github.com/continuous-delphi/delphi-renameunit ^
  -Issue 3 ^
  -TicketListFile "%~dp0repo_tickets.txt" ^
  -Comment "Completed in v0.1.7.0"

REM --- Commit ---
echo fix: use line number instead of byte offset for log after-lines> "%TEMP%\commit_msg.txt"
echo.>> "%TEMP%\commit_msg.txt"
echo ExtractSourceLine used the original source byte offset to extract>> "%TEMP%\commit_msg.txt"
echo the after-line from modified text. When replacement length differs>> "%TEMP%\commit_msg.txt"
echo from the original, the offset is wrong in the modified string.>> "%TEMP%\commit_msg.txt"
echo Added ExtractSourceLineByNumber which uses the stable 1-based line>> "%TEMP%\commit_msg.txt"
echo number from the replacement record instead.>> "%TEMP%\commit_msg.txt"
echo.>> "%TEMP%\commit_msg.txt"
echo Resolves #3>> "%TEMP%\commit_msg.txt"
echo.>> "%TEMP%\commit_msg.txt"
echo v0.1.7.0>> "%TEMP%\commit_msg.txt"
git add -A
git commit -F "%TEMP%\commit_msg.txt"
del "%TEMP%\commit_msg.txt"

endlocal
