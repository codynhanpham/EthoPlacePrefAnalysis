function gui()
    %%GUI Launches the SLEAP GUI for labeling and training.
    %
    % This function launches a detached TTY process that will start the SLEAP GUI
    % A new Terminal window will open that is unmanaged by MATLAB

    [uvpath, sleapdir] = io.sleap.install();

    if isempty(uvpath) || isempty(sleapdir)
        error('SLEAP installation not found. Please run io.sleap.install() first and ensure that SLEAP is installed correctly.');
    end

    currentpwd = pwd();
    cleanup = onCleanup(@() cd(currentpwd));

    cd(sleapdir);
    cmd = buildLaunchCommand(uvpath, sleapdir);
    systermCmd(cmd, 'KeepOpen', true);
end

function cmd = buildLaunchCommand(uvpath, sleapdir)
    runCmd = sprintf('"%s" run --project "%s" sleap', uvpath, sleapdir);

    if ispc
        cmd = sprintf('echo %s && echo. && echo SLEAP GUI will start in just a moment... && echo. && %s && echo. && echo. && echo You may now close this terminal', runCmd, runCmd);
    else
        cmd = sprintf('printf ''%%s\\n\\n'' ''%s'' && printf ''%%s\\n\\n'' ''SLEAP GUI will start in just a moment...'' && %s && printf ''\\n\\n%%s\\n'' ''You may now close this terminal''', runCmd, runCmd);
    end
end


function status = systermCmd(command, options)
    %%CMD Launches a command in a new, independent native terminal window.
    % This function is copied from the systerm module
    %
    % Syntax:
    %   status = systerm.cmd(command)
    %
    % Input:
    %   command - String or character vector containing the command to run.
    %       When empty, a new terminal window will be opened without executing any command.
    % Named Arguments:
    %   'KeepOpen' (optional) - Logical flag indicating whether to keep the terminal open after the command completes. Default is false.
    %
    % Output:
    %   status - System exit code (0 typically means success).

    arguments
        command {mustBeTextScalarOrEmpty} = []
        options.KeepOpen (1,1) logical = false
    end

    command = char(strip(string(command)));
    keepOpen = options.KeepOpen || isempty(command);

    if ispc
        fullCmd = buildWindowsLaunchCommand(command, keepOpen);
        status = system(fullCmd);
        
    elseif ismac
            fullCmd = buildMacLaunchCommand(command, keepOpen);
        status = system(fullCmd);
        
    elseif isunix % Linux/Unix derivatives
            fullCmd = buildUnixLaunchCommand(command, keepOpen);
        status = system(fullCmd);
        
    else
        error('Unsupported operating system platform detected.');
    end
end

function mustBeTextScalarOrEmpty(x)
    if isempty(x)
        return;
    end
    mustBeTextScalar(x);
end

function fullCmd = buildWindowsLaunchCommand(command, keepOpen)
    if isempty(command)
        fullCmd = 'start "" cmd.exe /k';
        return;
    end

    if keepOpen
        modeFlag = '/k';
    else
        modeFlag = '/c';
    end

    fullCmd = sprintf('start "" cmd.exe %s "%s"', modeFlag, escapeCmdQuotes(command));
end

function fullCmd = buildMacLaunchCommand(command, keepOpen)
    if isempty(command)
        shellCommand = 'bash';
    elseif keepOpen
        shellCommand = sprintf('bash -lc %s', shellQuote([command, '; exec bash']));
    else
        shellCommand = sprintf('bash -lc %s', shellQuote([command, '; exit']));
    end

    escapedShellCommand = escapeAppleScriptString(shellCommand);
    fullCmd = sprintf([ ...
        'osascript -e ''tell application "Terminal" to do script "%s"'' ', ...
        '-e ''tell application "Terminal" to activate'''], escapedShellCommand);
end

function fullCmd = buildUnixLaunchCommand(command, keepOpen)
    terminalBin = detectUnixTerminal();

    if isempty(command)
        shellCommand = 'bash';
    elseif keepOpen
        shellCommand = sprintf('bash -lc %s', shellQuote([command, '; exec bash']));
    else
        shellCommand = sprintf('bash -lc %s', shellQuote([command, '; exit']));
    end

    switch terminalBin
        case 'konsole'
            if keepOpen || isempty(command)
                fullCmd = sprintf('(konsole --hold -e %s) >/dev/null 2>&1 &', shellCommand);
            else
                fullCmd = sprintf('(konsole -e %s) >/dev/null 2>&1 &', shellCommand);
            end
        case 'kitty'
            if keepOpen || isempty(command)
                fullCmd = sprintf('(kitty --hold -e %s) >/dev/null 2>&1 &', shellCommand);
            else
                fullCmd = sprintf('(kitty -e %s) >/dev/null 2>&1 &', shellCommand);
            end
        case 'alacritty'
            fullCmd = sprintf('(alacritty -e %s) >/dev/null 2>&1 &', shellCommand);
        case 'ghostty'
            fullCmd = sprintf('(ghostty -e %s) >/dev/null 2>&1 &', shellCommand);
        case 'xterm'
            if keepOpen || isempty(command)
                fullCmd = sprintf('(xterm -hold -e %s) >/dev/null 2>&1 &', shellCommand);
            else
                fullCmd = sprintf('(xterm -e %s) >/dev/null 2>&1 &', shellCommand);
            end
        otherwise
            fullCmd = sprintf('(%s -e %s) >/dev/null 2>&1 &', terminalBin, shellCommand);
    end
end

function terminalBin = detectUnixTerminal()
    if ~isempty(getenv('TERMINAL'))
        terminalBin = strtrim(getenv('TERMINAL'));
        return;
    end

    candidates = {'gnome-terminal', 'mate-terminal', 'xfce4-terminal', 'konsole', 'kitty', 'alacritty', 'ghostty', 'xterm'};
    for i = 1:numel(candidates)
        [status, ~] = system(sprintf('command -v %s >/dev/null 2>&1', candidates{i}));
        if status == 0
            terminalBin = candidates{i};
            return;
        end
    end

    terminalBin = 'xterm';
end

function escaped = escapeCmdQuotes(command)
    escaped = strrep(command, '"', '""');
end

function escaped = shellQuote(command)
    escaped = ['''', strrep(command, '''', '''"''"''"'''), ''''];
end

function escaped = escapeAppleScriptString(command)
    escaped = strrep(command, '\', '\\');
    escaped = strrep(escaped, '"', '\"');
    escaped = strrep(escaped, char(13), ' ');
    escaped = strrep(escaped, char(10), ' ');
end
