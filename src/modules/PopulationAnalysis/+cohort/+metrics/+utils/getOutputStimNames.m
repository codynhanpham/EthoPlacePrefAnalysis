function outputStimNames = getOutputStimNames(standardizedTables, override)
	arguments
		standardizedTables struct {sdTable.mustBeStandardizedTable}
		override {validator.mustBeTextOrEmpty} = {}
	end

	overrideNames = string(sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, override));
	if ~isempty(overrideNames)
		if isPerTableOverride(overrideNames)
			outputStimNames = collectUniqueLabelsFromPerTableOverride(overrideNames);
			return;
		end

		overrideNames = string(overrideNames);
		overrideNames = overrideNames(:);
		outputStimNames = overrideNames;
		return;
	end

	outputStimNames = strings(0, 1);
	for i = 1:numel(standardizedTables)
		localNames = string(standardizedTables(i).stimuliSorted);
		localNames = localNames(:);
		for j = 1:numel(localNames)
			thisName = strtrim(localNames(j));
			if strlength(thisName) == 0
				continue;
			end
			if isempty(outputStimNames) || ~any(strcmpi(outputStimNames, thisName))
				outputStimNames(end+1, 1) = thisName; %#ok<AGROW>
			end
		end
	end
end


function tf = isPerTableOverride(overrideNames)
	tf = iscell(overrideNames) && ~isempty(overrideNames) && ...
		any(cellfun(@iscell, overrideNames));
end


function names = collectUniqueLabelsFromPerTableOverride(perTableOverride)
	names = strings(0, 1);
	for i = 1:numel(perTableOverride)
		labelsI = string(perTableOverride{i});
		labelsI = labelsI(:);
		for j = 1:numel(labelsI)
			thisName = strtrim(labelsI(j));
			if strlength(thisName) == 0
				continue;
			end
			if isempty(names) || ~any(strcmpi(names, thisName))
				names(end+1, 1) = thisName; %#ok<AGROW>
			end
		end
	end
end