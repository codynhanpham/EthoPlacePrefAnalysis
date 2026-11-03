function [exitCode, stdout] = execute(command, stdoutCallback, cancelCheck)
%%EXECUTE Executes a system command and prints stdout in real-time.
%   This function uses the Java Runtime class to launch an external process
%   and reads its output stream concurrently.
%
%   INPUTS:
%       command - (string) The system command to execute.
%       stdoutCallback - (function_handle) A callback function to process each line of stdout.
%                  The function should accept a single char array argument (the line of output).
%       cancelCheck - (function_handle, optional) A zero-argument function polled after
%                  each stdout line; when it returns true, the process tree is killed
%                  and execute returns exitCode -15 (canceled). Default is @() false.
%
%   OUTPUTS:
%       exitCode - (integer) The exit code of the executed command; -1 on execution
%                  error; -15 when canceled via cancelCheck.
%       stdout - (string) Collected stdout/stderr output from the executed command.

arguments
    command {mustBeTextScalar}
    stdoutCallback (1,1) function_handle = @(outputline)[]
    cancelCheck (1,1) function_handle = @() false
end

command = char(command);
stdoutLines = {};

% Hold the process in a handle map so the onCleanup safeguard can reach it
% even during workspace teardown (Ctrl+C): onCleanup fires on ANY function
% exit, while try/catch is not guaranteed to intercept Ctrl+C. The cleanup
% task must only touch value-captured data (the map handle + its contents).
procHolder = containers.Map('KeyType', 'double', 'ValueType', 'any');
cleanupObj = onCleanup(@() destroyHeldProcess(procHolder)); %#ok<NASGU>

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
    % Capture the OS PID eagerly: the reflection/library calls inside
    % processPid are unsafe during workspace teardown (onCleanup tasks).
    procHolder(1) = {process, processPid(process)};

    % Get input stream (stdout of the process)
    inputStream = process.getInputStream();
    reader = java.io.BufferedReader(java.io.InputStreamReader(inputStream));

    % Poll-based read loop: non-blocking character drain plus periodic cancel
    % checks, so cancellation also works while the process produces no output
    % (e.g. during silent model-loading phases).
    canceled = false;
    lineBuf = '';
    lastSync = tic;
    while true
        % Drain all currently available characters (non-blocking).
        while reader.ready()
            c = reader.read();
            if c < 0
                break; % EOF
            end
            if c == 10 % '\n'
                stdoutLines{end+1} = lineBuf; %#ok<AGROW>
                stdoutCallback(lineBuf);
                lineBuf = '';
            elseif c ~= 13 % skip '\r'
                lineBuf(end+1) = char(c); %#ok<AGROW>
            end
        end
        if ~process.isAlive()
            break;
        end
        % Full drawnow (not 'limitrate', which can skip event processing) so
        % uiprogressdlg Cancel button presses actually sync. Throttled to 10 Hz.
        if toc(lastSync) >= 0.1
            drawnow;
            lastSync = tic;
            if cancelCheck()
                canceled = true;
                break;
            end
        end
        pause(0.05);
    end

    if canceled
        % User abort: kill the whole process tree (e.g. uv -> python
        % grandchildren holding the GPU) and report the conventional cancel code.
        killProcessTree(procHolder(1));
        exitCode = -15;
    else
        % Final drain: the process has exited, so the stream is at EOF and
        % blocking reads are safe.
        line = reader.readLine();
        while ~isempty(line)
            matlabLine = [lineBuf, char(line)];
            lineBuf = '';
            stdoutLines{end+1} = matlabLine; %#ok<AGROW>
            stdoutCallback(matlabLine);
            line = reader.readLine();
        end
        if ~isempty(lineBuf)
            % Final partial line without a trailing newline.
            stdoutLines{end+1} = lineBuf; %#ok<AGROW>
            stdoutCallback(lineBuf);
        end
        % Wait for process to complete and get exit code
        exitCode = process.waitFor();
    end
    stdout = strjoin(string(stdoutLines), newline);

    % Clean up
    reader.close();
    inputStream.close();
    remove(procHolder, 1);

