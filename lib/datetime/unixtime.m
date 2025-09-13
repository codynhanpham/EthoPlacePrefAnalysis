function [unixtime, unixtime_str] = unixtime()
    %UNIXTIME Get current Epoch & Unix Timestamp in milliseconds
    %   Note that the epoch is relative to your local time zone.
    %   If you want to get the epoch in UTC, use unixtimeUTC() instead.
    %
    %   unixtime = unixtime()
    %   [unixtime, funixtime] = unixtime()
    %       unixtime (double) is the current time in Unix time
    %       unixtime_str (char) is a formatted string of the current time in Unix time
    
    import java.util.TimeZone;
    dt = datetime('now','TimeZone',char(TimeZone.getDefault().getID()));
    unixtime = posixtime(dt) * 1000;
    unixtime_str = num2str(unixtime);
end