classdef testFingerprintPipeline < matlab.unittest.TestCase
    methods (Test)
        function endToEndWithAggregateInput(testCase)
            stdTables = makePipelineFixture();

            out = cohort.fingerprintPipeline(stdTables, ...
                MinCohortN=2, NPerm=50, NBoot=50, MakeFigures=false);

            % Core outputs populated.
            testCase.verifyEqual(numel(unique(string(out.perAnimalLong.SubjectKey))), 4);
            testCase.verifyEqual(out.strainGroups, "aggregate");
            testCase.verifyEqual(width(out.fingerprint.zMatrix), height(out.fingerprint.colLabels));
            testCase.verifyEqual(height(out.fingerprint.zMatrix), height(out.fingerprint.rowLabels));
            testCase.verifyTrue(~isempty(out.statsTable));
            testCase.verifyTrue(ismember('MeanD2', out.mahalTable.Properties.VariableNames));

            % All five tiers present.
            tiers = categories(out.perAnimalLong.Tier);
            for expectedTier = ["exploration", "baseline", "stim_all", "per-stim", "delta"]
                testCase.verifyTrue(ismember(expectedTier, tiers));
            end
        end

        function aggregateAndSplitInputsGiveConsistentCohorts(testCase)
            pairA = makePipelineFixture("strainA");
            pairB = makePipelineFixture("strainB");

            outSplit = cohort.fingerprintPipeline({pairA, pairB}, ...
                MinCohortN=2, NPerm=50, NBoot=50, MakeFigures=false);

            testCase.verifyEqual(numel(outSplit.strainGroups), 2);
            testCase.verifyEqual(string(outSplit.strainGroups(1)), "strainA");
            testCase.verifyEqual(string(outSplit.strainGroups(2)), "strainB");

            % Both strains appear in the cohort table.
            testCase.verifyTrue(ismember("strainA", unique(string(outSplit.cohortTable.Strain))));
            testCase.verifyTrue(ismember("strainB", unique(string(outSplit.cohortTable.Strain))));
            % Subject keys of different strains stay distinct.
            keysLong = unique(string(outSplit.perAnimalLong.SubjectKey));
            testCase.verifyEqual(numel(keysLong), 8); % 4 subjects per strain
        end

        function savePathWritesMatAndCsvs(testCase)
            stdTables = makePipelineFixture();
            tmpDir = tempname;
            mkdir(tmpDir);
            cleanupObj = onCleanup(@() rmdir(tmpDir, 's')); %#ok<NASGU>

            out = cohort.fingerprintPipeline(stdTables, ...
                MinCohortN=2, NPerm=50, NBoot=50, MakeFigures=false, ...
                SavePath=fullfile(tmpDir, 'fpout.mat'));

            testCase.verifyTrue(isfile(fullfile(tmpDir, 'fpout.mat')));
            testCase.verifyTrue(isfile(fullfile(tmpDir, 'fpout_perAnimalLong.csv')));
            testCase.verifyTrue(isfile(fullfile(tmpDir, 'fpout_cohortTable.csv')));
            testCase.verifyTrue(isfile(fullfile(tmpDir, 'fpout_statsTable.csv')));
            testCase.verifyTrue(isfile(fullfile(tmpDir, 'fpout_mahalTable.csv')));
            testCase.verifyFalse(isfolder(fullfile(tmpDir, 'fpout.partial')));

            % A second run at the same SavePath must refuse to clobber.
            testCase.verifyError(@() cohort.fingerprintPipeline(stdTables, ...
                MinCohortN=2, NPerm=50, NBoot=50, MakeFigures=false, ...
                SavePath=fullfile(tmpDir, 'fpout.mat')), ...
                'cohort:fingerprintPipeline:SavePathExists');

            % Explicit Overwrite=true succeeds.
            out2 = cohort.fingerprintPipeline(stdTables, ...
                MinCohortN=2, NPerm=50, NBoot=50, MakeFigures=false, ...
                SavePath=fullfile(tmpDir, 'fpout.mat'), Overwrite=true); %#ok<NASGU>
            testCase.verifyTrue(isfile(fullfile(tmpDir, 'fpout.mat')));
        end

        function badSaveDirErrors(testCase)
            stdTables = makePipelineFixture();
            testCase.verifyError(@() cohort.fingerprintPipeline(stdTables, ...
                MinCohortN=2, NPerm=50, NBoot=50, MakeFigures=false, ...
                SavePath=fullfile(tempname, 'nope', 'fpout.mat')), ...
                'cohort:fingerprintPipeline:MissingSaveDir');
        end
    end
end


function standardizedTables = makePipelineFixture(strainName)
    if nargin < 1
        strainName = "strainA";
    end

    animals = [ ...
        struct('id', "M01", 'strain', string(strainName), 'genotype', "WT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10); ...
        struct('id', "M02", 'strain', string(strainName), 'genotype', "WT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10); ...
        struct('id', "M03", 'strain', string(strainName), 'genotype', "MUT", 'sex', "F", 'cagecode', "C2", 'dob', "", 'age', 10); ...
        struct('id', "M04", 'strain', string(strainName), 'genotype', "MUT", 'sex', "F", 'cagecode', "C2", 'dob', "", 'age', 10)];
    nAnimals = numel(animals);

    nRows = 14;
    xData = zeros(nRows, nAnimals);
    for a = 1:nAnimals
        if strcmp(animals(a).genotype, "MUT")
            base = 3 * (a - 1) + 6; % MUT animals range further right
        else
            base = 3 * (a - 1);
        end
        xData(:, a) = [base, base+1, base+2, repmat(base+2, 1, nRows-3)]';
    end
    yData = zeros(nRows, nAnimals);

    distFromMidline = xData - 1.5;
    arenaGrid = 0.5 * sign(distFromMidline);

    metadata = configureDictionary("string", "struct");
    for a = 1:nAnimals
        metadata(char(sprintf('k%d', a))) = animals(a);
    end

    standardizedTables = [makeOneProtocolTable(metadata, xData, yData, distFromMidline, arenaGrid, 'protocol1.flac'), ...
        makeOneProtocolTable(metadata, xData, yData, distFromMidline, arenaGrid, 'protocol2.flac')];
end


function stdTable = makeOneProtocolTable(metadata, xData, yData, distFromMidline, arenaGrid, stimfileName)
    nRows = size(xData, 1);
    trialTime = (0:nRows-1)' / 10;
    stimulusName = [ ...
        "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; ...
        "A"; "A"; "B"; "B"; "A"; "A"; "B"; "B"; "A"; "A"; "NONE | Post-Stimulus"];
    centerpointData = table(trialTime, stimulusName, ...
        xData, yData, distFromMidline, arenaGrid, ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
        'Y center', 'Distance from Midline', 'Arena Grid Score'});

    stdTable = struct( ...
        'stimfileName', stimfileName, ...
        'stimuliSorted', ["A", "B"], ...
        'animalMetadata', metadata, ...
        'fps', 10, ...
        'px2cm', 0.5, ...
        'centerpointData', centerpointData, ...
        'bodyparts', table());
end
