classdef testPeriodThreading < matlab.unittest.TestCase
    methods (Test)
        function preStimModeRenamesAggregatesAndDropsBouts(testCase)
            standardizedTables = makeTwoProtocolFixture();

            tPre = cohort.summary(standardizedTables, Period='pre-stimulus', ...
                MetricsToInclude={'speed', 'rateofstay', 'midlineCrossingFreq', 'distanceTravel'});

            names = tPre.Properties.VariableNames;
            testCase.verifyTrue(ismember('Speed Mean During Pre-Stimulus (cm/s)', names));
            testCase.verifyFalse(ismember('Speed Mean During Stimulus (cm/s)', names));
            testCase.verifyFalse(ismember('Speed Mean During A (cm/s)', names));
            testCase.verifyFalse(any(contains(names, 'Bout')));
            testCase.verifyFalse(any(contains(names, 'Last-First')));

            % Embedded-label per-stim families survive in pre-stim mode.
            testCase.verifyTrue(ismember('Percent Time on A Side During Pre-Stimulus (%)', names));
            testCase.verifyTrue(ismember('Midline Crossings Into A During Pre-Stimulus (count)', names));
            testCase.verifyTrue(ismember('Midline Crossings Into B During Pre-Stimulus (count)', names));

            % distanceTravel emits only its pre-stim column in pre-stim mode.
            testCase.verifyTrue(ismember('Distance During Pre-Stimulus (cm)', names));
            testCase.verifyFalse(ismember('Distance During Stimulus (cm)', names));
            testCase.verifyFalse(ismember('Distance During Post-Stimulus (cm)', names));
        end

        function defaultPeriodMatchesLegacyNames(testCase)
            standardizedTables = makeTwoProtocolFixture();

            tStim = cohort.summary(standardizedTables, ...
                MetricsToInclude={'speed', 'rateofstay', 'preferenceIndex'});

            names = tStim.Properties.VariableNames;
            testCase.verifyTrue(ismember('Speed Mean During Stimulus (cm/s)', names));
            testCase.verifyTrue(ismember('Speed Mean During A (cm/s)', names));
            testCase.verifyTrue(ismember('Speed Mean During First A Bout (cm/s)', names));
            testCase.verifyTrue(ismember('Percent Time on A Side During Active Stimulus (%)', names));
            testCase.verifyTrue(any(contains(names, 'Preference Index During Active Stimulus')));
        end

        function preStimValuesUsePreStimRowsOnly(testCase)
            standardizedTables = makeTwoProtocolFixture();
            % Fixture animals move at constant speed during pre-stimulus and
            % freeze during the stimulus period: speed is 1 cm per 0.1 s frame
            % pre-stim, 0 during stim.
            tPre = cohort.summary(standardizedTables, Period='pre-stimulus', MetricsToInclude={'speed'});
            tStim = cohort.summary(standardizedTables, Period='stimulus', MetricsToInclude={'speed'});

            preSpeeds = tPre.('Speed Mean During Pre-Stimulus (cm/s)');
            stimSpeeds = tStim.('Speed Mean During Stimulus (cm/s)');

            testCase.verifyEqual(mean(preSpeeds), 10, 'AbsTol', 1e-9);
            testCase.verifyEqual(mean(stimSpeeds), 0, 'AbsTol', 1e-9);
        end

        function maskUtilsHandlePreStimPeriod(testCase)
            stimSequence = ["NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; "A"; "A"; "B"; "NONE | Post-Stimulus"];
            expected = [true; true; false; false; false; false];

            maskAll = cohort.metrics.utils.periodMaskAllStim(stimSequence, ["A", "B"], true, 'pre-stimulus');
            maskStim = cohort.metrics.utils.periodMaskForStim(stimSequence, "A", ["A", "B"], true, 'pre-stimulus');
            bouts = cohort.metrics.utils.stimBoutMasksForStim(stimSequence, "A", ["A", "B"], true, 'pre-stimulus');

            testCase.verifyEqual(maskAll, expected);
            testCase.verifyEqual(maskStim, expected);
            testCase.verifyTrue(isempty(bouts));

            % Default behavior unchanged.
            maskDefault = cohort.metrics.utils.periodMaskAllStim(stimSequence, ["A", "B"], false);
            testCase.verifyEqual(maskDefault, [false; false; true; true; true; false]);
        end

        function headMetricsSupportPreStimPeriod(testCase)
            standardizedTables = makeTwoProtocolFixture();

            tPre = cohort.summary(standardizedTables, Period='pre-stimulus', MetricsToInclude={'headSpeed'});
            names = tPre.Properties.VariableNames;
            testCase.verifyTrue(ismember('Head Speed Mean During Pre-Stimulus (cm/s)', names));
            testCase.verifyFalse(any(contains(names, 'During A ')));
        end
    end
end


function standardizedTables = makeTwoProtocolFixture()
    % 2 tables x 2 animals (WT F, MUT F) x 1 strain. Animals move rightward at
    % 1 cm per frame during pre-stimulus and hold still afterwards.
    animals = [ ...
        struct('id', "M01", 'strain', "strainA", 'genotype', "WT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10); ...
        struct('id', "M02", 'strain', "strainA", 'genotype', "MUT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10)];

    bodyparts = table();
    metadata = configureDictionary("string", "struct");
    for a = 1:numel(animals)
        metadata(char(sprintf('k%d', a))) = animals(a);
    end

    standardizedTables = [makeOneProtocolTable(metadata, bodyparts, 'protocol1.flac'), ...
        makeOneProtocolTable(metadata, bodyparts, 'protocol2.flac')];
end


function stdTable = makeOneProtocolTable(metadata, bodyparts, stimfileName)
    nRows = 12;
    trialTime = (0:nRows-1)' / 10;
    stimulusName = [ ...
        "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; ...
        "A"; "A"; "B"; "B"; "A"; "A"; "B"; "B"; "NONE | Post-Stimulus"];
    xData = [0:1:(nRows-1)]';
    xData(4:end) = 3;

    centerpointData = table(trialTime, stimulusName, ...
        repmat(xData, 1, 2), zeros(nRows, 2), repmat(xData, 1, 2), sign(repmat(xData, 1, 2)), ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
        'Y center', 'Distance from Midline', 'Arena Grid Score'});

    stdTable = struct( ...
        'stimfileName', stimfileName, ...
        'stimuliSorted', ["A", "B"], ...
        'animalMetadata', metadata, ...
        'fps', 10, ...
        'px2cm', 0.5, ...
        'centerpointData', centerpointData, ...
        'bodyparts', bodyparts);
end
