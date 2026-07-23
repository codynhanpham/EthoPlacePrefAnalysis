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
    systerm.cmd(cmd, 'KeepOpen', true);
end

function cmd = buildLaunchCommand(uvpath, sleapdir)
    runCmd = sprintf('"%s" run --project "%s" sleap', uvpath, sleapdir);

    if ispc
        cmd = sprintf('echo %s && echo. && echo SLEAP GUI will start in just a moment... && echo. && %s && echo. && echo. && echo You may now close this terminal', runCmd, runCmd);
    else
        cmd = sprintf('printf ''%%s\\n\\n'' ''%s'' && printf ''%%s\\n\\n'' ''SLEAP GUI will start in just a moment...'' && %s && printf ''\\n\\n%%s\\n'' ''You may now close this terminal''', runCmd, runCmd);
    end
end