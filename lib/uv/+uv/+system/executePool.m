function [exitCodes, stdouts] = executePool(commands, kvargs)
    %%EXECUTEPOOL Run multiple system commands concurrently with real-time stdout callbacks.
    %   Fans out external processes using java.lang.ProcessBuilder. At most Workers
    %   processes run at once; remaining commands are queued and started as running
    %   processes exit. stdout/stderr lines are reported on the main MATLAB thread
    %   via LineCallbackFcn. All commands are attempted even if some fail
    %   (finish-all): a non-zero exit or a failed start does not stop the pool.
    %
    %   Inputs:
    %       commands - (1,N) cell array of char / string array of full command strings.
    %
    %   Name-Value Arguments:
    %       Workers (1,1) double - Maximum number of concurrent processes. Default is 1.
    %           Clamped to the number of commands.
    %       LineCallbackFcn (function_handle) - Called as fcn(cmdIndex, line) on the main
    %           thread for every stdout/stderr line of every process, where cmdIndex is
    %           the index of the command in commands and line is a char vector.
    %           Default is a no-op.
    %       ProcessDoneFcn (function_handle) - Called as fcn(cmdIndex, exitCode) on the
    %           main thread when a process exits (or fails to start, with exitCode -1).
    %           Default is a no-op.
    %       CancelCheckFcn (function_handle) - Zero-argument function polled in the
    %           main loop; when it returns true, all in-flight process trees are
    %           killed, pending commands are never started, and every unfinished
    %           command is reported with exit code -15 (canceled) via ProcessDoneFcn.
    %           Default is @() false.
    %
    %   Outputs:
    %       exitCodes (1,N) double - Exit code per command; -1 if the process
    %           failed to start; -15 if canceled via CancelCheckFcn.
    %       stdouts (1,N) string - Full captured stdout/stderr per command
    %           (partial for canceled commands).
    %
    %   Interruption: an error in a callback or Ctrl+C in the Command Window kills
    %   all in-flight process trees (including grandchildren) before rethrowing.
    %
    %   Implementation notes:
    %       Output is drained with non-blocking single-character reads guarded by
    %       BufferedReader.ready(), because MATLAB cannot implement Java interfaces
    %       (no Runnable reader threads) and arrays passed to Java are copies (so
    %       block reads into a shared buffer do not work). Polling happens on the
    %       main MATLAB thread, which keeps all callbacks UI-thread-safe.

    arguments
        commands (1,:) {mustBeText}
        kvargs.Workers (1,1) double {mustBeInteger, mustBePositive} = 1
        kvargs.LineCallbackFcn (1,1) function_handle = @(varargin) []
        kvargs.ProcessDoneFcn (1,1) function_handle = @(varargin) []
        kvargs.CancelCheckFcn (1,1) function_handle = @() false
    end

    commands = cellstr(commands);
    nCmds = numel(commands);
    exitCodes = -ones(1, nCmds);
    stdouts = strings(1, nCmds);
    if nCmds == 0
        return;
    end

    nSlots = min(kvargs.Workers, nCmds);
    procMap = containers.Map('KeyType', 'double', 'ValueType', 'any'); % slot -> {process, osPid}
    readers = cell(1, nSlots);         % java.io.BufferedReader per slot
    slotCmd = zeros(1, nSlots);        % command index per slot (0 = slot free)
    lineBuf = repmat({''}, 1, nSlots); % partial-line buffer per slot
    outBuf = repmat({''}, 1, nSlots);  % full stdout accumulation per slot
    nextCmd = 1;

    % Safety net: if the pool is interrupted (callback error or Ctrl+C), kill
    % any still-running external process trees so they are not orphaned.
    % onCleanup fires on ANY function exit including Ctrl+C, which try/catch is
    % not guaranteed to intercept. The cleanup task must only touch
    % value-captured data: at workspace teardown, nested-function workspace
    % variables may already be destroyed, but the map handle and its contents
    % (process + eagerly captured OS PID, for the tree kill) survive.
    cleanupObj = onCleanup(@() destroyAllFromMap(procMap)); %#ok<NASGU>

    try
        for slot = 1:nSlots
            launchNext(slot);
        end
        poolLoop();
    catch ME
        destroyAll();
        rethrow(ME);
    end

    function poolLoop()
        %POOLLOOP Main polling loop: drain output, finalize exited processes, launch queued commands.
        lastSync = tic;
        while any(slotCmd > 0)
            didWork = false;
            for slot = 1:nSlots
                if slotCmd(slot) == 0
                    continue;
                end
                if drainSlot(slot)
                    didWork = true;
                end
                if slotCmd(slot) > 0
                    entry = procMap(slot);
                    if ~entry{1}.isAlive()
                        finalizeSlot(slot);
                        launchNext(slot);
                    end
                end
            end
            if ~didWork
                pause(0.05);
            end
            % Full drawnow (not 'limitrate', which can skip event processing)
            % so uiprogressdlg Cancel button presses actually sync. Throttled
            % to 10 Hz to bound event-queue churn during heavy output.
            if toc(lastSync) >= 0.1
                drawnow;
                lastSync = tic;
                if kvargs.CancelCheckFcn()
                    % User abort: kill in-flight trees and mark everything
                    % unfinished as canceled (-15), then unwind normally.
                    cancelPool();
                    return;
                end
            end
        end
    end

    function launchNext(slot)
        %LAUNCHNEXT Start the next pending command in the given slot, if any.
        %   Keeps consuming pending commands until one starts successfully or
        %   the queue is exhausted, so a failed start never leaves a slot idle
        %   with pending commands behind it.
        while slotCmd(slot) == 0 && nextCmd <= nCmds
            idx = nextCmd;
            nextCmd = nextCmd + 1;
            cmdParts = parseCommandLine(commands{idx});
            if isempty(cmdParts)
                exitCodes(idx) = -1;
                kvargs.ProcessDoneFcn(idx, -1);
                continue;
            end
            try
                pb = java.lang.ProcessBuilder(cmdParts);
                % Redirect error stream to output stream
                pb.redirectErrorStream(true);
                proc = pb.start();
            catch ME
                exitCodes(idx) = -1;
                stdouts(idx) = "";
                warning('system:executePool:StartFailed', ...
                    'Failed to start command [%d]: %s\n%s', idx, commands{idx}, ME.message);
                kvargs.ProcessDoneFcn(idx, -1);
                continue;
            end
            % Capture the OS PID eagerly: the reflection/library calls inside
            % processPid are unsafe during workspace teardown (onCleanup tasks).
            procMap(slot) = {proc, processPid(proc)};
            readers{slot} = java.io.BufferedReader(java.io.InputStreamReader(proc.getInputStream()));
            slotCmd(slot) = idx;
            lineBuf{slot} = '';
            outBuf{slot} = '';
        end
    end

    function drained = drainSlot(slot)
        %DRAINSLOT Non-blocking read of all currently available output of a slot.
        %   ready() guarantees the next read() will not block, so this never
        %   stalls the pool loop on a partial line.
        drained = false;
        rdr = readers{slot};
        while rdr.ready()
            c = rdr.read();
            if c < 0
                break; % EOF
            end
            drained = true;
            if c == 10 % '\n'
                emitLine(slot);
            elseif c ~= 13 % skip '\r'
                lineBuf{slot}(end+1) = char(c);
            end
        end
    end

    function emitLine(slot)
        %EMITLINE Dispatch one completed line from a slot's partial-line buffer.
        line = lineBuf{slot};
        lineBuf{slot} = '';
        outBuf{slot} = [outBuf{slot}, line, newline];
        kvargs.LineCallbackFcn(slotCmd(slot), line);
    end

    function finalizeSlot(slot)
        %FINALIZESLOT Drain remaining output of an exited process and record results.
        idx = slotCmd(slot);
        rdr = readers{slot};
        % The process has exited, so the stream is at EOF and blocking reads are safe.
        line = rdr.readLine();
        while ~isempty(line)
            lineBuf{slot} = [lineBuf{slot}, char(line)];
            emitLine(slot);
            line = rdr.readLine();
        end
        if ~isempty(lineBuf{slot})
            % Final partial line without a trailing newline.
            outBuf{slot} = [outBuf{slot}, lineBuf{slot}];
            kvargs.LineCallbackFcn(idx, lineBuf{slot});
            lineBuf{slot} = '';
        end
        entry = procMap(slot);
        exitCode = entry{1}.exitValue();
        exitCodes(idx) = exitCode;
        stdouts(idx) = string(outBuf{slot});
        try
            rdr.close();
        catch
            % Ignore cleanup errors
        end
        remove(procMap, slot);
        readers{slot} = [];
        outBuf{slot} = '';
        slotCmd(slot) = 0;
        kvargs.ProcessDoneFcn(idx, exitCode);
    end

    function cancelPool()
        %CANCELPOOL Kill all in-flight process trees and mark every unfinished
        %   command as canceled (exit code -15), then let the pool unwind.
        for slot = 1:nSlots
            if slotCmd(slot) > 0
                idx = slotCmd(slot);
                killProcessTree(procMap(slot));
                remove(procMap, slot);
                try
                    readers{slot}.close();
                catch
                    % Ignore cleanup errors
                end
                exitCodes(idx) = -15;
                stdouts(idx) = string(outBuf{slot});
                readers{slot} = [];
                slotCmd(slot) = 0;
                kvargs.ProcessDoneFcn(idx, -15);
            end
        end
        % Pending commands are never started; report them as canceled too.
        while nextCmd <= nCmds
            idx = nextCmd;
            nextCmd = nextCmd + 1;
            exitCodes(idx) = -15;
            stdouts(idx) = "";
            kvargs.ProcessDoneFcn(idx, -15);
        end
    end

    function destroyAll()
        %DESTROYALL Forcibly destroy any still-running process trees (error path).
        ks = procMap.keys();
        for i = 1:numel(ks)
            killProcessTree(procMap(ks{i}));
        end
        if ~isempty(ks)
            remove(procMap, ks);
        end
    end
end

function destroyAllFromMap(procMap)
    %DESTROYALLFROMMAP onCleanup task: kill everything still in the process map.
    %   Must only touch value-captured data (the map handle and its contents):
    %   at workspace teardown (e.g. Ctrl+C), workspace variables of the exiting
    %   function may already be destroyed. The OS PID was captured eagerly at
    %   launch, so no JVM reflection or library loading happens here.
    ks = procMap.keys();
    for i = 1:numel(ks)
        killProcessTree(procMap(ks{i}));
    end
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
    %   (vendored copy, kept identical to the one in execute.m).

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
