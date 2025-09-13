function yyyyMMddhhmmSS = timenowYMDhms()
    import java.util.TimeZone;
    dt = datetime('now','TimeZone',char(TimeZone.getDefault().getID()));
    yyyyMMddhhmmSS = datetime(dt,'Format','yyyyMMddhhmmSS');
    yyyyMMddhhmmSS = char(yyyyMMddhhmmSS);
end