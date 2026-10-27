function groups = adaptPipelineInput(inputTables)
    %ADAPTPIPELINEINPUT Normalize fingerprint pipeline input to strain groups.
    %
    %   groups = cohort.internal.adaptPipelineInput(inputTables)
    %
    %   Accepts either:
    %       1) An aggregate cross-strain standardizedTables struct array with
    %          exactly 2 elements (2 stim protocols). Treated as a single
    %          group; strain identity per subject comes from the 'Gene' column
    %          of the metric tables downstream. Group label: 'aggregate'.
    %       2) A cell array where each element is one strain's 2-element
    %          standardizedTables pair. All subjects within an element must
    %          share a single strain value; the group label is that strain.
    %
    %   Returns a cell array of groups, each a struct with fields:
    %       .tables      - the 2-element standardizedTables struct array
    %       .strainLabel - string group label
    %
    %   Any other input shape is a hard error.

    arguments
        inputTables
    end

    groups = {};

    if isstruct(inputTables)
        sdTable.mustBeStandardizedTable(inputTables);
        if numel(inputTables) ~= 2
            error('cohort:internal:adaptPipelineInput:WrongTableCount', ...
                'Aggregate (struct array) input must contain exactly 2 standardizedTables (2 stim protocols), got %d.', ...
                numel(inputTables));
        end
        groups{1} = struct('tables', inputTables, 'strainLabel', "aggregate");
        return;
    end

    if iscell(inputTables)
        for i = 1:numel(inputTables)
            thisPair = inputTables{i};
            if ~isstruct(thisPair)
                error('cohort:internal:adaptPipelineInput:InvalidElement', ...
                    'Input cell element %d must be a struct array of standardizedTables.', i);
            end
            sdTable.mustBeStandardizedTable(thisPair);
            if numel(thisPair) ~= 2
                error('cohort:internal:adaptPipelineInput:WrongTableCount', ...
                    'Input cell element %d must contain exactly 2 standardizedTables (2 stim protocols), got %d.', ...
                    i, numel(thisPair));
            end

            strainLabel = singleStrainLabel(thisPair, i);
            groups{end+1} = struct('tables', thisPair, 'strainLabel', strainLabel); %#ok<AGROW>
        end
        return;
    end

    error('cohort:internal:adaptPipelineInput:InvalidInput', ...
        'Input must be either a 2-element standardizedTables struct array (aggregate) or a cell array of per-strain pairs.');
end


function strainLabel = singleStrainLabel(stdPair, elementIdx)
    strains = strings(0, 1);
    for t = 1:numel(stdPair)
        mdList = stdPair(t).animalMetadata.values();
        if ~isstruct(mdList)
            mdList = struct([]);
        end
        for k = 1:numel(mdList)
            md = mdList(k);
            if isstruct(md) && isfield(md, 'strain')
                strains(end+1, 1) = string(md.strain); %#ok<AGROW>
            else
                strains(end+1, 1) = ""; %#ok<AGROW>
            end
        end
    end

    uniqueStrains = unique(strains);
    if numel(uniqueStrains) ~= 1
        error('cohort:internal:adaptPipelineInput:MixedStrainElement', ...
            'Input cell element %d was declared strain-split but contains %d distinct strain values: %s. Split the element by strain, or pass a single aggregate struct array instead.', ...
            elementIdx, numel(uniqueStrains), strjoin(uniqueStrains, ', '));
    end

    strainLabel = uniqueStrains(1);
    if strlength(strtrim(strainLabel)) == 0
        strainLabel = sprintf('strainGroup%d', elementIdx);
    end
end
