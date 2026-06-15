function out = textToChar(value)
    if ischar(value)
        out = value;
        return;
    end

    if isstring(value)
        if isempty(value)
            out = '';
        else
            out = char(value(1));
        end
        return;
    end

    if iscell(value)
        if isempty(value)
            out = '';
            return;
        end
        firstVal = value{1};
        if ischar(firstVal)
            out = firstVal;
        elseif isstring(firstVal)
            out = char(firstVal);
        else
            out = char(string(firstVal));
        end
        return;
    end

    out = char(string(value));
end