catch ME
    if isKey(procHolder, 1)
        killProcessTree(procHolder(1));
        remove(procHolder, 1);
    end
    if contains(ME.message, 'Operation terminated by user')
        % Ctrl+C: propagate the interrupt after cleanup instead of
        % swallowing it as a generic command failure.
        rethrow(ME);
    end
    errorMsg = getReport(ME);
    warning('Error executing command: %s\n', errorMsg);
    exitCode = -1;
    stdout = strjoin(string(stdoutLines), newline);
end
end

function destroyHeldProcess(procHolder)
    %DESTROYHELDPROCESS onCleanup task: kill the held process, if any.
    %   Must only touch value-captured data (the map handle and its contents):
    %   at workspace teardown (e.g. Ctrl+C), workspace variables of the exiting
    %   function may already be destroyed. The OS PID was captured eagerly at
    %   launch, so no JVM reflection or library loading happens here.
    if procHolder.Count == 0
        return;
    end
    killProcessTree(procHolder(1));
end

function killProcessTree(entry)
    %KILLPROCESSTREE Forcibly destroy a spawned process and its whole tree.
    %   entry = {java.lang.Process, osPid (double, NaN if unknown)}.
    %   Killing only the direct child (e.g. the uv launcher) orphans
    %   grandchildren (e.g. the python holding the GPU). Strategy, in order:
    %     1. Java 9+ ProcessHandle descendants (absent on the Java 8 JRE
    %        bundled with MATLAB).
    %     2. Native tree kill by PID: taskkill /T (Windows) or kill + pkill -P
    %        (unix). Fast and reliable; no WMI/CIM (which can hang).
    %     3. destroyForcibly() on the direct child (always).
    process = entry{1};
    pid = entry{2};
    try
        descendants = process.toHandle().descendants().toArray();
        for i = 1:numel(descendants)
            try
                if descendants(i).isAlive()
                    descendants(i).destroyForcibly();
                end
            catch
                % Ignore cleanup errors
            end
        end
    catch
        % Java 8: no ProcessHandle API; fall through to the PID-based kill.
    end
    if ~isnan(pid)
        if ispc
            system(sprintf('taskkill /F /T /PID %d >nul 2>&1', pid));
        elseif isunix
            system(sprintf('kill -9 %d 2>/dev/null; pkill -KILL -P %d 2>/dev/null', pid, pid));
        end
    end
    try
        process.destroyForcibly();
    catch
        % Ignore cleanup errors
    end
end

function pid = processPid(process)
    %PROCESSPID OS PID of a freshly spawned Java Process; NaN if unavailable.
    %   Called eagerly at launch: the Java 8 reflection + loadlibrary path is
    %   unsafe to run during workspace teardown (e.g. inside onCleanup tasks).
    pid = NaN;
    try
        pid = double(process.pid()); % Java 9+
        if pid > 0
            return;
        end
    catch
    end
    try
        pid = double(process.toHandle().pid()); % Java 9+ alternate
        if pid > 0
            return;
        end
    catch
    end
    if ispc
        % Java 8 (bundled with MATLAB): ProcessImpl keeps the OS handle in a
        % private 'handle' field; kernel32!GetProcessId maps handle -> PID.
        try
            f = process.getClass().getDeclaredField('handle');
            f.setAccessible(true);
            h = f.get(process);
            loadPidLib();
            pid = double(calllib('kernel32_pidhelper', 'GetProcessId', uint64(h)));
            if pid <= 0
                pid = NaN;
            end
        catch
            pid = NaN;
        end
    end
end

function loadPidLib()
    %LOADPIDLIB Load kernel32!GetProcessId once per session (Windows, Java 8 only).
    persistent loaded
    if ~isempty(loaded) && loaded && libisloaded('kernel32_pidhelper')
        return;
    end
    protoFile = fullfile(tempdir, 'uv_kernel32_pid_proto.h');
    if ~isfile(protoFile)
        fid = fopen(protoFile, 'w');
        if fid < 0
            error('uv:system:PidLibFailed', 'Could not write kernel32 prototype header.');
        end
        fprintf(fid, 'unsigned int GetProcessId(unsigned long long h);\n');
        fclose(fid);
    end
    if ~libisloaded('kernel32_pidhelper')
        loadlibrary('kernel32.dll', protoFile, 'alias', 'kernel32_pidhelper');
    end
    loaded = true;
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