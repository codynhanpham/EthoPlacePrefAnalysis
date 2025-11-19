function [exitCode] = execute(command, stdoutCallback)
%%EXECUTE Executes a system command and prints stdout in real-time.
%   This function uses the Java Runtime class to launch an external process
%   and reads its output stream concurrently.
%
%   INPUTS:
%       command - (string) The system command to execute.
%       stdoutCallback - (function_handle) A callback function to process each line of stdout.
%                  The function should accept a single char array argument (the line of output).
%
%   OUTPUTS:
%       exitCode - (integer) The exit code of the executed command.

arguments
    command {mustBeTextScalar}
    stdoutCallback (1,1) function_handle = @(varargin)[]
end

command = char(command);

try
    % Parse command into executable and arguments
    % Split the command while respecting quoted strings
    cmdParts = parseCommandLine(command);
    
    if isempty(cmdParts)
        error('Empty command provided');
    end

    % Create ProcessBuilder
    pb = java.lang.ProcessBuilder(cmdParts);

    % Redirect error stream to output stream
    pb.redirectErrorStream(true);

    % Start the process
    process = pb.start();

    % Get input stream (stdout of the process)
    inputStream = process.getInputStream();
    reader = java.io.BufferedReader(java.io.InputStreamReader(inputStream));

    % Read output line by line in real-time
    line = reader.readLine();
    while ~isempty(line)
        % Convert Java string to MATLAB string
        matlabLine = char(line);

        stdoutCallback(matlabLine);

        % Try to read next line (non-blocking)
        line = reader.readLine();
    end

    % Wait for process to complete and get exit code
    exitCode = process.waitFor();

    % Clean up
    reader.close();
    inputStream.close();

catch ME
    errorMsg = getReport(ME);
    warning('Error executing command: %s\n', errorMsg);
    exitCode = -1;

    % Clean up if process was created
    if exist('process', 'var') && ~isempty(process)
        try
            process.destroyForcibly();
        catch
            % Ignore cleanup errors
        end
    end
end
end

function cmdParts = parseCommandLine(command)
    %PARSECOMMANDLINE Parse a command line string into executable and arguments
    %   Handles quoted strings properly to avoid issues with spaces and special chars
    
    cmdParts = {};
    i = 1;
    n = length(command);
    
    while i <= n
        % Skip whitespace
        while i <= n && isspace(command(i))
            i = i + 1;
        end
        
        if i > n
            break;
        end
        
        % Start of a new argument
        arg = '';
        inQuotes = false;
        quoteChar = '';
        
        while i <= n
            ch = command(i);
            
            if ~inQuotes && (ch == '"' || ch == '''')
                % Start of quoted section
                inQuotes = true;
                quoteChar = ch;
            elseif inQuotes && ch == quoteChar
                % End of quoted section
                inQuotes = false;
                quoteChar = '';
            elseif ~inQuotes && isspace(ch)
                % End of argument (unquoted space)
                break;
            else
                % Regular character, add to argument
                arg = [arg, ch]; %#ok<AGROW>
            end
            
            i = i + 1;
        end
        
        if ~isempty(arg)
            cmdParts{end+1} = arg; %#ok<AGROW>
        end
    end
end