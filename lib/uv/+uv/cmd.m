function [exitCode, stdout] = cmd(cmd, kvargs)
    %%X Alias to uv.cmd('tool run CMD'), in other words, same as 'uvx <CMD>' from CLI
    %
    %   exitCode = uv.cmd(cmd)
    %
    %   Inputs:
    %       cmd (char): Command string to execute with uv. This should be the part of the command that comes after 'uv' in the CLI. For example, if you want to run 'uv run myscript.py', then cmd should be 'run myscript.py'.
    %
    %       UpdateCallbackFcn (function_handle, optional): A callback function that will be called with each line of output from the command. The function should accept a single char array argument (the line of output).
    %
    %   Outputs:
    %       exitCode (integer): The exit code of the executed command. A value of 0 typically indicates success, while a non-zero value indicates an error.
    %       stdout (string): Collected stdout/stderr output from the executed command.

    arguments
        cmd {mustBeTextScalar}
        kvargs.Project = []
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin) []
    end
    uvbin = uv.install();

    cmd = strtrim(cmd);
    fullCmd = sprintf('"%s" %s%s', uvbin, buildProjectPrefix(kvargs.Project), cmd);
    [exitCode, stdout] = uv.system.execute(fullCmd, kvargs.UpdateCallbackFcn);
end

function prefix = buildProjectPrefix(projectDir)
    if isempty(projectDir)
        prefix = "";
        return;
    end

    prefix = sprintf('--project "%s" ', char(projectDir));
end