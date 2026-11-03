function tests = testUvRunManyPool
    tests = functiontests(localfunctions);
end

function testFinishAllAndExitCodes(testCase)
    cmds = {echoCmd('alpha'), exitCmd(3), echoCmd('beta')};
    [exitCodes, stdouts] = uv.system.executePool(cmds, Workers=2);

    % Finish-all: every command attempted and reported, indexed by command order.
    testCase.verifyEqual(double(exitCodes), [0, 3, 0]);
    testCase.verifyTrue(contains(stdouts(1), "alpha"));
    testCase.verifyTrue(contains(stdouts(3), "beta"));
end

function testStdoutCapturedPerCommand(testCase)
    cmds = {echoCmd('first-token'), echoCmd('second-token')};
    [exitCodes, stdouts] = uv.system.executePool(cmds, Workers=2);

    testCase.verifyEqual(double(exitCodes), [0, 0]);
    testCase.verifyTrue(contains(stdouts(1), "first-token"));
    testCase.verifyTrue(contains(stdouts(2), "second-token"));
    testCase.verifyFalse(contains(stdouts(1), "second-token"));
    testCase.verifyFalse(contains(stdouts(2), "first-token"));
end

function testLineCallbackCarriesIndexAndPreservesOrder(testCase)
    seenIdx = [];
    seenLines = {};
    function cb(i, line)
        seenIdx(end+1) = i; %#ok<NASGU>
        seenLines{end+1} = line; %#ok<NASGU>
    end

    cmds = {twoLineCmd('one-a', 'one-b'), twoLineCmd('two-a', 'two-b'), twoLineCmd('three-a', 'three-b')};
    [exitCodes, ~] = uv.system.executePool(cmds, Workers=2, LineCallbackFcn=@cb);
    testCase.verifyEqual(double(exitCodes), [0, 0, 0]);

    % Every reported index is valid.
    testCase.verifyTrue(all(ismember(seenIdx, [1 2 3])));
    % Per-command lines preserve their emission order (interleaving across
    % commands is allowed and expected).
    for k = 1:3
        kLines = seenLines(seenIdx == k);
        testCase.verifyGreaterThanOrEqual(numel(kLines), 2);
        testCase.verifyEqual(kLines{1}, sprintf('%s-a', cmdTag(k)));
        testCase.verifyEqual(kLines{2}, sprintf('%s-b', cmdTag(k)));
    end
end

function testProcessDoneFcnFiresForAllInOrder(testCase)
    doneIdx = [];
    doneCodes = [];
    function cb(i, code)
        doneIdx(end+1) = i; %#ok<NASGU>
        doneCodes(end+1) = code; %#ok<NASGU>
    end

    cmds = {echoCmd('x'), exitCmd(5), echoCmd('y'), echoCmd('z')};
    exitCodes = uv.system.executePool(cmds, Workers=2, ProcessDoneFcn=@cb);

    testCase.verifyEqual(sort(doneIdx), [1 2 3 4]);
    testCase.verifyEqual(double(exitCodes), [0, 5, 0, 0]);
    codeByIdx = zeros(1, 4);
    codeByIdx(doneIdx) = doneCodes;
    testCase.verifyEqual(codeByIdx, [0 5 0 0]);
end

function testWorkersClampedToCommandCount(testCase)
    cmds = {echoCmd('only1'), echoCmd('only2')};
    exitCodes = uv.system.executePool(cmds, Workers=10);
    testCase.verifyEqual(double(exitCodes), [0, 0]);
end

function testEmptyCommandList(testCase)
    [exitCodes, stdouts] = uv.system.executePool(strings(1, 0), Workers=3);
    testCase.verifyEqual(numel(exitCodes), 0);
    testCase.verifyEqual(numel(stdouts), 0);
end

function testCancelStopsInFlightAndSkipsPending(testCase)
    t0 = tic;
    exitCodes = uv.system.executePool({longCmd(), echoCmd('never-started')}, ...
        Workers=1, CancelCheckFcn=@() toc(t0) > 1.5);
    elapsed = toc(t0);
    % Killed in-flight command and never-started pending command both report -15.
    testCase.verifyEqual(double(exitCodes), [-15, -15]);
    testCase.verifyLessThan(elapsed, 15); % the long command would run ~29 s if not killed
end

function testCancelDestroysInFlightProcess(testCase)
    % A process killed mid-run must not finish its work.
    sentinel = [tempname '.txt'];
    cleanup = onCleanup(@() deleteIfExists(sentinel)); %#ok<NASGU>
    t0 = tic;
    exitCodes = uv.system.executePool({sleeperCmd(sentinel)}, ...
        Workers=1, CancelCheckFcn=@() toc(t0) > 1);
    testCase.verifyEqual(double(exitCodes), -15);
    pause(5); % outlive the sleeper's 3 s delay
    testCase.verifyFalse(isfile(sentinel), 'Canceled process still completed its work');
end

function testExecuteSequentialCancel(testCase)
    t0 = tic;
    exitCode = uv.system.execute(longCmd(), @(line) [], @() toc(t0) > 1.5);
    testCase.verifyEqual(double(exitCode), -15);
    testCase.verifyLessThan(toc(t0), 15);
end

function testCancelKillsGrandchildProcessTree(testCase)
    testCase.assumeTrue(ispc, 'Windows-only: detects leaked ping.exe via tasklist');
    pre = pingCount();
    t0 = tic;
    exitCodes = uv.system.executePool({'cmd /c "ping -t 127.0.0.1"'}, ...
        Workers=1, CancelCheckFcn=@() toc(t0) > 1.5);
    testCase.verifyEqual(double(exitCodes), -15);
    % The token sweep runs fire-and-forget in the background; poll for it.
    pollUntil = tic;
    while toc(pollUntil) < 10 && pingCount() ~= pre
        pause(0.5);
    end
    testCase.verifyEqual(pingCount(), pre, 'Grandchild ping.exe survived the cancel');
end

function cmd = echoCmd(token)
    if ispc
        cmd = sprintf('cmd /c echo %s', token);
    else
        cmd = sprintf('sh -c "echo %s"', token);
    end
end

function cmd = exitCmd(code)
    if ispc
        cmd = sprintf('cmd /c exit %d', code);
    else
        cmd = sprintf('sh -c "exit %d"', code);
    end
end

function cmd = twoLineCmd(first, second)
    if ispc
        % No space before &&: cmd's echo prints everything after 'echo ',
        % including a trailing space if one precedes &&.
        cmd = sprintf('cmd /c "echo %s&&echo %s"', first, second);
    else
        cmd = sprintf('sh -c "echo %s; echo %s"', first, second);
    end
end

function tag = cmdTag(k)
    tags = {'one', 'two', 'three'};
    tag = tags{k};
end

function cmd = longCmd()
    if ispc
        cmd = 'ping -n 30 127.0.0.1'; % ~29 s, first output line immediate
    else
        cmd = 'ping -c 30 127.0.0.1';
    end
end

function cmd = sleeperCmd(sentinelFile)
    %SLEEPERCMD Command that writes a file only if allowed to run to completion.
    if ispc
        cmd = sprintf('powershell -NoProfile -Command "Start-Sleep -Seconds 3; Set-Content -Path ''%s'' -Value done"', sentinelFile);
    else
        cmd = sprintf('sh -c "sleep 3; touch ''%s''"', sentinelFile);
    end
end

function deleteIfExists(f)
    if isfile(f)
        delete(f);
    end
end

function n = pingCount()
    [~, out] = system('tasklist /FI "IMAGENAME eq ping.exe"');
    n = numel(strfind(out, 'ping.exe'));
end
