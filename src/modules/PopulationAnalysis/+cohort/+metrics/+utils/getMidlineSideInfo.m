function info = getMidlineSideInfo(standardizedTable, kvargs)
	arguments
		standardizedTable (1,1) struct
		kvargs.StimulusIncludesTrailingISI (1,1) logical = true
	end

	cp = standardizedTable.centerpointData;
	info.trialTime = cp{:, 'Trial time'};
	info.stimSequence = string(cp{:, 'Stimulus name'});
	info.xData = cp{:, 'X center'};
	info.yData = cp{:, 'Y center'};
	info.distanceFromMidline = cp{:, 'Distance from Midline'};
	info.localStimNames = string(standardizedTable.stimuliSorted);
	info.localStimNames = info.localStimNames(:);

	info.allStimMask = cohort.metrics.utils.periodMaskAllStim( ...
		info.stimSequence, info.localStimNames, kvargs.StimulusIncludesTrailingISI);

	info.stimMasks = cell(numel(info.localStimNames), 1);
	for s = 1:numel(info.localStimNames)
		info.stimMasks{s} = cohort.metrics.utils.periodMaskForStim( ...
			info.stimSequence, info.localStimNames(s), info.localStimNames, kvargs.StimulusIncludesTrailingISI);
	end

	info.midlineNegativeMask = info.distanceFromMidline < 0;
	info.midlinePositiveMask = info.distanceFromMidline > 0;
	info.midlineZeroMask = info.distanceFromMidline == 0;
end