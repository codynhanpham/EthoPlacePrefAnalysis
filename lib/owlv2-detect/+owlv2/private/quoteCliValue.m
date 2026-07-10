function value = quoteCliValue(value)
    value = string(value);
    value = strrep(value, '"', '\"');
    value = '"' + value + '"';
end