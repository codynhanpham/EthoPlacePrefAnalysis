function exitCode = run(cmd, kvargs)
    %%RUN Alias to uv.cmd('run CMD'), in other words, same as 'uv run <CMD>' from CLI
    %
    %   exitCode = uv.run(cmd, kvargs);
    %
    %   Inputs:
    %       cmd (char): Command string to execute with uv run. This should be the part of the command that comes after 'uv run' in the CLI. For example, if you want to run 'uv run myscript.py', then cmd should be 'myscript.py'.
    %
    %       UpdateCallbackFcn (function_handle, optional): A callback function that will be called with each line of output from the command. The function should accept a single char array argument (the line of output).
    %
    %   Outputs:
    %       exitCode (integer): The exit code of the executed command. A value of 0 typically indicates success, while a non-zero value indicates an error.

    arguments
        cmd {mustBeTextScalar}
        
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin) []
    end
    uvbin = uv.install();

    cmd = strtrim(cmd);
    fullCmd = sprintf('"%s" run %s', uvbin, cmd);
    exitCode = uv.system.execute(fullCmd, kvargs.UpdateCallbackFcn);
end