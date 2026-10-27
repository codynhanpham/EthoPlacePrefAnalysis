classdef testNewMetrics < matlab.unittest.TestCase
    methods (Test)
        function tortuosityOfStraightPathIsOne(testCase)
            stdTable = makeSingleAnimalTable([0:1:10]', zeros(11, 1), "A");
            t = cohort.metrics.tortuosity(stdTable);
            testCase.verifyEqual(t.('Tortuosity During Stimulus (path/net)'), 1, 'AbsTol', 1e-12);
        end

        function tortuosityOfReturnTripIsNaN(testCase)
            % Out-and-back within the stimulus period: net displacement 0 -> NaN.
            % 3 pre-stim rows, then A-period x: 0 1 2 3 2 1 0 0.
            x = [7; 8; 9; 0; 1; 2; 3; 2; 1; 0; 0];
            stdTable = makeSingleAnimalTable(x, zeros(numel(x), 1), "A");
            t = cohort.metrics.tortuosity(stdTable);
            testCase.verifyTrue(isnan(t.('Tortuosity During Stimulus (path/net)')));
        end

        function zoneOccupancyFractionIsTimeWeighted(testCase)
            % 4 samples, equal intervals; distances [1 1 3 3]:
            % in-zone intervals = 1 of 3 -> 33.33%.
            trialTime = (0:3)';
            stdTable = makeZoneTable(trialTime, [1; 1; 3; 3]);

            t = cohort.metrics.zoneOccupancy(stdTable, MidlineZoneHalfWidthCm=2);
            expected = 100 / 3;
            testCase.verifyEqual(t.('Percent Time Near Midline During Stimulus (%)'), expected, 'AbsTol', 1e-9);
        end

        function arenaEntropyZeroForSingleBinAndOneBitForTwoBins(testCase)
            % All points identical -> single occupied bin -> H = 0.
            stdTable = makeAllActiveTable(ones(10, 1), ones(10, 1));
            t = cohort.metrics.arenaEntropy(stdTable, EntropyBinSizeCm=5);
            testCase.verifyEqual(t.('Occupancy Entropy During Stimulus (bits)'), 0, 'AbsTol', 1e-12);

            % Two equally occupied far-apart bins -> H = 1 bit.
            x = [zeros(5, 1); 100 * ones(5, 1)];
            y = zeros(10, 1);
            stdTable = makeAllActiveTable(x, y);
            t = cohort.metrics.arenaEntropy(stdTable, EntropyBinSizeCm=5);
            testCase.verifyEqual(t.('Occupancy Entropy During Stimulus (bits)'), 1, 'AbsTol', 1e-12);
        end

        function speedSlopeOfLinearRamp(testCase)
            % Segment speeds [1 1 2 2 3] over t = 0:5, 2-s bins: bin medians
            % [1 2 3] at bin centers [1 3 5] -> slope 0.5 cm/s per s = 30 per min.
            x = [0; 1; 2; 4; 6; 9];
            y = zeros(6, 1);
            stdTable = makeAllActiveTable(x, y);

            t = cohort.metrics.speedSlope(stdTable, SlopeBinSec=2);
            testCase.verifyEqual(t.('Speed Slope During Stimulus (cm/s per min)'), 30, 'AbsTol', 1e-9);
        end

        function newMetricsAvailableThroughSummary(testCase)
            stdTable = makeSingleAnimalTable([0:1:10]', zeros(11, 1), "A");
            stdTables = repmat(stdTable, 1, 1);

            t = cohort.summary(stdTables, MetricsToInclude={'tortuosity', 'arenaEntropy', 'zoneOccupancy', 'speedSlope'});
            names = t.Properties.VariableNames;
            testCase.verifyTrue(ismember('Tortuosity During Stimulus (path/net)', names));
            testCase.verifyTrue(ismember('Occupancy Entropy During Stimulus (bits)', names));
            testCase.verifyTrue(ismember('Percent Time Near Midline During Stimulus (%)', names));
            testCase.verifyTrue(ismember('Speed Slope During Stimulus (cm/s per min)', names));
        end
    end
end


function standardizedTable = makeAllActiveTable(x, y)
    n = numel(x);
    trialTime = (0:n-1)';
    stimulusName = repmat("A", n, 1);
    centerpointData = table(trialTime, stimulusName, x, y, x, sign(x), ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', 'Y center', ...
        'Distance from Midline', 'Arena Grid Score'});

    standardizedTable = struct('stimfileName', "s.flac", 'stimuliSorted', ["A", "B"], ...
        'animalMetadata', makeSingleAnimalMetadata(), 'fps', 1, 'px2cm', 1, ...
        'centerpointData', centerpointData, 'bodyparts', table());
end


function standardizedTable = makeSingleAnimalTable(x, y, activeStim)
    n = numel(x);
    trialTime = (0:n-1)';
    stimulusName = [repmat("NONE | Pre-Stimulus", min(3, n), 1); repmat(string(activeStim), max(0, n - 3), 1)];
    stimulusName = stimulusName(1:n);
    centerpointData = table(trialTime, stimulusName, x, y, x, sign(x), ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', 'Y center', ...
        'Distance from Midline', 'Arena Grid Score'});

    standardizedTable = struct('stimfileName', "s.flac", 'stimuliSorted', ["A", "B"], ...
        'animalMetadata', makeSingleAnimalMetadata(), 'fps', 1, 'px2cm', 1, ...
        'centerpointData', centerpointData, 'bodyparts', table());
end


function standardizedTable = makeZoneTable(trialTime, distFromMidline)
    n = numel(trialTime);
    stimulusName = repmat("A", n, 1);
    x = distFromMidline;
    y = zeros(n, 1);
    centerpointData = table(trialTime, stimulusName, x, y, distFromMidline, sign(distFromMidline), ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', 'Y center', ...
        'Distance from Midline', 'Arena Grid Score'});

    standardizedTable = struct('stimfileName', "s.flac", 'stimuliSorted', ["A", "B"], ...
        'animalMetadata', makeSingleAnimalMetadata(), 'fps', 1, 'px2cm', 1, ...
        'centerpointData', centerpointData, 'bodyparts', table());
end


function metadata = makeSingleAnimalMetadata()
    metadata = configureDictionary("string", "struct");
    metadata("animal1") = struct('id', "M1", 'strain', "strainA", 'genotype', "WT", ...
        'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10);
end
