function bool = istext(x)
    bool = isstring(x) || ischar(x) || iscellstr(x);
    
    allstr = all(cellfun(@(y)isstring(y)|ischar(y), x, 'UniformOutput', true));
    bool = bool || allstr;
end