function [headX, headY, earLX, earLY, earRX, earRY, noseX, noseY, available] = getHeadPositionMatrices(bodyparts, nRows, nAnimals)
%GETHEADPOSITIONMATRICES Return ear-midpoint, ear-pair, and nose coordinate matrices.
% Bodypart coordinates in a standardized table are already in centimeters.
% Availability requires both ear columns AND nose columns; when unavailable,
% all outputs are NaN matrices and available is false.

headX = nan(nRows, nAnimals);
headY = nan(nRows, nAnimals);
earLX = nan(nRows, nAnimals);
earLY = nan(nRows, nAnimals);
earRX = nan(nRows, nAnimals);
earRY = nan(nRows, nAnimals);
noseX = nan(nRows, nAnimals);
noseY = nan(nRows, nAnimals);
available = false;

if isempty(bodyparts) || height(bodyparts) ~= nRows
    return;
end

variableNames = string(bodyparts.Properties.VariableNames);
xVariables = variableNames(startsWith(variableNames, 'X '));
leftX = findBodypartVariable(xVariables, {'earleft', 'earl'});
rightX = findBodypartVariable(xVariables, {'earright', 'earr'});
noseXVar = findBodypartVariable(xVariables, {'nose'});
if strlength(leftX) == 0 || strlength(rightX) == 0 || strlength(noseXVar) == 0
    return;
end

leftY = "Y " + extractAfter(leftX, "X ");
rightY = "Y " + extractAfter(rightX, "X ");
noseYVar = "Y " + extractAfter(noseXVar, "X ");
if ~ismember(leftY, variableNames) || ~ismember(rightY, variableNames) || ...
        ~ismember(noseYVar, variableNames)
    return;
end

leftXData = bodyparts{:, char(leftX)};
leftYData = bodyparts{:, char(leftY)};
rightXData = bodyparts{:, char(rightX)};
rightYData = bodyparts{:, char(rightY)};
noseXData = bodyparts{:, char(noseXVar)};
noseYData = bodyparts{:, char(noseYVar)};
if ~isequal(size(leftXData), [nRows, nAnimals]) || ...
        ~isequal(size(leftYData), [nRows, nAnimals]) || ...
        ~isequal(size(rightXData), [nRows, nAnimals]) || ...
        ~isequal(size(rightYData), [nRows, nAnimals]) || ...
        ~isequal(size(noseXData), [nRows, nAnimals]) || ...
        ~isequal(size(noseYData), [nRows, nAnimals])
    return;
end

earLX = leftXData;
earLY = leftYData;
earRX = rightXData;
earRY = rightYData;
noseX = noseXData;
noseY = noseYData;
headX = (earLX + earRX) / 2;
headY = (earLY + earRY) / 2;
available = true;
end

function foundVariable = findBodypartVariable(xVariables, candidates)
    foundVariable = "";
    for variableIndex = 1:numel(xVariables)
        bodypartName = extractAfter(xVariables(variableIndex), "X ");
        normalizedName = lower(regexprep(char(bodypartName), '[-_ ]', ''));
        if any(strcmpi(normalizedName, candidates))
            foundVariable = xVariables(variableIndex);
            return;
        end
    end
end
