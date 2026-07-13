function [pairsCell, isCanonical, isUsable] = canonicalizeTriggerEvents(triggerEvents)
    % Returns trigger events as a 1xN cell array of [on off] numeric vectors.
    pairsCell = cell(1, 0);
    isCanonical = true;
    isUsable = false;

    if isempty(triggerEvents)
        return;
    end

    if isnumeric(triggerEvents)
        vals = double(triggerEvents);
        if isvector(vals) && numel(vals) == 2 && all(isfinite(vals))
            pairsCell = {reshape(vals, 1, 2)};
            isCanonical = false; % legacy flat [on, off]
            isUsable = true;
            return;
        end
        if ismatrix(vals) && size(vals, 2) == 2 && all(isfinite(vals), 'all')
            nEvents = size(vals, 1);
            pairsCell = cell(1, nEvents);
            for ii = 1:nEvents
                pairsCell{ii} = vals(ii, :);
            end
            isCanonical = nEvents ~= 1;
            isUsable = true;
            return;
        end
        return;
    end

    if iscell(triggerEvents)
        if isempty(triggerEvents)
            return;
        end
        nEvents = numel(triggerEvents);
        tempPairs = cell(1, nEvents);
        for ii = 1:nEvents
            row = triggerEvents{ii};
            if ~(isnumeric(row) && numel(row) == 2 && all(isfinite(row)))
                return;
            end
            tempPairs{ii} = double(reshape(row, 1, 2));
        end
        pairsCell = tempPairs;
        isCanonical = true;
        isUsable = true;
    end
end