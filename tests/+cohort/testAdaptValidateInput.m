classdef testAdaptValidateInput < matlab.unittest.TestCase
    methods (Test)
        function aggregateStructBecomesSingleGroup(testCase)
            standardizedTables = makeTwoProtocolFixture();

            groups = cohort.internal.adaptPipelineInput(standardizedTables);
            testCase.verifyEqual(numel(groups), 1);
            testCase.verifyEqual(string(groups{1}.strainLabel), "aggregate");

            protocolLabels = cohort.internal.validateProtocolTables(groups{1}.tables);
            testCase.verifyEqual(string(protocolLabels(1)), "protocol1.flac");
            testCase.verifyEqual(string(protocolLabels(2)), "protocol2.flac");
        end

        function strainSplitCellBecomesPerStrainGroups(testCase)
            pair1 = makeTwoProtocolFixture("strainA");
            pair2 = makeTwoProtocolFixture("strainB");

            groups = cohort.internal.adaptPipelineInput({pair1, pair2});
            testCase.verifyEqual(numel(groups), 2);
            testCase.verifyEqual(string(groups{1}.strainLabel), "strainA");
            testCase.verifyEqual(string(groups{2}.strainLabel), "strainB");
        end

        function sharedStimfileNamesDoNotCollide(testCase)
            % Both strain pairs use the same stimfileNames; protocol identity
            % still resolves per group via ORDER.
            pair1 = makeTwoProtocolFixture("strainA");
            pair2 = makeTwoProtocolFixture("strainB");

            groups = cohort.internal.adaptPipelineInput({pair1, pair2});
            for g = 1:2
                protocolLabels = cohort.internal.validateProtocolTables(groups{g}.tables);
                testCase.verifyEqual(string(protocolLabels(1)), "protocol1.flac");
            end
        end

        function aggregateWithThreeTablesErrors(testCase)
            pair = [makeTwoProtocolFixture(), makeOneTableFixture()];
            testCase.verifyError(@() cohort.internal.adaptPipelineInput(pair), ...
                'cohort:internal:adaptPipelineInput:WrongTableCount');
        end

        function cellElementWithMixedStrainErrors(testCase)
            pair = makeTwoProtocolFixture();
            % Overwrite second animal's strain in both tables.
            for t = 1:2
                keysT = keys(pair(t).animalMetadata);
                md = pair(t).animalMetadata(keysT{2});
                md.strain = "otherStrain";
                pair(t).animalMetadata(keysT{2}) = md;
            end

            testCase.verifyError(@() cohort.internal.adaptPipelineInput({pair}), ...
                'cohort:internal:adaptPipelineInput:MixedStrainElement');
        end

        function subjectMissingFromTable2Errors(testCase)
            pair = makeTwoProtocolFixture();
            keysT = keys(pair(2).animalMetadata);
            pair(2).animalMetadata = remove(pair(2).animalMetadata, keysT(end));
            cp = pair(2).centerpointData;
            cp.('X center') = cp.('X center')(:, 1:end-1);
            cp.('Y center') = cp.('Y center')(:, 1:end-1);
            cp.('Distance from Midline') = cp.('Distance from Midline')(:, 1:end-1);
            cp.('Arena Grid Score') = cp.('Arena Grid Score')(:, 1:end-1);
            pair(2).centerpointData = cp;

            testCase.verifyError(@() cohort.internal.validateProtocolTables(pair), ...
                'cohort:internal:validateProtocolTables:SubjectSetMismatch');
        end

        function missingPreStimulusRowsError(testCase)
            pair = makeTwoProtocolFixture();
            cp = pair(2).centerpointData;
            keep = ~strcmpi(strtrim(string(cp{:, 'Stimulus name'})), "NONE | Pre-Stimulus");
            pair(2).centerpointData = cp(keep, :);

            testCase.verifyError(@() cohort.internal.validateProtocolTables(pair), ...
                'cohort:internal:validateProtocolTables:MissingPreStimulus');
        end

        function duplicatedSubjectWithinTableErrors(testCase)
            pair = makeTwoProtocolFixture();
            cp = pair(1).centerpointData;
            nCols = size(cp.('X center'), 2);
            cp.('X center') = [cp.('X center'), cp.('X center')(:, 1)];
            cp.('Y center') = [cp.('Y center'), cp.('Y center')(:, 1)];
            cp.('Distance from Midline') = [cp.('Distance from Midline'), cp.('Distance from Midline')(:, 1)];
            cp.('Arena Grid Score') = [cp.('Arena Grid Score'), cp.('Arena Grid Score')(:, 1)];
            pair(1).centerpointData = cp;
            keysT = keys(pair(1).animalMetadata);
            pair(1).animalMetadata(char("dup" + nCols)) = pair(1).animalMetadata(keysT{1});

            testCase.verifyError(@() cohort.internal.validateProtocolTables(pair), ...
                'cohort:internal:validateProtocolTables:DuplicateSubject');
        end

        function invalidInputShapeErrors(testCase)
            testCase.verifyError(@() cohort.internal.adaptPipelineInput(42), ...
                'cohort:internal:adaptPipelineInput:InvalidInput');
            testCase.verifyError(@() cohort.internal.adaptPipelineInput("abc"), ...
                'cohort:internal:adaptPipelineInput:InvalidInput');
        end
    end
end


function standardizedTables = makeTwoProtocolFixture(strainName)
    if nargin < 1
        strainName = "strainA";
    end

    animals = [ ...
        struct('id', "M01", 'strain', string(strainName), 'genotype', "WT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10); ...
        struct('id', "M02", 'strain', string(strainName), 'genotype', "MUT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10)];
    nAnimals = numel(animals);

    nRows = 12;
    xCol = [0:1:(nRows-1)]';
    xCol(4:end) = 3;
    xData = repmat(xCol, 1, nAnimals);
    distFromMidline = xData;
    arenaGrid = sign(xData) * 0.5;

    bodyparts = table();
    metadata = configureDictionary("string", "struct");
    for a = 1:nAnimals
        metadata(char(sprintf('k%d', a))) = animals(a);
    end

    standardizedTables = [makeOneProtocolTable(metadata, xData, distFromMidline, arenaGrid, 'protocol1.flac'), ...
        makeOneProtocolTable(metadata, xData, distFromMidline, arenaGrid, 'protocol2.flac')];
end


function stdTable = makeOneProtocolTable(metadata, xData, distFromMidline, arenaGrid, stimfileName)
    nRows = size(xData, 1);
    trialTime = (0:nRows-1)' / 10;
    stimulusName = [ ...
        "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; ...
        "A"; "A"; "B"; "B"; "A"; "A"; "B"; "B"; "NONE | Post-Stimulus"];
    centerpointData = table(trialTime, stimulusName, ...
        xData, zeros(size(xData)), distFromMidline, arenaGrid, ...
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


function standardizedTables = makeOneTableFixture()
    pair = makeTwoProtocolFixture();
    standardizedTables = pair(1);
end
