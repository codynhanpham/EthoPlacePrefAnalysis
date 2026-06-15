function out = padToTwo(x)
    out = x;
    if numel(out) == 0
        out = ["Stimulus 1"; "Stimulus 2"];
    elseif numel(out) == 1
        out = [out; "Stimulus 2"];
    else
        out = out(1:2);
    end
end
