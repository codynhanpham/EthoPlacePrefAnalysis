function [unixtime, unixtime_str] = unixtimeUTC()
    %UNIXTIME Get current Epoch & Unix Timestamp in milliseconds
    %   Note that the epoch is relative to the UTC time zone.
    %   If you want to get the epoch in your local time zone, use unixtime() instead.
    %
    %   unixtime = unixtimeUTC()
    %   [unixtime, funixtime] = unixtimeUTC()
    %       unixtime (double) is the current time (UTC) in Unix time
    %       unixtime_str (char) is a formatted string of the current time in Unix time

    unixtime = posixtime(datetime('now', 'TimeZone', 'UTC')) * 1000;
    unixtime_str = num2str(unixtime);
end