function [geneId, litterId, mouseNumber] = parseMouseId(mouseId, strainName)
    arguments
        mouseId {mustBeTextScalar}
        strainName {mustBeTextScalar}
    end
    mouseId = string(mouseId);
    strainName = string(strainName);

    parts = split(mouseId, '_');
    if length(parts) >= 4 && parts(1) == strainName
        geneId = char(parts(2));
        litterId = char(parts(3));
        mouseNumber = char(parts(4));
    else
        geneId = '';
        litterId = '';
        mouseNumber = '';
    end
end
