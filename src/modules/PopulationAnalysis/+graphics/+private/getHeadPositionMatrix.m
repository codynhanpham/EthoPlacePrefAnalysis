function tbl = getHeadPositionMatrix(tbl)
%GETHEADPOSITIONMATRIX Add 'Head X' and 'Head Y' columns as the midpoint of the ears.
%   tbl = graphics.private.getHeadPositionMatrix(tbl)
%
%   Input tbl must be a standardized bodyparts table with at least:
%       'Trial time', 'Stimulus name', and 'X/Y <EarL>' and 'X/Y <EarR>' columns
%   where the ear bodypart names are matched case-insensitively (e.g., 'Ear_left',
%   'ear_left', 'EarLeft' with fuzzy separators '-','_',' ').
%
%   The output table keeps all original columns and appends:
%       'Head X' : multi-column (time x replicates) midpoint of the ear X columns
%       'Head Y' : multi-column (time x replicates) midpoint of the ear Y columns
%
%   NaN ear positions propagate: if either ear is NaN at a frame, the head
%   midpoint at that frame is NaN (i.e., plain mean without 'omitnan').

    arguments
        tbl table
    end

    varNames = tbl.Properties.VariableNames;

    xVars = string(varNames(startsWith(varNames, 'X ')));
    yVars = string(varNames(startsWith(varNames, 'Y ')));

    earLXVar = findBodypartVar(xVars, {'ear left', 'earleft', 'ear l'});
    earRXVar = findBodypartVar(xVars, {'ear right', 'earright', 'ear r'});
    if isempty(earLXVar) || isempty(earRXVar)
        error('graphics:private:getHeadPositionMatrix:MissingEars', ...
            'Could not find both left and right ear bodypart columns (X/Y Ear_left and X/Y Ear_right) in the bodyparts table.');
    end

    earLYVar = "Y " + extractAfter(earLXVar, "X ");
    earRYVar = "Y " + extractAfter(earRXVar, "X ");
    if ~ismember(earLYVar, string(varNames)) || ~ismember(earRYVar, string(varNames))
        error('graphics:private:getHeadPositionMatrix:MissingEarY', ...
            'Could not find matching Y columns for ear bodyparts %s / %s.', earLXVar, earRXVar);
    end

    headX = (tbl{:, char(earLXVar)} + tbl{:, char(earRXVar)}) / 2;
    headY = (tbl{:, char(earLYVar)} + tbl{:, char(earRYVar)}) / 2;

    tbl = addvars(tbl, headX, headY, 'After', tbl.Properties.VariableNames{end});
    tbl.Properties.VariableNames{end-1} = 'Head X';
    tbl.Properties.VariableNames{end} = 'Head Y';
end

function foundVar = findBodypartVar(xVars, nameCandidates)
% Find the first X variable whose bodypart name fuzzy-matches any candidate.
% Matching normalizes separators ('-', '_', ' ') and case, and also handles
% camelCase names like 'EarLeft' by trying a no-space variant too.

    foundVar = "";
    for v = 1:numel(xVars)
        bodypartName = extractAfter(xVars(v), "X ");
        normalized = lower(regexreplace(bodypartName));
        for c = 1:numel(nameCandidates)
            candidate = nameCandidates{c};
            if strcmp(normalized, candidate) || strcmp(normalized, replace(candidate, ' ', ''))
                foundVar = xVars(v);
                return;
            end
        end
    end
end

function out = regexreplace(s)
    out = regexprep(char(s), '[-_ ]', '');
end
