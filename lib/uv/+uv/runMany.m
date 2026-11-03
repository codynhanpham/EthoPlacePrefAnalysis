function [exitCodes, stdouts] = runMany(cmds, kvargs)
    %%RUNMANY Run multiple commands concurrently, each as 'uv run <CMD>' from CLI.
    %   Fan-out counterpart of uv.run(): each command runs in its own OS process,
    %   with at most Workers processes running at once. All commands are attempted
    %   even if some fail (finish-all).
    %
    %   [exitCodes, stdouts] = uv.runMany(cmds, Name=Value, ...)
    %
    %   Inputs:
    %       cmds (cellstr | string array): Command strings to execute with uv run.
    %           Each element should be the part of the command that comes after
    %           'uv run' in the CLI. For example, to run 'uv run myscript.py',
    %           pass 'myscript.py'.
    %
    %   Name-Value Arguments:
    %       Project - Project directory passed as '--project <dir>'. Default [].
    %       Workers (1,1) double - Maximum number of concurrent processes.
    %           Default is 1 (sequential, equivalent to calling uv.run in a loop).
    %           Clamped to the number of commands.
    %       DebugCommand (1,1) logical - Print each full command before launch.
    %           Default false.
    %       LineCallbackFcn (function_handle) - Called as fcn(cmdIndex, line) on the
    %           main thread for every stdout/stderr line of every process.
    %           Default is a no-op.
    %       ProcessDoneFcn (function_handle) - Called as fcn(cmdIndex, exitCode) on
    %           the main thread when a process exits. Default is a no-op.
    %       CancelCheckFcn (function_handle) - Zero-argument function polled in the
    %           pool loop; when it returns true, in-flight process trees are killed,
    %           pending commands are never started, and unfinished commands report
    %           exit code -15 (canceled). Default is @() false.
    %
    %   Outputs:
    %       exitCodes (1,N) double - Exit code per command; -1 if a process failed
    %           to start; -15 if canceled via CancelCheckFcn.
    %       stdouts (1,N) string - Collected stdout/stderr output per command.

    arguments
        cmds (1,:) {mustBeText}
        kvargs.Project = []
        kvargs.Workers (1,1) double {mustBeInteger, mustBePositive} = 1
        kvargs.DebugCommand (1,1) logical = false
        kvargs.LineCallbackFcn (1,1) function_handle = @(varargin) []
        kvargs.ProcessDoneFcn (1,1) function_handle = @(varargin) []
        kvargs.CancelCheckFcn (1,1) function_handle = @() false
    end
    uvbin = uv.install();

    cmds = cellstr(cmds);
    prefix = buildRunPrefix(kvargs.Project);
    fullCmds = cell(size(cmds));
    for i = 1:numel(cmds)
        fullCmds{i} = sprintf('"%s" run %s%s', uvbin, prefix, strtrim(cmds{i}));
        if kvargs.DebugCommand
            fprintf('uv.runMany command [%d]: %s\n', i, fullCmds{i});
        end
    end

    [exitCodes, stdouts] = uv.system.executePool(fullCmds, ...
        Workers=kvargs.Workers, ...
        LineCallbackFcn=kvargs.LineCallbackFcn, ...
        ProcessDoneFcn=kvargs.ProcessDoneFcn, ...
        CancelCheckFcn=kvargs.CancelCheckFcn);
end

function prefix = buildRunPrefix(projectDir)
    if isempty(projectDir)
        prefix = "";
        return;
    end

    prefix = sprintf('--project "%s" ', char(projectDir));
end
