function callback = createLiveStdoutCallback()
    callback = @printLine;
end

function printLine(line)
    fprintf('%s\n', line);
end